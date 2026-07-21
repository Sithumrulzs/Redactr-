import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../services/company_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_entrance.dart';

class InviteEmployeeScreen extends StatefulWidget {
  final String companyId;
  final String? companyName;

  const InviteEmployeeScreen(
      {super.key, required this.companyId, this.companyName});

  @override
  State<InviteEmployeeScreen> createState() => _InviteEmployeeScreenState();
}

class _InviteEmployeeScreenState extends State<InviteEmployeeScreen> {
  final _companyService = CompanyService();
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _isSending = false;
  String? _error;
  String? _sharingEmail;

  Future<void> _sendInvite() async {
    final email = _controller.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid email address.');
      _focusNode.requestFocus();
      return;
    }

    setState(() {
      _isSending = true;
      _error = null;
    });

    try {
      await _companyService.inviteEmployee(email);
      _controller.clear();
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Invite created for $email — now send them the link below.',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md)),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _shareExtension(String email) async {
    setState(() => _sharingEmail = email);
    try {
      final url = await _companyService.generateDownloadLink();
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
              Icon(Icons.error_outline_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Could not generate link. Check your subscription is active.',
                  style: TextStyle(color: Colors.white),
                ),
              ),
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
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final companyLabel = widget.companyName != null
        ? 'Invite to ${widget.companyName}'
        : 'Invite employee';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(companyLabel),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.text,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // ── How it works banner ────────────────────────────────────────
          AnimatedEntrance(
            delay: const Duration(milliseconds: 60),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          color: AppColors.primary, size: 16),
                      SizedBox(width: 6),
                      Text('How it works',
                          style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _HowItWorksStep(
                      number: '1', text: 'Enter their email and tap Send invite'),
                  const SizedBox(height: 6),
                  _HowItWorksStep(
                      number: '2',
                      text:
                          'Tap "Send extension link" on the pending card — share via WhatsApp, iMessage, or any app'),
                  const SizedBox(height: 6),
                  _HowItWorksStep(
                      number: '3',
                      text:
                          'They install the extension and sign in with their invited email — auto-joined instantly'),
                ],
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          // ── Email input ─────────────────────────────────────────────────
          AnimatedEntrance(
            delay: const Duration(milliseconds: 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Employee email',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) =>
                            _isSending ? null : _sendInvite(),
                        style: const TextStyle(
                            color: AppColors.text, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'employee@company.com',
                          prefixIcon: const Icon(Icons.email_outlined,
                              color: AppColors.textDim, size: 18),
                          errorText: _error,
                          errorMaxLines: 3,
                          errorStyle: const TextStyle(
                              color: AppColors.danger, fontSize: 12.5),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isSending ? null : _sendInvite,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.background,
                          disabledBackgroundColor:
                              AppColors.primary.withValues(alpha: 0.4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.md),
                          ),
                          elevation: 0,
                        ),
                        child: _isSending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.background),
                              )
                            : const Text(
                                'Send invite',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13),
                              ),
                      ),
                    ),
                  ],
                ),
                if (_isSending) ...[
                  const SizedBox(height: AppSpacing.sm),
                  const Text(
                    'Sending… this may take a few seconds on first use.',
                    style:
                        TextStyle(color: AppColors.textDim, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.xxl),

          // ── Pending invites ─────────────────────────────────────────────
          AnimatedEntrance(
            delay: const Duration(milliseconds: 180),
            child: Row(
              children: [
                _PulsingDot(),
                const SizedBox(width: 8),
                const Text(
                  'Pending invites',
                  style: TextStyle(
                    color: AppColors.warning,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          StreamBuilder<List<Map<String, dynamic>>>(
            stream:
                _companyService.watchPendingInvites(widget.companyId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: LinearProgressIndicator(
                    color: AppColors.primary,
                    backgroundColor: AppColors.surfaceAlt,
                  ),
                );
              }

              final invites = snapshot.data ?? [];

              if (invites.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: AppTheme.cardDecoration(),
                  child: const Row(
                    children: [
                      Icon(Icons.inbox_rounded,
                          color: AppColors.textDim, size: 18),
                      SizedBox(width: AppSpacing.sm),
                      Text('No pending invites.',
                          style: TextStyle(
                              color: AppColors.textDim, fontSize: 13)),
                    ],
                  ),
                );
              }

              return Column(
                children: [
                  for (int i = 0; i < invites.length; i++)
                    AnimatedEntrance(
                      delay: Duration(milliseconds: i * 70),
                      child: Padding(
                        padding: EdgeInsets.only(
                            bottom: i < invites.length - 1
                                ? AppSpacing.sm
                                : 0),
                        child: _InvitePendingCard(
                          email: invites[i]['email'] as String? ?? '',
                          isSharing: _sharingEmail ==
                              (invites[i]['email'] as String? ?? ''),
                          onShare: () => _shareExtension(
                              invites[i]['email'] as String? ?? ''),
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

// ── How it works step ─────────────────────────────────────────────────────────

class _HowItWorksStep extends StatelessWidget {
  final String number;
  final String text;
  const _HowItWorksStep({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primary,
          ),
          alignment: Alignment.center,
          child: Text(number,
              style: const TextStyle(
                  color: AppColors.background,
                  fontSize: 10,
                  fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  color: AppColors.primary, fontSize: 12.5, height: 1.4)),
        ),
      ],
    );
  }
}

// ── Pulsing dot ───────────────────────────────────────────────────────────────

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

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
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.warning
              .withValues(alpha: 0.45 + 0.55 * _anim.value),
          boxShadow: [
            BoxShadow(
              color: AppColors.warning
                  .withValues(alpha: 0.35 * _anim.value),
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

class _InvitePendingCard extends StatelessWidget {
  final String email;
  final bool isSharing;
  final VoidCallback? onShare;
  const _InvitePendingCard(
      {required this.email, required this.isSharing, this.onShare});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.28)),
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
                    const Text(
                      'Waiting to sign in to the extension',
                      style: TextStyle(
                          color: AppColors.textDim, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Pending',
                  style: TextStyle(
                      color: AppColors.warning,
                      fontSize: 11,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.md),

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
