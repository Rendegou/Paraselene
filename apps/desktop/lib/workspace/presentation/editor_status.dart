// 保存状态视图：仅订阅 EditingSession/controller，不重建正文输入客户端。
// 恢复、重试和导出由既有控制器负责，完整错误始终有可访问入口。
import 'package:flutter/material.dart';
import '../../domain/editing/save_coordinator.dart';
import '../../theme/workbench_theme.dart';
import '../workspace_controller.dart';
import 'save_recovery_panel.dart';
import 'save_status_snapshot.dart';
import 'workbench_chrome.dart';

export 'save_error_banner.dart';

/// 订阅实际保存状态；compact 只改变表现，错误恢复入口仍可键盘到达。
class SaveStatusIndicator extends StatelessWidget {
  const SaveStatusIndicator({
    required this.controller,
    required this.labels,
    this.compact = false,
    super.key,
  });

  /// 作品/保存状态的所有者。
  final WorkspaceController controller;

  /// 当前界面语言及伪本地化入口。
  final WorkbenchLabels labels;

  /// 窄窗只显示点或警告图标，详细信息位于恢复面板。
  final bool compact;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller.editing, controller]),
    builder: (_, _) => _SaveStatusBody(
      controller: controller,
      labels: labels,
      compact: compact,
    ),
  );
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

  @override
  Widget build(BuildContext context) {
    final snapshot = SaveStatusSnapshot.of(controller);
    if (snapshot.isEmpty) return const SizedBox.shrink();
    final text = snapshot.statusText(labels);
    final color = snapshot.hasError
        ? WorkbenchTokens.warning
        : snapshot.status == SaveStatus.saved
        ? WorkbenchTokens.saved
        : WorkbenchTokens.muted;
    if (compact) {
      return _CompactSaveStatus(
        snapshot: snapshot,
        labels: labels,
        color: color,
        controller: controller,
      );
    }
    final content = _SaveStatusContent(
      text: text,
      color: color,
      failed: snapshot.hasError,
    );
    if (snapshot.hasError) {
      return Semantics(
        liveRegion: true,
        child: Tooltip(
          message: snapshot.description(labels),
          child: TextButton(
            onPressed: () async =>
                showSaveRecoveryPanel(context, controller, labels),
            child: content,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 2),
      child: Semantics(liveRegion: true, child: content),
    );
  }
}

class _CompactSaveStatus extends StatelessWidget {
  const _CompactSaveStatus({
    required this.snapshot,
    required this.labels,
    required this.color,
    required this.controller,
  });
  final SaveStatusSnapshot snapshot;
  final WorkbenchLabels labels;
  final Color color;
  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    if (snapshot.hasError) {
      return IconButton(
        onPressed: () async =>
            showSaveRecoveryPanel(context, controller, labels),
        tooltip: snapshot.description(labels),
        icon: Icon(
          Icons.warning_amber_rounded,
          size: 17,
          color: color,
          key: const ValueKey('save-status-error-icon'),
        ),
      );
    }
    final text = snapshot.statusText(labels);
    return Semantics(
      liveRegion: true,
      label: text,
      child: ExcludeSemantics(
        child: Tooltip(
          message: text,
          child: SizedBox(
            width: 34,
            height: 34,
            child: Center(child: _SaveDot(color: color)),
          ),
        ),
      ),
    );
  }
}

class _SaveStatusContent extends StatelessWidget {
  const _SaveStatusContent({
    required this.text,
    required this.color,
    required this.failed,
  });
  final String text;
  final Color color;
  final bool failed;

  @override
  Widget build(BuildContext context) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 6,
    children: [
      if (failed)
        Icon(Icons.warning_amber_rounded, size: 15, color: color)
      else
        _SaveDot(color: color),
      Text(
        text,
        key: const ValueKey('save-status'),
        style: WorkbenchTokens.ui(size: 12, color: color),
      ),
    ],
  );
}

class _SaveDot extends StatelessWidget {
  const _SaveDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('save-status-dot'),
    width: 6,
    height: 6,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// 工具区展示语言元数据，不由界面 locale 推断作者稿件语言。
class LanguageMetadata extends StatelessWidget {
  const LanguageMetadata({required this.labels, super.key});

  /// 当前界面的文本包装器。
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
