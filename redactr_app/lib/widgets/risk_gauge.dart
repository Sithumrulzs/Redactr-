import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Circular 0-100 risk score indicator: a track ring, a colored progress arc,
/// the score centered, and an optional "Low/Medium/High risk" caption below.
class RiskGauge extends StatelessWidget {
  final int score;
  final double size;
  final bool showLabel;

  const RiskGauge({super.key, required this.score, this.size = 88, this.showLabel = true});

  static Color colorFor(int score) {
    if (score >= 70) return AppColors.red;
    if (score >= 30) return AppColors.amber;
    return AppColors.green;
  }

  static String labelFor(int score) {
    if (score >= 70) return 'High risk';
    if (score >= 30) return 'Medium risk';
    return 'Low risk';
  }

  @override
  Widget build(BuildContext context) {
    final color = colorFor(score);

    final gauge = SizedBox(
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
              value: (score / 100).clamp(0, 1),
              strokeWidth: 6,
              color: color,
              strokeCap: StrokeCap.round,
              backgroundColor: Colors.transparent,
            ),
          ),
          Text(
            '$score',
            style: TextStyle(color: color, fontSize: size * 0.28, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );

    if (!showLabel) return gauge;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        gauge,
        const SizedBox(height: AppSpacing.sm),
        Text(labelFor(score), style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
