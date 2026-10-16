import 'package:flutter/material.dart';

import '../data/recovery_export.dart';
import '../data/workspace_repository.dart';
import '../workspace_controller.dart';
import 'workbench_chrome.dart';

/// Runs the recovery export against the real Windows save dialog and reports
/// the actual path, chapter count and omissions; cancel shows nothing.
final class RecoveryExportFlow {
  const RecoveryExportFlow._();

  static Future<void> run(
    BuildContext context,
    WorkspaceController controller,
    WorkbenchLabels labels,
  ) async {
    final work = controller.currentWork;
    if (work == null) return;
    final s = labels.strings;
    final exporter = RecoveryExporter(
      controller.repository,
      const FileSelectorGateway(),
    );
    try {
      final outcome = await exporter.export(
        work: work,
        chapters: controller.chapters,
        loadedStates: controller.editing.loadedStates,
      );
      if (outcome == null || !context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(labels(s.exportDone)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${labels(s.exportPathLabel)}: ${outcome.path}'),
              const SizedBox(height: 8),
              Text(labels(s.exportChapters(outcome.chapters))),
              if (outcome.omitted.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  labels(s.exportOmitted(outcome.omitted.length)),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(labels(s.closeDialog)),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      final code = error is WorkspaceFailure ? error.code : 'export_failed';
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(labels(s.exportFailed)),
          content: Text(labels(s.errorCode('\u2068$code\u2069'))),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(labels(s.closeDialog)),
            ),
          ],
        ),
      );
    }
  }
}
