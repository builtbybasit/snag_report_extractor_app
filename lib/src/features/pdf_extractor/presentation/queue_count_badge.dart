import 'package:flutter/material.dart';

/// A small pill that shows how many files are queued and visually pulses
/// (scale + fade) whenever the count changes, giving immediate feedback when
/// a file is added to or removed from the queue.
class QueueCountBadge extends StatelessWidget {
  final int count;

  const QueueCountBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: animation,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: Container(
        // Keying by count makes AnimatedSwitcher run its transition on change.
        key: ValueKey<int>(count),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          "$count ${count == 1 ? 'file' : 'files'}",
          style: TextStyle(
            color: scheme.onPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }
}
