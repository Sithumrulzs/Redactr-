import 'package:flutter/material.dart';
import '../models/alert.dart';
import '../services/alert_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_entrance.dart';
import '../widgets/risk_gauge.dart';
import '../widgets/status_pill.dart';

class AlertDetailScreen extends StatefulWidget {
  final Alert alert;
  final String companyId;

  const AlertDetailScreen({super.key, required this.alert, required this.companyId});

  @override
  State<AlertDetailScreen> createState() => _AlertDetailScreenState();
}

class _AlertDetailScreenState extends State<AlertDetailScreen>
    with SingleTickerProviderStateMixin {
  final _alertService = AlertService();
  bool _isUpdating = false;

  // Success overlay
  late final AnimationController _successCtrl;
  late final Animation<double> _successScale;
  AlertStatus? _completedAction;

  @override
  void initState() {
    super.initState();
    _successCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _successScale =
        CurvedAnimation(parent: _successCtrl, curve: Curves.easeOutBack);
  }

  @override
  void dispose() {
    _successCtrl.dispose();
    super.dispose();
  }

  Future<void> _setStatus(AlertStatus status) async {
    setState(() => _isUpdating = true);
    try {
      await _alertService.updateStatus(
          widget.companyId, widget.alert.id, status);
      setState(() {
        widget.alert.status = status;
        _isUpdating = false;
        _completedAction = status;
      });
      await _successCtrl.forward();
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _isUpdating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update. Please try again.')),
        );
      }
    }
  }

  static String _findingLabel(String type) =>
      type.replaceAll('_', ' ').toLowerCase().split(' ').map((w) {
        if (w.isEmpty) return w;
        return '${w[0].toUpperCase()}${w.substring(1)}';
      }).join(' ');

  static IconData _iconFor(String type) {
    switch (type) {
      case 'AWS_KEY':
      case 'API_KEY':     return Icons.vpn_key_rounded;
      case 'CREDIT_CARD': return Icons.credit_card_rounded;
      case 'SSN':         return Icons.badge_rounded;
      case 'EMAIL':       return Icons.email_rounded;
      case 'IP_ADDRESS':  return Icons.public_rounded;
      case 'PERSON':      return Icons.person_rounded;
      case 'LOCATION':    return Icons.location_on_rounded;
      case 'PHONE':       return Icons.phone_rounded;
      default:            return Icons.shield_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final alert       = widget.alert;
    final statusColor = AppTheme.severityColor(alert.status.name);
    final riskColor   = RiskGauge.colorFor(alert.riskScore);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Alert detail'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              // ── Hero risk card ─────────────────────────────────────────────
              AnimatedEntrance(
                delay: const Duration(milliseconds: 60),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  decoration: AppTheme.glowCardDecoration(glowColor: riskColor),
                  child: Column(
                    children: [
                      // Icon + type
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: riskColor.withValues(alpha: 0.15),
                          border: Border.all(
                              color: riskColor.withValues(alpha: 0.4)),
                        ),
                        alignment: Alignment.center,
                        child: Icon(_iconFor(alert.findingType),
                            color: riskColor, size: 28),
                      ),
                      const SizedBox(height: AppSpacing.md),

                      Text(_findingLabel(alert.findingType),
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          )),
                      const SizedBox(height: AppSpacing.xs),

                      // Animated risk gauge
                      RiskGauge(
                          score: alert.riskScore,
                          size: 100,
                          showLabel: true,
                          animate: true),

                      const SizedBox(height: AppSpacing.lg),

                      // Employee
                      Text(alert.employee,
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: AppSpacing.sm),

                      Text(
                        alert.whatWasBlocked,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textMuted),
                      ),

                      const SizedBox(height: AppSpacing.lg),

                      // Status pill + timestamp
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          StatusPill(
                              label: alert.statusLabel, color: statusColor),
                          const SizedBox(width: AppSpacing.md),
                          Text(
                            _formatTime(alert.timestamp),
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.xl),

              // ── Info row ───────────────────────────────────────────────────
              AnimatedEntrance(
                delay: const Duration(milliseconds: 180),
                child: Row(
                  children: [
                    _InfoTile(
                        label: 'Risk score',
                        value: '${alert.riskScore}/100',
                        icon: Icons.monitor_heart_rounded,
                        color: riskColor),
                    const SizedBox(width: AppSpacing.md),
                    _InfoTile(
                        label: 'Finding type',
                        value: _findingLabel(alert.findingType),
                        icon: _iconFor(alert.findingType),
                        color: AppColors.info),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.xl),

              // ── Action buttons ─────────────────────────────────────────────
              if (alert.status == AlertStatus.pending) ...[
                AnimatedEntrance(
                  delay: const Duration(milliseconds: 280),
                  child: _ActionButton(
                    label: 'Approve — allow this content',
                    icon: Icons.check_circle_rounded,
                    color: AppColors.success,
                    isLoading: _isUpdating,
                    onTap: () => _setStatus(AlertStatus.approved),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                AnimatedEntrance(
                  delay: const Duration(milliseconds: 340),
                  child: _ActionButton(
                    label: 'Deny — block this content',
                    icon: Icons.cancel_rounded,
                    color: AppColors.danger,
                    isLoading: _isUpdating,
                    onTap: () => _setStatus(AlertStatus.denied),
                  ),
                ),
              ] else
                AnimatedEntrance(
                  delay: const Duration(milliseconds: 280),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(
                          color: statusColor.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          alert.status == AlertStatus.approved
                              ? Icons.check_circle_rounded
                              : Icons.cancel_rounded,
                          color: statusColor,
                          size: 20,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          'This alert was ${alert.status.name}',
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: AppSpacing.xxl),
            ],
          ),

          // ── Action success overlay ─────────────────────────────────────────
          if (_completedAction != null)
            ScaleTransition(
              scale: _successScale,
              child: Container(
                color: AppColors.background.withValues(alpha: 0.95),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: (_completedAction == AlertStatus.approved
                                ? AppColors.success
                                : AppColors.danger)
                            .withValues(alpha: 0.15),
                      ),
                      child: Icon(
                        _completedAction == AlertStatus.approved
                            ? Icons.check_rounded
                            : Icons.close_rounded,
                        color: _completedAction == AlertStatus.approved
                            ? AppColors.success
                            : AppColors.danger,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      _completedAction == AlertStatus.approved
                          ? 'Alert approved'
                          : 'Alert denied',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)   return '${diff.inHours}h ago';
    return '${t.day}/${t.month}/${t.year}';
  }
}

// ── Info tile ─────────────────────────────────────────────────────────────────

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _InfoTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: AppTheme.cardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: AppSpacing.sm),
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: color)),
            const SizedBox(height: 2),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

// ── Action button ─────────────────────────────────────────────────────────────

class _ActionButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isLoading;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.isLoading,
    required this.onTap,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp:   (_) { setState(() => _pressed = false); if (!widget.isLoading) widget.onTap(); },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: AppDurations.fast,
        child: AnimatedContainer(
          duration: AppDurations.base,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: _pressed ? 0.7 : 1.0),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: _pressed ? 0.15 : 0.28),
                blurRadius: _pressed ? 6 : 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: widget.isLoading
              ? const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(widget.icon, color: Colors.white, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      widget.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
