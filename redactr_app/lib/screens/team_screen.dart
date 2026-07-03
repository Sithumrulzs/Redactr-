import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../services/company_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_entrance.dart';
import 'invite_employee_screen.dart';
import '../main.dart' show slideRoute;

class TeamScreen extends StatefulWidget {
  final String companyId;
  const TeamScreen({super.key, required this.companyId});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  final _companyService = CompanyService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
              child: AnimatedEntrance(
                delay: const Duration(milliseconds: 60),
                beginOffset: const Offset(0, -0.04),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Team',
                              style: Theme.of(context).textTheme.headlineSmall),
                          const SizedBox(height: 2),
                          const Text('Members & access control',
                              style: TextStyle(
                                  color: AppColors.textMuted, fontSize: 13)),
                        ],
                      ),
                    ),
                    PressScale(
                      onTap: () => Navigator.of(context).push(slideRoute(
                          InviteEmployeeScreen(
                              companyId: widget.companyId))),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.primary, AppColors.accent],
                          ),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person_add_rounded,
                                color: AppColors.background, size: 16),
                            SizedBox(width: 6),
                            Text(
                              'Invite',
                              style: TextStyle(
                                color: AppColors.background,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.xl),

            // ── Member list ──────────────────────────────────────────────────
            Expanded(
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _companyService.watchTeamMembers(widget.companyId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg),
                      itemCount: 4,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (_, _) =>
                          const SkeletonBox(height: 72, radius: AppRadius.lg),
                    );
                  }

                  final members = snapshot.data ?? [];

                  if (members.isEmpty) {
                    return _EmptyTeam(
                      onInvite: () => Navigator.of(context).push(slideRoute(
                          InviteEmployeeScreen(companyId: widget.companyId))),
                    );
                  }

                  return ListView.separated(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    itemCount: members.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (_, i) {
                      final member = members[i];
                      return AnimatedEntrance(
                        delay: Duration(milliseconds: 80 + i * 55),
                        child: _MemberCard(member: member),
                      );
                    },
                  );
                },
              ),
            ),

            // ── Pending invites section ────────────────────────────────────
            _PendingInvitesSection(companyId: widget.companyId),
          ],
        ),
      ),
    );
  }
}

// ── Member card ───────────────────────────────────────────────────────────────

class _MemberCard extends StatelessWidget {
  final Map<String, dynamic> member;
  const _MemberCard({required this.member});

  @override
  Widget build(BuildContext context) {
    final name    = member['displayName'] as String? ??
        member['email'] as String? ?? 'Team member';
    final email   = member['email'] as String? ?? '';
    final role    = member['role'] as String? ?? 'employee';
    final isAdmin = role == 'admin';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppTheme.cardDecoration(),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isAdmin
                  ? AppColors.primary.withValues(alpha: 0.15)
                  : AppColors.surfaceAlt,
              border: Border.all(
                color: isAdmin
                    ? AppColors.primary.withValues(alpha: 0.4)
                    : AppColors.border,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                color: isAdmin ? AppColors.primary : AppColors.textMuted,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),

          const SizedBox(width: AppSpacing.md),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  email,
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Role badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isAdmin
                  ? AppColors.primary.withValues(alpha: 0.12)
                  : AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isAdmin
                    ? AppColors.primary.withValues(alpha: 0.3)
                    : AppColors.border,
              ),
            ),
            child: Text(
              isAdmin ? 'Admin' : 'Employee',
              style: TextStyle(
                color: isAdmin ? AppColors.primary : AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pending invites ───────────────────────────────────────────────────────────

class _PendingInvitesSection extends StatefulWidget {
  final String companyId;
  const _PendingInvitesSection({required this.companyId});

  @override
  State<_PendingInvitesSection> createState() => _PendingInvitesSectionState();
}

class _PendingInvitesSectionState extends State<_PendingInvitesSection> {
  final _service = CompanyService();
  // tracks which email is currently generating a share link
  String? _sharingEmail;

  Future<void> _shareExtension(String email) async {
    setState(() => _sharingEmail = email);
    try {
      final url = await _service.generateDownloadLink();
      if (!mounted) return;
      await Share.share(
        'Hi! You\'ve been invited to join our company on Redactr.\n\n'
        'Download the Chrome extension here:\n$url\n\n'
        'Install it, open it, and sign in with this Google account ($email) '
        'to get started automatically.',
        subject: 'Your Redactr Chrome Extension',
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not generate link. Check your subscription is active.'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _sharingEmail = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _service.watchPendingInvites(widget.companyId),
      builder: (context, snapshot) {
        final invites = snapshot.data ?? [];
        if (invites.isEmpty) return const SizedBox.shrink();

        return AnimatedEntrance(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
                child: Row(
                  children: [
                    const Icon(Icons.mail_outline_rounded,
                        color: AppColors.warning, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Pending invites (${invites.length})',
                      style: const TextStyle(
                        color: AppColors.warning,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 60,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  scrollDirection: Axis.horizontal,
                  itemCount: invites.length,
                  separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
                  itemBuilder: (_, i) {
                    final email = invites[i]['email'] as String? ?? '';
                    final isSharing = _sharingEmail == email;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.schedule_rounded, color: AppColors.warning, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            email,
                            style: const TextStyle(
                                color: AppColors.warning, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 8),
                          // Share extension link button
                          GestureDetector(
                            onTap: isSharing ? null : () => _shareExtension(email),
                            child: Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                              ),
                              alignment: Alignment.center,
                              child: isSharing
                                  ? const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 1.5, color: AppColors.primary),
                                    )
                                  : const Icon(Icons.ios_share_rounded,
                                      color: AppColors.primary, size: 14),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 6, AppSpacing.lg, 0),
                child: Text(
                  'Tap   to send the employee their extension download link',
                  style: TextStyle(
                    color: AppColors.textDim,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyTeam extends StatelessWidget {
  final VoidCallback onInvite;
  const _EmptyTeam({required this.onInvite});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.10),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: const Icon(Icons.people_outline_rounded,
                  color: AppColors.primary, size: 36),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('No team members yet',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Invite your first employee so they can join your company automatically.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.xl),
            PressScale(
              onTap: onInvite,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl, vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.accent]),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  boxShadow: [
                    BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        blurRadius: 14,
                        offset: const Offset(0, 6)),
                  ],
                ),
                child: const Text(
                  'Invite employee',
                  style: TextStyle(
                      color: AppColors.background,
                      fontWeight: FontWeight.w700,
                      fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
