import 'package:flutter/material.dart';
import '../services/company_service.dart';
import '../theme/app_theme.dart';

/// Enterprise-only. Lets an admin manage the plain-English concept labels
/// (e.g. "internal project codename") that the GLiNER Tier-2 engine in every
/// employee's extension matches on-device — see server/index.js's
/// addCustomEntity and offscreen/offscreen.src.js's labelToFinding().
///
/// Validation mirrors the server: non-empty, ≤40 characters,
/// letters/digits/spaces/hyphens only (enforced client-side for immediate
/// feedback; the server re-validates authoritatively).
class CustomEntitiesScreen extends StatefulWidget {
  final List<String> initialEntities;

  const CustomEntitiesScreen({super.key, required this.initialEntities});

  @override
  State<CustomEntitiesScreen> createState() => _CustomEntitiesScreenState();
}

class _CustomEntitiesScreenState extends State<CustomEntitiesScreen> {
  final _companyService = CompanyService();
  final _controller     = TextEditingController();
  late List<String> _entities;
  bool   _isSaving = false;
  String? _error;

  static final _labelRe = RegExp(r'^[a-z0-9 -]+$');

  @override
  void initState() {
    super.initState();
    _entities = List.of(widget.initialEntities);
  }

  String? _validate(String label) {
    if (label.isEmpty) return 'Label cannot be empty.';
    if (label.length > 40) return 'Label must be 40 characters or fewer.';
    if (!_labelRe.hasMatch(label)) {
      return 'Only letters, digits, spaces, and hyphens are allowed.';
    }
    return null;
  }

  Future<void> _add() async {
    final raw   = _controller.text.trim().toLowerCase();
    final error = _validate(raw);
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    setState(() {
      _isSaving = true;
      _error    = null;
    });
    try {
      final updated = await _companyService.addCustomEntity(raw);
      setState(() {
        _entities  = updated;
        _isSaving  = false;
        _controller.clear();
      });
    } catch (e) {
      setState(() {
        _isSaving = false;
        _error    = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _remove(String label) async {
    setState(() => _entities.remove(label));
    try {
      await _companyService.removeCustomEntity(label);
    } catch (_) {
      setState(() => _entities.add(label));
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
      appBar: AppBar(title: const Text('AI entity types')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text(
            'Describe sensitive concepts in plain English — every employee\'s browser '
            'detects them on-device using GLiNER AI. For example: "internal project codename", '
            '"client account name", or "proprietary formula name". '
            'Up to 15 labels per company.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    hintText: 'e.g. internal project codename',
                  ),
                  textCapitalization: TextCapitalization.none,
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
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.background),
                      )
                    : const Text('Add'),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.red, fontSize: 12.5),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          if (_entities.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Text(
                'No custom entity types yet.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            )
          else
            ...(_entities.map(
              (label) => Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                decoration: AppTheme.elevatedCardDecoration(),
                child: ListTile(
                  title: Text(label),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, color: AppColors.textDim),
                    onPressed: () => _remove(label),
                  ),
                ),
              ),
            )),
        ],
      ),
    );
  }
}
