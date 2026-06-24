import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Consistent "title + optional trailing widget" row used above list
/// sections (e.g. "Recent activity", Alerts filters).
class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const SectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          ?trailing,
        ],
      ),
    );
  }
}
