// 保存状态视图：直接订阅 EditingSession，展示保存/冲突/失败，并提供恢复入口。
// 读边界：状态只来自 EditingSession.saveState 与 controller 的屏障错误，不读取仓库。
// 写边界：重试走 controller.retrySave；导出走 RecoveryExportFlow；本文件不写正文。
// 关键不变量：保存状态变化只重建保存区，不重建正文编辑器的 document/input client；
// 错误必须可见、可聚焦且能键盘到达，Tooltip 不能是唯一解释或唯一入口。
import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/editing/save_coordinator.dart';
import '../../theme/workbench_theme.dart';
import '../workspace_controller.dart';
import 'export_flow.dart';
import 'workbench_chrome.dart';

/// 一次保存状态的只读快照，供工具栏与恢复面板共同渲染。
final class _SaveSnapshot {
  const _SaveSnapshot({
    required this.status,
    required this.text,
    required this.errorCode,
    required this.draftNotice,
  });

  factory _SaveSnapshot.of(WorkspaceController controller) {
    final state = controller.editing.saveState;
    final status = state?.status;
    final errorCode = state?.errorCode ?? controller.errorCode;
    final text = switch (status) {
      SaveStatus.dirty => 'dirty',
      SaveStatus.saving => 'saving',
      SaveStatus.saved => 'saved',
      SaveStatus.conflict => 'conflict',
      SaveStatus.error => 'error',
      null => errorCode == null ? null : 'error',
    };
    return _SaveSnapshot(
      status: status,
      text: text,
      errorCode: errorCode,
      draftNotice: state != null && state.baseHead != state.head
          ? 'draft-restored'
          : null,
    );
  }

  final SaveStatus? status;
  final String? text;
  final String? errorCode;
  final String? draftNotice;

  bool get hasError => errorCode != null || status == SaveStatus.error;

  bool get isConflict => status == SaveStatus.conflict;

  bool get isEmpty => text == null && errorCode == null && draftNotice == null;
}

/// 保存状态组件：宽窗显示状态点+文字，窄窗显示状态点/警告图标，错误可打开恢复面板。
///
/// 通过 [ListenableBuilder] 同时订阅 EditingSession 与 controller：保存协调器只
/// 通知 EditingSession，若外层只监听 controller，状态文字会停留在旧值。
class SaveStatusIndicator extends StatelessWidget {
  const SaveStatusIndicator({
    required this.controller,
    required this.labels,
    this.compact = false,
    super.key,
  });

  final WorkspaceController controller;
  final WorkbenchLabels labels;

  /// 窄窗/大字号：只保留状态点或警告图标，完整文案放进恢复面板。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller.editing, controller]),
      builder: (context, _) => _SaveStatusBody(
        controller: controller,
        labels: labels,
        compact: compact,
      ),
    );
  }
}

class _SaveStatusBody extends StatelessWidget {
  const _SaveStatusBody({
    required this.controller,
    required this.labels,
    required this.compact,
  });

  final WorkspaceController controller;
  final WorkbenchLabels labels;
  final bool compact;

  String _statusText(_SaveSnapshot snapshot) {
    final s = labels.strings;
    return switch (snapshot.text) {
      'dirty' => labels(s.saveDirty),
      'saving' => labels(s.saveSaving),
      'saved' => labels(s.saveSaved),
      'conflict' => labels(s.saveConflict),
      'error' => labels(s.saveError),
      _ => '',
    };
  }

  String _errorDescription(_SaveSnapshot snapshot, String text) {
    final s = labels.strings;
    final parts = <String>[text];
    if (snapshot.draftNotice != null) {
      parts.add(labels(s.draftRestoredBase));
    }
    if (snapshot.errorCode != null) {
      parts.add(labels(s.errorCode('\u2068${snapshot.errorCode}\u2069')));
    }
    return parts.where((part) => part.isNotEmpty).join('；');
  }

  Color _color(_SaveSnapshot snapshot) {
    if (snapshot.hasError || snapshot.isConflict) {
      return WorkbenchTokens.warning;
    }
    if (snapshot.status == SaveStatus.saved) return WorkbenchTokens.saved;
    return WorkbenchTokens.muted;
  }

