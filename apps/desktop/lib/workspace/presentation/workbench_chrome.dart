// 工作台通用界面组件：文案包装、顶部工具栏、通用操作按钮与语言/版式菜单。
//
// 读边界：只读取 controller 的目录、保存状态与 editor actions 的选区/线程快照。
// 写边界：确认本章、版本、导出、语言与工具入口都调用既有 controller/流程。
// 关键不变量：忙碌时禁用变更操作；所有按钮都有 48px 可点击区域与 tooltip。
import 'dart:async';

import 'package:flutter/material.dart';

import '../../cowrite/discussion_index.dart';
import '../../cowrite/discussion_thread.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/workbench_theme.dart';
import '../data/workspace_repository.dart';
import '../workspace_controller.dart';
import 'editor_action_registry.dart';
import 'editor_status.dart';
import 'editor_tools.dart';
import 'export_flow.dart';
import 'workbench_dialogs.dart';

/// Transforms translated chrome only for the optional expansion harness.
///
/// 界面文案包装：伪本地化只作用于 UI 文案，不翻译也不改写作品、章节与作者正文。
class WorkbenchLabels {
  const WorkbenchLabels(this.strings, this.pseudo);
  final AppLocalizations strings;
  final bool pseudo;

  /// 返回本地化文案；伪本地化时复制并加方括号，仅用于扩展性验证。
  String call(String value) => pseudo ? '[$value · $value]' : value;
}

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
  final WorkspaceController controller;
  final WorkbenchLabels labels;
  final Locale locale;
  final ValueChanged<Locale> onLocaleChanged;
  final bool focus;
  final bool wide;
  final VoidCallback onFocus;
  final VoidCallback onWide;
  final EditorActionRegistry? actions;
  final VoidCallback? onShowSidebar;

  AppLocalizations get _s => labels.strings;
  bool get _hasChapter => controller.editing.hasOpenChapter;
  bool get _real => controller.repository.mode == WorkspaceMode.realBridge;

  Future<void> _confirm(BuildContext context) async {
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

  Future<void> _versions(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => VersionsDialog(controller: controller, labels: labels),
  );

  Future<void> _export(BuildContext context) =>
      RecoveryExportFlow.manuscript(context, controller, labels);

  /// 打开本章完整讨论索引；选择条目后按真实线程 ID 重开，不新建线程。
  Future<void> _showIndex(BuildContext context) async {
    final threads = actions?.threads ?? const <DiscussionThread>[];
    if (threads.isEmpty) return;
    await showDiscussionIndex(
      context,
      threads: threads,
      strings: _s,
      onOpen: _openThread,
    );
  }

  void _openThread(DiscussionThread thread) =>
      actions?.onOpenThread?.call(thread);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: WorkbenchTokens.toolbarHeight,
      padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
      decoration: const BoxDecoration(
        color: WorkbenchTokens.toolbar,
        border: Border(bottom: BorderSide(color: WorkbenchTokens.stroke)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 大字号时文字宽度按缩放倍率增长，工具栏提前切到图标模式，避免溢出。
          final scale = MediaQuery.textScalerOf(context).scale(1);
          final compact = constraints.maxWidth < 1120 * scale;
          final narrow = constraints.maxWidth < 760 * scale;
          return Row(
            children: [
              if (onShowSidebar != null)
                _BarButton(
                  icon: Icons.view_sidebar_outlined,
                  tooltip: _s.chapters,
                  onPressed: onShowSidebar,
                ),
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        controller.currentWork?.title ?? _s.workspaceTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WorkbenchTokens.ui(
                          size: 15,
                          weight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: SaveStatusIndicator(
                        controller: controller,
                        labels: labels,
                        compact: narrow,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              _editorActions(context, compact, narrow: narrow),
              if (!narrow) ...[
                const SizedBox(width: 2),
                _chapterMenu(context, compact),
                _modelButton(context),
                _layoutMenu(context, compact),
                _focusButton(compact),
                _chapterDiscussionButton(compact),
                _exportMenu(context, compact),
                _languageMenu(compact),
              ],
              _moreMenu(context, compact, narrow: narrow),
            ],
          );
        },
      ),
    );
  }

  /// 编辑器动作：查找、讨论记录与“讨论这段”只在编辑器挂载后出现。
  Widget _editorActions(
    BuildContext context,
    bool compact, {
    bool narrow = false,
  }) {
    final registry = actions;
    if (registry == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: registry,
      builder: (context, _) {
        final threads = registry.threads;
        // 忙碌/保存屏障期间禁止创建讨论；动作本身还会在点击时再次校验。
        final canDiscuss = registry.canDiscuss && !controller.isBusy;
        // 尚未落盘的讨论草稿用入口角标提示，索引不掩盖保存失败。
        final hasUnsavedDiscussions = threads.any((thread) => thread.dirty);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!narrow && canDiscuss)
              _BarButton(
                icon: Icons.chat_bubble_outline,
                label: _s.discussSelection,
                accent: true,
                tooltip:
                    '${_s.selectionCount(registry.selectedCodePoints)} · ${_s.discussSelection}',
                onPressed: registry.onDiscussSelection,
              ),
            _BarButton(
              icon: Icons.search,
              label: _s.findInChapter,
              tooltip: _s.findInChapter,
              compact: compact,
              selected: registry.findOpen,
              onPressed: registry.onFind,
            ),
            if (narrow && canDiscuss)
              _BarButton(
                icon: Icons.chat_bubble_outline,
                accent: true,
                tooltip:
                    '${_s.selectionCount(registry.selectedCodePoints)} · ${_s.discussSelection}',
                onPressed: registry.onDiscussSelection,
              ),
            // 索引在宽窗与窄窗都由顶栏同一入口打开，窄窗显示为图标按钮；
            // 有未落盘草稿时在入口上叠加角标，避免保存失败被普通入口掩盖。
            if (threads.isNotEmpty)
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _BarButton(
                    icon: Icons.forum_outlined,
                    label: _s.discussionIndex(threads.length),
                    tooltip: _s.discussionIndex(threads.length),
                    compact: compact || narrow,
                    onPressed: () => unawaited(_showIndex(context)),
                  ),
                  if (hasUnsavedDiscussions)
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
              ),
          ],
        );
      },
    );
  }

  Widget _chapterMenu(BuildContext context, bool compact) {
    final enabled = !controller.isBusy && _hasChapter;
    return PopupMenuButton<String>(
      enabled: enabled,
      tooltip: _s.chapterAndVersions,
      onSelected: (value) {
        if (value == 'confirm') unawaited(_confirm(context));
        if (value == 'versions') unawaited(_versions(context));
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'confirm',
          enabled: enabled,
          child: Text(_s.confirmChapter),
        ),
        PopupMenuItem(
          value: 'versions',
          enabled: enabled,
          child: Text(_s.versionsTitle),
        ),
      ],
      child: _BarMenu(
        icon: Icons.menu_book_outlined,
        label: _s.chapterAndVersions,
        compact: compact,
        enabled: enabled,
      ),
    );
  }

  Widget _modelButton(BuildContext context) => _BarButton(
    icon: Icons.key_outlined,
    label: _s.modelSettings,
    tooltip: _s.modelSettings,
    compact: true,
    onPressed: controller.isBusy || !_real
        ? null
        : () => unawaited(
            openWorkspaceTool(
              context,
              controller,
              labels,
              actions?.editor,
              WorkspaceTool.deepseek,
            ),
          ),
  );

  Widget _layoutMenu(BuildContext context, bool compact) =>
      PopupMenuButton<bool>(
        tooltip: _s.layoutMenu,
        onSelected: (value) {
          if (value != wide) onWide();
        },
        itemBuilder: (_) => [
          CheckedPopupMenuItem(
            checked: !wide,
            value: false,
            child: Text(_s.layoutComfort),
          ),
          CheckedPopupMenuItem(
            checked: wide,
            value: true,
            child: Text(_s.layoutWide),
          ),
          const PopupMenuItem(
            enabled: false,
            height: 30,
            child: Text(
              'Noto Serif SC · 20 px',
              style: TextStyle(fontSize: 11, color: WorkbenchTokens.muted),
            ),
          ),
        ],
        child: _BarMenu(
          icon: Icons.format_line_spacing,
          label: _s.layoutMenu,
          compact: compact,
        ),
      );

  Widget _focusButton(bool compact) => _BarButton(
    icon: focus ? Icons.fullscreen_exit : Icons.fullscreen,
    label: focus ? _s.focusOff : _s.focusOn,
    tooltip: focus ? _s.focusOff : _s.focusOn,
    compact: compact,
    selected: focus,
    onPressed: onFocus,
  );

  Widget _chapterDiscussionButton(bool compact) {
    final registry = actions;
    return _BarButton(
      icon: Icons.forum_outlined,
      label: _s.chapterDiscussion,
      tooltip: _s.chapterDiscussion,
      compact: compact,
      onPressed: registry?.onChapterDiscussion,
    );
  }

  Widget _exportMenu(BuildContext context, bool compact) =>
      PopupMenuButton<String>(
        tooltip: _s.exportMenu,
        onSelected: (value) {
          if (value == 'manuscript') unawaited(_export(context));
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'manuscript',
            enabled: !controller.isBusy && _hasChapter,
            child: Text(_s.exportWork),
          ),
        ],
        child: _BarMenu(
          icon: Icons.file_download_outlined,
          label: _s.exportMenu,
          compact: compact,
          enabled: !controller.isBusy && _hasChapter,
        ),
      );

  Widget _languageMenu(bool compact) => PopupMenuButton<Locale>(
    tooltip: _s.languageLabel,
    onSelected: onLocaleChanged,
    itemBuilder: (_) => [
      PopupMenuItem(
        value: const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
        child: Text(_s.chineseLabel),
      ),
      PopupMenuItem(value: const Locale('en'), child: Text(_s.englishLabel)),
    ],
    child: _BarMenu(
      icon: Icons.translate,
      label: _s.languageLabel,
      compact: compact,
    ),
  );

  Widget _moreMenu(BuildContext context, bool compact, {bool narrow = false}) {
    final enabled = !controller.isBusy && _hasChapter;
    return PopupMenuButton<Object>(
      tooltip: _s.moreTools,
      onSelected: (value) {
        if (value is WorkspaceTool) {
          unawaited(
            openWorkspaceTool(
              context,
              controller,
              labels,
              actions?.editor,
              value,
            ),
          );
        } else if (value == 'sources') {
          actions?.onRefreshSources?.call();
        } else if (value == 'languages') {
          unawaited(_showLanguageInfo(context));
        } else if (value == 'discuss') {
          actions?.onDiscussSelection?.call();
        } else if (value == 'chapterDiscussion') {
          actions?.onChapterDiscussion?.call();
        } else if (value == 'confirm') {
          unawaited(_confirm(context));
        } else if (value == 'versions') {
          unawaited(_versions(context));
        } else if (value == 'focus') {
          onFocus();
        } else if (value == 'export') {
          unawaited(_export(context));
        } else if (value == 'comfort' || value == 'wide') {
          final target = value == 'wide';
          if (target != wide) onWide();
        } else if (value == 'zh' || value == 'en') {
          onLocaleChanged(
            value == 'zh'
                ? const Locale.fromSubtags(
                    languageCode: 'zh',
                    scriptCode: 'Hans',
                  )
                : const Locale('en'),
          );
        }
      },
      itemBuilder: (_) {
        // 菜单打开时按最新的 actions/选区能力计算，不沿用上一帧缓存。
        final tools = workspaceToolItems(
          controller: controller,
          labels: labels,
          hasSelection: actions?.canDiscuss ?? false,
        );
        return [
          if (narrow) ...[
            PopupMenuItem(
              value: 'discuss',
              enabled: (actions?.canDiscuss ?? false) && !controller.isBusy,
              child: Text(_s.discussSelection),
            ),
            PopupMenuItem(
              value: 'chapterDiscussion',
              enabled: actions?.onChapterDiscussion != null,
              child: Text(_s.chapterDiscussion),
            ),
            PopupMenuItem(
              value: 'confirm',
              enabled: enabled,
              child: Text(_s.confirmChapter),
            ),
            PopupMenuItem(
              value: 'versions',
              enabled: enabled,
              child: Text(_s.versionsTitle),
            ),
            CheckedPopupMenuItem(
              checked: !wide,
              value: 'comfort',
              child: Text(_s.layoutComfort),
            ),
            CheckedPopupMenuItem(
              checked: wide,
              value: 'wide',
              child: Text(_s.layoutWide),
            ),
            PopupMenuItem(
              value: 'focus',
              child: Text(focus ? _s.focusOff : _s.focusOn),
            ),
            PopupMenuItem(
              value: 'export',
              enabled: enabled,
              child: Text(_s.exportWork),
            ),
            PopupMenuItem(value: 'zh', child: Text(_s.chineseLabel)),
            PopupMenuItem(value: 'en', child: Text(_s.englishLabel)),
            const PopupMenuDivider(),
          ],
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
            enabled: _real && actions?.onRefreshSources != null,
            child: Text(_s.refreshSources),
          ),
          PopupMenuItem(value: 'languages', child: Text(_s.languageLabel)),
        ];
      },
      child: _BarMenu(
        icon: Icons.more_horiz,
        label: _s.moreTools,
        compact: compact,
      ),
    );
  }

  Future<void> _showLanguageInfo(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(_s.languageLabel),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${_s.workLanguage}: ${_s.undeterminedLanguage}'),
          const SizedBox(height: 6),
          Text('${_s.documentLanguage}: ${_s.undeterminedLanguage}'),
          const SizedBox(height: 6),
          Text('${_s.outputLanguage}: ${_s.undeterminedLanguage}'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_s.closeDialog),
        ),
      ],
    ),
  );
}

