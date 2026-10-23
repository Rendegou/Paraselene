// 顶栏配置与业务动作：保持所有写入经过控制器，UI按约束组合。
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../cowrite/discussion_index.dart';
import '../../cowrite/discussion_thread.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/workbench_theme.dart';
import '../data/workspace_repository.dart';
import '../workspace_controller.dart';
import 'editor_action_registry.dart';
import 'export_flow.dart';
import 'toolbar_row.dart';
import 'workbench_dialogs.dart';
import 'workbench_labels.dart';

/// 顶部工具栏：左侧作品名与保存状态，右侧对齐原版的扁平文字操作。
///
/// [actions] 由编辑器注册；为 null 时只显示目录级操作（用于空态）。
/// [onShowSidebar] 非 null 时显示展开目录按钮（目录收起或抽屉模式）。
class WorkbenchToolbar extends StatelessWidget {
  const WorkbenchToolbar({
    required this.controller,
    required this.labels,
    required this.locale,
    required this.onLocaleChanged,
    required this.focus,
    required this.wide,
    required this.onFocus,
    required this.onWide,
    this.actions,
    this.onShowSidebar,
    super.key,
  });

  /// 当前作品会话的权威控制器，写入只经过公开命令。
  final WorkspaceController controller;

  /// 界面文案适配器，不转换作者内容。
  final WorkbenchLabels labels;

  /// 当前界面语言，与作品和输出语言独立。
  final Locale locale;

  /// 只修改界面语言，不转换作品内容。
  final ValueChanged<Locale> onLocaleChanged;

  /// 当前专注状态，仅改变工具区可见性。
  final bool focus;

  /// 是否使用宽稿上限，不缩放作者正文。
  final bool wide;

  /// 恢复正文焦点，不创建新的输入客户端。
  final VoidCallback onFocus;

  /// 切换阅读宽度，沿用现有持久偏好。
  final VoidCallback onWide;

  /// 当前编辑器注册的能力，未挂载时为空。
  final EditorActionRegistry? actions;

  /// 目录收起后恢复同一导航入口。
  final VoidCallback? onShowSidebar;

  /// 当前界面标签，独立于作品和模型输出语言。
  AppLocalizations get strings => labels.strings;

  /// 当前是否有可执行章节操作的编辑会话。
  bool get hasChapter => controller.editing.hasOpenChapter;

  /// 当前是否具备真实 Rust 桥接，不表示作者数据验收已通过。
  bool get real => controller.repository.mode == WorkspaceMode.realBridge;

  /// 准备确认材料并等待对话框关闭，写入仍需作者明确采纳。
  Future<void> confirm(BuildContext context) async {
    final prepared = await controller.prepareConfirmation();
    if (prepared == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => ConfirmChapterDialog(
        controller: controller,
        labels: labels,
        prepared: prepared,
      ),
    );
  }

  /// 打开版本视图；返回的 Future 在视图关闭后完成。
  Future<void> versions(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => VersionsDialog(controller: controller, labels: labels),
  );

  /// 通过现有恢复导出流程选择目标，取消不会写文件。
  Future<void> export(BuildContext context) =>
      RecoveryExportFlow.manuscript(context, controller, labels);

  /// 打开本章完整讨论索引；选择条目后按真实线程 ID 重开，不新建线程。
  Future<void> showIndex(BuildContext context) async {
    final threads = actions?.threads ?? const <DiscussionThread>[];
    if (threads.isEmpty) return;
    await showDiscussionIndex(
      context,
      threads: threads,
      strings: strings,
      onOpen: openThread,
    );
  }

  /// 按真实线程身份重开，失效处理交由编辑器能力接缝负责。
  void openThread(DiscussionThread thread) =>
      actions?.onOpenThread?.call(thread);

  @override
  Widget build(BuildContext context) => Container(
    height: math.max(
      WorkbenchTokens.toolbarHeight,
      MediaQuery.textScalerOf(context).scale(24) + 16,
    ),
    padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
    decoration: const BoxDecoration(
      color: WorkbenchTokens.toolbar,
      border: Border(bottom: BorderSide(color: WorkbenchTokens.stroke)),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) =>
          ToolbarRow(toolbar: this, availableWidth: constraints.maxWidth),
    ),
  );

  /// 显示语言元数据未知状态，不按界面 locale 猜测作品语言。
  Future<void> showLanguageInfo(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(strings.languageLabel),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${strings.workLanguage}: ${strings.undeterminedLanguage}'),
          const SizedBox(height: 6),
          Text('${strings.documentLanguage}: ${strings.undeterminedLanguage}'),
          const SizedBox(height: 6),
          Text('${strings.outputLanguage}: ${strings.undeterminedLanguage}'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.closeDialog),
        ),
      ],
    ),
  );
}
