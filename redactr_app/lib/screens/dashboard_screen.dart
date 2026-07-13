import 'package:flutter/material.dart';
import '../models/alert.dart';
import '../services/alert_service.dart';
import '../services/company_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/alert_card.dart';
import '../widgets/animated_entrance.dart';
import '../widgets/live_intercept_stream.dart';
import '../widgets/risk_gauge.dart';
import '../widgets/section_header.dart';
import 'alert_detail_screen.dart';
import '../main.dart' show slideRoute;

// Motion constants for the dashboard hero badge
const int    _kBreatheDurationMs = 5500;
const int    _kPingDurationMs    = 450;
const double _kPingScale         = 1.5;

class DashboardScreen extends StatefulWidget {
  final String companyId;
  const DashboardScreen({super.key, required this.companyId});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  final _alertService = AlertService();
  final _companyService = CompanyService();
  final _authService = AuthService();

  String _orgName = '';
  String _greeting = '';

  final _heroIconKey = GlobalKey();
  Rect? _logoFilterRect;

  late final AnimationController _glowCtrl;
  late final AnimationController _filterPulseCtrl;
  late final Animation<double> _glowAnim;
  late final Animation<double> _filterPulseAnim;

  @override
  void initState() {
    super.initState();
    _greeting = _timeGreeting();
    _companyService.getCompanyName(widget.companyId).then((n) {
      if (mounted && n != null) setState(() => _orgName = n);
    });

    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _kBreatheDurationMs),
    )..repeat(reverse: true);
    _glowAnim = CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut);

    _filterPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _kPingDurationMs),
    );
    _filterPulseAnim = CurvedAnimation(
      parent: _filterPulseCtrl,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    _filterPulseCtrl.dispose();
    super.dispose();
  }

  static String _timeGreeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  void _openAlert(Alert alert) => Navigator.of(context).push(
    slideRoute(AlertDetailScreen(alert: alert, companyId: widget.companyId)),
  );

  int _teamRiskScore(List<Alert> alerts) {
    final pending = alerts
        .where((a) => a.status == AlertStatus.pending)
        .toList();
    if (pending.isEmpty) return 0;
    return (pending.map((a) => a.riskScore).reduce((a, b) => a + b) /
            pending.length)
        .round();
  }

  // ── Brand icon: stationary badge + breathing ring + sonar ping ───────────
  Widget _buildHeroIcon() {
    return AnimatedBuilder(
      animation: Listenable.merge([_glowCtrl, _filterPulseCtrl]),
      builder: (context, _) {
        final breathe = _glowAnim.value;       // 0→1 eased, 5 500 ms
        final pingT   = _filterPulseAnim.value; // 0→1 eased, 450 ms

        // 120×120 gives the ping ring room to expand to 1.5× badge radius
        return SizedBox(
          width: 120,
          height: 120,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // ① Badge — perfectly stationary; key used by _updateLogoFilterRect
              Container(
                key: _heroIconKey,
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.08),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.22),
                    width: 1.5,
                  ),
                ),
                padding: const EdgeInsets.all(14),
                child: Image.asset(
                  'assets/branding/icon512.png',
                  fit: BoxFit.contain,
                ),
              ),

              // ② Breathing hairline ring: 1 px stroke, opacity 0.25→0.50,
              //    scale 1.0→1.03 — idle life without any glow or shadow
              IgnorePointer(
                child: Transform.scale(
                  scale: 1.0 + 0.03 * breathe,
                  child: Opacity(
                    opacity: (0.25 + 0.25 * breathe).clamp(0.0, 1.0),
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.primary,
                          width: 1.0,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // ③ Sonar ping: stroke circle, no fill, no blur — emits on intercept
              IgnorePointer(
                child: CustomPaint(
                  size: const Size(120, 120),
                  painter: _SonarPingPainter(pingT),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _updateLogoFilterRect() {
    if (!mounted) return;
    final render = _heroIconKey.currentContext?.findRenderObject();
    if (render is RenderBox) {
      final topLeft = render.localToGlobal(Offset.zero);
      final rect = topLeft & render.size;
      if (_logoFilterRect != rect) {
        setState(() {
          _logoFilterRect = rect;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logoFilterRect == null) {
        _updateLogoFilterRect();
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // ── Layer 1: Ambient intercept stream background ──────────────────
          Positioned.fill(
            child: LiveInterceptStream(
              logoFilterRect: _logoFilterRect,
              onIntercept: () {
                _filterPulseCtrl.forward(from: 0.0);
              },
            ),
          ),

          // ── Layer 2: Dashboard content ────────────────────────────────────
          StreamBuilder<List<Alert>>(
            stream: _alertService.watchAlerts(widget.companyId),
            builder: (context, snapshot) {
              final alerts = snapshot.data ?? [];
              final score = _teamRiskScore(alerts);
              final pendingCount = alerts
                  .where((a) => a.status == AlertStatus.pending)
                  .length;
              final blockedToday = alerts.where((a) {
                final now = DateTime.now();
                final t = a.timestamp;
                return t.year == now.year &&
                    t.month == now.month &&
                    t.day == now.day;
              }).length;
              final approvedCount = alerts
                  .where((a) => a.status == AlertStatus.approved)
                  .length;
              final recent = alerts.take(4).toList();
              final riskColor = RiskGauge.colorFor(score);

              return CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  // ── Hero ─────────────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: SafeArea(
                      bottom: false,
                      child: Column(
                        children: [
                          // Top bar: greeting + avatar
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.xl,
                              AppSpacing.lg,
                              AppSpacing.xl,
                              0,
                            ),
                            child: AnimatedEntrance(
                              delay: const Duration(milliseconds: 60),
                              beginOffset: const Offset(0, -0.04),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _greeting,
                                          style: const TextStyle(
                                            color: AppColors.textMuted,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          user?.displayName?.split(' ').first ??
                                              _orgName,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.headlineSmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Avatar
                                  PressScale(
                                    child: Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: AppColors.primary.withValues(
                                            alpha: 0.4,
                                          ),
                                          width: 1.5,
                                        ),
                                        image: user?.photoURL != null
                                            ? DecorationImage(
                                                image: NetworkImage(
                                                  user!.photoURL!,
                                                ),
                                                fit: BoxFit.cover,
                                              )
                                            : null,
                                        color: AppColors.surfaceAlt,
                                      ),
                                      child: user?.photoURL == null
                                          ? const Icon(
                                              Icons.person_rounded,
                                              color: AppColors.primary,
                                              size: 22,
                                            )
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: AppSpacing.xxl),

                          // Floating brand icon
                          AnimatedEntrance(
                            delay: const Duration(milliseconds: 120),
                            child: _buildHeroIcon(),
                          ),

                          const SizedBox(height: AppSpacing.lg),

                          // "AI-POWERED DATA PROTECTION" label only
                          AnimatedEntrance(
                            delay: const Duration(milliseconds: 180),
                            child: const Text(
                              'AI-POWERED DATA PROTECTION',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.3,
                              ),
                            ),
                          ),

                          const SizedBox(height: AppSpacing.xxl),
                        ],
                      ),
                    ),
                  ),

                  // ── Stat cards ────────────────────────────────────────────
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      0,
                      AppSpacing.xl,
                      0,
                    ),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: AppSpacing.sm,
                            mainAxisSpacing: AppSpacing.sm,
                            mainAxisExtent: 76,
                          ),
                      delegate: SliverChildListDelegate([
                        _GlassStatCard(
                          label: 'Blocked today',
                          value: blockedToday,
                          icon: Icons.shield_outlined,
                          entranceDelayMs: 280,
                        ),
                        _GlassStatCard(
                          label: 'Pending review',
                          value: pendingCount,
                          icon: Icons.pending_outlined,
                          entranceDelayMs: 340,
                        ),
                        _GlassStatCard(
                          label: 'Approved',
                          value: approvedCount,
                          icon: Icons.check_circle_outline,
                          entranceDelayMs: 400,
                        ),
                        _GlassStatCard(
                          label: 'All alerts',
                          value: alerts.length,
                          icon: Icons.notifications_outlined,
                          entranceDelayMs: 460,
                        ),
                      ]),
                    ),
                  ),

                  // ── Risk score card ───────────────────────────────────────
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.xl,
                      AppSpacing.xl,
                      0,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: AnimatedEntrance(
                        delay: const Duration(milliseconds: 520),
                        child: Container(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                riskColor.withValues(alpha: 0.12),
                                AppColors.surface,
                              ],
                            ),
                            border: Border.all(
                              color: riskColor.withValues(alpha: 0.28),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: riskColor.withValues(alpha: 0.09),
                                blurRadius: 20,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              RiskGauge(
                                score: score,
                                showLabel: false,
                                animate: true,
                              ),
                              const SizedBox(width: AppSpacing.xl),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'TEAM RISK SCORE',
                                      style: TextStyle(
                                        color: AppColors.textDim,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.0,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      RiskGauge.labelFor(score),
                                      style: TextStyle(
                                        color: riskColor,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                        height: 1,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '$pendingCount alert${pendingCount == 1 ? '' : 's'} pending',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: AppSpacing.sm),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: riskColor.withValues(
                                          alpha: 0.10,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          AppRadius.sm,
                                        ),
                                        border: Border.all(
                                          color: riskColor.withValues(
                                            alpha: 0.28,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        '$score / 100',
                                        style: TextStyle(
                                          color: riskColor,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ── Recent activity ───────────────────────────────────────
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.xl,
                      AppSpacing.xl,
                      0,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: AnimatedEntrance(
                        delay: const Duration(milliseconds: 580),
                        child: SectionHeader(
                          title: 'Recent activity',
                          trailing: TextButton(
                            onPressed: () {},
                            child: const Text(
                              'See all',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  if (snapshot.connectionState == ConnectionState.waiting)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xl,
                        0,
                        AppSpacing.xl,
                        AppSpacing.lg,
                      ),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) => Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.sm,
                            ),
                            child: SkeletonBox(
                              height: 76,
                              radius: AppRadius.lg,
                            ),
                          ),
                          childCount: 3,
                        ),
                      ),
                    )
                  else if (alerts.isEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xl,
                        0,
                        AppSpacing.xl,
                        AppSpacing.xl,
                      ),
                      sliver: SliverToBoxAdapter(child: _EmptyAlerts()),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xl,
                        0,
                        AppSpacing.xl,
                        AppSpacing.xxl,
                      ),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) => Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.sm,
                            ),
                            child: AlertCard(
                              alert: recent[i],
                              onTap: () => _openAlert(recent[i]),
                              entranceDelayMs: 620 + i * 60,
                            ),
                          ),
                          childCount: recent.length,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Glass stat card — all brand-colored ───────────────────────────────────────

class _GlassStatCard extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final int entranceDelayMs;

  const _GlassStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.entranceDelayMs,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedEntrance(
      delay: Duration(milliseconds: entranceDelayMs),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.surface.withValues(alpha: 0.96),
              AppColors.surface.withValues(alpha: 0.84),
            ],
          ),
          border: Border.all(
            color: AppColors.textMuted.withValues(alpha: 0.16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Icon badge
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: AppColors.textMuted.withValues(alpha: 0.08),
                border: Border.all(
                  color: AppColors.textMuted.withValues(alpha: 0.18),
                ),
              ),
              child: Icon(icon, color: AppColors.textDim, size: 18),
            ),
            const SizedBox(width: 12),
            // Value + label
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TweenAnimationBuilder<int>(
                    tween: IntTween(begin: 0, end: value),
                    duration: AppDurations.xslow,
                    curve: Curves.easeOutCubic,
                    builder: (ctx, v, child) => Text(
                      '$v',
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        height: 1,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyAlerts extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.success.withValues(alpha: 0.08),
            AppColors.surface,
          ],
        ),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.success.withValues(alpha: 0.12),
              border: Border.all(
                color: AppColors.success.withValues(alpha: 0.3),
              ),
            ),
            child: const Icon(
              Icons.verified_rounded,
              color: AppColors.success,
              size: 30,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('All clear', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'No alerts yet — they\'ll appear here once the extension detects something.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

// ── Sonar ping painter ────────────────────────────────────────────────────────
// Stroke-only expanding circle emitted on each node absorption. No fill, no
// blur, no shadow — a crisp ring that grows from the badge edge and fades out.

class _SonarPingPainter extends CustomPainter {
  final double pingT; // 0→1, already eased by _filterPulseAnim (easeOutCubic)

  const _SonarPingPainter(this.pingT);

  @override
  void paint(Canvas canvas, Size size) {
    if (pingT <= 0) return;
    final center      = size.center(Offset.zero);
    final badgeRadius = 76.0 / 2;
    // Scale badge radius from 1.0× to _kPingScale× as pingT goes 0→1
    final radius  = badgeRadius * (1.0 + (_kPingScale - 1.0) * pingT);
    final opacity = (0.9 * (1.0 - pingT)).clamp(0.0, 1.0);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color       = AppColors.primary.withValues(alpha: opacity),
    );
  }

  @override
  bool shouldRepaint(_SonarPingPainter old) => old.pingT != pingT;
}
