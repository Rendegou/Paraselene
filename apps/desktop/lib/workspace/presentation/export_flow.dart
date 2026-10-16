import 'package:flutter/material.dart';

import '../data/recovery_export.dart';
import '../data/workspace_repository.dart';
import '../workspace_controller.dart';
import 'workbench_chrome.dart';

/// Verified export, user cancellation, and write/read-back failure.
enum RecoveryExportResult { success, cancelled, failed }

/// Runs the recovery export against the real Windows save dialog and reports
/// the actual path, chapter count and omissions; cancel shows nothing.
final class RecoveryExportFlow {
  const RecoveryExportFlow._();

  static Future<RecoveryExportResult> run(
    BuildContext context,
    WorkspaceController controller,
    WorkbenchLabels labels, {
    SavePathGateway gateway = const FileSelectorGateway(),
    bool barrierHeld = false,
  }) async {
    if (barrierHeld) return _run(context, controller, labels, gateway: gateway);
    var result = RecoveryExportResult.cancelled;
    await controller.recoveryBarrier(() async {
      result = await _run(context, controller, labels, gateway: gateway);
    });
    return result;
  }

  static Future<RecoveryExportResult> _run(
    BuildContext context,
    WorkspaceController controller,
    WorkbenchLabels labels, {
    SavePathGateway gateway = const FileSelectorGateway(),
  }) async {
    final work = controller.currentWork;
    if (work == null) return RecoveryExportResult.cancelled;
    final s = labels.strings;
    final exporter = RecoveryExporter(controller.repository, gateway);
    try {
      final outcome = await exporter.export(
        work: work,
        chapters: controller.chapters,
        loadedStates: controller.editing.loadedStates,
        filenameSuffix: s.recoveryFilenameSuffix,
      );
      if (outcome == null) return RecoveryExportResult.cancelled;
      if (!context.mounted) return RecoveryExportResult.failed;
      await _showOutcome(context, labels, outcome);
      return RecoveryExportResult.success;
    } catch (error) {
      if (!context.mounted) return RecoveryExportResult.failed;
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
      return RecoveryExportResult.failed;
    }
  }

  static Future<void> _showOutcome(
    BuildContext context,
    WorkbenchLabels labels,
    ExportOutcome outcome,
  ) {
    final s = labels.strings;
    return showDialog<void>(
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
  }
}
