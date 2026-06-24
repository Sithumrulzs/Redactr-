import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Vertically centers short, single-purpose form content (sign in/up,
/// company setup) on any screen size — content stays centered when it fits
/// the viewport, and scrolls normally if it doesn't (e.g. keyboard open on
/// a small phone). Also caps width so it doesn't stretch edge-to-edge on
/// tablets/large screens.
class CenteredFormPage extends StatelessWidget {
  final List<Widget> children;
  final double maxWidth;

  const CenteredFormPage({super.key, required this.children, this.maxWidth = 420});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - AppSpacing.xl * 2),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
