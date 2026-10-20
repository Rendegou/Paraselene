// 写作工作台左侧目录：品牌、搜索、章节/资料页签、章节目录与底部状态。
//
// 只读展示与导航：章节正文按需加载，不把整部作品放进内存；资料页签按需
// 读取当前作品资料，单击条目先看轻量只读预览，再由作者决定带入讨论或展开编辑，
// 不写库、不发起模型请求。
// 资料读取的身份与并发由 LoreDirectory 统一管理，切换作品后旧请求不会污染新作品。
import 'dart:async';

import 'package:flutter/material.dart';

import '../../cowrite/discussion_registry.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../lore/lore_library.dart';
import '../../theme/workbench_theme.dart';
import '../data/real_workspace_repository.dart';
import '../data/workspace_repository.dart';
import '../workspace_controller.dart';
import 'lore_directory.dart';
import 'lore_preview.dart';
import 'work_picker.dart';
import 'workbench_chrome.dart';
import 'workbench_dialogs.dart';

enum _SidebarTab { chapters, resources }

/// 目录侧栏；[onCollapse] 为 null 时在抽屉里使用，不做收起。
///
/// 侧栏只触发 controller 的既有命令；忙碌时禁用重命名/归档等写操作。
class WorkbenchSidebar extends StatefulWidget {
  const WorkbenchSidebar({
    required this.controller,
    required this.labels,
    this.onCollapse,
    this.closeOnSelect = false,
    super.key,
  });
  final WorkspaceController controller;
  final WorkbenchLabels labels;
  final VoidCallback? onCollapse;
  final bool closeOnSelect;

  @override
  State<WorkbenchSidebar> createState() => _WorkbenchSidebarState();
}

class _WorkbenchSidebarState extends State<WorkbenchSidebar> {
  final TextEditingController _query = TextEditingController();
  _SidebarTab _tab = _SidebarTab.chapters;
  late final LoreDirectory _lore;

  WorkspaceController get _controller => widget.controller;
  AppLocalizations get _s => widget.labels.strings;

  @override
  void initState() {
    super.initState();
    _lore = LoreDirectory(loader: _readLore, currentWorkId: _currentWorkId)
      ..addListener(_onLoreChanged);
    _controller.addListener(_onController);
    _syncLore();
  }

