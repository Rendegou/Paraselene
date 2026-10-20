// 工作台内容区：纸面、空态与错误态；正式内容交给手稿编辑面。
//
// 只读取 controller 的加载阶段与错误码；不写库、不加载未打开章节正文。
// 技术错误码原样展示，不泄露异常字符串或私有路径。
import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/workbench_theme.dart';
import '../workspace_controller.dart';
import 'editor_action_registry.dart';
import 'manuscript_editor.dart';
import 'workbench_chrome.dart';

/// 内容区按加载阶段分发；正式写作、空库与错误态共用同一纸面底色。
class WorkbenchContent extends StatelessWidget {
  const WorkbenchContent({
    required this.controller,
    required this.labels,
    required this.wide,
    required this.actions,
    this.onExitFocus,
    super.key,
  });
  final WorkspaceController controller;
  final WorkbenchLabels labels;
  final bool wide;
  final EditorActionRegistry actions;

  /// 专注模式的退出动作；由工作台按当前是否专注传入，编辑器据此做最外层 Escape。
  final VoidCallback? onExitFocus;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: WorkbenchTokens.paper,
    child: switch (controller.phase) {
      WorkspacePhase.loading => const Center(
        child: SizedBox(
          width: 160,
          child: LinearProgressIndicator(minHeight: 2),
        ),
      ),
      WorkspacePhase.empty => _EmptyState(
        labels: labels,
        title: labels.strings.noWorksTitle,
        body: labels.strings.noWorksBody,
        action: labels.strings.createDemo,
        onAction: () => unawaited(controller.seedDemo()),
      ),
      WorkspacePhase.error => _EmptyState(
        labels: labels,
        title: labels.strings.errorTitle,
        body: labels.strings.errorBody,
        technicalCode: controller.errorCode,
        action: labels.strings.retry,
        onAction: () => unawaited(controller.refresh()),
      ),
      WorkspacePhase.content => ManuscriptEditor(
        controller: controller,
        labels: labels,
        wide: wide,
        actions: actions,
        onExitFocus: onExitFocus,
      ),
    },
  );
}

/// 居中空态/错误态：标题、说明、可选技术码与一个主操作。
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.labels,
    required this.title,
    this.body,
    this.technicalCode,
    this.action,
    this.onAction,
  });
  final WorkbenchLabels labels;
  final String title;
  final String? body;
  final String? technicalCode;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsetsDirectional.all(48),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              labels(title),
              textAlign: TextAlign.center,
              style: WorkbenchTokens.ui(
                size: 22,
                weight: FontWeight.w500,
                height: 1.7,
              ),
            ),
            if (body != null) ...[
              const SizedBox(height: 12),
              Text(
                labels(body!),
                textAlign: TextAlign.center,
                style: WorkbenchTokens.ui(
                  size: 14,
                  color: WorkbenchTokens.muted,
                  height: 1.9,
                ),
              ),
            ],
            if (technicalCode != null) ...[
              const SizedBox(height: 10),
              Text(
                labels(labels.strings.errorCode('\u2068$technicalCode\u2069')),
                textAlign: TextAlign.center,
                style: WorkbenchTokens.ui(
                  size: 12,
                  color: WorkbenchTokens.muted,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 20),
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: WorkbenchTokens.accent,
                  minimumSize: const Size(48, 48),
                ),
                child: Text(labels(action!)),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