/// 顶部栏扁平按钮：视觉高度 40（触控/鼠标目标足够大），键盘可聚焦，
/// 悬停使用原版浅灰底，选中态使用浅蓝底；语义名与禁用态走 Semantics。
/// 明确豁免 48px 规范：按钮位于 56px 桌面工具栏内，与原版密度一致，且水平
/// 内边距、语义名与键盘焦点均已提供；最大化会破坏原版视觉比例。
class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.label,
    this.compact = false,
    this.selected = false,
    this.accent = false,
  });
  final IconData icon;
  final String tooltip;
  final String? label;
  final VoidCallback? onPressed;
  final bool compact;
  final bool selected;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final showLabel = label != null && !compact;
    final color = !enabled
        ? WorkbenchTokens.muted.withValues(alpha: 0.5)
        : accent
        ? WorkbenchTokens.accent
        : WorkbenchTokens.ink;
    return Semantics(
      label: tooltip,
      button: true,
      enabled: enabled,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: Material(
          color: selected ? WorkbenchTokens.selected : Colors.transparent,
          borderRadius: BorderRadius.circular(WorkbenchTokens.radius),
          child: InkWell(
            onTap: onPressed,
            canRequestFocus: enabled,
            borderRadius: BorderRadius.circular(WorkbenchTokens.radius),
            hoverColor: WorkbenchTokens.hover,
            focusColor: WorkbenchTokens.selected,
            child: Container(
              height: 40,
              padding: EdgeInsetsDirectional.symmetric(
                horizontal: showLabel ? 10 : 8,
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 17, color: color),
                  if (showLabel) ...[
                    const SizedBox(width: 7),
                    Text(
                      label!,
                      style: WorkbenchTokens.ui(size: 13, color: color),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 带下拉箭头的顶部栏菜单触发区。
class _BarMenu extends StatelessWidget {
  const _BarMenu({
    required this.icon,
    required this.label,
    required this.compact,
    this.enabled = true,
  });
  final IconData icon;
  final String label;
  final bool compact;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? WorkbenchTokens.ink
        : WorkbenchTokens.muted.withValues(alpha: 0.5);
    return Container(
      height: 40,
      padding: EdgeInsetsDirectional.symmetric(horizontal: compact ? 8 : 10),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: color),
          if (!compact) ...[
            const SizedBox(width: 7),
            Text(label, style: WorkbenchTokens.ui(size: 13, color: color)),
          ],
          const SizedBox(width: 3),
          Icon(Icons.arrow_drop_down, size: 16, color: color),
        ],
      ),
    );
  }
}

/// 讨论索引条目：目标文本（或全章讨论）+ 有效性 + 未发草稿。

/// 带图标与文案的通用操作按钮；保持至少 48px 的可点击尺寸。
class ChromeAction extends StatelessWidget {
  const ChromeAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    super.key,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
    ),
  );
}
