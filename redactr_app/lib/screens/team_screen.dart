import 'package:firebase_auth/firebase_auth.dart';
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
  final _currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
  late final Future<String?> _nameFuture =
      _companyService.getCompanyName(widget.companyId);

  Future<void> _removeMember(Map<String, dynamic> member) async {
    final name = member['displayName'] as String? ??
        member['email'] as String? ?? 'this member';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl)),
        title: Row(
          children: [
            const Icon(Icons.person_remove_rounded,
                color: AppColors.danger, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Remove $name?',
                  style: const TextStyle(color: AppColors.text)),
            ),
          ],
        ),
        content: Text(
          '$name will lose access to the company and their extension will be delinked.',
          style: const TextStyle(
              color: AppColors.textMuted, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove',
                style: TextStyle(
                    color: AppColors.danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _companyService.removeMember(member['uid'] as String);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$name has been removed.'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

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
                              style:
                                  Theme.of(context).textTheme.headlineSmall),
                          const SizedBox(height: 2),
                          FutureBuilder<String?>(
                            future: _nameFuture,
                            builder: (_, snap) => Text(
                              snap.data != null
                                  ? 'Members of ${snap.data}'
                                  : 'Members & access control',
                              style: const TextStyle(
                                  color: AppColors.textMuted, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    PressScale(
                      onTap: () {
                        _nameFuture.then((name) {
                          if (context.mounted) {
                            Navigator.of(context).push(slideRoute(
                                InviteEmployeeScreen(
                                    companyId: widget.companyId,
                                    companyName: name)));
                          }
                        });
                      },
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
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, index) =>
                          const SkeletonBox(height: 72, radius: AppRadius.lg),
                    );
                  }

                  final members = snapshot.data ?? [];
                  final isAdmin = members.any(
                      (m) => m['uid'] == _currentUid && m['role'] == 'admin');

                  if (members.isEmpty) {
                    return FutureBuilder<String?>(
                      future: _nameFuture,
                      builder: (_, nameSnap) => _EmptyTeam(
                        companyName: nameSnap.data,
                        onInvite: () => Navigator.of(context).push(slideRoute(
                            InviteEmployeeScreen(
                                companyId: widget.companyId,
                                companyName: nameSnap.data))),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg),
                    itemCount: members.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (_, i) {
                      final member = members[i];
                      final canRemove =
                          isAdmin && member['uid'] != _currentUid;
                      return AnimatedEntrance(
                        delay: Duration(milliseconds: 80 + i * 55),
                        child: _MemberCard(
                          member: member,
                          canRemove: canRemove,
                          onRemove:
                              canRemove ? () => _removeMember(member) : null,
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            // ── Pending invites section ────────────────────────────────────
            FutureBuilder<String?>(
              future: _nameFuture,
              builder: (_, snap) => _PendingInvitesSection(
                companyId: widget.companyId,
                companyName: snap.data,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Member card ───────────────────────────────────────────────────────────────

class _MemberCard extends StatelessWidget {
  final Map<String, dynamic> member;
  final bool canRemove;
  final VoidCallback? onRemove;
  const _MemberCard({
    required this.member,
    this.canRemove = false,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final name = member['displayName'] as String? ??
        member['email'] as String? ?? 'Team member';
    final email = member['email'] as String? ?? '';
    final role = member['role'] as String? ?? 'employee';
    final photoURL = member['photoURL'] as String?;
    final isAdmin = role == 'admin';
    final leaksPrevented = (member['leaksPrevented'] as num?)?.toInt() ?? 0;
    final filesBlocked = (member['filesBlocked'] as num?)?.toInt() ?? 0;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppTheme.cardDecoration(),
      child: Row(
        children: [
          // Avatar — Google photo when available, letter fallback
          _MemberAvatar(
            photoURL: photoURL,
            name: name,
            isAdmin: isAdmin,
            size: 46,
          ),

          const SizedBox(width: AppSpacing.md),

          // Name + email + stat chips
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: Theme.of(context).textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  email,
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
                if (leaksPrevented > 0 || filesBlocked > 0) ...[
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      if (leaksPrevented > 0)
                        _StatChip(
                          icon: Icons.shield_rounded,
                          label: '$leaksPrevented blocked',
                          color: AppColors.danger,
                        ),
                      if (leaksPrevented > 0 && filesBlocked > 0)
                        const SizedBox(width: 6),
                      if (filesBlocked > 0)
                        _StatChip(
                          icon: Icons.insert_drive_file_rounded,
                          label: '$filesBlocked files',
                          color: AppColors.warning,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(width: AppSpacing.sm),

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

          if (canRemove) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: AppColors.danger.withValues(alpha: 0.25)),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.person_remove_rounded,
                    color: AppColors.danger, size: 14),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Member avatar (Google photo + letter fallback) ────────────────────────────

class _MemberAvatar extends StatelessWidget {
  final String? photoURL;
  final String name;
  final bool isAdmin;
  final double size;
  const _MemberAvatar({
    required this.photoURL,
    required this.name,
    required this.isAdmin,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
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
          fontSize: size * 0.35,
        ),
      ),
    );

    if (photoURL == null || photoURL!.isEmpty) return fallback;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isAdmin
              ? AppColors.primary.withValues(alpha: 0.4)
              : AppColors.border,
          width: 1.5,
        ),
      ),
      child: ClipOval(
        child: Image.network(
          photoURL!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback,
        ),
      ),
    );
  }
}

// ── Per-member stat chip ──────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _StatChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color.withValues(alpha: 0.8)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color.withValues(alpha: 0.9),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pulsing status dot ────────────────────────────────────────────────────────

class _PulsingDot extends StatefulWidget {
  final double size;
  const _PulsingDot({this.size = 8});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) => Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.warning.withValues(alpha: 0.45 + 0.55 * _anim.value),
          boxShadow: [
            BoxShadow(
              color: AppColors.warning.withValues(alpha: 0.35 * _anim.value),
              blurRadius: 5,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Pending invite card ───────────────────────────────────────────────────────

class _PendingInviteCard extends StatelessWidget {
  final String email;
  final bool isSharing;
  final VoidCallback? onShare;
  const _PendingInviteCard(
      {required this.email, required this.isSharing, this.onShare});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border:
            Border.all(color: AppColors.warning.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: AppColors.warning.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar + email row
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.warning.withValues(alpha: 0.1),
                  border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.3)),
                ),
                alignment: Alignment.center,
                child: Text(
                  email.isNotEmpty ? email[0].toUpperCase() : '?',
                  style: const TextStyle(
                      color: AppColors.warning,
                      fontWeight: FontWeight.w800,
                      fontSize: 16),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      email,
                      style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _PulsingDot(size: 6),
                        const SizedBox(width: 5),
                        const Text(
                          'Waiting to sign in',
                          style: TextStyle(
                              color: AppColors.textDim, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.md),

          // Divider
          Container(
              height: 1,
              color: AppColors.warning.withValues(alpha: 0.1)),

          const SizedBox(height: AppSpacing.md),

          // Share button
          PressScale(
            onTap: isSharing ? null : onShare,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                gradient: isSharing
                    ? null
                    : const LinearGradient(
                        colors: [AppColors.primary, AppColors.accent]),
                color: isSharing ? AppColors.surfaceAlt : null,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isSharing)
                    const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.8, color: AppColors.primary),
                    )
                  else
                    const Icon(Icons.ios_share_rounded,
                        color: AppColors.background, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    isSharing ? 'Generating link…' : 'Send extension link',
                    style: TextStyle(
                      color: isSharing
                          ? AppColors.primary
                          : AppColors.background,
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
    );
  }
}

// ── Pending invites section ───────────────────────────────────────────────────

class _PendingInvitesSection extends StatefulWidget {
  final String companyId;
  final String? companyName;
  const _PendingInvitesSection({required this.companyId, this.companyName});

  @override
  State<_PendingInvitesSection> createState() => _PendingInvitesSectionState();
}

class _PendingInvitesSectionState extends State<_PendingInvitesSection> {
  final _service = CompanyService();
  String? _sharingEmail;

  Future<void> _shareExtension(String email) async {
    setState(() => _sharingEmail = email);
    try {
      final url = await _service.generateDownloadLink();
      if (!mounted) return;
      final company = widget.companyName ?? 'our company';
      await Share.share(
        'Hi! You\'ve been invited to join $company on Redactr.\n\n'
        'Get started in 2 steps:\n\n'
        '1. Install the Chrome extension:\n$url\n\n'
        '2. Open it and sign in with Google using this email:\n$email\n\n'
        'You\'ll be automatically linked to $company. That\'s it!',
        subject: 'You\'re invited to $company on Redactr',
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.error_outline_rounded,
                  color: Colors.white, size: 18),
              SizedBox(width: 8),
              Expanded(
                  child: Text('Could not generate link. Check your subscription is active.',
                      style: TextStyle(color: Colors.white))),
            ],
          ),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md)),
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
              // Section header
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.md),
                child: Row(
                  children: [
                    _PulsingDot(),
                    const SizedBox(width: 8),
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

              // Invite cards
              ...List.generate(invites.length, (i) {
                final email = invites[i]['email'] as String? ?? '';
                final isSharing = _sharingEmail == email;
                return AnimatedEntrance(
                  delay: Duration(milliseconds: i * 70),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      0,
                      AppSpacing.lg,
                      i < invites.length - 1 ? AppSpacing.sm : 0,
                    ),
                    child: _PendingInviteCard(
                      email: email,
                      isSharing: isSharing,
                      onShare:
                          isSharing ? null : () => _shareExtension(email),
                    ),
                  ),
                );
              }),

              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        );
      },
    );
  }
}

// ── Empty team ────────────────────────────────────────────────────────────────

class _EmptyTeam extends StatelessWidget {
  final VoidCallback onInvite;
  final String? companyName;
  const _EmptyTeam({required this.onInvite, this.companyName});

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
              companyName != null
                  ? 'Invite your first employee so they can join $companyName automatically.'
                  : 'Invite your first employee so they can join your company automatically.',
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
