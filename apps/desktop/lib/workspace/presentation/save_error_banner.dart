// 保存错误条：始终显示在纸面之外，长错误和大字号可换行，恢复动作持续可达。
// 仅订阅控制器/编辑会话；重试和导出通过各自既有业务入口。
import 'package:flutter/material.dart';
import '../../theme/workbench_theme.dart';
import '../workspace_controller.dart';
import 'export_flow.dart';
import 'save_status_snapshot.dart';
import 'workbench_chrome.dart';

/// 所有窗口宽度均展示实际保存失败；内容区错误态负责自己的加载失败。
class SaveErrorBanner extends StatelessWidget {
  const SaveErrorBanner({
    required this.controller,
    required this.labels,
    super.key,
  });

  /// 保存状态与重试动作所有者。
  final WorkspaceController controller;

  /// 当前界面的文本包装器。
  final WorkbenchLabels labels;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller.editing, controller]),
    builder: (_, _) {
      if (controller.phase == WorkspacePhase.error) {
        return const SizedBox.shrink();
      }
      final snapshot = SaveStatusSnapshot.of(controller);
      if (!snapshot.hasError) return const SizedBox.shrink();
      return _ErrorBannerBody(
        controller: controller,
        labels: labels,
        snapshot: snapshot,
      );
    },
  );
}

class _ErrorBannerBody extends StatelessWidget {
  const _ErrorBannerBody({
    required this.controller,
    required this.labels,
    required this.snapshot,
  });
  final WorkspaceController controller;
  final WorkbenchLabels labels;
  final SaveStatusSnapshot snapshot;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    label: snapshot.statusText(labels),
    child: Container(
      key: const ValueKey('save-error-banner'),
      width: double.infinity,
      padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 8),
      color: WorkbenchTokens.warning.withValues(alpha: 0.08),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 4,
        children: [
          _ErrorBannerTitle(text: snapshot.statusText(labels)),
          SaveFailureDetails(snapshot: snapshot, labels: labels),
          Wrap(
            children: [
              TextButton(
                onPressed: controller.isBusy
                    ? null
                    : () async {
                        await controller.retrySave();
                      },
                child: Text(labels(labels.strings.retrySave)),
              ),
              TextButton(
                onPressed: controller.isBusy
                    ? null
                    : () async {
                        await RecoveryExportFlow.run(
                          context,
                          controller,
                          labels,
                        );
                      },
                child: Text(labels(labels.strings.exportDraft)),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _ErrorBannerTitle extends StatelessWidget {
  const _ErrorBannerTitle({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 8,
    children: [
      const Icon(
        Icons.warning_amber_rounded,
        size: 17,
        color: WorkbenchTokens.warning,
      ),
      Text(
        text,
        key: const ValueKey('save-error-text'),
        style: WorkbenchTokens.ui(size: 13, color: WorkbenchTokens.warning),
      ),
    ],
  );
}

/// 错误的补充信息；用于错误条，完整句子随可用宽度换行。
class SaveFailureDetails extends StatelessWidget {
  const SaveFailureDetails({
    required this.snapshot,
    required this.labels,
    super.key,
  });

  /// 当前保存错误快照。
  final SaveStatusSnapshot snapshot;

  /// 当前界面的文本包装器。
  final WorkbenchLabels labels;

  @override
  Widget build(BuildContext context) {
    final s = labels.strings;
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        if (snapshot.restoredDraft)
          Text(
            labels(s.draftRestoredBase),
            style: WorkbenchTokens.ui(size: 12, color: WorkbenchTokens.muted),
          ),
        if (snapshot.errorCode != null)
          Text(
            labels(s.errorCode('\u2068${snapshot.errorCode}\u2069')),
            key: const ValueKey('save-error-code'),
            style: WorkbenchTokens.ui(size: 12, color: WorkbenchTokens.muted),
          ),
        if (snapshot.errorCode == 'durable_save_failed')
          Text(
            labels(s.durableSaveFailed),
            style: WorkbenchTokens.ui(size: 12, color: WorkbenchTokens.warning),
          ),
      ],
    );
  }
}
