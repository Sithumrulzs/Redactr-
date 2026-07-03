import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_entrance.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen>
    with TickerProviderStateMixin {
  final _authService = AuthService();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _isSignUpMode = false;
  bool _isSubmitting = false;
  bool _obscurePassword = true;
  bool _emailFocused = false;
  bool _passwordFocused = false;
  String? _error;
  bool _showSuccess = false;

  // Breathing glow controller
  late final AnimationController _glowCtrl;
  late final Animation<double> _glowAnim;

  // Shake controller for error
  late final AnimationController _shakeCtrl;
  late final Animation<double> _shakeAnim;

  // Success scale
  late final AnimationController _successCtrl;
  late final Animation<double> _successScale;

  // Floating particles
  final _random = math.Random(42);

  @override
  void initState() {
    super.initState();

    _glowCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800))
      ..repeat(reverse: true);
    _glowAnim = CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut);

    _shakeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 480));
    _shakeAnim = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -10.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10.0, end: 10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10.0, end: -8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 6.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.easeInOut));

    _successCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _successScale = CurvedAnimation(parent: _successCtrl, curve: Curves.easeOutBack);

    _emailFocus.addListener(() => setState(() => _emailFocused = _emailFocus.hasFocus));
    _passwordFocus.addListener(() => setState(() => _passwordFocused = _passwordFocus.hasFocus));
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    _shakeCtrl.dispose();
    _successCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  String? _friendlyError(Object error) {
    if (error is! FirebaseAuthException) return 'Something went wrong. Please try again.';
    switch (error.code) {
      case 'email-already-in-use': return 'An account already exists for that email.';
      case 'weak-password':         return 'Password must be at least 6 characters.';
      case 'invalid-email':         return 'That doesn\'t look like a valid email.';
      case 'user-not-found':
      case 'invalid-credential':
      case 'wrong-password':        return 'Email or password is incorrect.';
      default:                      return 'Something went wrong. Please try again.';
    }
  }

  Future<void> _submitEmailForm() async {
    final email    = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (!email.contains('@') || !email.contains('.')) {
      _setError('Enter a valid email address.');
      return;
    }
    if (password.length < 6) {
      _setError('Password must be at least 6 characters.');
      return;
    }
    setState(() { _isSubmitting = true; _error = null; });
    try {
      if (_isSignUpMode) {
        await _authService.signUpWithEmail(email, password);
      } else {
        await _authService.signInWithEmail(email, password);
      }
      _showSuccessAnimation();
    } catch (e) {
      if (!mounted) return;
      setState(() { _isSubmitting = false; });
      _setError(_friendlyError(e));
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() { _isSubmitting = true; _error = null; });
    try {
      final result = await _authService.signInWithGoogle();
      if (result == null && mounted) {
        setState(() => _isSubmitting = false);
      } else {
        _showSuccessAnimation();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _isSubmitting = false; });
      _setError('Sign-in failed. Please try again.');
    }
  }

  void _setError(String? msg) {
    setState(() => _error = msg);
    if (msg != null) {
      _shakeCtrl.forward(from: 0);
    }
  }

  void _showSuccessAnimation() {
    setState(() => _showSuccess = true);
    _successCtrl.forward();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // ── Animated radial glow background ──────────────────────────────
          AnimatedBuilder(
            animation: _glowAnim,
            builder: (_, __) => Positioned(
              top: -size.height * 0.15,
              left: size.width * 0.1,
              right: size.width * 0.1,
              child: Container(
                height: size.height * 0.6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.10 + 0.06 * _glowAnim.value),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Floating particles ────────────────────────────────────────────
          ...List.generate(12, (i) => _FloatingParticle(
            seed: i,
            random: _random,
            screenSize: size,
          )),

          // ── Form content ──────────────────────────────────────────────────
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: AnimatedBuilder(
                animation: _shakeAnim,
                builder: (_, child) => Transform.translate(
                  offset: Offset(_shakeAnim.value, 0),
                  child: child,
                ),
                child: Column(
                  children: [
                    SizedBox(height: size.height * 0.10),

                    // Logo
                    AnimatedEntrance(
                      delay: const Duration(milliseconds: 100),
                      beginOffset: const Offset(0, -0.06),
                      child: Column(
                        children: [
                          SvgPicture.asset(
                            'assets/branding/redactr-logo-reverse.svg',
                            height: 36,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          const Text(
                            'On-device leak protection for your team',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: size.height * 0.07),

                    // Mode toggle pill
                    AnimatedEntrance(
                      delay: const Duration(milliseconds: 220),
                      child: _ModePill(
                        isSignUp: _isSignUpMode,
                        onToggle: () => setState(() {
                          _isSignUpMode = !_isSignUpMode;
                          _error = null;
                        }),
                      ),
                    ),

                    const SizedBox(height: AppSpacing.xl),

                    // Email field
                    AnimatedEntrance(
                      delay: const Duration(milliseconds: 300),
                      child: _AnimatedField(
                        controller: _emailCtrl,
                        focusNode: _emailFocus,
                        isFocused: _emailFocused,
                        hint: 'Email address',
                        icon: Icons.mail_outline_rounded,
                        keyboardType: TextInputType.emailAddress,
                      ),
                    ),

                    const SizedBox(height: AppSpacing.md),

                    // Password field
                    AnimatedEntrance(
                      delay: const Duration(milliseconds: 360),
                      child: _AnimatedField(
                        controller: _passwordCtrl,
                        focusNode: _passwordFocus,
                        isFocused: _passwordFocused,
                        hint: 'Password',
                        icon: Icons.lock_outline_rounded,
                        obscure: _obscurePassword,
                        suffix: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: AppColors.textDim,
                            size: 20,
                          ),
                          onPressed: () =>
                              setState(() => _obscurePassword = !_obscurePassword),
                        ),
                        onSubmitted: (_) => _submitEmailForm(),
                      ),
                    ),

                    const SizedBox(height: AppSpacing.xl),

                    // Primary button
                    AnimatedEntrance(
                      delay: const Duration(milliseconds: 420),
                      child: _PrimaryButton(
                        label: _isSignUpMode ? 'Create account' : 'Sign in',
                        isLoading: _isSubmitting,
                        onTap: _submitEmailForm,
                      ),
                    ),

                    const SizedBox(height: AppSpacing.lg),

                    // OR divider
                    AnimatedEntrance(
                      delay: const Duration(milliseconds: 480),
                      child: Row(
                        children: [
                          const Expanded(child: Divider(color: AppColors.border)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                            child: Text(
                              'or continue with',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                          const Expanded(child: Divider(color: AppColors.border)),
                        ],
                      ),
                    ),

                    const SizedBox(height: AppSpacing.lg),

                    // Google button
                    AnimatedEntrance(
                      delay: const Duration(milliseconds: 530),
                      child: _GoogleButton(
                        isLoading: _isSubmitting,
                        onTap: _signInWithGoogle,
                      ),
                    ),

                    // Error message
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.lg),
                      AnimatedEntrance(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(
                                color: AppColors.danger.withValues(alpha: 0.35)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded,
                                  color: AppColors.danger, size: 16),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: const TextStyle(
                                      color: AppColors.danger, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    SizedBox(height: size.height * 0.06),
                  ],
                ),
              ),
            ),
          ),

          // ── Success overlay ───────────────────────────────────────────────
          if (_showSuccess)
            ScaleTransition(
              scale: _successScale,
              child: Container(
                color: AppColors.background,
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.success.withValues(alpha: 0.15),
                        border: Border.all(
                            color: AppColors.success.withValues(alpha: 0.4),
                            width: 2),
                      ),
                      child: const Icon(Icons.check_rounded,
                          color: AppColors.success, size: 40),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      _isSignUpMode ? 'Account created!' : 'Welcome back!',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Mode pill (Sign in / Sign up) ─────────────────────────────────────────────

class _ModePill extends StatelessWidget {
  final bool isSignUp;
  final VoidCallback onToggle;

  const _ModePill({required this.isSignUp, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _pill('Sign in', !isSignUp, () { if (isSignUp) onToggle(); }),
          _pill('Create account', isSignUp, () { if (!isSignUp) onToggle(); }),
        ],
      ),
    );
  }

  Widget _pill(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppDurations.base,
          curve: AppCurves.spring,
          margin: const EdgeInsets.all(3),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          alignment: Alignment.center,
          child: AnimatedDefaultTextStyle(
            duration: AppDurations.fast,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: active ? AppColors.background : AppColors.textMuted,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}

// ── Animated field with focus glow ────────────────────────────────────────────

class _AnimatedField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isFocused;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscure;
  final Widget? suffix;
  final ValueChanged<String>? onSubmitted;

  const _AnimatedField({
    required this.controller,
    required this.focusNode,
    required this.isFocused,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.obscure = false,
    this.suffix,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppDurations.base,
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: isFocused
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.20),
                  blurRadius: 16,
                  spreadRadius: 0,
                ),
              ]
            : [],
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: keyboardType,
        obscureText: obscure,
        onSubmitted: onSubmitted,
        style: const TextStyle(color: AppColors.text, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(
            icon,
            color: isFocused ? AppColors.primary : AppColors.textDim,
            size: 20,
          ),
          suffixIcon: suffix,
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: BorderSide(
              color: isFocused ? AppColors.primary : AppColors.border,
              width: isFocused ? 1.5 : 1,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
        ),
      ),
    );
  }
}

// ── Primary button ────────────────────────────────────────────────────────────

class _PrimaryButton extends StatefulWidget {
  final String label;
  final bool isLoading;
  final VoidCallback onTap;

  const _PrimaryButton({
    required this.label,
    required this.isLoading,
    required this.onTap,
  });

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) { setState(() => _pressed = false); if (!widget.isLoading) widget.onTap(); },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: AppDurations.fast,
        child: AnimatedContainer(
          duration: AppDurations.base,
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primary, AppColors.accent],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(AppRadius.md),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: _pressed ? 0.2 : 0.35),
                blurRadius: _pressed ? 8 : 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: widget.isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.background,
                  ),
                )
              : Text(
                  widget.label,
                  style: const TextStyle(
                    color: AppColors.background,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
        ),
      ),
    );
  }
}

