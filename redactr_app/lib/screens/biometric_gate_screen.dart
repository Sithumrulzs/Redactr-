import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../theme/app_theme.dart';
import '../widgets/centered_form_page.dart';

/// Shown on app cold-start when Firebase already has a persisted signed-in
/// session (see AuthGate in main.dart — this never appears during the live
/// sign-up flow itself, only on a *later* app open). Uses local_auth, which
/// automatically adapts to whatever the device supports — fingerprint,
/// face unlock, iris, or a fallback to the device's PIN/pattern/password —
/// without any per-platform branching here.
class BiometricGateScreen extends StatefulWidget {
  final VoidCallback onSuccess;

  const BiometricGateScreen({super.key, required this.onSuccess});

  @override
  State<BiometricGateScreen> createState() => _BiometricGateScreenState();
}

class _BiometricGateScreenState extends State<BiometricGateScreen> {
  final _localAuth = LocalAuthentication();
  bool _isAuthenticating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _attemptUnlock();
  }

  Future<void> _attemptUnlock() async {
    setState(() {
      _isAuthenticating = true;
      _error = null;
    });

    try {
      // No fingerprint/face/PIN/pattern set up at all on this device —
      // nothing to gate against, so don't lock the user out of the app.
      final supported = await _localAuth.isDeviceSupported();
      if (!supported) {
        widget.onSuccess();
        return;
      }

      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Unlock Redactr',
        options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
      );

      if (didAuthenticate) {
        widget.onSuccess();
      } else if (mounted) {
        setState(() => _isAuthenticating = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isAuthenticating = false;
        _error = 'Could not verify. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CenteredFormPage(
        children: [
          Center(child: Image.asset('assets/branding/icon256.png', width: 72, height: 72)),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Unlock Redactr',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Verify it\'s you to continue',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.red, fontSize: 13)),
          ],
          const SizedBox(height: AppSpacing.xl),
          ElevatedButton.icon(
            onPressed: _isAuthenticating ? null : _attemptUnlock,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.background,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: _isAuthenticating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background),
                  )
                : const Icon(Icons.fingerprint),
            label: Text(_isAuthenticating ? 'Verifying…' : 'Unlock'),
          ),
        ],
      ),
    );
  }
}
