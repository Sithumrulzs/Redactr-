import 'package:flutter/material.dart';
import '../models/alert.dart';
import '../theme/app_theme.dart';
import 'animated_entrance.dart';
import 'risk_gauge.dart';
import 'status_pill.dart';

class AlertCard extends StatelessWidget {
  final Alert alert;
  final VoidCallback? onTap;
  final int entranceDelayMs;

  const AlertCard({
    super.key,
    required this.alert,
    this.onTap,
    this.entranceDelayMs = 0,
  });

  static IconData _iconFor(String findingType) {
    switch (findingType) {
      case 'AWS_KEY':
      case 'API_KEY':
        return Icons.vpn_key_rounded;
      case 'CREDIT_CARD':
        return Icons.credit_card_rounded;
      case 'EMAIL':
        return Icons.email_rounded;
      case 'SSN':
        return Icons.badge_rounded;
      case 'IP_ADDRESS':
        return Icons.public_rounded;
      case 'PERSON':
        return Icons.person_rounded;
      case 'LOCATION':
        return Icons.location_on_rounded;
      case 'PHONE':
        return Icons.phone_rounded;
      default:
        return Icons.shield_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = AppTheme.severityColor(alert.status.name);
    final riskColor = RiskGauge.colorFor(alert.riskScore);

    return AnimatedEntrance(
      delay: Duration(milliseconds: entranceDelayMs),
      beginOffset: const Offset(0, 0.05),
      child: PressScale(
        onTap: onTap,
        child: Container(
          decoration: AppTheme.cardDecoration(),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left accent bar
                      Container(
                        width: 3,
                        height: 56,
                        margin: const EdgeInsets.only(right: AppSpacing.md),
                        decoration: BoxDecoration(
                          color: riskColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      // Icon
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: riskColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        alignment: Alignment.center,
                        child: Icon(_iconFor(alert.findingType), color: riskColor, size: 20),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(alert.employee, style: Theme.of(context).textTheme.titleSmall),
                            const SizedBox(height: 2),
                            Text(
                              alert.whatWasBlocked,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Row(
                              children: [
                                StatusPill(label: alert.statusLabel, color: statusColor),
                                const SizedBox(width: AppSpacing.sm),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceAlt,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    alert.findingType.replaceAll('_', ' '),
                                    style: const TextStyle(
                                      color: AppColors.textDim,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                Text(_relativeTime(alert.timestamp), style: Theme.of(context).textTheme.labelSmall),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      const Icon(Icons.chevron_right_rounded, color: AppColors.textDim, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
