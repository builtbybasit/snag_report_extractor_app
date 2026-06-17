// pdf_extractor_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:snag_report_extractor_app/src/constants/app_sizes.dart';
import 'package:snag_report_extractor_app/src/features/pdf_extractor/presentation/pdf_extractor_controller.dart';
import 'package:snag_report_extractor_app/src/features/pdf_extractor/presentation/widgets/extract_bar.dart';
import 'package:snag_report_extractor_app/src/features/pdf_extractor/presentation/widgets/output_directory_section.dart';
import 'package:snag_report_extractor_app/src/features/pdf_extractor/presentation/widgets/pdf_drop_zone.dart';
import 'package:snag_report_extractor_app/src/features/pdf_extractor/presentation/widgets/pdf_extractor_app_bar.dart';
import 'package:snag_report_extractor_app/src/features/pdf_extractor/presentation/widgets/queue_header.dart';
import 'package:snag_report_extractor_app/src/features/pdf_extractor/presentation/widgets/queue_list.dart';

class PdfExtractorScreen extends ConsumerWidget {
  const PdfExtractorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Whether the queue is non-empty: this only flips when files are added to
    // or removed from an empty/non-empty queue, so the surrounding column does
    // not rebuild on every progress tick.
    final hasFiles = ref.watch(
      pdfExtractorScreenControllerProvider.select((s) => s.items.isNotEmpty),
    );

    return Scaffold(
      appBar: PdfExtractorAppBar(isDark: isDark),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const OutputDirectorySection(),
                gapH24,
                PdfDropZone(isDark: isDark),
                gapH24,
                if (hasFiles) ...[
                  const QueueHeader(),
                  gapH12,
                  const QueueList(),
                  gapH16,
                ],
                const ExtractBar(),
                gapH8,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
