// 顶栏菜单：从工具栏只读配置构建，操作继续使用原有业务命令。
import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/workbench_controls.dart';
import '../../theme/workbench_theme.dart';
import 'toolbar_controls.dart';
import 'workbench_toolbar.dart';
import 'editor_tools.dart';

/// ToolbarChapterMenu 使用统一菜单外观和最新能力。
class ToolbarChapterMenu extends StatelessWidget {
  const ToolbarChapterMenu({
    required this.toolbar,
    this.compact = false,
    super.key,
  });

  /// 当前帧的只读工具栏配置，不由组件持久化。
  final WorkbenchToolbar toolbar;

  /// 是否只展示图标；可访问名称仍保留。
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final enabled = !toolbar.controller.isBusy && toolbar.hasChapter;
    return PopupMenuButton<String>(
      style: WorkbenchControls.menuTrigger(),
      borderRadius: BorderRadius.circular(WorkbenchTokens.radius),
      enabled: enabled,
      tooltip: toolbar.strings.chapterAndVersions,
      onSelected: (value) {
        if (value == 'confirm') unawaited(toolbar.confirm(context));
        if (value == 'versions') unawaited(toolbar.versions(context));
      },
      itemBuilder: (_) => [
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
      ],
      icon: ToolbarMenuTrigger(
        icon: Icons.menu_book_outlined,
        label: toolbar.strings.chapterAndVersions,
        compact: compact,
        enabled: enabled,
      ),
    );
  }
}

/// ToolbarModelButton 使用统一菜单外观和最新能力。
class ToolbarModelButton extends StatelessWidget {
  const ToolbarModelButton({
    required this.toolbar,
    this.compact = false,
    super.key,
  });

  /// 当前帧的只读工具栏配置，不由组件持久化。
  final WorkbenchToolbar toolbar;

  /// 是否只展示图标；可访问名称仍保留。
  final bool compact;
  @override
  Widget build(BuildContext context) => ToolbarButton(
    icon: Icons.key_outlined,
    label: toolbar.strings.modelSettings,
    tooltip: toolbar.strings.modelSettings,
    compact: true,
    onPressed: toolbar.controller.isBusy || !toolbar.real
        ? null
        : () => unawaited(
            openWorkspaceTool(
              context,
              toolbar.controller,
              toolbar.labels,
              toolbar.actions?.editor,
              WorkspaceTool.deepseek,
            ),
          ),
  );
}

/// ToolbarLayoutMenu 使用统一菜单外观和最新能力。
class ToolbarLayoutMenu extends StatelessWidget {
  const ToolbarLayoutMenu({
    required this.toolbar,
    this.compact = false,
    super.key,
  });

  /// 当前帧的只读工具栏配置，不由组件持久化。
  final WorkbenchToolbar toolbar;

  /// 是否只展示图标；可访问名称仍保留。
  final bool compact;
  @override
  Widget build(BuildContext context) => PopupMenuButton<bool>(
    style: WorkbenchControls.menuTrigger(),
    borderRadius: BorderRadius.circular(WorkbenchTokens.radius),
    tooltip: toolbar.strings.layoutMenu,
    onSelected: (value) {
      if (value != toolbar.wide) toolbar.onWide();
    },
    itemBuilder: (_) => [
      WorkbenchCheckedMenuItem<bool>(
        checked: !toolbar.wide,
        value: false,
        child: Text(toolbar.strings.layoutComfort),
      ),
      WorkbenchCheckedMenuItem<bool>(
        checked: toolbar.wide,
        value: true,
        child: Text(toolbar.strings.layoutWide),
      ),
      PopupMenuItem(
        enabled: false,
        height: 30,
        child: Text(
          'Notebook Serif · 20 px',
          style: WorkbenchTokens.ui(size: 12, color: WorkbenchTokens.muted),
        ),
      ),
    ],
    icon: ToolbarMenuTrigger(
      icon: Icons.format_line_spacing,
      label: toolbar.strings.layoutMenu,
      compact: compact,
    ),
  );
}

/// ToolbarFocusButton 使用统一菜单外观和最新能力。
class ToolbarFocusButton extends StatelessWidget {
  const ToolbarFocusButton({
    required this.toolbar,
    this.compact = false,
    super.key,
  });

