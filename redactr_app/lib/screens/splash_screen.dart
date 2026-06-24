import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_theme.dart';

/// Premium ~5s intro built around the product's own concept — scanning for
/// leaks — rather than a generic logo fade: a glowing scanline sweeps down
/// over the real brand lockup (redactr-logo-reverse.svg) as it's revealed,
/// followed by a confirmation "ping" bounce, a glossy shimmer pass, the
/// tagline, and a drawn underline. Pure AnimationController/Tween/Stack —
/// no video asset, no new heavy dependency beyond the SVG renderer already
/// added for the real wordmark.
class SplashScreen extends StatefulWidget {
  final VoidCallback onFinished;

  const SplashScreen({super.key, required this.onFinished});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 5200);
  static const _logoWidth = 280.0;
  static const _logoHeight = 66.0; // matches redactr-logo-reverse.svg's 420:100 aspect ratio

  late final AnimationController _controller;
  late final Animation<double> _glowOpacity;
  late final Animation<double> _scanReveal;
  late final Animation<double> _scanLineOpacity;
  late final Animation<double> _logoPulse;
  late final Animation<double> _shimmerX;
  late final Animation<double> _taglineOpacity;
  late final Animation<Offset> _taglineOffset;
  late final Animation<double> _underlineWidth;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration);

    _glowOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.1, curve: Curves.easeOut)),
    );
    _scanReveal = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.04, 0.40, curve: Curves.easeInOut)),
    );
    _scanLineOpacity = Tween(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.32, 0.40, curve: Curves.easeIn)),
    );
    _logoPulse = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.06).chain(CurveTween(curve: Curves.easeOut)), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.06, end: 1.0).chain(CurveTween(curve: Curves.easeIn)), weight: 1),
    ]).animate(CurvedAnimation(parent: _controller, curve: const Interval(0.38, 0.52)));
    _shimmerX = Tween(begin: -0.5, end: 1.5).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.48, 0.70, curve: Curves.easeInOut)),
    );
    _taglineOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.62, 0.80, curve: Curves.easeOut)),
    );
    _taglineOffset = Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.62, 0.80, curve: Curves.easeOut)),
    );
    _underlineWidth = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.80, 0.94, curve: Curves.easeInOut)),
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
              // Soft radial glow breathing in behind everything.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 0.9,
                      colors: [
                        AppColors.primary.withValues(alpha: 0.16 * _glowOpacity.value),
                        AppColors.background,
                      ],
                    ),
                  ),
                ),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.scale(
                      scale: _logoPulse.value,
                      child: SizedBox(
                        width: _logoWidth,
                        height: _logoHeight,
                        child: Stack(
                          clipBehavior: Clip.hardEdge,
                          children: [
                            // The lockup itself, revealed top-to-bottom like a scan.
                            ClipRect(
                              clipper: _TopDownClipper(_scanReveal.value),
                              child: SvgPicture.asset(
                                'assets/branding/redactr-logo-reverse.svg',
                                width: _logoWidth,
                                height: _logoHeight,
                              ),
                            ),
                            // The glowing scanline tracking the reveal boundary.
                            if (_scanLineOpacity.value > 0)
                              Positioned(
                                left: 0,
                                right: 0,
                                top: (_logoHeight * _scanReveal.value) - 1,
                                child: Opacity(
                                  opacity: _scanLineOpacity.value,
                                  child: Container(
                                    height: 2,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.primary.withValues(alpha: 0.8),
                                          blurRadius: 10,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            // Glossy shimmer pass once the lockup is fully revealed.
                            if (_scanReveal.value >= 1.0)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: Align(
                                    alignment: Alignment(_shimmerX.value * 2 - 1, 0),
                                    child: Transform.rotate(
                                      angle: -0.35,
                                      child: Container(
                                        width: _logoWidth * 0.3,
                                        height: _logoHeight * 2,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.centerLeft,
                                            end: Alignment.centerRight,
                                            colors: [
                                              Colors.white.withValues(alpha: 0),
                                              Colors.white.withValues(alpha: 0.35),
                                              Colors.white.withValues(alpha: 0),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
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
            ],
          );
        },
      ),
    );
  }
}

/// Reveals its child from the top down as [progress] goes 0 -> 1 — used to
/// make the logo look like it's being scanned into view.
class _TopDownClipper extends CustomClipper<Rect> {
  final double progress;

  _TopDownClipper(this.progress);

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width, size.height * progress.clamp(0.0, 1.0));

  @override
  bool shouldReclip(_TopDownClipper oldClipper) => oldClipper.progress != progress;
}
