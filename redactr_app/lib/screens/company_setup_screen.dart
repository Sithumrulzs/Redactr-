import 'package:flutter/material.dart';
import '../services/company_service.dart';
import '../theme/app_theme.dart';
import '../widgets/centered_form_page.dart';

/// Shown once, right after a user's first sign-in, if they have no
/// users/{uid} doc yet (see AuthGate in main.dart). Creates a new company
/// with them as admin via the claimOrJoinCompany Cloud Function — unless
/// an invite is already waiting for their email, in which case the
/// Function joins them to that company instead and this form is skipped
/// entirely (AuthGate checks the profile again before showing this).
class CompanySetupScreen extends StatefulWidget {
  final VoidCallback onCompanyReady;

  const CompanySetupScreen({super.key, required this.onCompanyReady});

  @override
  State<CompanySetupScreen> createState() => _CompanySetupScreenState();
}

class _CompanySetupScreenState extends State<CompanySetupScreen> {
  final _companyService = CompanyService();
  final _controller = TextEditingController();
  bool _isSubmitting = false;
  String? _error;

  Future<void> _submit() async {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a company name.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      await _companyService.claimOrJoinCompany(companyName: name);
      widget.onCompanyReady();
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _error = 'Could not create your company. Please try again.';
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
      backgroundColor: AppColors.background,
      body: CenteredFormPage(
        children: [
          Text("You're almost set up", style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Name your company to finish setting up your Redactr admin account.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.xl),
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: 'Company name',
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: const BorderSide(color: AppColors.border),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(_error!, style: const TextStyle(color: AppColors.red, fontSize: 13)),
          ],
          const SizedBox(height: AppSpacing.lg),
          ElevatedButton(
            onPressed: _isSubmitting ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.background,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background),
                  )
                : const Text('Continue'),
          ),
        ],
      ),
    );
  }
}
