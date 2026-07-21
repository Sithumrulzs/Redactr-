import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/alert.dart';
import '../services/alert_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_entrance.dart';

class InsightsScreen extends StatefulWidget {
  final String companyId;
  const InsightsScreen({super.key, required this.companyId});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  final _alertService = AlertService();

  static const _typeColors = <String, Color>{
    'AWS_KEY': AppColors.danger,
    'API_KEY': AppColors.danger,
    'CREDIT_CARD': AppColors.warning,
    'SSN': AppColors.danger,
    'EMAIL': AppColors.info,
    'IP_ADDRESS': AppColors.info,
    'PERSON': AppColors.primary,
    'LOCATION': AppColors.primary,
    'PHONE': AppColors.warning,
  };

  Color _colorFor(String type) => _typeColors[type] ?? AppColors.textDim;

  List<BarChartGroupData> _last7DaysBars(List<Alert> alerts) {
    final now = DateTime.now();
    final days = List.generate(
      7,
      (i) => DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: 6 - i)),
    );
    return [
      for (var i = 0; i < days.length; i++)
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: alerts
                  .where((a) {
                    final t = a.timestamp;
                    return t.year == days[i].year &&
                        t.month == days[i].month &&
                        t.day == days[i].day;
                  })
                  .length
                  .toDouble(),
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.accent],
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
              ),
              width: 20,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(6),
              ),
            ),
          ],
        ),
    ];
  }

  Map<String, int> _byFindingType(List<Alert> alerts) {
    final counts = <String, int>{};
    for (final a in alerts) {
      counts[a.findingType] = (counts[a.findingType] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sorted);
  }

  Map<String, int> _byEmployee(List<Alert> alerts) {
    final counts = <String, int>{};
    for (final a in alerts) {
      counts[a.employee] = (counts[a.employee] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sorted.take(5));
  }

  static String _dayLabel(int i) {
    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final now = DateTime.now();
    final idx = (now.weekday - 1 - (6 - i)) % 7;
    return days[idx < 0 ? idx + 7 : idx];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: StreamBuilder<List<Alert>>(
          stream: _alertService.watchAlerts(widget.companyId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              );
            }

            final alerts = snapshot.data ?? [];
            final total = alerts.length;

            return CustomScrollView(
              slivers: [
                // ── Header ──────────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.lg,
                      AppSpacing.lg,
                      0,
                    ),
                    child: AnimatedEntrance(
                      delay: const Duration(milliseconds: 60),
                      beginOffset: const Offset(0, -0.04),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Insights',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Data from your team\'s activity',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Summary stat row ────────────────────────────────────────
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.xl,
                    AppSpacing.lg,
                    0,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: AnimatedEntrance(
                      delay: const Duration(milliseconds: 120),
                      child: Row(
                        children: [
                          _SummaryTile(
                            label: 'Total',
                            value: total,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: AppSpacing.md),
                          _SummaryTile(
                            label: 'Pending',
                            value: alerts
                                .where((a) => a.status == AlertStatus.pending)
                                .length,
                            color: AppColors.warning,
                          ),
                          const SizedBox(width: AppSpacing.md),
                          _SummaryTile(
                            label: 'Resolved',
                            value: alerts
                                .where((a) => a.status != AlertStatus.pending)
                                .length,
                            color: AppColors.success,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                if (alerts.isEmpty) ...[
                  SliverFillRemaining(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xxl),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.primary.withValues(
                                  alpha: 0.10,
                                ),
                              ),
                              child: const Icon(
                                Icons.bar_chart_rounded,
                                color: AppColors.primary,
                                size: 36,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            Text(
                              'No data yet',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              'Charts will appear once the extension starts blocking content.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  // ── 7-day bar chart ──────────────────────────────────────
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.xl,
                      AppSpacing.lg,
                      0,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: AnimatedEntrance(
                        delay: const Duration(milliseconds: 200),
                        child: _ChartCard(
                          title: 'Last 7 days',
                          subtitle: '$total total alerts',
                          child: SizedBox(
                            height: 160,
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: 1),
                              duration: AppDurations.xslow,
                              curve: Curves.easeOutCubic,
                              builder: (context, v, _) => BarChart(
                                BarChartData(
                                  maxY:
                                      (_last7DaysBars(alerts)
                                              .map((g) => g.barRods.first.toY)
                                              .fold(
                                                0.0,
                                                (a, b) => a > b ? a : b,
                                              ) +
                                          2) *
                                      1,
                                  alignment: BarChartAlignment.spaceAround,
                                  gridData: FlGridData(
                                    show: true,
                                    drawVerticalLine: false,
                                    getDrawingHorizontalLine: (_) => FlLine(
                                      color: AppColors.border.withValues(
                                        alpha: 0.4,
                                      ),
                                      strokeWidth: 1,
                                    ),
                                  ),
                                  borderData: FlBorderData(show: false),
                                  titlesData: FlTitlesData(
                                    topTitles: const AxisTitles(
                                      sideTitles: SideTitles(showTitles: false),
                                    ),
                                    rightTitles: const AxisTitles(
                                      sideTitles: SideTitles(showTitles: false),
                                    ),
                                    leftTitles: const AxisTitles(
                                      sideTitles: SideTitles(showTitles: false),
                                    ),
                                    bottomTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        getTitlesWidget: (val, _) => Text(
                                          _dayLabel(val.toInt()),
                                          style: const TextStyle(
                                            color: AppColors.textDim,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  barGroups: _last7DaysBars(alerts)
                                      .map(
                                        (g) => BarChartGroupData(
                                          x: g.x,
                                          barRods: g.barRods
                                              .map(
                                                (r) => BarChartRodData(
                                                  toY: r.toY * v,
                                                  gradient: r.gradient,
                                                  width: r.width,
                                                  borderRadius: r.borderRadius,
                                                ),
                                              )
                                              .toList(),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ── Breakdown pie + legend ───────────────────────────────
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.xl,
                      AppSpacing.lg,
                      0,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: AnimatedEntrance(
                        delay: const Duration(milliseconds: 300),
                        child: _ChartCard(
                          title: 'By finding type',
                          subtitle:
                              '${_byFindingType(alerts).length} categories',
                          child: Column(
                            children: [
                              SizedBox(
                                height: 160,
                                child: TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0, end: 1),
                                  duration: AppDurations.xslow,
                                  curve: Curves.easeOutCubic,
                                  builder: (context, v, _) => PieChart(
                                    PieChartData(
                                      sectionsSpace: 3,
                                      centerSpaceRadius: 40,
                                      sections: [
                                        for (final e in _byFindingType(
                                          alerts,
                                        ).entries)
                                          PieChartSectionData(
                                            value: e.value.toDouble() * v,
                                            color: _colorFor(e.key),
                                            radius: 32,
                                            title: v > 0.8
                                                ? '${(e.value / total * 100).round()}%'
                                                : '',
                                            titleStyle: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Wrap(
                                spacing: AppSpacing.md,
                                runSpacing: AppSpacing.sm,
                                children: [
                                  for (final e in _byFindingType(
                                    alerts,
                                  ).entries)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: _colorFor(e.key),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          '${e.key.replaceAll('_', ' ')} · ${e.value}',
                                          style: const TextStyle(
                                            color: AppColors.textMuted,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ── Top employees ────────────────────────────────────────
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.xl,
                      AppSpacing.lg,
                      AppSpacing.xxl,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: AnimatedEntrance(
                        delay: const Duration(milliseconds: 400),
                        child: _ChartCard(
                          title: 'Most active members',
                          subtitle: 'By alert count',
                          child: Column(
                            children: [
                              for (final e in _byEmployee(alerts).entries)
                                _EmployeeBar(
                                  name: e.key,
                                  count: e.value,
                                  max: _byEmployee(alerts).values.first,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Summary tile ──────────────────────────────────────────────────────────────

class _SummaryTile extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _SummaryTile({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.lg,
        ),
        decoration: AppTheme.cardDecoration(),
        child: Column(
          children: [
            TweenAnimationBuilder<int>(
              tween: IntTween(begin: 0, end: value),
              duration: AppDurations.xslow,
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => Text(
                '$v',
                style: TextStyle(
                  color: color,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

// ── Chart card ────────────────────────────────────────────────────────────────

class _ChartCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: AppTheme.elevatedCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          child,
        ],
      ),
    );
  }
}

// ── Employee bar ──────────────────────────────────────────────────────────────

class _EmployeeBar extends StatelessWidget {
  final String name;
  final int count;
  final int max;

  const _EmployeeBar({
    required this.name,
    required this.count,
    required this.max,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  name,
                  style: Theme.of(context).textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('$count', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: count / max),
              duration: AppDurations.xslow,
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 6,
                backgroundColor: AppColors.border,
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
