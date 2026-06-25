import 'package:flutter/material.dart';
import '../services/company_service.dart';
import '../theme/app_theme.dart';

/// Enterprise-only. Lets an admin manage the literal phrases (codenames,
/// internal project names, etc.) that get merged into every employee's
/// Tier-1 scan — see server/index.js's addCustomKeyword and
/// redactr-extension/lib/detector.js's findCustomKeywords. Deliberately
/// not raw regex: an admin-supplied pattern running in every employee's
/// browser on every keystroke would be a real ReDoS risk.
class CustomKeywordsScreen extends StatefulWidget {
  final List<String> initialKeywords;

  const CustomKeywordsScreen({super.key, required this.initialKeywords});

  @override
  State<CustomKeywordsScreen> createState() => _CustomKeywordsScreenState();
}

class _CustomKeywordsScreenState extends State<CustomKeywordsScreen> {
  final _companyService = CompanyService();
  final _controller = TextEditingController();
  late List<String> _keywords;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _keywords = List.of(widget.initialKeywords);
  }

  Future<void> _add() async {
    final keyword = _controller.text.trim();
    if (keyword.isEmpty) return;

    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final updated = await _companyService.addCustomKeyword(keyword);
      setState(() {
        _keywords = updated;
        _controller.clear();
        _isSaving = false;
      });
    } catch (e) {
      setState(() {
        _isSaving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _remove(String keyword) async {
    setState(() => _keywords.remove(keyword));
    try {
      await _companyService.removeCustomKeyword(keyword);
    } catch (_) {
      // Re-add on failure — best-effort UI, the server is the source of truth.
      setState(() => _keywords.add(keyword));
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
      appBar: AppBar(title: const Text('Custom keywords')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text(
            'Add internal codenames, project names, or other terms your team should never paste '
            'into ChatGPT, Claude, or Gemini. Every employee\'s extension blocks prompts containing '
            'them, the same way it already blocks API keys and card numbers.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(hintText: 'e.g. project-falcon'),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton(
                onPressed: _isSaving ? null : _add,
                child: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background),
                      )
                    : const Text('Add'),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(_error!, style: const TextStyle(color: AppColors.red, fontSize: 12.5)),
          ],
          const SizedBox(height: AppSpacing.xl),
          if (_keywords.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Text(
                'No custom keywords yet.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            )
          else
            ...(_keywords.map(
              (keyword) => Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                decoration: AppTheme.elevatedCardDecoration(),
                child: ListTile(
                  title: Text(keyword),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, color: AppColors.textDim),
                    onPressed: () => _remove(keyword),
                  ),
                ),
              ),
            )),
        ],
      ),
    );
  }
}
