import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Cinematic ~5.5s intro: icon scans into view, then "Redact" drops and
/// bounces into place (an elastic curve gives the spring/overshoot-then-
/// settle "jump" feel), then the brand's teal "r" follows with its own
/// glow, dropping in right after. A slow continuous zoom (Ken Burns) and a
/// breathing background glow run under everything for depth. Pure
/// AnimationController/Tween/Stack — no video asset, no extra dependency.
class SplashScreen extends StatefulWidget {
  final VoidCallback onFinished;

  const SplashScreen({super.key, required this.onFinished});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 5800);
  static const _iconSize = 84.0;

  late final AnimationController _controller;
  late final Animation<double> _zoom;
  late final Animation<double> _glowOpacity;
  late final Animation<double> _scanReveal;
  late final Animation<double> _scanLineOpacity;
  late final Animation<double> _iconPulse;
  late final Animation<double> _redactJump;
  late final Animation<double> _rJump;
  late final Animation<double> _rGlow;
  late final Animation<double> _taglineOpacity;
  late final Animation<Offset> _taglineOffset;
  late final Animation<double> _underlineWidth;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration);

    _zoom = Tween(begin: 1.05, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _glowOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.5, curve: Curves.easeOut)),
    );
    _scanReveal = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.03, 0.26, curve: Curves.easeInOut)),
    );
    _scanLineOpacity = Tween(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.21, 0.27, curve: Curves.easeIn)),
    );
    _iconPulse = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.08).chain(CurveTween(curve: Curves.easeOut)), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.08, end: 1.0).chain(CurveTween(curve: Curves.easeIn)), weight: 1),
    ]).animate(CurvedAnimation(parent: _controller, curve: const Interval(0.26, 0.38)));
    // elasticOut overshoots past 1.0 then settles — that overshoot is what
    // reads as a "jump then bounce into place" landing, rather than a
    // smooth reveal.
    _redactJump = CurvedAnimation(parent: _controller, curve: const Interval(0.40, 0.64, curve: Curves.elasticOut));
    _rJump = CurvedAnimation(parent: _controller, curve: const Interval(0.56, 0.82, curve: Curves.elasticOut));
    _rGlow = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOut)), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)), weight: 2),
    ]).animate(CurvedAnimation(parent: _controller, curve: const Interval(0.56, 0.80)));
    _taglineOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.82, 0.92, curve: Curves.easeOut)),
    );
    _taglineOffset = Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.82, 0.92, curve: Curves.easeOut)),
    );
    _underlineWidth = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.92, 0.99, curve: Curves.easeInOut)),
    );

    _controller.forward().whenComplete(widget.onFinished);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Stack(
            children: [
              // Breathing radial glow behind everything.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 0.9,
                      colors: [
                        AppColors.primary.withValues(alpha: 0.18 * _glowOpacity.value),
                        AppColors.background,
                      ],
                    ),
                  ),
                ),
              ),
              // Slow Ken Burns zoom on the whole composition.
              Center(
                child: Transform.scale(
                  scale: _zoom.value,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // --- Icon: scans into view top-down ---
                      Transform.scale(
                        scale: _iconPulse.value,
                        child: SizedBox(
                          width: _iconSize,
                          height: _iconSize,
                          child: Stack(
                            clipBehavior: Clip.hardEdge,
                            children: [
                              ClipRect(
                                clipper: _TopDownClipper(_scanReveal.value),
                                child: Image.asset('assets/branding/icon256.png', width: _iconSize, height: _iconSize),
                              ),
                              if (_scanLineOpacity.value > 0)
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  top: (_iconSize * _scanReveal.value) - 1,
                                  child: Opacity(
                                    opacity: _scanLineOpacity.value,
                                    child: Container(
                                      height: 2,
                                      decoration: BoxDecoration(
                                        color: AppColors.primary,
                                        boxShadow: [
                                          BoxShadow(color: AppColors.primary.withValues(alpha: 0.8), blurRadius: 10, spreadRadius: 1),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      // --- Wordmark: "Redact" drops/bounces into place, then "r" follows ---
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Opacity(
                            opacity: _redactJump.value.clamp(0.0, 1.0),
                            child: Transform.translate(
                              offset: Offset(0, (1 - _redactJump.value) * -36),
                              child: Transform.scale(
                                scale: 0.7 + 0.3 * _redactJump.value,
                                child: const Text(
                                  'Redact',
                                  style: TextStyle(
                                    color: AppColors.text,
                                    fontSize: 36,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Stack(
                            alignment: Alignment.center,
                            clipBehavior: Clip.none,
                            children: [
                              if (_rGlow.value > 0)
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.primary.withValues(alpha: 0.6 * _rGlow.value),
                                        blurRadius: 24,
                                        spreadRadius: 4,
                                      ),
                                    ],
                                  ),
                                ),
                              Opacity(
                                opacity: _rJump.value.clamp(0.0, 1.0),
                                child: Transform.translate(
                                  offset: Offset(0, (1 - _rJump.value) * -36),
                                  child: Transform.scale(
                                    scale: 0.7 + 0.3 * _rJump.value,
                                    child: const Text(
                                      'r',
                                      style: TextStyle(
                                        color: AppColors.primary,
                                        fontSize: 36,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Opacity(
                        opacity: _taglineOpacity.value,
                        child: Transform.translate(
                          offset: Offset(0, _taglineOffset.value.dy * 20),
                          child: Text(
                            'On-device leak protection for your team',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      ClipRect(
                        child: Align(
                          alignment: Alignment.center,
                          widthFactor: _underlineWidth.value,
                          child: Container(width: 56, height: 2, color: AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Reveals its child from the top down as [progress] goes 0 -> 1 — used to
/// make the icon look like it's being scanned into view.
class _TopDownClipper extends CustomClipper<Rect> {
  final double progress;

  _TopDownClipper(this.progress);

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width, size.height * progress.clamp(0.0, 1.0));

  @override
  bool shouldReclip(_TopDownClipper oldClipper) => oldClipper.progress != progress;
}