// ── Google button ─────────────────────────────────────────────────────────────

class _GoogleButton extends StatefulWidget {
  final bool isLoading;
  final VoidCallback onTap;
  const _GoogleButton({required this.isLoading, required this.onTap});

  @override
  State<_GoogleButton> createState() => _GoogleButtonState();
}

class _GoogleButtonState extends State<_GoogleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) { setState(() => _pressed = false); if (!widget.isLoading) widget.onTap(); },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: AppDurations.fast,
        child: Container(
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.md),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _pressed ? 0.05 : 0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.login_rounded, color: Color(0xFF1F1F1F), size: 20),
              const SizedBox(width: 10),
              const Text(
                'Continue with Google',
                style: TextStyle(
                  color: Color(0xFF1F1F1F),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Floating particle ─────────────────────────────────────────────────────────

class _FloatingParticle extends StatefulWidget {
  final int seed;
  final math.Random random;
  final Size screenSize;

  const _FloatingParticle({
    required this.seed,
    required this.random,
    required this.screenSize,
  });

  @override
  State<_FloatingParticle> createState() => _FloatingParticleState();
}

class _FloatingParticleState extends State<_FloatingParticle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final double _x, _size;
  late final int _speed;

  @override
  void initState() {
    super.initState();
    final r = math.Random(widget.seed * 31 + 7);
    _x = r.nextDouble() * widget.screenSize.width;
    _size = 2.0 + r.nextDouble() * 2.5;
    _speed = 4000 + r.nextInt(5000);

    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _speed),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        final y = widget.screenSize.height * (1 - t);
        final opacity = (math.sin(t * math.pi) * 0.5).clamp(0.0, 0.5);
        return Positioned(
          left: _x,
          top: y,
          child: Opacity(
            opacity: opacity,
            child: Container(
              width: _size,
              height: _size,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary,
              ),
            ),
          ),
        );
      },
    );
  }
}
