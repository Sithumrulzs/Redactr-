import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
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

  /// Resolves the signed-in user's profile. Uses claimOrJoinCompany as the
  /// primary path because it returns {companyId, role} directly from the
  /// server, bypassing any Firestore client-side cache that could return a
  /// stale "doc doesn't exist" result after a recent server write.
  /// Falls back to a direct Firestore read and trial check if the server
  /// call fails (cold start timeout, rate limit, etc.).
  Future<Map<String, dynamic>?> _resolveProfile() async {
    // Primary: ask the server. Already-joined users get a fast short-circuit
    // (server reads users/{uid}, sees it exists, returns immediately).
    // Post-payment users get auto-joined via invites/{email}.
    try {
      final data = await _companyService.claimOrJoinCompany();
      if (data.containsKey('companyId')) return data;
    } catch (_) {}

    // Fallback: direct Firestore read (covers cold-start timeout / rate limit).
    try {
      final profile = await _companyService.getUserProfile(widget.uid);
      if (profile != null) return profile;
    } catch (_) {}

    // Trial check.
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
          // No invite, no trial, no profile — block access.
          inner = const _NoAccessScreen();
        } else if (snapshot.data!.containsKey('__trial') &&
            !snapshot.data!.containsKey('companyId')) {
          // Active trial but no company yet — collect company name first.
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

// ── No-access screen — shown when email has no trial and no paid plan ─────────

class _NoAccessScreen extends StatefulWidget {
  const _NoAccessScreen();

  @override
  State<_NoAccessScreen> createState() => _NoAccessScreenState();
}

class _NoAccessScreenState extends State<_NoAccessScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ambientCtrl;

  @override
  void initState() {
    super.initState();
    _ambientCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
  }

  @override
  void dispose() {
    _ambientCtrl.dispose();
    super.dispose();
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // ── Ambient drifting orbs background ────────────────────────────
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _ambientCtrl,
              builder: (_, _) => CustomPaint(
                painter: _AmbientOrbs(_ambientCtrl.value),
              ),
            ),
          ),

          // ── Foreground content ───────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(flex: 2),

                  // Lock icon — red, kept exactly
                  Center(
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.danger.withValues(alpha: 0.10),
                        border: Border.all(
                          color: AppColors.danger.withValues(alpha: 0.32),
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.lock_outline_rounded,
                        color: AppColors.danger,
                        size: 34,
                      ),
                    ),
                  ),

                  const SizedBox(height: AppSpacing.xl),

                  Text(
                    'Access Restricted',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Text(
                    'This Google account hasn\'t purchased a Redactr plan\nor started a free trial yet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13.5,
                      height: 1.55,
                    ),
                  ),

                  const SizedBox(height: AppSpacing.xxl),

                  // Free trial card
                  _AccessCard(
                    icon: Icons.rocket_launch_rounded,
                    accentColor: AppColors.primary,
                    title: 'Start a free trial',
                    onTap: () => _open(
                        'https://redactr-swart.vercel.app/pages/trial.html'),
                  ),

                  const SizedBox(height: AppSpacing.md),

                  // Pricing card
                  _AccessCard(
                    icon: Icons.diamond_rounded,
                    accentColor: AppColors.warning,
                    title: 'View pricing plans',
                    onTap: () => _open(
                        'https://redactr-swart.vercel.app/pages/pricing.html'),
                  ),

                  const Spacer(flex: 2),

                  GestureDetector(
                    onTap: () => AuthService().signOut(),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                      child: Text(
                        'Sign out',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textDim,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Premium access card — title + icon only, idle glow breathing ───────────────

class _AccessCard extends StatefulWidget {
  final IconData icon;
  final Color accentColor;
  final String title;
  final VoidCallback onTap;

  const _AccessCard({
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.onTap,
  });

  @override
  State<_AccessCard> createState() => _AccessCardState();
}

class _AccessCardState extends State<_AccessCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _idleCtrl;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _idleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _idleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedBuilder(
        animation: _idleCtrl,
        builder: (_, _) {
          final breathe = _idleCtrl.value; // 0→1 eased
          return AnimatedScale(
            scale: _pressed ? 0.97 : 1.0,
            duration: AppDurations.fast,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.lg,
              ),
              decoration: BoxDecoration(
                color: _pressed ? AppColors.surfaceAlt : AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _pressed
                      ? widget.accentColor.withValues(alpha: 0.55)
                      : widget.accentColor
                          .withValues(alpha: 0.18 + 0.14 * breathe),
                  width: 1.5,
                ),
                boxShadow: _pressed
                    ? []
                    : [
                        BoxShadow(
                          color: widget.accentColor
                              .withValues(alpha: 0.09 + 0.07 * breathe),
                          blurRadius: 22 + 12 * breathe,
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
              ),
              child: Row(
                children: [
                  // Premium icon container with breathing border
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: widget.accentColor.withValues(alpha: 0.09),
                      border: Border.all(
                        color: widget.accentColor
                            .withValues(alpha: 0.22 + 0.12 * breathe),
                        width: 1.0,
                      ),
                    ),
                    child: Icon(
                      widget.icon,
                      color: widget.accentColor,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: widget.accentColor.withValues(alpha: 0.55),
                    size: 14,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Ambient orbs — two slow-drifting radial gradients painted on the background

class _AmbientOrbs extends CustomPainter {
  final double t; // 0..1 repeating

  const _AmbientOrbs(this.t);

  void _paintOrb(Canvas canvas, Offset center, double radius, Color color) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final angle = t * 2 * math.pi;

    // Teal orb — drifts gently in the upper-left region
    final x1 = size.width  * (0.12 + 0.14 * math.sin(angle));
    final y1 = size.height * (0.18 + 0.09 * math.cos(angle));
    _paintOrb(canvas, Offset(x1, y1), size.width * 0.58,
        AppColors.primary.withValues(alpha: 0.07));

    // Amber orb — counter-drifts in the lower-right region
    final x2 = size.width  * (0.76 + 0.10 * math.cos(angle + 1.6));
    final y2 = size.height * (0.68 + 0.11 * math.sin(angle + 1.6));
    _paintOrb(canvas, Offset(x2, y2), size.width * 0.52,
        AppColors.warning.withValues(alpha: 0.05));
  }

  @override
  bool shouldRepaint(_AmbientOrbs old) => old.t != t;
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
