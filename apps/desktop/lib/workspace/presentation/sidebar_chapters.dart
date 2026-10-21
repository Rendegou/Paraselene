// 章节目录展示：活动、归档与空态分别组合，不持有仓库或写入状态。
import 'dart:async';
import 'package:flutter/material.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/workbench_controls.dart';
import '../../theme/workbench_theme.dart';
import '../data/workspace_repository.dart';
import 'sidebar_chrome.dart';

/// 显示章节索引与归档区；所有写入交还宿主。
class SidebarChapterDirectory extends StatelessWidget {
  const SidebarChapterDirectory({
    required this.strings,
    required this.chapters,
    required this.archived,
    required this.selectedId,
    required this.queryEmpty,
    required this.busy,
    required this.onCreate,
    required this.onSelect,
    required this.onMenu,
    required this.onRestore,
    super.key,
  });

  /// 当前界面语言的完整标签集合。
  final AppLocalizations strings;

  /// 按当前筛选条件生成的章节快照，保留真实身份。
  final List<WorkspaceChapter> chapters;

  /// 归档章节快照，展示不改变归档状态。
  final List<WorkspaceChapter> archived;

  /// 当前章节身份，为空表示尚未打开章节。
  final String? selectedId;

  /// 筛选词是否为空，用于区分无数据和无匹配。
  final bool queryEmpty;

  /// 写屏障状态，为真时禁止变更入口。
  final bool busy;

  /// 允许新增章节时的动作，忙碌或无作品时为空。
  final VoidCallback? onCreate;

  /// 按章节真实身份导航，不复制整部作品正文。
  final Future<void> Function(WorkspaceChapter) onSelect;

  /// 按真实章节和全局逻辑像素坐标打开上下文菜单。
  final Future<void> Function(WorkspaceChapter, Offset) onMenu;

  /// 通过控制器恢复章节，不绕过写屏障。
  final Future<void> Function(WorkspaceChapter) onRestore;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SidebarHeading(
        strings.chapterDirectory,
        onAdd: onCreate,
        addTooltip: strings.newChapter,
      ),
      for (var index = 0; index < chapters.length; index++)
        SidebarChapterRow(
          chapter: chapters[index],
          index: index,
          selected: selectedId == chapters[index].id,
          busy: busy,
          onSelect: onSelect,
          onMenu: onMenu,
        ),
      if (chapters.isEmpty)
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 8, 16),
          child: Text(
            queryEmpty ? strings.emptyChapters : strings.noMatchingChapters,
            style: WorkbenchTokens.ui(
              size: 12,
              color: WorkbenchTokens.muted,
              height: 1.9,
            ),
          ),
        ),
      if (archived.isNotEmpty)
        SidebarArchivedChapters(
          strings: strings,
          chapters: archived,
          busy: busy,
          onRestore: onRestore,
        ),
    ],
  );
}

/// 活动章节行，保留上下文菜单、选中语义和原章节键。
class SidebarChapterRow extends StatelessWidget {
  const SidebarChapterRow({
    required this.chapter,
    required this.index,
    required this.selected,
    required this.busy,
    required this.onSelect,
    required this.onMenu,
    super.key,
  });

  /// 当前行绑定的真实章节身份。
  final WorkspaceChapter chapter;

  /// 筛选列表的零基序号，只用于显示编号。
  final int index;

  /// 当前行的选中状态，同时暴露选中语义。
  final bool selected;

  /// 写屏障状态，为真时禁止变更入口。
  final bool busy;

  /// 按章节真实身份导航，不复制整部作品正文。
  final Future<void> Function(WorkspaceChapter) onSelect;

  /// 按真实章节和全局逻辑像素坐标打开上下文菜单。
  final Future<void> Function(WorkspaceChapter, Offset) onMenu;
  @override
  Widget build(BuildContext context) => Padding(
    key: ValueKey('chapter-${chapter.id}'),
    padding: const EdgeInsetsDirectional.only(bottom: 3),
    child: GestureDetector(
      onSecondaryTapDown: busy
          ? null
          : (details) => unawaited(onMenu(chapter, details.globalPosition)),
      onLongPressStart: busy
          ? null
          : (details) => unawaited(onMenu(chapter, details.globalPosition)),
      child: Semantics(
        selected: selected,
        child: TextButton(
          style: WorkbenchControls.button(selected: selected),
          onPressed: busy ? null : () => unawaited(onSelect(chapter)),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(11, 10, 11, 10),
            child: SidebarChapterLabel(
              chapter: chapter,
              index: index,
              selected: selected,
              busy: busy,
            ),
          ),
        ),
      ),
    ),
  );
}

/// 章节编号和标题按各自文字角色排版，不裁断作者标题。
class SidebarChapterLabel extends StatelessWidget {
  const SidebarChapterLabel({
    required this.chapter,
    required this.index,
    required this.selected,
    required this.busy,
    super.key,
  });

  /// 当前行绑定的真实章节身份。
  final WorkspaceChapter chapter;

  /// 筛选列表的零基序号，只用于显示编号。
  final int index;

  /// 当前行的选中状态，同时暴露选中语义。
  final bool selected;

  /// 写屏障状态，为真时禁止变更入口。
  final bool busy;
  @override
  Widget build(BuildContext context) {
    final tone = busy
        ? WorkbenchTokens.muted.withValues(alpha: 0.5)
        : selected
        ? WorkbenchTokens.accent
        : WorkbenchTokens.muted;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: MediaQuery.textScalerOf(context).scale(18),
          child: Text(
            (index + 1).toString().padLeft(2, '0'),
            style: WorkbenchTokens.ui(
              size: 12,
              color: tone,
              height: 1.65,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            chapter.title,
            style: WorkbenchTokens.ui(
              size: 14,
              height: 1.65,
              weight: selected ? FontWeight.w500 : FontWeight.w400,
              color: busy
                  ? tone
                  : selected
                  ? WorkbenchTokens.accent
                  : WorkbenchTokens.ink,
            ),
          ),
        ),
      ],
    );
  }
}

/// 归档章节与恢复入口，恢复操作不会直接改写作者正文。
class SidebarArchivedChapters extends StatelessWidget {
  const SidebarArchivedChapters({
    required this.strings,
    required this.chapters,
    required this.busy,
    required this.onRestore,
    super.key,
  });

  /// 当前界面语言的完整标签集合。
  final AppLocalizations strings;

  /// 按当前筛选条件生成的章节快照，保留真实身份。
  final List<WorkspaceChapter> chapters;

  /// 写屏障状态，为真时禁止变更入口。
  final bool busy;

  /// 通过控制器恢复章节，不绕过写屏障。
  final Future<void> Function(WorkspaceChapter) onRestore;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 18),
      SidebarHeading(strings.archivedChapters),
      for (final chapter in chapters)
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(chapter.title, style: WorkbenchTokens.ui(size: 13)),
              ),
              SidebarTextAction(
                strings.restoreChapter,
                busy ? null : () => unawaited(onRestore(chapter)),
                color: WorkbenchTokens.accent,
              ),
            ],
          ),
        ),
    ],
  );
}
