import 'package:flutter/material.dart';
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
                  'Invite sent to $email',
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
          duration: const Duration(seconds: 4),
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
          // ── Description ────────────────────────────────────────────────
          AnimatedEntrance(
            delay: const Duration(milliseconds: 60),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border:
                    Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded,
                      color: AppColors.primary, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      widget.companyName != null
                          ? 'When this person signs into the Chrome extension with this email, '
                              'they\'ll automatically join ${widget.companyName}.'
                          : 'When this person signs into the Chrome extension with this email, '
                              'they\'ll automatically join your company.',
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 13,
                          height: 1.5),
                    ),
                  ),
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
                        onSubmitted: (_) => _isSending ? null : _sendInvite(),
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
                            borderRadius: BorderRadius.circular(AppRadius.md),
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
                                    fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                      ),
                    ),
                  ],
                ),
                if (_isSending) ...[
                  const SizedBox(height: AppSpacing.sm),
                  const Text(
                    'Sending… this may take a few seconds on first use.',
                    style: TextStyle(color: AppColors.textDim, fontSize: 12),
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
                const Icon(Icons.schedule_rounded,
                    color: AppColors.warning, size: 16),
                const SizedBox(width: 6),
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
            stream: _companyService.watchPendingInvites(widget.companyId),
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
                  for (final invite in invites)
                    AnimatedEntrance(
                      child: Container(
                        margin:
                            const EdgeInsets.only(bottom: AppSpacing.sm),
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md, vertical: 14),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(
                              color:
                                  AppColors.warning.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color:
                                    AppColors.warning.withValues(alpha: 0.12),
                                borderRadius:
                                    BorderRadius.circular(AppRadius.sm),
                              ),
                              alignment: Alignment.center,
                              child: const Icon(Icons.mail_outline_rounded,
                                  color: AppColors.warning, size: 16),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    invite['email'] as String? ?? '',
                                    style: const TextStyle(
                                        color: AppColors.text,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Waiting for them to sign in',
                                    style: TextStyle(
                                        color: AppColors.textDim,
                                        fontSize: 11.5),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color:
                                    AppColors.warning.withValues(alpha: 0.12),
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
