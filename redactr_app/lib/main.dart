import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'models/alert.dart';
import 'screens/alerts_screen.dart';
import 'screens/biometric_gate_screen.dart';
import 'screens/company_setup_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/insights_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/sign_in_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/team_screen.dart';
import 'services/alert_service.dart';
import 'services/auth_service.dart';
import 'services/company_service.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const RedactrApp());
}

class RedactrApp extends StatelessWidget {
  const RedactrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Redactr',
      theme: AppTheme.dark,
      debugShowCheckedModeBanner: false,
      home: const AuthGate(),
    );
  }
}

Widget _premiumTransition(Widget child, Animation<double> animation) {
  return FadeTransition(
    opacity: animation,
    child: ScaleTransition(
      scale: Tween(
        begin: 0.97,
        end: 1.0,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
      child: child,
    ),
  );
}

const _transitionDuration = Duration(milliseconds: 450);

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _showSplash = true;
  bool _firebaseReady = false;
  Object? _firebaseError;
  bool? _requiresBiometric;
  bool _biometricPassed = false;
  final _authService = AuthService();

  @override
  void initState() {
    super.initState();
    Firebase.initializeApp()
        .then((_) {
          if (mounted) setState(() => _firebaseReady = true);
          _authService.authStateChanges.first.then((user) {
            if (mounted) setState(() => _requiresBiometric = user != null);
          });
        })
        .catchError((error) {
          if (mounted) setState(() => _firebaseError = error);
        });
  }

  static const _loadingScreen = Scaffold(
    backgroundColor: AppColors.background,
    body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
  );

  @override
  Widget build(BuildContext context) {
    Widget content;

    if (_showSplash) {
      content = SplashScreen(
        onFinished: () => setState(() => _showSplash = false),
      );
    } else if (_firebaseError != null) {
      content = const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Text(
              'Sign-in is unavailable: Firebase isn\'t configured for this build yet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textDim),
            ),
          ),
        ),
      );
    } else if (!_firebaseReady) {
      content = _loadingScreen;
    } else {
      content = StreamBuilder<User?>(
        stream: _authService.authStateChanges,
        builder: (context, snapshot) {
          Widget inner;
          if (snapshot.connectionState == ConnectionState.waiting) {
            inner = _loadingScreen;
          } else {
            final user = snapshot.data;
            if (user == null) {
              inner = const SignInScreen();
            } else if (_requiresBiometric == null) {
              inner = _loadingScreen;
            } else if (_requiresBiometric! && !_biometricPassed) {
              inner = BiometricGateScreen(
                onSuccess: () => setState(() => _biometricPassed = true),
              );
            } else {
              inner = _ProfileGate(uid: user.uid);
            }
          }
          return AnimatedSwitcher(
            duration: _transitionDuration,
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: _premiumTransition,
            child: inner,
          );
        },
      );
    }

    return AnimatedSwitcher(
      duration: _transitionDuration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: _premiumTransition,
      child: content,
    );
  }
}

class _ProfileGate extends StatefulWidget {
  final String uid;
  const _ProfileGate({required this.uid});

  @override
  State<_ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<_ProfileGate> {
  final _companyService = CompanyService();
  late Future<Map<String, dynamic>?> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = _resolveProfile();
    _registerFcmToken();
  }

  /// Checks company profile first; if none, falls back to trial entitlement
  /// so trial users don't land on CompanySetupScreen.
  Future<Map<String, dynamic>?> _resolveProfile() async {
    final profile = await _companyService.getUserProfile(widget.uid);
    if (profile != null) return profile;
    try {
      final e = await _companyService.getEntitlement();
      if (e.plan == 'trial' || e.plan == 'trial_expired') {
        return {
          '__trial': true,
          'plan': e.plan,
          'trialDaysLeft': e.trialDaysLeft,
          'trialExpired': e.trialExpired,
        };
      }
    } catch (_) {}
    return null;
  }

  void _refresh() {
    setState(() {
      _profileFuture = _resolveProfile();
    });
  }

