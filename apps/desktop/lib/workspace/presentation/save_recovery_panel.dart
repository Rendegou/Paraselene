// 保存恢复面板：在当前会话上提供重试和导出，导出前先关闭局部路由。
// 错误状态实时订阅，不创建新仓库或复制正文；await 后只使用仍挂载的上下文。
import 'package:flutter/material.dart';
import '../../theme/workbench_theme.dart';
import '../workspace_controller.dart';
import 'export_flow.dart';
import 'save_status_snapshot.dart';
import 'workbench_chrome.dart';

/// 打开恢复面板；调用者等待路由结束，导出继续使用原宿主上下文。
Future<void> showSaveRecoveryPanel(
  BuildContext context,
  WorkspaceController controller,
  WorkbenchLabels labels,
) => showDialog<void>(
  context: context,
  builder: (dialogContext) => _SaveRecoveryPanel(
    controller: controller,
    labels: labels,
    onExport: () async {
      Navigator.of(dialogContext).pop();
      if (context.mounted) {
        await RecoveryExportFlow.run(context, controller, labels);
      }
    },
  ),
);

class _SaveRecoveryPanel extends StatelessWidget {
  const _SaveRecoveryPanel({
    required this.controller,
    required this.labels,
    required this.onExport,
  });
  final WorkspaceController controller;
  final WorkbenchLabels labels;
  final Future<void> Function() onExport;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller.editing, controller]),
    builder: (_, _) => _RecoveryDialogBody(
      controller: controller,
      labels: labels,
      onExport: onExport,
    ),
  );
}

class _RecoveryDialogBody extends StatelessWidget {
  const _RecoveryDialogBody({
    required this.controller,
    required this.labels,
    required this.onExport,
  });
  final WorkspaceController controller;
  final WorkbenchLabels labels;
  final Future<void> Function() onExport;

  @override
  Widget build(BuildContext context) {
    final s = labels.strings;
    return AlertDialog(
      key: const ValueKey('save-recovery-panel'),
      title: Text(labels(s.saveError)),
      content: SingleChildScrollView(
        child: _RecoveryDetails(
          snapshot: SaveStatusSnapshot.of(controller),
          labels: labels,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(labels(s.closeDialog)),
        ),
        TextButton(
          onPressed: controller.isBusy ? null : onExport,
          child: Text(labels(s.exportDraft)),
        ),
        FilledButton(
          autofocus: true,
          onPressed: controller.isBusy
              ? null
              : () async {
                  final route = ModalRoute.of(context);
                  final saved = await controller.retrySave();
                  if (saved && context.mounted && route?.isCurrent == true) {
                    Navigator.of(context).pop();
                  }
                },
          child: Text(labels(s.retrySave)),
        ),
      ],
    );
  }
}

class _RecoveryDetails extends StatelessWidget {
  const _RecoveryDetails({required this.snapshot, required this.labels});
  final SaveStatusSnapshot snapshot;
  final WorkbenchLabels labels;

  @override
  Widget build(BuildContext context) {
    final s = labels.strings;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          snapshot.statusText(labels),
          key: const ValueKey('save-recovery-status'),
          style: WorkbenchTokens.ui(size: 13),
        ),
        if (snapshot.restoredDraft)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 6),
            child: Text(
              labels(s.draftRestoredBase),
              style: WorkbenchTokens.ui(size: 12, color: WorkbenchTokens.muted),
            ),
          ),
        if (snapshot.errorCode != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 6),
            child: Text(
              labels(s.errorCode('\u2068${snapshot.errorCode}\u2069')),
              key: const ValueKey('save-recovery-code'),
              style: WorkbenchTokens.ui(size: 12, color: WorkbenchTokens.muted),
            ),
          ),
        if (snapshot.errorCode == 'durable_save_failed')
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 6),
            child: Text(
              labels(s.durableSaveFailed),
              style: WorkbenchTokens.ui(
                size: 12,
                color: WorkbenchTokens.warning,
              ),
            ),
          ),
      ],
    );
  }
}
