import 'package:flutter/material.dart';
import '../models/alert.dart';
import '../theme/app_theme.dart';
import 'risk_gauge.dart';
import 'status_pill.dart';

class AlertCard extends StatelessWidget {
  final Alert alert;
  final VoidCallback? onTap;

  const AlertCard({super.key, required this.alert, this.onTap});

  static IconData _iconFor(String findingType) {
    switch (findingType) {
      case 'AWS_KEY':
      case 'API_KEY':
        return Icons.vpn_key_rounded;
      case 'CREDIT_CARD':
        return Icons.credit_card_rounded;
      case 'EMAIL':
        return Icons.email_rounded;
      case 'IP_ADDRESS':
        return Icons.public_rounded;
      case 'PERSON':
        return Icons.person_rounded;
      case 'LOCATION':
        return Icons.location_on_rounded;
      default:
        return Icons.shield_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = AppTheme.severityColor(alert.status.name);
    final riskColor = RiskGauge.colorFor(alert.riskScore);

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: riskColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                alignment: Alignment.center,
                child: Icon(_iconFor(alert.findingType), color: riskColor, size: 22),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(alert.employee, style: Theme.of(context).textTheme.titleMedium),
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
                        Text(_relativeTime(alert.timestamp), style: Theme.of(context).textTheme.labelSmall),
                      ],
                    ),
                  ],
                ),
              ),
            ],
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
