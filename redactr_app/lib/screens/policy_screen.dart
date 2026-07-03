import 'package:flutter/material.dart';
import '../services/company_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_entrance.dart';

// Built-in detection rules (managed by the extension, shown read-only here)
const _builtInRules = [
  (icon: Icons.credit_card_rounded,   label: 'Credit Card Numbers',    sub: 'Visa, Mastercard, Amex, Discover', color: AppColors.danger),
  (icon: Icons.badge_rounded,          label: 'Social Security Numbers', sub: 'US SSN pattern (XXX-XX-XXXX)',     color: AppColors.danger),
  (icon: Icons.vpn_key_rounded,        label: 'API Keys & Tokens',       sub: 'AWS, GitHub, Stripe and more',     color: AppColors.warning),
  (icon: Icons.email_rounded,          label: 'Email Addresses',          sub: 'All RFC-compliant addresses',      color: AppColors.info),
  (icon: Icons.public_rounded,         label: 'IP Addresses',             sub: 'IPv4 and IPv6',                   color: AppColors.info),
  (icon: Icons.phone_rounded,          label: 'Phone Numbers',            sub: 'US & international formats',      color: AppColors.warning),
  (icon: Icons.person_rounded,         label: 'Names (NER)',              sub: 'Tier-2 AI detection',             color: AppColors.primary),
  (icon: Icons.location_on_rounded,    label: 'Locations (NER)',          sub: 'Tier-2 AI detection',             color: AppColors.primary),
  (icon: Icons.account_balance_rounded,label: 'Bank Account Numbers',     sub: 'Routing + account patterns',      color: AppColors.danger),
];

class PolicyScreen extends StatefulWidget {
  final String companyId;
  const PolicyScreen({super.key, required this.companyId});

  @override
  State<PolicyScreen> createState() => _PolicyScreenState();
}

class _PolicyScreenState extends State<PolicyScreen> {
  final _companyService = CompanyService();
  final Map<String, bool> _ruleEnabled = {};
  List<String> _customKeywords = [];
  bool _loadingKeywords = true;
  final _keywordCtrl = TextEditingController();
  bool _addingKeyword = false;

  @override
  void initState() {
    super.initState();
    for (final r in _builtInRules) {
      _ruleEnabled[r.label] = true;
    }
    _loadEntitlement();
  }

  @override
  void dispose() {
    _keywordCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEntitlement() async {
    try {
      final e = await _companyService.getEntitlement();
      if (mounted) {
        setState(() {
          _customKeywords = e.customKeywords;
          _loadingKeywords = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingKeywords = false);
    }
  }

  Future<void> _addKeyword() async {
    final kw = _keywordCtrl.text.trim();
    if (kw.isEmpty) return;
    setState(() => _addingKeyword = true);
    try {
      final updated = await _companyService.addCustomKeyword(kw);
      _keywordCtrl.clear();
      if (mounted) setState(() { _customKeywords = updated; _addingKeyword = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _addingKeyword = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _removeKeyword(String kw) async {
    try {
      await _companyService.removeCustomKeyword(kw);
      if (mounted) setState(() => _customKeywords.remove(kw));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Detection Policies')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // Intro card
          AnimatedEntrance(
            delay: const Duration(milliseconds: 60),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: AppTheme.glowCardDecoration(),
              child: Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary.withValues(alpha: 0.15),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.security_rounded, color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Active protection', style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 2),
                        Text(
                          'All enabled rules run on-device in real time inside the browser extension.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          // Built-in rules
          AnimatedEntrance(
            delay: const Duration(milliseconds: 120),
            child: const Text(
              'BUILT-IN RULES',
              style: TextStyle(color: AppColors.textDim, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          ...List.generate(_builtInRules.length, (i) {
            final rule = _builtInRules[i];
            final enabled = _ruleEnabled[rule.label] ?? true;
            return AnimatedEntrance(
              delay: Duration(milliseconds: 160 + i * 45),
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _RuleCard(
                  icon: rule.icon,
                  label: rule.label,
                  sub: rule.sub,
                  color: rule.color,
                  enabled: enabled,
                  onToggle: (v) => setState(() => _ruleEnabled[rule.label] = v),
                ),
              ),
            );
          }),

          const SizedBox(height: AppSpacing.xl),

          // Custom keywords
          AnimatedEntrance(
            delay: const Duration(milliseconds: 560),
            child: const Text(
              'CUSTOM KEYWORDS',
              style: TextStyle(color: AppColors.textDim, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          AnimatedEntrance(
            delay: const Duration(milliseconds: 580),
            child: Text(
              'Exact phrases to block — enterprise plan only.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Add keyword row
          AnimatedEntrance(
            delay: const Duration(milliseconds: 600),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _keywordCtrl,
                    style: const TextStyle(color: AppColors.text, fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'e.g. CONFIDENTIAL, Project X',
                      prefixIcon: Icon(Icons.add_rounded, color: AppColors.textDim, size: 20),
                    ),
                    onSubmitted: (_) => _addKeyword(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                PressScale(
                  onTap: _addKeyword,
                  child: AnimatedContainer(
                    duration: AppDurations.base,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: _addingKeyword ? 0.4 : 1.0),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: _addingKeyword
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background),
                          )
                        : const Icon(Icons.check_rounded, color: AppColors.background, size: 20),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          // Keyword chips
          if (_loadingKeywords)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
            )
          else if (_customKeywords.isEmpty)
            AnimatedEntrance(
              delay: const Duration(milliseconds: 640),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: AppTheme.cardDecoration(),
                child: Text(
                  'No custom keywords yet. Add phrases above to block them across your team.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            )
          else
            AnimatedEntrance(
              delay: const Duration(milliseconds: 640),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: _customKeywords
                    .map((kw) => _KeywordChip(
                          keyword: kw,
                          onRemove: () => _removeKeyword(kw),
                        ))
                    .toList(),
              ),
            ),

          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}

// ── Rule card ─────────────────────────────────────────────────────────────────

class _RuleCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final Color color;
  final bool enabled;
  final ValueChanged<bool> onToggle;

  const _RuleCard({
    required this.icon,
    required this.label,
    required this.sub,
    required this.color,
    required this.enabled,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppDurations.base,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: enabled ? AppColors.surface : AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: enabled ? AppColors.border : AppColors.border.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: AppDurations.base,
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: enabled
                  ? color.withValues(alpha: 0.14)
                  : AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              color: enabled ? color : AppColors.textDim,
              size: 19,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedDefaultTextStyle(
                  duration: AppDurations.fast,
                  style: TextStyle(
                    color: enabled ? AppColors.text : AppColors.textDim,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  child: Text(label),
                ),
                const SizedBox(height: 2),
                Text(sub, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Switch(
            value: enabled,
            onChanged: onToggle,
            activeThumbColor: AppColors.primary,
            inactiveThumbColor: AppColors.textDim,
            inactiveTrackColor: AppColors.surfaceAlt,
          ),
        ],
      ),
    );
  }
}

// ── Keyword chip ──────────────────────────────────────────────────────────────

class _KeywordChip extends StatelessWidget {
  final String keyword;
  final VoidCallback onRemove;

  const _KeywordChip({required this.keyword, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            keyword,
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close_rounded, color: AppColors.primary, size: 14),
          ),
        ],
      ),
    );
  }
}
