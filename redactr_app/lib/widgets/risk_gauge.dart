import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class RiskGauge extends StatelessWidget {
  final int score;
  final double size;
  final bool showLabel;
  final bool animate;

  const RiskGauge({
    super.key,
    required this.score,
    this.size = 88,
    this.showLabel = true,
    this.animate = false,
  });

  static Color colorFor(int score) {
    if (score >= 70) return AppColors.danger;
    if (score >= 30) return AppColors.warning;
    return AppColors.success;
  }

  static String labelFor(int score) {
    if (score >= 70) return 'High risk';
    if (score >= 30) return 'Medium risk';
    return 'Low risk';
  }

  @override
  Widget build(BuildContext context) {
    final color = colorFor(score);

    final gauge = TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: score.toDouble()),
      duration: animate ? AppDurations.xslow : Duration.zero,
      curve: Curves.easeOutCubic,
      builder: (context, animScore, _) {
        final displayScore = animScore.round();
        final displayColor = colorFor(displayScore);
        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: 1,
                  strokeWidth: 6,
                  color: AppColors.border,
                ),
              ),
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: (animScore / 100).clamp(0, 1),
                  strokeWidth: 6,
                  color: displayColor,
                  strokeCap: StrokeCap.round,
                  backgroundColor: Colors.transparent,
                ),
              ),
              Text(
                '$displayScore',
                style: TextStyle(
                  color: displayColor,
                  fontSize: size * 0.28,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      },
    );

    if (!showLabel) return gauge;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        gauge,
        const SizedBox(height: AppSpacing.sm),
        Text(
          labelFor(score),
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
