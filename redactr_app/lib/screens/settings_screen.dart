import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/company_service.dart';
import '../theme/app_theme.dart';
import '../widgets/section_header.dart';
import 'custom_keywords_screen.dart';
import 'invite_employee_screen.dart';

const _kAppVersion = '1.0.0';

class SettingsScreen extends StatefulWidget {
  final String companyId;

  const SettingsScreen({super.key, required this.companyId});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _authService = AuthService();
  final _companyService = CompanyService();
  bool _notificationsEnabled = true;
  late final _entitlementFuture = _companyService.getEntitlement();

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: AppTheme.elevatedCardDecoration(),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: AppColors.surfaceAlt,
                  backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
                  child: user?.photoURL == null
                      ? const Icon(Icons.person, color: AppColors.primary)
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
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user?.email ?? '',
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (user != null) ...[
                        const SizedBox(height: 4),
                        FutureBuilder(
                          future: _companyService.getRoleAndCompanyName(user.uid),
                          builder: (context, snapshot) {
                            final info = snapshot.data;
                            if (info == null) return const SizedBox.shrink();
                            final role = info.role;
                            final roleLabel = role.isEmpty ? '' : '${role[0].toUpperCase()}${role.substring(1)} · ';
                            return Text(
                              '$roleLabel${info.companyName}',
                              style: const TextStyle(color: AppColors.primary, fontSize: 11.5, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
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
          const SizedBox(height: AppSpacing.xl),
          SectionHeader(title: 'Plan'),
          FutureBuilder(
            future: _entitlementFuture,
            builder: (context, snapshot) {
              final entitlement = snapshot.data;
              return Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: AppTheme.elevatedCardDecoration(),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      entitlement == null ? 'Loading…' : '${entitlement.plan[0].toUpperCase()}${entitlement.plan.substring(1)}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (entitlement != null)
                      Text(
                        entitlement.tier2Allowed ? 'Tier-2 NER included' : 'Tier-1 only',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          SectionHeader(title: 'Team'),
          ListTile(
            tileColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              side: const BorderSide(color: AppColors.border),
            ),
            leading: const Icon(Icons.person_add_alt, color: AppColors.primary),
            title: const Text('Invite employee'),
            trailing: const Icon(Icons.chevron_right, color: AppColors.textDim),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => InviteEmployeeScreen(companyId: widget.companyId)),
            ),
          ),
          FutureBuilder(
            future: _entitlementFuture,
            builder: (context, snapshot) {
              final entitlement = snapshot.data;
              if (entitlement?.plan != 'enterprise') return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: ListTile(
                  tileColor: AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    side: const BorderSide(color: AppColors.border),
                  ),
                  leading: const Icon(Icons.key, color: AppColors.primary),
                  title: const Text('Custom keywords'),
                  subtitle: Text('${entitlement!.customKeywords.length} active'),
                  trailing: const Icon(Icons.chevron_right, color: AppColors.textDim),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CustomKeywordsScreen(initialKeywords: entitlement.customKeywords),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          SectionHeader(title: 'Preferences'),
          Container(
            decoration: AppTheme.elevatedCardDecoration(),
            child: SwitchListTile(
              value: _notificationsEnabled,
              onChanged: (value) => setState(() => _notificationsEnabled = value),
              activeThumbColor: AppColors.primary,
              title: const Text('Push notifications'),
              subtitle: const Text('Get notified when a new alert needs review'),
              contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          SectionHeader(title: 'About'),
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: AppTheme.elevatedCardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.sm,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Version', style: Theme.of(context).textTheme.bodyMedium),
                    Text(_kAppVersion, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
                const Divider(height: 1),
                Text(
                  'Detection runs fully on-device in the Redactr browser extension — prompt '
                  'text and scan results never leave your team\'s machines.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          OutlinedButton.icon(
            onPressed: () => _authService.signOut(),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.red,
              side: const BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}
