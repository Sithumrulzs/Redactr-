import 'package:flutter/material.dart';
import '../models/alert.dart';
import '../services/alert_service.dart';
import '../theme/app_theme.dart';
import '../widgets/alert_card.dart';
import 'alert_detail_screen.dart';

class AlertsScreen extends StatefulWidget {
  final String companyId;

  const AlertsScreen({super.key, required this.companyId});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  final _alertService = AlertService();
  String _query = '';
  AlertStatus? _statusFilter;

  void _openAlert(Alert alert) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AlertDetailScreen(alert: alert, companyId: widget.companyId)),
    );
  }

  List<Alert> _filter(List<Alert> alerts) {
    final query = _query.trim().toLowerCase();
    return alerts.where((alert) {
      final matchesStatus = _statusFilter == null || alert.status == _statusFilter;
      final matchesQuery = query.isEmpty ||
          alert.employee.toLowerCase().contains(query) ||
          alert.findingType.toLowerCase().contains(query);
      return matchesStatus && matchesQuery;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alerts')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
            child: Column(
              spacing: AppSpacing.sm,
              children: [
                TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: 'Search by employee or finding type',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    filled: true,
                    fillColor: AppColors.surface,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                  ),
                ),
                // Four chips at this label width don't reliably fit
                // alongside the screen's 16px side padding on the
                // narrowest common phones (e.g. 360px Galaxy S8) — a
                // plain Row here would clip/overflow. Scrolling
                // horizontally is the standard Flutter fix for a
                // filter-chip row instead of trying to compress labels.
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip('All', null),
                      const SizedBox(width: AppSpacing.sm),
                      _filterChip('Pending', AlertStatus.pending),
                      const SizedBox(width: AppSpacing.sm),
                      _filterChip('Approved', AlertStatus.approved),
                      const SizedBox(width: AppSpacing.sm),
                      _filterChip('Denied', AlertStatus.denied),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Alert>>(
              stream: _alertService.watchAlerts(widget.companyId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.primary));
                }

                final alerts = _filter(snapshot.data ?? []);
                if (alerts.isEmpty) {
                  return Center(
                    child: Text('No alerts match your filters', style: Theme.of(context).textTheme.bodySmall),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
                  itemCount: alerts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final alert = alerts[index];
                    return AlertCard(alert: alert, onTap: () => _openAlert(alert));
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, AlertStatus? status) {
    final selected = _statusFilter == status;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _statusFilter = status),
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.primary.withValues(alpha: 0.18),
      side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
      labelStyle: TextStyle(
        color: selected ? AppColors.primary : AppColors.textDim,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
      ),
      showCheckmark: false,
    );
  }
}
