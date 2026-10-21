// 顶栏按可用宽度与文字缩放组合；动作入口不会因窄窗消失。
import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/workbench_theme.dart';
import 'editor_status.dart';
import 'toolbar_controls.dart';
import 'toolbar_menus.dart';
import 'toolbar_more_menu.dart';
import 'workbench_toolbar.dart';

/// 根据窗口约束选择普通、紧凑和折叠入口。
class ToolbarRow extends StatelessWidget {
  const ToolbarRow({
    required this.toolbar,
    required this.availableWidth,
    super.key,
  });

  /// 当前帧的只读工具栏配置，不由组件持久化。
  final WorkbenchToolbar toolbar;

  /// 父约束提供的可用宽度，单位为逻辑像素。
  final double availableWidth;
  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final compact = availableWidth < 1120 * scale;
    final narrow = availableWidth < 760 * scale;
    return Row(
      children: [
        if (toolbar.onShowSidebar != null)
          ToolbarButton(
            icon: Icons.view_sidebar_outlined,
            tooltip: toolbar.strings.chapters,
            onPressed: toolbar.onShowSidebar,
          ),
        Flexible(
          child: ToolbarDocumentTitle(toolbar: toolbar, narrow: narrow),
        ),
        const Spacer(),
        ToolbarEditorActions(
          toolbar: toolbar,
          compact: compact,
          narrow: narrow,
        ),
        if (!narrow) ...[
          const SizedBox(width: 2),
          ToolbarChapterMenu(toolbar: toolbar, compact: compact),
          ToolbarModelButton(toolbar: toolbar),
          ToolbarLayoutMenu(toolbar: toolbar, compact: compact),
          ToolbarFocusButton(toolbar: toolbar, compact: compact),
          ToolbarChapterDiscussion(toolbar: toolbar, compact: compact),
          ToolbarExportMenu(toolbar: toolbar, compact: compact),
          ToolbarLanguageMenu(toolbar: toolbar, compact: compact),
        ],
        ToolbarMoreMenu(toolbar: toolbar, compact: compact, narrow: narrow),
      ],
    );
  }
}

/// 当前作品标题及订阅式保存状态，不控制正文生命周期。
class ToolbarDocumentTitle extends StatelessWidget {
  const ToolbarDocumentTitle({
    required this.toolbar,
    required this.narrow,
    super.key,
  });

  /// 当前帧的只读工具栏配置，不由组件持久化。
  final WorkbenchToolbar toolbar;

  /// 是否折叠次要操作，核心入口仍可达。
  final bool narrow;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Flexible(
        child: Text(
          toolbar.controller.currentWork?.title ??
              toolbar.strings.workspaceTitle,
          style: WorkbenchTokens.ui(size: 15, weight: FontWeight.w500),
        ),
      ),
      const SizedBox(width: 12),
      Flexible(
        child: SaveStatusIndicator(
          controller: toolbar.controller,
          labels: toolbar.labels,
          compact: narrow,
        ),
      ),
    ],
  );
}

/// 编辑器作用域动作，直接监听选区和讨论状态。
class ToolbarEditorActions extends StatelessWidget {
  const ToolbarEditorActions({
    required this.toolbar,
    required this.compact,
    required this.narrow,
    super.key,
  });

  /// 当前帧的只读工具栏配置，不由组件持久化。
  final WorkbenchToolbar toolbar;

  /// 是否只展示图标；可访问名称仍保留。
  final bool compact;

  /// 是否折叠次要操作，核心入口仍可达。
  final bool narrow;
  @override
  Widget build(BuildContext context) {
    final registry = toolbar.actions;
    if (registry == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: registry,
      builder: (context, _) => ToolbarEditorActionRow(
        toolbar: toolbar,
        compact: compact,
        narrow: narrow,
      ),
    );
  }
}

/// 查找、选段讨论和讨论索引共用共享按钮底座。
class ToolbarEditorActionRow extends StatelessWidget {
  const ToolbarEditorActionRow({
    required this.toolbar,
    required this.compact,
    required this.narrow,
    super.key,
  });

  /// 当前帧的只读工具栏配置，不由组件持久化。
  final WorkbenchToolbar toolbar;

  /// 是否只展示图标；可访问名称仍保留。
  final bool compact;

  /// 是否折叠次要操作，核心入口仍可达。
  final bool narrow;
  @override
  Widget build(BuildContext context) {
    final registry = toolbar.actions!;
    final s = toolbar.strings;
    final canDiscuss = registry.canDiscuss && !toolbar.controller.isBusy;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!narrow && canDiscuss)
          ToolbarButton(
            icon: Icons.chat_bubble_outline,
            label: s.discussSelection,
            accent: true,
            tooltip:
                '${s.selectionCount(registry.selectedCodePoints)} · ${s.discussSelection}',
            onPressed: registry.onDiscussSelection,
          ),
        ToolbarButton(
          icon: Icons.search,
          label: s.findInChapter,
          tooltip: s.findInChapter,
          compact: compact,
          selected: registry.findOpen,
          onPressed: registry.onFind,
        ),
        if (narrow && canDiscuss)
          ToolbarButton(
            icon: Icons.chat_bubble_outline,
            accent: true,
            tooltip:
                '${s.selectionCount(registry.selectedCodePoints)} · ${s.discussSelection}',
            onPressed: registry.onDiscussSelection,
          ),
        if (registry.threads.isNotEmpty)
          ToolbarDiscussionIndex(toolbar: toolbar, compact: compact || narrow),
      ],
    );
  }
}

/// 讨论索引的未保存草稿角标，不改变索引入口的命中范围。
class ToolbarDiscussionIndex extends StatelessWidget {
  const ToolbarDiscussionIndex({
    required this.toolbar,
    required this.compact,
    super.key,
  });

  /// 当前帧的只读工具栏配置，不由组件持久化。
  final WorkbenchToolbar toolbar;

  /// 是否只展示图标；可访问名称仍保留。
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final threads = toolbar.actions!.threads;
    final label = toolbar.strings.discussionIndex(threads.length);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ToolbarButton(
          icon: Icons.forum_outlined,
          label: label,
          tooltip: label,
          compact: compact,
          onPressed: () => unawaited(toolbar.showIndex(context)),
        ),
        if (threads.any((thread) => thread.dirty))
          PositionedDirectional(
            top: 3,
            end: 3,
            child: IgnorePointer(
              child: Container(
                key: const ValueKey('discussion-unsaved-dot'),
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: WorkbenchTokens.accent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
