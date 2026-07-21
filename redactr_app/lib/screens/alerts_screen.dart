import 'package:flutter/material.dart';
import '../models/alert.dart';
import '../services/alert_service.dart';
import '../theme/app_theme.dart';
import '../widgets/alert_card.dart';
import '../widgets/animated_entrance.dart';
import 'alert_detail_screen.dart';
import '../main.dart' show slideRoute;

class AlertsScreen extends StatefulWidget {
  final String companyId;
  const AlertsScreen({super.key, required this.companyId});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen>
    with SingleTickerProviderStateMixin {
  final _alertService = AlertService();
  String _query = '';
  AlertStatus? _statusFilter;
  late final AnimationController _searchCtrl;
  late final Animation<double> _searchAnim;

  @override
  void initState() {
    super.initState();
    _searchCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _searchAnim = CurvedAnimation(parent: _searchCtrl, curve: AppCurves.spring);
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _searchCtrl.forward();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openAlert(Alert alert) {
    Navigator.of(context).push(
      slideRoute(AlertDetailScreen(alert: alert, companyId: widget.companyId)),
    );
  }

  List<Alert> _filter(List<Alert> alerts) {
    final query = _query.trim().toLowerCase();
    return alerts.where((a) {
      final matchesStatus = _statusFilter == null || a.status == _statusFilter;
      final matchesQuery =
          query.isEmpty ||
          a.employee.toLowerCase().contains(query) ||
          a.findingType.toLowerCase().contains(query);
      return matchesStatus && matchesQuery;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ───────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                0,
              ),
              child: AnimatedEntrance(
                delay: const Duration(milliseconds: 60),
                beginOffset: const Offset(0, -0.04),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Alerts',
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.left,
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Review & manage security events',
                        textAlign: TextAlign.left,
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

            const SizedBox(height: AppSpacing.lg),

            // ── Search bar ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: FadeTransition(
                opacity: _searchAnim,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, 0.08),
                    end: Offset.zero,
                  ).animate(_searchAnim),
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    style: const TextStyle(color: AppColors.text, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search employee or finding type…',
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: AppColors.textDim,
                        size: 20,
                      ),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                Icons.close_rounded,
                                color: AppColors.textDim,
                                size: 18,
                              ),
                              onPressed: () => setState(() => _query = ''),
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.sm),

            // ── Filter chips ─────────────────────────────────────────────────
            AnimatedEntrance(
              delay: const Duration(milliseconds: 200),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Row(
                  children: [
                    _chip('All', null),
                    const SizedBox(width: AppSpacing.sm),
                    _chip('Pending', AlertStatus.pending),
                    const SizedBox(width: AppSpacing.sm),
                    _chip('Approved', AlertStatus.approved),
                    const SizedBox(width: AppSpacing.sm),
                    _chip('Denied', AlertStatus.denied),
                  ],
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            // ── List ─────────────────────────────────────────────────────────
            Expanded(
              child: StreamBuilder<List<Alert>>(
                stream: _alertService.watchAlerts(widget.companyId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                      itemCount: 5,
                      separatorBuilder: (context, _) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, _) =>
                          const SkeletonBox(height: 80, radius: AppRadius.lg),
                    );
                  }

                  final alerts = _filter(snapshot.data ?? []);

                  if (alerts.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xxl),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.primary.withValues(
                                  alpha: 0.10,
                                ),
                              ),
                              child: const Icon(
                                Icons.search_off_rounded,
                                color: AppColors.primary,
                                size: 30,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            Text(
                              'No alerts match your filters',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              'Try adjusting your search or filter.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    itemCount: alerts.length,
                    separatorBuilder: (context, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (_, i) => AlertCard(
                      alert: alerts[i],
                      onTap: () => _openAlert(alerts[i]),
                      entranceDelayMs: i * 40,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, AlertStatus? status) {
    final selected = _statusFilter == status;
    return PressScale(
      onTap: () => setState(() => _statusFilter = status),
      child: AnimatedContainer(
        duration: AppDurations.base,
        curve: AppCurves.spring,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.15)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.primary : AppColors.textMuted,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