  Future<void> _registerFcmToken() async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      final token = await messaging.getToken();
      if (token != null) {
        await _companyService.saveFcmToken(widget.uid, token);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _profileFuture,
      builder: (context, snapshot) {
        Widget inner;
        if (snapshot.connectionState == ConnectionState.waiting) {
          inner = const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        } else if (snapshot.data == null) {
          inner = CompanySetupScreen(onCompanyReady: _refresh);
        } else if (snapshot.data!.containsKey('__trial')) {
          inner = TrialShell(
            plan: snapshot.data!['plan'] as String,
            trialDaysLeft: snapshot.data!['trialDaysLeft'] as int,
            trialExpired: snapshot.data!['trialExpired'] as bool,
          );
        } else {
          final companyId = snapshot.data!['companyId'] as String;
          inner = RootShell(companyId: companyId);
        }
        return AnimatedSwitcher(
          duration: _transitionDuration,
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: _premiumTransition,
          child: inner,
        );
      },
    );
  }
}

// ── Trial shell — minimal view-only app for trial users ──────────────────────

class TrialShell extends StatelessWidget {
  final String plan;
  final int trialDaysLeft;
  final bool trialExpired;

  const TrialShell({
    super.key,
    required this.plan,
    required this.trialDaysLeft,
    required this.trialExpired,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.xxl),
              Center(
                child: Image.asset(
                  'assets/branding/icon512.png',
                  width: 72,
                  height: 72,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Center(
                child: Text(
                  'Redactr',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),

              // Trial status card
              Container(
                padding: const EdgeInsets.all(AppSpacing.xl),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: trialExpired
                      ? AppColors.danger.withValues(alpha: 0.08)
                      : AppColors.primary.withValues(alpha: 0.08),
                  border: Border.all(
                    color: trialExpired
                        ? AppColors.danger.withValues(alpha: 0.3)
                        : AppColors.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      trialExpired
                          ? Icons.timer_off_outlined
                          : Icons.timer_outlined,
                      color: trialExpired
                          ? AppColors.danger
                          : AppColors.primary,
                      size: 36,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      trialExpired
                          ? 'Your free trial has ended'
                          : '$trialDaysLeft day${trialDaysLeft != 1 ? 's' : ''} left in your trial',
                      style: TextStyle(
                        color: trialExpired
                            ? AppColors.danger
                            : AppColors.primary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      trialExpired
                          ? 'Upgrade to a paid plan to continue protecting your business.'
                          : 'You have full extension access during your trial. The mobile app dashboard is available after upgrading.',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.xl),

              // Upgrade button
              ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.background,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'View Pricing & Upgrade',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),

              const SizedBox(height: AppSpacing.md),

              if (!trialExpired) ...[
                OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textDim,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Download Chrome Extension',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TRIAL INCLUDES',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                        ),
                      ),
                      SizedBox(height: AppSpacing.sm),
                      _TrialFeatureRow(
                        icon: Icons.check_circle_outline,
                        text: 'Full Tier-1 keyword scanning on all AI tools',
                      ),
                      _TrialFeatureRow(
                        icon: Icons.check_circle_outline,
                        text: 'Works on ChatGPT, Claude, Gemini & more',
                      ),
                      _TrialFeatureRow(
                        icon: Icons.lock_outline,
                        text: 'Dashboard & alerts — upgrade to unlock',
                        locked: true,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TrialFeatureRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool locked;

  const _TrialFeatureRow({
    required this.icon,
    required this.text,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: locked ? AppColors.textMuted : AppColors.primary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: locked ? AppColors.textMuted : AppColors.text,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Root shell with custom animated bottom nav ────────────────────────────────

class RootShell extends StatefulWidget {
  final String companyId;
  const RootShell({super.key, required this.companyId});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;
  final _alertService = AlertService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Alert>>(
      stream: _alertService.watchAlerts(widget.companyId),
      builder: (context, snapshot) {
        final pendingCount = (snapshot.data ?? [])
            .where((a) => a.status == AlertStatus.pending)
            .length;

        final screens = [
          DashboardScreen(companyId: widget.companyId),
          AlertsScreen(companyId: widget.companyId),
          InsightsScreen(companyId: widget.companyId),
          TeamScreen(companyId: widget.companyId),
          SettingsScreen(companyId: widget.companyId),
        ];

        return Scaffold(
          body: IndexedStack(index: _index, children: screens),
          bottomNavigationBar: _AppNavBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            pendingAlertCount: pendingCount,
          ),
        );
      },
    );
  }
}

// ── Custom animated bottom nav bar ────────────────────────────────────────────

typedef _TabDef = ({IconData icon, IconData activeIcon, String label});

const List<_TabDef> _tabs = [
  (
    icon: Icons.dashboard_outlined,
    activeIcon: Icons.dashboard_rounded,
    label: 'Dashboard',
  ),
  (
    icon: Icons.shield_outlined,
    activeIcon: Icons.shield_rounded,
    label: 'Alerts',
  ),
  (
    icon: Icons.insights_outlined,
    activeIcon: Icons.insights_rounded,
    label: 'Insights',
  ),
  (
    icon: Icons.people_outline_rounded,
    activeIcon: Icons.people_rounded,
    label: 'Team',
  ),
  (
    icon: Icons.settings_outlined,
    activeIcon: Icons.settings_rounded,
    label: 'Settings',
  ),
];

class _AppNavBar extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final int pendingAlertCount;

  const _AppNavBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.pendingAlertCount,
  });

  @override
  State<_AppNavBar> createState() => _AppNavBarState();
}

class _AppNavBarState extends State<_AppNavBar> {
  final List<bool> _pressed = List.filled(5, false);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              for (int i = 0; i < _tabs.length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) => setState(() => _pressed[i] = true),
                    onTapUp: (_) {
                      setState(() => _pressed[i] = false);
                      widget.onDestinationSelected(i);
                    },
                    onTapCancel: () => setState(() => _pressed[i] = false),
                    child: AnimatedScale(
                      scale: _pressed[i] ? 0.86 : 1.0,
                      duration: AppDurations.fast,
                      curve: Curves.easeOut,
                      child: _NavItem(
                        tab: _tabs[i],
                        selected: widget.selectedIndex == i,
                        badge: i == 1 ? widget.pendingAlertCount : 0,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final _TabDef tab;
  final bool selected;
  final int badge;

  const _NavItem({
    required this.tab,
    required this.selected,
    required this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            AnimatedContainer(
              duration: AppDurations.base,
              curve: AppCurves.spring,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.14)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                selected ? tab.activeIcon : tab.icon,
                color: selected ? AppColors.primary : AppColors.textDim,
                size: 22,
              ),
            ),
            if (badge > 0)
              Positioned(
                top: 2,
                right: 6,
                child: AnimatedScale(
                  scale: badge > 0 ? 1.0 : 0.0,
                  duration: AppDurations.base,
                  curve: AppCurves.spring,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: AppColors.danger,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      badge > 99 ? '99+' : '$badge',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        AnimatedDefaultTextStyle(
          duration: AppDurations.fast,
          style: TextStyle(
            fontFamily: Theme.of(context).textTheme.bodySmall?.fontFamily,
            fontSize: 10,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.primary : AppColors.textDim,
          ),
          child: Text(tab.label),
        ),
      ],
    );
  }
}

/// Shared slide+fade page route used for all Navigator.push calls.
Route<T> slideRoute<T>(Widget page) => PageRouteBuilder<T>(
  pageBuilder: (context, animation, secondaryAnimation) => page,
  transitionsBuilder: (context, animation, secondaryAnimation, child) {
    final slide = Tween(
      begin: const Offset(1.0, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
    final fade = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: animation, curve: const Interval(0, 0.6)),
    );
    return FadeTransition(
      opacity: fade,
      child: SlideTransition(position: slide, child: child),
    );
  },
  transitionDuration: AppDurations.base,
  reverseTransitionDuration: AppDurations.fast,
);