  @override
  void didUpdateWidget(WorkbenchSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
    }
    _syncLore();
  }

  @override
  void dispose() {
    _controller.removeListener(_onController);
    _lore.removeListener(_onLoreChanged);
    _lore.dispose();
    _query.dispose();
    super.dispose();
  }

  String? _currentWorkId() => _controller.currentWork?.id;

  /// 资料行加载器：当前只有原生仓库暴露资料能力，其他仓库没有资料可读。
  Future<List<Map<String, dynamic>>> _readLore(String workId) {
    final repository = _controller.repository;
    if (repository is! RealWorkspaceRepository) {
      return Future.value(const <Map<String, dynamic>>[]);
    }
    return repository.lore.list(workId);
  }

  void _onController() {
    // 作品切换后资料集合属于另一部作品；状态机立即失效旧请求并读取当前作品。
    if (mounted) _syncLore();
  }

  void _onLoreChanged() {
    if (mounted) setState(() {});
  }

  /// 同步资料状态；仓库不具备资料能力时保持空态且不发起读取。
  void _syncLore({bool force = false}) {
    if (_controller.repository is! RealWorkspaceRepository) {
      _lore.clear();
      return;
    }
    _lore.sync(force: force);
  }

  String _normalized(String value) => value.trim().toLowerCase();

  bool _matches(String text, String query) =>
      query.isEmpty || text.toLowerCase().contains(query);

  List<WorkspaceChapter> get _visibleChapters {
    final query = _normalized(_query.text);
    if (query.isEmpty) return _controller.chapters;
    return [
      for (final chapter in _controller.chapters)
        if (_matches(chapter.title, query)) chapter,
    ];
  }

  List<Map<String, dynamic>> get _visibleLore {
    final query = _normalized(_query.text);
    if (query.isEmpty) return _lore.rows;
    return [
      for (final row in _lore.rows)
        if (row['entry'] is Map &&
            _matches((row['entry'] as Map)['name'] as String? ?? '', query))
          row,
    ];
  }

  Future<void> _openLore() async {
    final repository = _controller.repository;
    final work = _controller.currentWork;
    if (repository is! RealWorkspaceRepository || work == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => LoreLibrary(repository: repository.lore, work: work.id),
    );
    // 资料库可能已增删条目：关闭后对当前作品显式刷新，旧作品状态由状态机负责丢弃。
    if (mounted) _syncLore(force: true);
  }

  /// 单击资料行：先看当前条目的轻量只读预览，是否带入由作者随后决定。
  Future<void> _openLoreEntry(String entryId) async {
    final row = loreRowById(_lore.rows, entryId);
    final data = row == null ? null : LorePreviewData.fromRow(row);
    if (data == null) {
      // 条目在当前列表里找不到：明确提示缺失，不改用其它条目冒充。
      _showLoreMessage(_s.loreEntryMissing);
      return;
    }
    final registry = _controller.discussions;
    final target = registry == null
        ? null
        : LoreDiscussionTarget.capture(registry);
    final history = registry == null
        ? const <LoreRequestSnapshot>[]
        : loreRequestSnapshots(registry.threads, entryId);
    final attached =
        registry != null &&
        loreEntryAttached(
          registry.threads,
          entryId,
          threadId: target?.threadId,
        );
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => LorePreview(
        data: data,
        history: history,
        attached: attached,
        onClose: () => Navigator.of(dialogContext).pop(),
        onAttach: target == null
            ? null
            : () => _attachLoreEntry(registry, entryId, target),
        onRemove: target == null
            ? null
            : () => _removeLoreEntry(registry, entryId, target),
        onEdit: () {
          Navigator.of(dialogContext).pop();
          unawaited(_openLoreEntryEdit(entryId));
        },
      ),
    );
  }

  /// “展开编辑”复用 LoreLibrary 的既有编辑与确认链，不重建工作台。
  Future<void> _openLoreEntryEdit(String entryId) async {
    final repository = _controller.repository;
    final work = _controller.currentWork;
    if (!mounted || repository is! RealWorkspaceRepository || work == null) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => LoreLibrary(
        repository: repository.lore,
        work: work.id,
        initialEntry: entryId,
        editInitialEntry: true,
      ),
    );
    if (mounted) _syncLore(force: true);
  }

  /// 只有作者明确点“带入讨论”才写引用集合；没有打开章节时不冒充成功。
  bool _attachLoreEntry(
    DiscussionRegistry? registry,
    String entryId,
    LoreDiscussionTarget target,
  ) {
    if (registry == null || registry.work == null || registry.chapter == null) {
      _showLoreMessage(_s.loreAttachUnavailable);
      return false;
    }
    try {
      attachLoreReference(registry, entryId, target: target);
    } on WorkspaceFailure catch (failure) {
      _showLoreMessage(
        failure.code == 'invalid_input'
            ? _s.loreAttachLimit
            : _s.loreAttachUnavailable,
      );
      return false;
    }
    // 沿用既有整章讨论能力边界：引用只帮助讨论，生成正文仍需在正文选段。
    _showLoreMessage(_s.loreAttachedBoundary);
    return true;
  }

  bool _removeLoreEntry(
    DiscussionRegistry? registry,
    String entryId,
    LoreDiscussionTarget target,
  ) {
    if (registry == null) return false;
    try {
      removeLoreReference(registry, entryId, target: target);
    } on WorkspaceFailure {
      _showLoreMessage(_s.loreAttachUnavailable);
      return false;
    }
    return true;
  }

  void _showLoreMissing() => _showLoreMessage(_s.loreEntryMissing);

  void _showLoreMessage(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openWorkPicker() async {
    await showDialog<void>(
      context: context,
      builder: (_) =>
          WorkPicker(controller: _controller, labels: widget.labels),
    );
  }

  Future<void> _createChapter() async {
    final title = await showTitlePrompt(
      context: context,
      labels: widget.labels,
      title: _s.newChapter,
      fieldLabel: _s.chapterTitleLabel,
    );
    if (title != null) await _controller.createChapter(title);
  }

  Future<void> _renameChapter(WorkspaceChapter chapter) async {
    final title = await showTitlePrompt(
      context: context,
      labels: widget.labels,
      title: _s.renameChapter,
      fieldLabel: _s.chapterTitleLabel,
      initial: chapter.title,
      // 重命名已有标题，提交按钮显示“保存”，与新建章节的“创建”区分。
      submitAction: _s.saveAction,
    );
    if (title != null) await _controller.renameChapter(chapter, title);
  }

  /// 章节行不常驻菜单按钮，避免破坏原版视觉；右键/长按才展开操作。
  Future<void> _chapterMenu(
    WorkspaceChapter chapter,
    Offset globalPosition,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox) return;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(globalPosition, globalPosition),
      Offset.zero & overlay.size,
    );
    final action = await showMenu<String>(
      context: context,
      position: position,
      items: [
        PopupMenuItem(value: 'rename', child: Text(_s.renameChapter)),
        PopupMenuItem(value: 'archive', child: Text(_s.archiveChapter)),
      ],
    );
    if (!mounted || action == null || _controller.isBusy) return;
    if (action == 'rename') await _renameChapter(chapter);
    if (action == 'archive') {
      await _controller.setChapterArchived(chapter, true);
    }
  }

  Future<void> _selectChapter(WorkspaceChapter chapter) async {
    if (widget.closeOnSelect) Navigator.of(context).pop();
    await _controller.selectChapter(chapter);
  }

  /// 侧栏文字操作：用 InkWell 保持 28px 视觉高度，不引入 Material 按钮块。
  Widget _textAction(
    String label,
    VoidCallback? onPressed, {
    Color color = WorkbenchTokens.muted,
    double size = 12,
  }) {
    final enabled = onPressed != null;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(WorkbenchTokens.radius),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(WorkbenchTokens.radius),
        hoverColor: WorkbenchTokens.hover,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 6,
            vertical: 4,
          ),
          child: Text(
            label,
            style: WorkbenchTokens.ui(
              size: size,
              color: enabled ? color : color.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }

  String _count(int value) => value > 99 ? '99+' : '$value';

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: WorkbenchTokens.frame,
        border: Border(right: BorderSide(color: WorkbenchTokens.stroke)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _brand(),
          _search(),
          _tabs(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 19, 12, 16),
              child: _tab == _SidebarTab.chapters
                  ? _chapterDirectory()
                  : _resourceDirectory(),
            ),
          ),
          _footer(),
        ],
      ),
    );
  }

  Widget _brand() => SizedBox(
    height: 56,
    child: Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 20),
      child: Row(
        children: [
          const Icon(
            Icons.menu_book_outlined,
            size: 21,
            color: WorkbenchTokens.accent,
          ),
          const SizedBox(width: 11),
          Text(
            '幻月',
            style: WorkbenchTokens.ui(
              size: 18,
              weight: FontWeight.w500,
              letterSpacing: 0.7,
            ),
          ),
          const Spacer(),
          if (widget.onCollapse != null)
            IconButton(
              tooltip: _s.closeDialog,
              onPressed: widget.onCollapse,
              icon: const Icon(Icons.view_sidebar_outlined, size: 16),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    ),
  );

  /// 搜索占位跟随当前页签，明确筛选对象是章节还是资料。
  Widget _search() {
    final hint = _tab == _SidebarTab.chapters
        ? _s.searchChapters
        : _s.searchResources;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 17, 16, 18),
      child: Container(
        height: 36,
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xffeaecf0),
          borderRadius: BorderRadius.circular(WorkbenchTokens.radius),
        ),
        child: Row(
          children: [
            const Icon(Icons.search, size: 15, color: WorkbenchTokens.muted),
            const SizedBox(width: 9),
            Expanded(
              child: TextField(
                key: const ValueKey('sidebar-search-field'),
                controller: _query,
                style: WorkbenchTokens.ui(size: 13),
                cursorColor: WorkbenchTokens.accent,
                decoration: InputDecoration(
                  hintText: hint,
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            if (_query.text.trim().isNotEmpty)
              InkWell(
                key: const ValueKey('sidebar-search-clear'),
                onTap: _clearQuery,
                borderRadius: BorderRadius.circular(WorkbenchTokens.radius),
                hoverColor: WorkbenchTokens.hover,
                child: const Padding(
                  padding: EdgeInsetsDirectional.only(start: 8),
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: WorkbenchTokens.muted,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 一键清空当前页签的筛选词；只恢复列表，不改变目录数据。
  void _clearQuery() {
    if (_query.text.isEmpty) return;
    setState(_query.clear);
  }

  Widget _tabs() => Container(
    padding: const EdgeInsetsDirectional.symmetric(horizontal: 20),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: WorkbenchTokens.stroke)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: _tabButton(
              _s.sideChapters,
              _controller.chapters.length,
              _SidebarTab.chapters,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: _tabButton(
              _s.sideResources,
              _lore.rows.length,
              _SidebarTab.resources,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _tabButton(String label, int count, _SidebarTab tab) {
    final active = _tab == tab;
    return InkWell(
      onTap: () {
        if (_tab == tab) return;
        setState(() {
          _tab = tab;
          // 搜索只作用于当前页签对象：切换时清空旧词，避免跨对象过滤。
          _query.clear();
        });
      },
      borderRadius: BorderRadius.circular(WorkbenchTokens.radius),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(2, 7, 2, 10),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? WorkbenchTokens.accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          padding: const EdgeInsetsDirectional.only(bottom: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WorkbenchTokens.ui(
                    size: 13,
                    color: active ? WorkbenchTokens.ink : WorkbenchTokens.muted,
                    weight: active ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                _count(count),
                style: WorkbenchTokens.ui(
                  size: 12,
                  color: WorkbenchTokens.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heading(
    String label, {
    VoidCallback? onAdd,
    String? addTooltip,
  }) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 8, 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: WorkbenchTokens.ui(size: 12, color: WorkbenchTokens.muted),
          ),
        ),
        if (onAdd != null)
          IconButton(
            tooltip: addTooltip,
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 16),
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          ),
      ],
    ),
  );

  Widget _chapterDirectory() {
    final chapters = _visibleChapters;
    final emptyText = _query.text.trim().isEmpty
        ? _s.emptyChapters
        : _s.noMatchingChapters;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          _s.chapterDirectory,
          onAdd: _controller.isBusy || _controller.currentWork == null
              ? null
              : _createChapter,
          addTooltip: _s.newChapter,
        ),
        for (final chapter in chapters)
          _chapterRow(chapter, chapters.indexOf(chapter)),
        if (chapters.isEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 8, 16),
            child: Text(
              emptyText,
              style: WorkbenchTokens.ui(
                size: 12,
                color: WorkbenchTokens.muted,
                height: 1.9,
              ),
            ),
          ),
        if (_controller.archivedChapters.isNotEmpty) ...[
          const SizedBox(height: 18),
          _heading(_s.archivedChapters),
          for (final chapter in _controller.archivedChapters)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 4, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      chapter.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WorkbenchTokens.ui(size: 13),
                    ),
                  ),
                  _textAction(
                    _s.restoreChapter,
                    _controller.isBusy
                        ? null
                        : () => _controller.setChapterArchived(chapter, false),
                    color: WorkbenchTokens.accent,
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _chapterRow(WorkspaceChapter chapter, int index) {
    final selected = _controller.currentChapter?.id == chapter.id;
    final number = (index + 1).toString().padLeft(2, '0');
    return Padding(
      key: ValueKey('chapter-${chapter.id}'),
      padding: const EdgeInsetsDirectional.only(bottom: 3),
      child: GestureDetector(
        onSecondaryTapDown: (details) =>
            unawaited(_chapterMenu(chapter, details.globalPosition)),
        onLongPressStart: (details) =>
            unawaited(_chapterMenu(chapter, details.globalPosition)),
        child: Material(
          color: selected ? WorkbenchTokens.selected : Colors.transparent,
          borderRadius: BorderRadius.circular(WorkbenchTokens.radius),
          child: InkWell(
            borderRadius: BorderRadius.circular(WorkbenchTokens.radius),
            hoverColor: WorkbenchTokens.hover,
            onTap: _controller.isBusy
                ? null
                : () => unawaited(_selectChapter(chapter)),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(11, 10, 11, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 18,
                    child: Text(
                      number,
                      style: WorkbenchTokens.ui(
                        size: 12,
                        color: selected
                            ? WorkbenchTokens.accent
                            : WorkbenchTokens.muted,
                        height: 1.65,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      chapter.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: WorkbenchTokens.ui(
                        size: 14,
                        height: 1.65,
                        weight: selected ? FontWeight.w500 : FontWeight.w400,
                        color: selected
                            ? WorkbenchTokens.accent
                            : WorkbenchTokens.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _resourceDirectory() {
    if (_lore.loading) {
      return const Padding(
        padding: EdgeInsetsDirectional.all(12),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    if (_lore.errorCode != null) {
      // 读取失败显式给出原因与重试入口；正文与其它页签不受影响。
      return Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _s.loreReadFailed,
              style: WorkbenchTokens.ui(
                size: 12,
                color: WorkbenchTokens.muted,
                height: 1.9,
              ),
            ),
            _textAction(_s.retry, _lore.retry, color: WorkbenchTokens.accent),
          ],
        ),
      );
    }
    final rows = _visibleLore;
    final groups = <String, List<Map<String, dynamic>>>{
      'character': [],
      'world': [],
      'location': [],
    };
    for (final row in rows) {
      final entry = row['entry'];
      if (entry is! Map) continue;
      final kind = entry['kind'] as String?;
      groups[kind]?.add(row);
    }
    final groupLabels = {
      'character': _s.loreGroupCharacters,
      'world': _s.loreGroupWorld,
      'location': _s.loreGroupLocations,
    };
    final hasVisible = groups.values.any((items) => items.isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          _s.resourceDirectory,
          onAdd: _controller.currentWork == null ? null : _openLore,
          addTooltip: _s.newEntity,
        ),
        if (!hasVisible)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 16),
            child: Text(
              _query.text.trim().isEmpty
                  ? _s.resourcesEmpty
                  : _s.noMatchingResources,
              style: WorkbenchTokens.ui(
                size: 12,
                color: WorkbenchTokens.muted,
                height: 1.9,
              ),
            ),
          )
        else
          for (final kind in groups.keys)
            if (groups[kind]!.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(8, 10, 8, 7),
                child: Text(
                  groupLabels[kind]!,
                  style: WorkbenchTokens.ui(
                    size: 12,
                    color: WorkbenchTokens.muted,
                  ),
                ),
              ),
              for (final row in groups[kind]!) _resourceRow(row, kind),
            ],
      ],
    );
  }

  Widget _resourceRow(Map<String, dynamic> row, String kind) {
    final entry = row['entry'] as Map;
    final entryId = entry['id'] as String? ?? '';
    final name = entry['name'] as String? ?? '';
    final icon = switch (kind) {
      'location' => Icons.place_outlined,
      'world' => Icons.public_outlined,
      _ => Icons.people_outline,
    };
    return InkWell(
      key: ValueKey('lore-row-$entryId'),
      // 行点击要带上具体条目 ID：默认只读预览，不再直接打开整个资料库。
      onTap: _controller.isBusy
          ? null
          : () {
              if (entryId.isEmpty) {
                _showLoreMissing();
                return;
              }
              unawaited(_openLoreEntry(entryId));
            },
      borderRadius: BorderRadius.circular(WorkbenchTokens.radius),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(8, 9, 8, 9),
        child: Row(
          children: [
            Icon(icon, size: 16, color: WorkbenchTokens.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WorkbenchTokens.ui(size: 13),
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 14,
              color: WorkbenchTokens.muted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer() => Container(
    padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 10),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: WorkbenchTokens.stroke)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            _controller.repository.mode == WorkspaceMode.realBridge
                ? _s.sidebarReal
                : _s.sidebarSynthetic,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: WorkbenchTokens.ui(size: 12, color: WorkbenchTokens.muted),
          ),
        ),
        _textAction(_s.switchWork, _controller.isBusy ? null : _openWorkPicker),
      ],
    ),
  );
}
