import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/centered_form_page.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _authService = AuthService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isSignUpMode = false;
  bool _isSubmitting = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _friendlyError(Object error) {
    if (error is! FirebaseAuthException) return 'Something went wrong. Please try again.';
    switch (error.code) {
      case 'email-already-in-use':
        return 'An account already exists for that email — try signing in instead.';
      case 'weak-password':
        return 'That password is too weak — use at least 6 characters.';
      case 'invalid-email':
        return 'That doesn\'t look like a valid email address.';
      case 'user-not-found':
      case 'invalid-credential':
      case 'wrong-password':
        return 'Email or password is incorrect.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }

  Future<void> _submitEmailForm() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      if (_isSignUpMode) {
        await _authService.signUpWithEmail(email, password);
      } else {
        await _authService.signInWithEmail(email, password);
      }
      // On success, AuthGate's authStateChanges listener handles navigation.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = _friendlyError(e);
      });
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final result = await _authService.signInWithGoogle();
      if (result == null && mounted) {
        setState(() => _isSubmitting = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = 'Sign-in failed. Please try again.';
      });
    }
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.border),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CenteredFormPage(
        children: [
          Center(child: SvgPicture.asset('assets/branding/redactr-logo-reverse.svg', height: 32)),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'On-device leak protection for your team',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.xxl),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: _fieldDecoration('Email address'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: _fieldDecoration('Password').copyWith(
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: AppColors.textDim,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          ElevatedButton(
            onPressed: _isSubmitting ? null : _submitEmailForm,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.background,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background),
                  )
                : Text(_isSignUpMode ? 'Create account' : 'Sign in'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: _isSubmitting
                ? null
                : () => setState(() {
                      _isSignUpMode = !_isSignUpMode;
                      _error = null;
                    }),
            child: Text(
              _isSignUpMode ? 'Already have an account? Sign in' : "Don't have an account? Sign up",
              style: const TextStyle(color: AppColors.textDim, fontSize: 13),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.red, fontSize: 13)),
          ],
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              const Expanded(child: Divider(color: AppColors.border)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Text('or continue with', style: Theme.of(context).textTheme.labelSmall),
              ),
              const Expanded(child: Divider(color: AppColors.border)),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          ElevatedButton.icon(
            onPressed: _isSubmitting ? null : _signInWithGoogle,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF1F1F1F),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
            ),
            icon: const Icon(Icons.login, size: 20),
            label: const Text('Sign in with Google'),
          ),
        ],
      ),
    );
  }
}
