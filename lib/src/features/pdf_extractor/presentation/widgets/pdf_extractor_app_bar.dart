import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:snag_report_extractor_app/src/app.dart';
import 'package:snag_report_extractor_app/src/constants/app_sizes.dart';
import 'package:snag_report_extractor_app/src/routing/app_routing.dart';
import 'package:snag_report_extractor_app/src/theme_mode_provider.dart';

/// Top app bar for the extractor screen: branding on the left, Logs and
/// theme-toggle actions on the right.
class PdfExtractorAppBar extends ConsumerWidget
    implements PreferredSizeWidget {
  const PdfExtractorAppBar({super.key, required this.isDark});

  final bool isDark;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppBar(
      toolbarHeight: 64,
      titleSpacing: 16,
      backgroundColor: isDark ? AppColors.surface : null,
      flexibleSpace: isDark
          ? null
          : Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF3B7BF6), AppColors.blueDark],
                ),
              ),
            ),
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(9),
            ),
            padding: const EdgeInsets.all(3),
            child: Image.asset(
              'assets/images/icon-1024x1024.png',
              fit: BoxFit.contain,
            ),
          ),
          gapW12,
          const Text(
            'Snag Report Extractor',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
        ],
      ),
      actions: [
        _action(
          context,
          icon: Icons.insights_rounded,
          tooltip: "Logs",
          onTap: () => context.goNamed(AppRoute.logs.name),
        ),
        gapW8,
        _action(
          context,
          icon: isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
          tooltip: "Toggle theme",
          onTap: () => ref.read(themeModeProvider.notifier).toggleTheme(),
        ),
        gapW16,
      ],
    );
  }

  Widget _action(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(9),
      ),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        tooltip: tooltip,
        color: Colors.white,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
