// 折叠菜单按打开时的能力生成，所有动作保持原业务身份。
import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/workbench_controls.dart';
import '../../theme/workbench_theme.dart';
import 'toolbar_controls.dart';
import 'workbench_toolbar.dart';
import 'editor_tools.dart';

/// 折叠菜单按打开时的能力生成条目，选中动作按明确身份分发。
class ToolbarMoreMenu extends StatelessWidget {
  const ToolbarMoreMenu({
    required this.toolbar,
    required this.compact,
    this.narrow = false,
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
    return PopupMenuButton<Object>(
      style: WorkbenchControls.menuTrigger(),
      borderRadius: BorderRadius.circular(WorkbenchTokens.radius),
      tooltip: toolbar.strings.moreTools,
      onSelected: (value) => _select(context, value),
      itemBuilder: _items,
      icon: ToolbarMenuTrigger(
        icon: Icons.more_horiz,
        label: toolbar.strings.moreTools,
        compact: compact,
      ),
    );
  }

  void _select(BuildContext context, Object value) {
    if (value is WorkspaceTool) {
      unawaited(
        openWorkspaceTool(
          context,
          toolbar.controller,
          toolbar.labels,
          toolbar.actions?.editor,
          value,
        ),
      );
    } else if (value == 'sources') {
      toolbar.actions?.onRefreshSources?.call();
    } else if (value == 'languages') {
      unawaited(toolbar.showLanguageInfo(context));
    } else if (value == 'discuss') {
      toolbar.actions?.onDiscussSelection?.call();
    } else if (value == 'chapterDiscussion') {
      toolbar.actions?.onChapterDiscussion?.call();
    } else if (value == 'confirm') {
      unawaited(toolbar.confirm(context));
    } else if (value == 'versions') {
      unawaited(toolbar.versions(context));
    } else if (value == 'focus') {
      toolbar.onFocus();
    } else if (value == 'export') {
      unawaited(toolbar.export(context));
    } else if (value == 'comfort' || value == 'wide') {
      final target = value == 'wide';
      if (target != toolbar.wide) toolbar.onWide();
    } else if (value == 'zh' || value == 'en') {
      toolbar.onLocaleChanged(
        value == 'zh'
            ? const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans')
            : const Locale('en'),
      );
    }
  }

  List<PopupMenuEntry<Object>> _items(BuildContext context) {
    final enabled = !toolbar.controller.isBusy && toolbar.hasChapter;
    // 菜单打开时按最新的 toolbar.actions/选区能力计算，不沿用上一帧缓存。
    final tools = workspaceToolItems(
      controller: toolbar.controller,
      labels: toolbar.labels,
      hasSelection: toolbar.actions?.canDiscuss ?? false,
    );
    return [
      if (narrow) ..._narrowItems(context, enabled),
      for (final item in tools)
        PopupMenuItem(
          value: item.tool,
          enabled: item.enabled,
          child: Row(
            children: [
              Icon(item.icon, size: 17, color: WorkbenchTokens.muted),
              const SizedBox(width: 10),
              Text(item.label),
            ],
          ),
        ),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: 'sources',
        enabled: toolbar.real && toolbar.actions?.onRefreshSources != null,
        child: Text(toolbar.strings.refreshSources),
      ),
      PopupMenuItem(
        value: 'languages',
        child: Text(toolbar.strings.languageLabel),
      ),
    ];
  }

  List<PopupMenuEntry<Object>> _narrowItems(
    BuildContext context,
    bool enabled,
  ) {
    final current = Localizations.localeOf(context).languageCode;
    return [
      PopupMenuItem(
        value: 'discuss',
        enabled:
            (toolbar.actions?.canDiscuss ?? false) &&
            !toolbar.controller.isBusy,
        child: Text(toolbar.strings.discussSelection),
      ),
      PopupMenuItem(
        value: 'chapterDiscussion',
        enabled: toolbar.actions?.onChapterDiscussion != null,
        child: Text(toolbar.strings.chapterDiscussion),
      ),
      PopupMenuItem(
        value: 'confirm',
        enabled: enabled,
        child: Text(toolbar.strings.confirmChapter),
      ),
      PopupMenuItem(
        value: 'versions',
        enabled: enabled,
        child: Text(toolbar.strings.versionsTitle),
      ),
      WorkbenchCheckedMenuItem<Object>(
        checked: !toolbar.wide,
        value: 'comfort',
        child: Text(toolbar.strings.layoutComfort),
      ),
      WorkbenchCheckedMenuItem<Object>(
        checked: toolbar.wide,
        value: 'wide',
        child: Text(toolbar.strings.layoutWide),
      ),
      PopupMenuItem(
        value: 'focus',
        child: Text(
          toolbar.focus ? toolbar.strings.focusOff : toolbar.strings.focusOn,
        ),
      ),
      PopupMenuItem(
        value: 'export',
        enabled: enabled,
        child: Text(toolbar.strings.exportWork),
      ),
      WorkbenchCheckedMenuItem<Object>(
        value: 'zh',
        checked: current == 'zh',
        child: Text(toolbar.strings.chineseLabel),
      ),
      WorkbenchCheckedMenuItem<Object>(
        value: 'en',
        checked: current == 'en',
        child: Text(toolbar.strings.englishLabel),
      ),
      const PopupMenuDivider(),
    ];
  }
}
