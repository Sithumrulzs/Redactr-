import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'animated_entrance.dart';

class StatCard extends StatelessWidget {
  final String label;
  final int value;
  final String? delta;
  final IconData icon;
  final Color color;
  final int entranceDelayMs;
  final VoidCallback? onTap;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.delta,
    this.entranceDelayMs = 0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedEntrance(
      delay: Duration(milliseconds: entranceDelayMs),
      beginOffset: const Offset(0, 0.08),
      child: PressScale(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: AppTheme.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, color: color, size: 19),
                  ),
                  if (delta != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.success.withValues(alpha: 0.25)),
                      ),
                      child: Text(
                        delta!,
                        style: const TextStyle(
                          color: AppColors.success,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TweenAnimationBuilder<int>(
                tween: IntTween(begin: 0, end: value),
                duration: AppDurations.xslow,
                curve: Curves.easeOutCubic,
                builder: (context, animVal, _) => Text(
                  animVal >= 1000
                      ? '${(animVal / 1000).toStringAsFixed(1)}k'
                      : '$animVal',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(fontSize: 26),
                ),
              ),
              const SizedBox(height: 3),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
