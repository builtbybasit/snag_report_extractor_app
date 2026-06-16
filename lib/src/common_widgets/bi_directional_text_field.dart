import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_sizes.dart';

final textDirectionProvider =
    NotifierProvider<TextDirectionNotifier, TextDirection>(
  TextDirectionNotifier.new,
);

class TextDirectionNotifier extends Notifier<TextDirection> {
  @override
  TextDirection build() => TextDirection.ltr;

  void toggle() {
    state =
        state == TextDirection.ltr ? TextDirection.rtl : TextDirection.ltr;
  }
}

class SpecialTextField extends ConsumerWidget {
  const SpecialTextField({super.key, final labelText});

  final String? labelText = null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textDirection = ref.watch(textDirectionProvider);

    void toggleTextDirection() {
      ref.read(textDirectionProvider.notifier).toggle();
    }

    return Padding(
      padding: const EdgeInsets.all(Sizes.p16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextFormField(
          textDirection: textDirection,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: labelText,
          ),
        ),
        gapH8,
        Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: 130,
            height: 25,
            child: ElevatedButton(
              onPressed: toggleTextDirection,
              child: const Text("Toggle DIR"),
            ),
          ),
        )
      ]),
    );
  }
}
