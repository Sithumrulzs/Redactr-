import 'package:flutter/material.dart';
import '../models/alert.dart';
import '../services/alert_service.dart';
import '../theme/app_theme.dart';
import '../widgets/risk_gauge.dart';
import '../widgets/status_pill.dart';

class AlertDetailScreen extends StatefulWidget {
  final Alert alert;
  final String companyId;

  const AlertDetailScreen({super.key, required this.alert, required this.companyId});

  @override
  State<AlertDetailScreen> createState() => _AlertDetailScreenState();
}

class _AlertDetailScreenState extends State<AlertDetailScreen> {
  final _alertService = AlertService();
  bool _isUpdating = false;

  Future<void> _setStatus(AlertStatus status) async {
    setState(() => _isUpdating = true);
    try {
      await _alertService.updateStatus(widget.companyId, widget.alert.id, status);
      setState(() {
        widget.alert.status = status;
        _isUpdating = false;
      });
    } catch (e) {
      setState(() => _isUpdating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update this alert. Please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final alert = widget.alert;
    final statusColor = AppTheme.severityColor(alert.status.name);

    return Scaffold(
      appBar: AppBar(title: const Text('Alert detail')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: AppTheme.elevatedCardDecoration(),
            child: Column(
              children: [
                RiskGauge(score: alert.riskScore, size: 96),
                const SizedBox(height: AppSpacing.lg),
                Text(alert.employee, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  alert.whatWasBlocked,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _infoChip('Type', alert.findingType),
                    const SizedBox(width: AppSpacing.sm),
                    StatusPill(label: alert.statusLabel, color: statusColor),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Detected ${alert.timestamp}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isUpdating ? null : () => _setStatus(AlertStatus.approved),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.background,
                  ),
                  icon: const Icon(Icons.check),
                  label: const Text('Approve'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isUpdating ? null : () => _setStatus(AlertStatus.denied),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.red,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.close),
                  label: const Text('Deny'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Text('$label: $value', style: const TextStyle(fontSize: 12)),
    );
  }
}