  Future<void> _openRecoveryPanel(BuildContext context) async {
    final hostContext = context;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _SaveRecoveryPanel(
        controller: controller,
        labels: labels,
        onExport: () {
          Navigator.of(dialogContext).pop();
          if (hostContext.mounted) {
            unawaited(RecoveryExportFlow.run(hostContext, controller, labels));
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _SaveSnapshot.of(controller);
    if (snapshot.isEmpty) return const SizedBox.shrink();
    final text = _statusText(snapshot);
    final color = _color(snapshot);
    if (compact) {
      return Semantics(
        liveRegion: true,
        button: snapshot.hasError,
        label: snapshot.hasError ? _errorDescription(snapshot, text) : text,
        child: Tooltip(
          message: text,
          child: InkWell(
            onTap: snapshot.hasError
                ? () => unawaited(_openRecoveryPanel(context))
                : null,
            borderRadius: BorderRadius.circular(WorkbenchTokens.radius),
            child: SizedBox(
              width: 34,
              height: 34,
              child: Center(
                child: snapshot.hasError
                    ? Icon(
                        Icons.warning_amber_rounded,
                        size: 17,
                        color: color,
                        key: const ValueKey('save-status-error-icon'),
                      )
                    : Container(
                        key: const ValueKey('save-status-dot'),
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
              ),
            ),
          ),
        ),
      );
    }
    final dot = snapshot.hasError
        ? Icon(Icons.warning_amber_rounded, size: 15, color: color)
        : Container(
            key: const ValueKey('save-status-dot'),
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          );
    // 用 Wrap 而不是 Row：顶栏空间被压缩时，状态文字换行而不是溢出。
    final content = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        dot,
        Text(
          text,
          key: const ValueKey('save-status'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: WorkbenchTokens.ui(size: 12, color: color),
        ),
      ],
    );
    if (!snapshot.hasError) {
      return Padding(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 2),
        child: Semantics(liveRegion: true, child: content),
      );
    }
    // 失败时工具栏只保留可点击的状态区；完整重试/导出放在内容外的错误条，
    // 避免错误文案挤占顶栏导致窄窗口溢出。
    return Tooltip(
      message: labels.strings.saveError,
      child: InkWell(
        onTap: () => unawaited(_openRecoveryPanel(context)),
        borderRadius: BorderRadius.circular(WorkbenchTokens.radius),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 2,
            vertical: 4,
          ),
          child: Semantics(
            liveRegion: true,
            button: true,
            label: _errorDescription(snapshot, text),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// 保存失败错误条：位于内容区上方、纸面之外，所有宽度都直接可见可操作。
///
/// 与工具栏状态区不同，这里始终显示失败/冲突文案、错误码、草稿基线差异，
/// 并提供重试保存与导出草稿；使用 Wrap 在 360×200% 下自然换行而不溢出。
class SaveErrorBanner extends StatelessWidget {
  const SaveErrorBanner({
    required this.controller,
    required this.labels,
    super.key,
  });

  final WorkspaceController controller;
  final WorkbenchLabels labels;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller.editing, controller]),
      builder: (context, _) {
        // 加载/重读失败由内容区错误态完整解释并带重试，此处不重复报同一错误码。
        if (controller.phase == WorkspacePhase.error) {
          return const SizedBox.shrink();
        }
        final snapshot = _SaveSnapshot.of(controller);
        if (!snapshot.hasError) return const SizedBox.shrink();
        return _SaveErrorBannerBody(
          controller: controller,
          labels: labels,
          snapshot: snapshot,
        );
      },
    );
  }
}

class _SaveErrorBannerBody extends StatelessWidget {
  const _SaveErrorBannerBody({
    required this.controller,
    required this.labels,
    required this.snapshot,
  });

  final WorkspaceController controller;
  final WorkbenchLabels labels;
  final _SaveSnapshot snapshot;

  String get _statusText {
    final s = labels.strings;
    return switch (snapshot.text) {
      'dirty' => labels(s.saveDirty),
      'saving' => labels(s.saveSaving),
      'saved' => labels(s.saveSaved),
      'conflict' => labels(s.saveConflict),
      _ => labels(s.saveError),
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = labels.strings;
    final busy = controller.isBusy;
    return Semantics(
      container: true,
      liveRegion: true,
      label: _statusText,
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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 17,
                  color: WorkbenchTokens.warning,
                ),
                const SizedBox(width: 7),
                Text(
                  _statusText,
                  key: const ValueKey('save-error-text'),
                  style: WorkbenchTokens.ui(
                    size: 13,
                    color: WorkbenchTokens.warning,
                  ),
                ),
              ],
            ),
            if (snapshot.draftNotice != null)
              Text(
                labels(s.draftRestoredBase),
                style: WorkbenchTokens.ui(
                  size: 12,
                  color: WorkbenchTokens.muted,
                ),
              ),
            if (snapshot.errorCode != null)
              Text(
                labels(s.errorCode('\u2068${snapshot.errorCode}\u2069')),
                key: const ValueKey('save-error-code'),
                style: WorkbenchTokens.ui(
                  size: 12,
                  color: WorkbenchTokens.muted,
                ),
              ),
            if (snapshot.errorCode == 'durable_save_failed')
              Text(
                labels(s.durableSaveFailed),
                style: WorkbenchTokens.ui(
                  size: 12,
                  color: WorkbenchTokens.warning,
                ),
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: busy
                      ? null
                      : () => unawaited(controller.retrySave()),
                  child: Text(labels(s.retrySave)),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => unawaited(
                          RecoveryExportFlow.run(context, controller, labels),
                        ),
                  child: Text(labels(s.exportDraft)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 保存失败恢复面板：所有宽度都能看到完整状态、错误码与出口。
class _SaveRecoveryPanel extends StatelessWidget {
  const _SaveRecoveryPanel({
    required this.controller,
    required this.labels,
    required this.onExport,
  });

  final WorkspaceController controller;
  final WorkbenchLabels labels;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller.editing, controller]),
      builder: (context, _) {
        final s = labels.strings;
        final snapshot = _SaveSnapshot.of(controller);
        final statusText = switch (snapshot.text) {
          'dirty' => labels(s.saveDirty),
          'saving' => labels(s.saveSaving),
          'saved' => labels(s.saveSaved),
          'conflict' => labels(s.saveConflict),
          'error' => labels(s.saveError),
          _ => labels(s.saveError),
        };
        return AlertDialog(
          key: const ValueKey('save-recovery-panel'),
          title: Text(labels(s.saveError)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusText,
                  key: const ValueKey('save-recovery-status'),
                  style: WorkbenchTokens.ui(size: 13),
                ),
                if (snapshot.draftNotice != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: 6),
                    child: Text(
                      labels(s.draftRestoredBase),
                      style: WorkbenchTokens.ui(
                        size: 12,
                        color: WorkbenchTokens.muted,
                      ),
                    ),
                  ),
                if (snapshot.errorCode != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: 6),
                    child: Text(
                      labels(s.errorCode('\u2068${snapshot.errorCode}\u2069')),
                      key: const ValueKey('save-recovery-code'),
                      style: WorkbenchTokens.ui(
                        size: 12,
                        color: WorkbenchTokens.muted,
                      ),
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
                      await controller.retrySave();
                      if (context.mounted) Navigator.of(context).pop();
                    },
              child: Text(labels(s.retrySave)),
            ),
          ],
        );
      },
    );
  }
}

/// Language metadata stays available outside the paper; it never guesses locales.
///
/// 语言元数据行：来源未知时统一显示未确定，不按界面 locale 猜测作品语言。
class LanguageMetadata extends StatelessWidget {
  const LanguageMetadata({required this.labels, super.key});
  final WorkbenchLabels labels;
  @override
  Widget build(BuildContext context) {
    final s = labels.strings;
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        Text(labels('${s.workLanguage}: ${s.undeterminedLanguage}')),
        Text(labels('${s.documentLanguage}: ${s.undeterminedLanguage}')),
        Text(labels('${s.outputLanguage}: ${s.undeterminedLanguage}')),
      ],
    );
  }
}
