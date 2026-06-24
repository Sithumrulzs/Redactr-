import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/alert.dart';
import '../services/alert_service.dart';
import '../theme/app_theme.dart';
import '../widgets/section_header.dart';

/// Charts over the same AlertService.watchAlerts(companyId) stream that
/// already powers Dashboard/Alerts — no new Cloud Function or stored
/// aggregate, just client-side grouping of data that's already live.
class InsightsScreen extends StatefulWidget {
  final String companyId;

  const InsightsScreen({super.key, required this.companyId});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  final _alertService = AlertService();

  static const _typeColors = {
    'AWS_KEY': AppColors.red,
    'API_KEY': AppColors.red,
    'CREDIT_CARD': AppColors.amber,
    'EMAIL': AppColors.primary,
    'IP_ADDRESS': AppColors.primary,
    'PERSON': AppColors.amber,
    'LOCATION': AppColors.amber,
  };

  Color _colorFor(String type) => _typeColors[type] ?? AppColors.textDim;

  List<BarChartGroupData> _last7DaysBars(List<Alert> alerts) {
    final now = DateTime.now();
    final days = List.generate(7, (i) => DateTime(now.year, now.month, now.day).subtract(Duration(days: 6 - i)));
    final counts = {
      for (final day in days)
        day: alerts.where((a) {
          final t = a.timestamp;
          return t.year == day.year && t.month == day.month && t.day == day.day;
        }).length,
    };

    return [
      for (var i = 0; i < days.length; i++)
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: counts[days[i]]!.toDouble(),
              color: AppColors.primary,
              width: 18,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
    ];
  }

  Map<String, int> _byFindingType(List<Alert> alerts) {
    final counts = <String, int>{};
    for (final alert in alerts) {
      counts[alert.findingType] = (counts[alert.findingType] ?? 0) + 1;
    }
    return counts;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Insights')),
      body: StreamBuilder<List<Alert>>(
        stream: _alertService.watchAlerts(widget.companyId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }

          final alerts = snapshot.data ?? [];
          if (alerts.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'No alerts yet — charts will appear once the extension blocks something.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            );
          }

          final byType = _byFindingType(alerts);
          final total = alerts.length;

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              SectionHeader(title: 'Alerts over the last 7 days'),
              Container(
                height: 180,
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: AppTheme.elevatedCardDecoration(),
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    titlesData: const FlTitlesData(
                      topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    barGroups: _last7DaysBars(alerts),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(title: 'Breakdown by finding type'),
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: AppTheme.elevatedCardDecoration(),
                child: Column(
                  children: [
                    SizedBox(
                      height: 160,
                      child: PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 36,
                          sections: [
                            for (final entry in byType.entries)
                              PieChartSectionData(
                                value: entry.value.toDouble(),
                                color: _colorFor(entry.key),
                                title: '${(entry.value / total * 100).round()}%',
                                radius: 36,
                                titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.background),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.md,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final entry in byType.entries)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(color: _colorFor(entry.key), shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 6),
                              Text('${entry.key} (${entry.value})', style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                      ],
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
