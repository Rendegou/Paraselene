// 恢复/手稿导出流程：在恢复屏障内调用 RecoveryExporter，并用本地化对话框反馈结果。
// 读边界：通过 WorkspaceController 读取当前作品、章节与内存草稿，不额外写仓库。
// 写边界：只写用户在系统对话框中选择的文件；是否已持有屏障由调用方声明。
// 关键不变量：取消对话框返回 cancelled 且不提示；错误码稳定展示，导出不改变正文。
import 'package:flutter/material.dart';

import '../data/real_workspace_repository.dart';
import '../data/recovery_export.dart';
import '../data/workspace_repository.dart';
import '../workspace_controller.dart';
import 'workbench_chrome.dart';

/// Verified export, user cancellation, and write/read-back failure.
///
/// 导出结果：成功、用户取消，或写入/读回校验失败。
enum RecoveryExportResult { success, cancelled, failed }

/// Recovery keeps only the draft transcript; manuscript appends confirmed lore.
///
/// 导出模式：恢复模式只含草稿誊本，手稿模式追加已确认设定资料。
enum ExportMode { recovery, manuscript }

/// Runs an export against the real Windows save dialog and reports the actual
/// path, chapter count, omissions and appended lore; cancel shows nothing.
///
/// 导出流程入口：统一处理屏障、系统保存对话框、结果提示与稳定错误码展示。
final class RecoveryExportFlow {
  const RecoveryExportFlow._();

  /// 在恢复屏障内执行一次导出并返回结果；barrierHeld 为真时假定调用方已持有屏障。
  ///
  /// 用户取消保存对话框时返回 cancelled；异常转为 failed 并显示稳定错误码。
  static Future<RecoveryExportResult> run(
    BuildContext context,
    WorkspaceController controller,
    WorkbenchLabels labels, {
    SavePathGateway gateway = const FileSelectorGateway(),
    bool barrierHeld = false,
    ExportMode mode = ExportMode.recovery,
  }) async {
    if (barrierHeld) {
      return _run(context, controller, labels, gateway: gateway, mode: mode);
    }
    var result = RecoveryExportResult.cancelled;
    await controller.recoveryBarrier(() async {
      result = await _run(
        context,
        controller,
        labels,
        gateway: gateway,
        mode: mode,
      );
    });
    return result;
  }

  /// Full manuscript plus confirmed lore through the same verified writer.
  ///
  /// 导出完整手稿并追加已确认设定资料；扩展名为 md，校验与提示复用同一条流程。
  static Future<RecoveryExportResult> manuscript(
    BuildContext context,
    WorkspaceController controller,
    WorkbenchLabels labels, {
    SavePathGateway gateway = const FileSelectorGateway(),
  }) => run(
    context,
    controller,
    labels,
    gateway: gateway,
    mode: ExportMode.manuscript,
  );

  static Future<RecoveryExportResult> _run(
    BuildContext context,
    WorkspaceController controller,
    WorkbenchLabels labels, {
    SavePathGateway gateway = const FileSelectorGateway(),
    ExportMode mode = ExportMode.recovery,
  }) async {
    final work = controller.currentWork;
    if (work == null) return RecoveryExportResult.cancelled;
    final s = labels.strings;
    final repository = controller.repository;
    final real = repository is RealWorkspaceRepository ? repository : null;
    final exporter = RecoveryExporter(
      repository,
      gateway,
      loadLore: mode == ExportMode.manuscript && real != null
          ? (workId) async {
              final rows = await real.lore.list(workId);
              final entries = <(String, String)>[];
              for (final row in rows) {
                final entry = row['entry'];
                final head = row['head'];
                if (entry is! Map || head is! Map) continue;
                final name = entry['name'] as String? ?? '';
                final body = head['body'] as String? ?? '';
                if (name.isEmpty || body.isEmpty) continue;
                entries.add((name, body));
              }
              return entries;
            }
          : null,
    );
    try {
      final outcome = await exporter.export(
        work: work,
        chapters: controller.chapters,
        loadedStates: controller.editing.loadedStates,
        filenameSuffix: mode == ExportMode.manuscript
            ? s.exportManuscriptSuffix
            : s.recoveryFilenameSuffix,
        includeLore: mode == ExportMode.manuscript,
        extension: mode == ExportMode.manuscript ? 'md' : 'txt',
      );
      if (outcome == null) return RecoveryExportResult.cancelled;
      if (!context.mounted) return RecoveryExportResult.failed;
      await _showOutcome(context, labels, outcome, mode);
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
    ExportMode mode,
  ) {
    final s = labels.strings;
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          labels(
            mode == ExportMode.manuscript ? s.exportWorkDone : s.exportDone,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${labels(s.exportPathLabel)}: ${outcome.path}'),
            const SizedBox(height: 8),
            Text(labels(s.exportChapters(outcome.chapters))),
            if (outcome.loreEntries > 0) ...[
              const SizedBox(height: 4),
              Text(labels(s.exportLoreCount(outcome.loreEntries))),
            ],
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
