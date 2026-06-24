import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'screens/alerts_screen.dart';
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
      home: const AuthGate(),
    );
  }
}

/// Always shows the splash animation first, then routes to [SignInScreen] or
/// [RootShell] depending on Firebase Auth state. If Firebase hasn't been
/// configured yet (no google-services.json / Gradle plugin wired in — see
/// the project plan's setup checkpoint), sign-in is unavailable but the rest
/// of the app's UI still renders rather than crashing.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _showSplash = true;
  bool _firebaseReady = false;
  Object? _firebaseError;
  final _authService = AuthService();

  @override
  void initState() {
    super.initState();
    Firebase.initializeApp().then((_) {
      if (mounted) setState(() => _firebaseReady = true);
    }).catchError((error) {
      if (mounted) setState(() => _firebaseError = error);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showSplash) {
      return SplashScreen(onFinished: () => setState(() => _showSplash = false));
    }

    if (_firebaseError != null) {
      return const Scaffold(
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
    }

    if (!_firebaseReady) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    return StreamBuilder<User?>(
      stream: _authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
          );
        }
        final user = snapshot.data;
        return user == null ? const SignInScreen() : _ProfileGate(uid: user.uid);
      },
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
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
          );
        }
        if (snapshot.data == null) {
          return CompanySetupScreen(onCompanyReady: _refresh);
        }
        final companyId = snapshot.data!['companyId'] as String;
        return RootShell(companyId: companyId);
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
