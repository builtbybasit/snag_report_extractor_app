import 'package:flutter/material.dart';

/// A white/surface rounded panel with a subtle border (and light shadow in
/// light mode), used for the major content sections.
Widget appPanel(
  BuildContext context, {
  required Widget child,
  EdgeInsets padding = const EdgeInsets.all(20),
}) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  return Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: theme.cardColor,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: theme.dividerColor.withValues(alpha: 0.6)),
      boxShadow: isDark
          ? null
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
    ),
    child: child,
  );
}
