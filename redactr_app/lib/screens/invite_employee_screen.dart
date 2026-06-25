import 'package:flutter/material.dart';
import '../services/company_service.dart';
import '../theme/app_theme.dart';
import '../widgets/section_header.dart';

class InviteEmployeeScreen extends StatefulWidget {
  final String companyId;

  const InviteEmployeeScreen({super.key, required this.companyId});

  @override
  State<InviteEmployeeScreen> createState() => _InviteEmployeeScreenState();
}

class _InviteEmployeeScreenState extends State<InviteEmployeeScreen> {
  final _companyService = CompanyService();
  final _controller = TextEditingController();
  bool _isSending = false;
  String? _error;

  Future<void> _sendInvite() async {
    final email = _controller.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }

    setState(() {
      _isSending = true;
      _error = null;
    });

    try {
      await _companyService.inviteEmployee(email);
      _controller.clear();
      setState(() => _isSending = false);
    } catch (e) {
      setState(() {
        _isSending = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invite employee')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text(
            'The next time this email signs in (via the browser extension), they join your '
            'company automatically instead of creating a new one.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: 'employee@company.com',
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              ElevatedButton(
                onPressed: _isSending ? null : _sendInvite,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.background,
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                ),
                child: _isSending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background),
                      )
                    : const Text('Invite'),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(_error!, style: const TextStyle(color: AppColors.red, fontSize: 13)),
          ],
          const SizedBox(height: AppSpacing.xl),
          SectionHeader(title: 'Pending invites'),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _companyService.watchPendingInvites(widget.companyId),
            builder: (context, snapshot) {
              final invites = snapshot.data ?? [];
              if (invites.isEmpty) {
                return Text('No pending invites.', style: Theme.of(context).textTheme.bodySmall);
              }
              return Column(
                spacing: AppSpacing.sm,
                children: [
                  for (final invite in invites)
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: AppTheme.elevatedCardDecoration(),
                      child: Row(
                        children: [
                          const Icon(Icons.mail_outline, color: AppColors.textDim, size: 18),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(child: Text(invite['email'] as String)),
                          Text('Pending', style: Theme.of(context).textTheme.labelSmall),
                        ],
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
