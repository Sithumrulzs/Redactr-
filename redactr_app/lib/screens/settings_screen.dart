import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/company_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_entrance.dart';
import 'custom_keywords_screen.dart';
import 'invite_employee_screen.dart';
import 'policy_screen.dart';
import 'team_screen.dart';
import '../main.dart' show slideRoute;

const _kAppVersion = '2.0.0';

class SettingsScreen extends StatefulWidget {
  final String companyId;
  const SettingsScreen({super.key, required this.companyId});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  final _authService    = AuthService();
  final _companyService = CompanyService();
  bool _notificationsEnabled = true;
  bool _signingOut = false;
  bool _deletingAccount = false;
  late final _entitlementFuture = _companyService.getEntitlement();
  String? _companyName;

  // Avatar glow pulse
  late final AnimationController _glowCtrl;
  late final Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2400))
      ..repeat(reverse: true);
    _glowAnim = CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut);
    _companyService.getCompanyName(widget.companyId).then((name) {
      if (mounted) setState(() => _companyName = name);
    });
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  Future<void> _deleteAccount() async {
    // First confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl)),
        title: const Row(
          children: [
            Icon(Icons.warning_rounded, color: AppColors.danger, size: 20),
            SizedBox(width: 8),
            Text('Delete account?',
                style: TextStyle(color: AppColors.text)),
          ],
        ),
        content: const Text(
          'This will permanently delete your account and remove you from your company. '
          'This cannot be undone.\n\n'
          'You will be asked to sign in again to confirm.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete account',
                style: TextStyle(
                    color: AppColors.danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _deletingAccount = true);
    try {
      // Delete Firestore record first so seat counts free immediately
      await _companyService.deleteUserData();
      // Re-authenticates if needed, then deletes Firebase Auth account
      // and revokes Google OAuth grant
      await _authService.deleteAccount();
    } catch (e) {
      if (!mounted) return;
      setState(() => _deletingAccount = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
            style: const TextStyle(color: AppColors.text),
          ),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    // Auth state stream handles navigation back to sign-in automatically.
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl)),
        title: const Text('Sign out?',
            style: TextStyle(color: AppColors.text)),
        content: const Text('You\'ll need to sign in again to access your dashboard.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out',
                style: TextStyle(
                    color: AppColors.danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      setState(() => _signingOut = true);
      await _authService.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Header ───────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
                child: AnimatedEntrance(
                  delay: const Duration(milliseconds: 60),
                  beginOffset: const Offset(0, -0.04),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Settings',
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 2),
                      const Text('Account & preferences',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),

            // ── Profile card ─────────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, 0),
              sliver: SliverToBoxAdapter(
                child: AnimatedEntrance(
                  delay: const Duration(milliseconds: 120),
                  child: AnimatedBuilder(
                    animation: _glowAnim,
                    builder: (_, child) => Container(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                        border: Border.all(
                          color: AppColors.primary.withValues(
                              alpha: 0.2 + 0.15 * _glowAnim.value),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(
                                alpha: 0.06 + 0.06 * _glowAnim.value),
                            blurRadius: 24,
                          ),
                        ],
                      ),
                      child: child,
                    ),
                    child: Row(
                      children: [
                        // Avatar
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.surfaceAlt,
                            image: user?.photoURL != null
                                ? DecorationImage(
                                    image: NetworkImage(user!.photoURL!),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                            border: Border.all(
                                color: AppColors.primary.withValues(alpha: 0.5),
                                width: 2),
                          ),
                          child: user?.photoURL == null
                              ? const Icon(Icons.person_rounded,
                                  color: AppColors.primary, size: 28)
                              : null,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user?.displayName ?? 'Not signed in',
                                style: Theme.of(context).textTheme.titleMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                user?.email ?? '',
                                style: Theme.of(context).textTheme.bodySmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (user != null) ...[
                                const SizedBox(height: 6),
                                FutureBuilder(
                                  future: _companyService
                                      .getRoleAndCompanyName(user.uid),
                                  builder: (context, snapshot) {
                                    final info = snapshot.data;
                                    if (info == null) {
                                      return const SizedBox.shrink();
                                    }
                                    final role = info.role;
                                    final cap = role.isEmpty
                                        ? ''
                                        : '${role[0].toUpperCase()}${role.substring(1)} · ';
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary
                                            .withValues(alpha: 0.12),
                                        borderRadius:
                                            BorderRadius.circular(AppRadius.sm),
                                        border: Border.all(
                                            color: AppColors.primary
                                                .withValues(alpha: 0.3)),
                                      ),
                                      child: Text(
                                        '$cap${info.companyName}',
                                        style: const TextStyle(
                                          color: AppColors.primary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── Plan card ─────────────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, 0),
              sliver: SliverToBoxAdapter(
                child: AnimatedEntrance(
                  delay: const Duration(milliseconds: 180),
                  child: _sectionLabel('PLAN'),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
              sliver: SliverToBoxAdapter(
                child: FutureBuilder(
                  future: _entitlementFuture,
                  builder: (context, snapshot) {
                    final e = snapshot.data;
                    final plan = e == null
                        ? 'Loading…'
                        : '${e.plan[0].toUpperCase()}${e.plan.substring(1)}';
                    return AnimatedEntrance(
                      delay: const Duration(milliseconds: 200),
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: AppTheme.cardDecoration(),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color:
                                    AppColors.warning.withValues(alpha: 0.12),
                                borderRadius:
                                    BorderRadius.circular(AppRadius.sm),
                              ),
                              alignment: Alignment.center,
                              child: const Icon(Icons.workspace_premium_rounded,
                                  color: AppColors.warning, size: 20),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(plan,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall),
                                  if (e != null)
                                    Text(
                                      e.tier2Allowed
                                          ? 'Tier-2 NER AI detection active'
                                          : 'Tier-1 pattern detection',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // ── Team section ─────────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, 0),
              sliver: SliverToBoxAdapter(
                child: AnimatedEntrance(
                  delay: const Duration(milliseconds: 260),
                  child: _sectionLabel('TEAM'),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
              sliver: SliverToBoxAdapter(
                child: AnimatedEntrance(
                  delay: const Duration(milliseconds: 280),
                  child: Column(
                    children: [
                      _SettingsTile(
                        icon: Icons.people_rounded,
                        label: 'Manage team',
                        sub: 'View members & roles',
                        color: AppColors.primary,
                        onTap: () => Navigator.of(context).push(slideRoute(
                            TeamScreen(companyId: widget.companyId))),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _SettingsTile(
                        icon: Icons.person_add_rounded,
                        label: 'Invite employee',
                        sub: _companyName != null
                            ? 'Invite someone to join $_companyName'
                            : 'Send an invite by email',
                        color: AppColors.success,
                        onTap: () => Navigator.of(context).push(slideRoute(
                            InviteEmployeeScreen(
                                companyId: widget.companyId,
                                companyName: _companyName))),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      FutureBuilder(
                        future: _entitlementFuture,
                        builder: (context, snapshot) {
                          if (snapshot.data?.plan != 'enterprise') {
                            return const SizedBox.shrink();
                          }
                          return _SettingsTile(
                            icon: Icons.key_rounded,
                            label: 'Custom keywords',
                            sub:
                                '${snapshot.data!.customKeywords.length} active',
                            color: AppColors.info,
                            onTap: () => Navigator.of(context).push(slideRoute(
                                CustomKeywordsScreen(
                                    initialKeywords:
                                        snapshot.data!.customKeywords))),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Policies section ─────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, 0),
              sliver: SliverToBoxAdapter(
                child: AnimatedEntrance(
                  delay: const Duration(milliseconds: 340),
                  child: _sectionLabel('SECURITY'),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
              sliver: SliverToBoxAdapter(
                child: AnimatedEntrance(
                  delay: const Duration(milliseconds: 360),
                  child: _SettingsTile(
                    icon: Icons.security_rounded,
                    label: 'Detection policies',
                    sub: 'Manage what gets blocked',
                    color: AppColors.warning,
                    onTap: () => Navigator.of(context).push(slideRoute(
                        PolicyScreen(companyId: widget.companyId))),
                  ),
                ),
              ),
            ),

            // ── Preferences section ───────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, 0),
              sliver: SliverToBoxAdapter(
                child: AnimatedEntrance(
                  delay: const Duration(milliseconds: 400),
                  child: _sectionLabel('PREFERENCES'),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
              sliver: SliverToBoxAdapter(
                child: AnimatedEntrance(
                  delay: const Duration(milliseconds: 420),
                  child: Container(
                    decoration: AppTheme.cardDecoration(),
                    child: SwitchListTile(
                      value: _notificationsEnabled,
                      onChanged: (v) =>
                          setState(() => _notificationsEnabled = v),
                      activeThumbColor: AppColors.primary,
                      inactiveThumbColor: AppColors.textDim,
                      inactiveTrackColor: AppColors.surfaceAlt,
                      title: const Text('Push notifications',
                          style: TextStyle(
                              color: AppColors.text,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                      subtitle: const Text(
                        'Get notified when a new alert needs review',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 12.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
                    ),
                  ),
                ),
              ),
            ),

            // ── About section ─────────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, 0),
              sliver: SliverToBoxAdapter(
                child: AnimatedEntrance(
                  delay: const Duration(milliseconds: 460),
                  child: Column(
                    children: [
                      _sectionLabel('ABOUT'),
                      const SizedBox(height: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: AppTheme.cardDecoration(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Version',
                                    style:
                                        Theme.of(context).textTheme.bodyMedium),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.10),
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.sm),
                                  ),
                                  child: const Text(
                                    _kAppVersion,
                                    style: TextStyle(
                                        color: AppColors.primary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.md),
                            const Divider(color: AppColors.border, height: 1),
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              'Detection runs fully on-device in the Redactr browser extension — '
                              'prompt text and scan results never leave your team\'s machines.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Sign out ──────────────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, 0),
              sliver: SliverToBoxAdapter(
                child: AnimatedEntrance(
                  delay: const Duration(milliseconds: 500),
                  child: PressScale(
                    onTap: _signingOut ? null : _signOut,
                    child: AnimatedContainer(
                      duration: AppDurations.base,
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(
                            color: AppColors.danger.withValues(alpha: 0.3)),
                      ),
                      alignment: Alignment.center,
                      child: _signingOut
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.danger),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.logout_rounded,
                                    color: AppColors.danger, size: 18),
                                SizedBox(width: 8),
                                Text(
                                  'Sign out',
                                  style: TextStyle(
                                    color: AppColors.danger,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Delete account ────────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
              sliver: SliverToBoxAdapter(
                child: AnimatedEntrance(
                  delay: const Duration(milliseconds: 560),
                  child: PressScale(
                    onTap: (_deletingAccount || _signingOut) ? null : _deleteAccount,
                    child: AnimatedContainer(
                      duration: AppDurations.base,
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(
                            color: AppColors.danger.withValues(alpha: 0.18)),
                      ),
                      alignment: Alignment.center,
                      child: _deletingAccount
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.danger),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.delete_forever_rounded,
                                    color: AppColors.danger.withValues(alpha: 0.65),
                                    size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  'Delete account',
                                  style: TextStyle(
                                    color: AppColors.danger.withValues(alpha: 0.65),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) => Text(
        label,
        style: const TextStyle(
          color: AppColors.textDim,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
        ),
      );
}

// ── Settings tile ─────────────────────────────────────────────────────────────

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final Color color;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.sub,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: AppTheme.cardDecoration(),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.titleSmall),
                  Text(sub, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textDim, size: 20),
          ],
        ),
      ),
    );
  }
}
