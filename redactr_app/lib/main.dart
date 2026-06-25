import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'screens/alerts_screen.dart';
import 'screens/biometric_gate_screen.dart';
import 'screens/company_setup_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/insights_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/sign_in_screen.dart';
import 'screens/splash_screen.dart';
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

/// Shared cross-fade + soft scale-in used everywhere the app switches
/// between top-level screens driven by auth/profile state (splash -> sign
/// in -> biometric -> dashboard) instead of a Navigator push, so those
/// switches don't just hard-cut.
Widget _premiumTransition(Widget child, Animation<double> animation) {
  return FadeTransition(
    opacity: animation,
    child: ScaleTransition(
      scale: Tween(begin: 0.98, end: 1.0).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
      child: child,
    ),
  );
}

const _transitionDuration = Duration(milliseconds: 450);

/// Always shows the splash animation first, then routes to [SignInScreen] or
/// [RootShell] depending on Firebase Auth state. If Firebase hasn't been
/// configured yet (no google-services.json / Gradle plugin wired in — see
/// the project plan's setup checkpoint), sign-in is unavailable but the rest
/// of the app's UI still renders rather than crashing.
///
/// Also gates a [BiometricGateScreen] in front of the dashboard — but only
/// when Firebase's *first* authStateChanges event already has a user (i.e.
/// a persisted session was restored on a cold app start). A live sign-in
/// during the same run (the initial sign-up flow) never triggers it — that
/// first event would be null in that case, since there's no session yet to
/// restore.
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
    Firebase.initializeApp().then((_) {
      if (mounted) setState(() => _firebaseReady = true);
      _authService.authStateChanges.first.then((user) {
        if (mounted) setState(() => _requiresBiometric = user != null);
      });
    }).catchError((error) {
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
      content = SplashScreen(onFinished: () => setState(() => _showSplash = false));
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
              // Still determining whether this was a restored session.
              inner = _loadingScreen;
            } else if (_requiresBiometric! && !_biometricPassed) {
              inner = BiometricGateScreen(onSuccess: () => setState(() => _biometricPassed = true));
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

/// Once signed in, checks whether this user already has a `users/{uid}`
/// Firestore doc (i.e. already belongs to a company). If not, shows
/// [CompanySetupScreen] first — [CompanySetupScreen.onCompanyReady]
/// triggers [_refresh] once the claimOrJoinCompany Cloud Function call
/// succeeds, re-checking the profile without needing a full sign-out/in.
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
    _profileFuture = _companyService.getUserProfile(widget.uid);
    _registerFcmToken();
  }

  void _refresh() {
    setState(() {
      _profileFuture = _companyService.getUserProfile(widget.uid);
    });
  }

  /// Best-effort — push notifications are a nice-to-have (see createAlert
  /// in firebase/functions/index.js), never block sign-in or company
  /// setup if this fails (e.g. the users/{uid} doc doesn't exist yet for
  /// a brand-new user, or the user denies the permission prompt).
  Future<void> _registerFcmToken() async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      final token = await messaging.getToken();
      if (token != null) {
        await _companyService.saveFcmToken(widget.uid, token);
      }
    } catch (_) {
      // Ignored — see comment above.
    }
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
            body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
          );
        } else if (snapshot.data == null) {
          inner = CompanySetupScreen(onCompanyReady: _refresh);
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

class RootShell extends StatefulWidget {
  final String companyId;

  const RootShell({super.key, required this.companyId});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      DashboardScreen(companyId: widget.companyId),
      AlertsScreen(companyId: widget.companyId),
      InsightsScreen(companyId: widget.companyId),
      SettingsScreen(companyId: widget.companyId),
    ];

    return Scaffold(
      body: screens[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.shield_outlined), selectedIcon: Icon(Icons.shield), label: 'Alerts'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Insights'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