  /// 当前帧的只读工具栏配置，不由组件持久化。
  final WorkbenchToolbar toolbar;

  /// 是否只展示图标；可访问名称仍保留。
  final bool compact;
  @override
  Widget build(BuildContext context) => ToolbarButton(
    icon: toolbar.focus ? Icons.fullscreen_exit : Icons.fullscreen,
    label: toolbar.focus ? toolbar.strings.focusOff : toolbar.strings.focusOn,
    tooltip: toolbar.focus ? toolbar.strings.focusOff : toolbar.strings.focusOn,
    compact: compact,
    selected: toolbar.focus,
    onPressed: toolbar.onFocus,
  );
}

/// ToolbarChapterDiscussion 使用统一菜单外观和最新能力。
class ToolbarChapterDiscussion extends StatelessWidget {
  const ToolbarChapterDiscussion({
    required this.toolbar,
    this.compact = false,
    super.key,
  });

  /// 当前帧的只读工具栏配置，不由组件持久化。
  final WorkbenchToolbar toolbar;

  /// 是否只展示图标；可访问名称仍保留。
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final registry = toolbar.actions;
    return ToolbarButton(
      icon: Icons.forum_outlined,
      label: toolbar.strings.chapterDiscussion,
      tooltip: toolbar.strings.chapterDiscussion,
      compact: compact,
      onPressed: registry?.onChapterDiscussion,
    );
  }
}

/// ToolbarExportMenu 使用统一菜单外观和最新能力。
class ToolbarExportMenu extends StatelessWidget {
  const ToolbarExportMenu({
    required this.toolbar,
    this.compact = false,
    super.key,
  });

  /// 当前帧的只读工具栏配置，不由组件持久化。
  final WorkbenchToolbar toolbar;

  /// 是否只展示图标；可访问名称仍保留。
  final bool compact;
  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    style: WorkbenchControls.menuTrigger(),
    borderRadius: BorderRadius.circular(WorkbenchTokens.radius),
    enabled: !toolbar.controller.isBusy && toolbar.hasChapter,
    tooltip: toolbar.strings.exportMenu,
    onSelected: (value) {
      if (value == 'manuscript') unawaited(toolbar.export(context));
    },
    itemBuilder: (_) => [
      PopupMenuItem(
        value: 'manuscript',
        enabled: !toolbar.controller.isBusy && toolbar.hasChapter,
        child: Text(toolbar.strings.exportWork),
      ),
    ],
    icon: ToolbarMenuTrigger(
      icon: Icons.file_download_outlined,
      label: toolbar.strings.exportMenu,
      compact: compact,
      enabled: !toolbar.controller.isBusy && toolbar.hasChapter,
    ),
  );
}

/// ToolbarLanguageMenu 使用统一菜单外观和最新能力。
class ToolbarLanguageMenu extends StatelessWidget {
  const ToolbarLanguageMenu({
    required this.toolbar,
    this.compact = false,
    super.key,
  });

  /// 当前帧的只读工具栏配置，不由组件持久化。
  final WorkbenchToolbar toolbar;

  /// 是否只展示图标；可访问名称仍保留。
  final bool compact;
  @override
  Widget build(BuildContext context) {
    // 语言菜单与版式菜单同一选中合同：当前界面语言显示浅蓝底与勾选。
    final current = Localizations.localeOf(context).languageCode;
    return PopupMenuButton<Locale>(
      style: WorkbenchControls.menuTrigger(),
      borderRadius: BorderRadius.circular(WorkbenchTokens.radius),
      tooltip: toolbar.strings.languageLabel,
      onSelected: toolbar.onLocaleChanged,
      itemBuilder: (_) => [
        WorkbenchCheckedMenuItem<Locale>(
          value: const Locale.fromSubtags(
            languageCode: 'zh',
            scriptCode: 'Hans',
          ),
          checked: current == 'zh',
          child: Text(toolbar.strings.chineseLabel),
        ),
        WorkbenchCheckedMenuItem<Locale>(
          value: const Locale('en'),
          checked: current == 'en',
          child: Text(toolbar.strings.englishLabel),
        ),
      ],
      icon: ToolbarMenuTrigger(
        icon: Icons.translate,
        label: toolbar.strings.languageLabel,
        compact: compact,
      ),
    );
  }
}
