import 'package:flutter/material.dart';
import '../models/alert.dart';
import '../services/alert_service.dart';
import '../theme/app_theme.dart';
import '../widgets/alert_card.dart';
import '../widgets/risk_gauge.dart';
import '../widgets/section_header.dart';
import 'alert_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  final String companyId;

  const DashboardScreen({super.key, required this.companyId});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _alertService = AlertService();

  void _openAlert(Alert alert) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AlertDetailScreen(alert: alert, companyId: widget.companyId)),
    );
  }

  int _teamRiskScore(List<Alert> alerts) {
    final pending = alerts.where((a) => a.status == AlertStatus.pending);
    if (pending.isEmpty) return 0;
    final avg = pending.map((a) => a.riskScore).reduce((a, b) => a + b) / pending.length;
    return avg.round();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/branding/icon128.png', height: 26),
            const SizedBox(width: AppSpacing.sm),
            Text('Redactr', style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      ),
      body: StreamBuilder<List<Alert>>(
        stream: _alertService.watchAlerts(widget.companyId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }

          final alerts = snapshot.data ?? [];
          final score = _teamRiskScore(alerts);
          final recent = alerts.take(3).toList();
          final pendingCount = alerts.where((a) => a.status == AlertStatus.pending).length;

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.xl),
                decoration: AppTheme.elevatedCardDecoration(),
                child: Row(
                  children: [
                    RiskGauge(score: score, showLabel: false),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Team risk score', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            '$pendingCount alert(s) awaiting review',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            RiskGauge.labelFor(score),
                            style: TextStyle(
                              color: RiskGauge.colorFor(score),
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(title: 'Recent activity'),
              if (alerts.isEmpty)
                Text(
                  'No alerts yet — they\'ll show up here as soon as the extension blocks something.',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                Column(
                  spacing: AppSpacing.sm,
                  children: recent
                      .map((alert) => AlertCard(alert: alert, onTap: () => _openAlert(alert)))
                      .toList(),
                ),
            ],
          );
        },
      ),
    );
  }
}
