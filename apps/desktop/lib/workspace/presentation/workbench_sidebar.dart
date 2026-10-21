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

import '../data/real_workspace_repository.dart';
import '../data/workspace_repository.dart';
import '../workspace_controller.dart';
import 'lore_directory.dart';
import 'lore_preview.dart';
import 'work_picker.dart';
import 'workbench_chrome.dart';
import 'workbench_dialogs.dart';
import 'sidebar_frame.dart';

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

  void _clearQuery() {
    if (_query.text.isEmpty) return;
    setState(_query.clear);
  }

  void _changeTab(bool resources) {
    final next = resources ? _SidebarTab.resources : _SidebarTab.chapters;
    if (_tab == next) return;
    setState(() {
      _tab = next;
      _query.clear();
    });
  }

  SidebarCommands get _commands => SidebarCommands(
    onTab: _changeTab,
    onQuery: (_) => setState(() {}),
    onClear: _clearQuery,
    onCreate: _controller.isBusy || _controller.currentWork == null
        ? null
        : () => unawaited(_createChapter()),
    onSelect: _selectChapter,
    onMenu: _chapterMenu,
    onRestore: (chapter) => _controller.setChapterArchived(chapter, false),
    onAddResource: _controller.currentWork == null
        ? null
        : () => unawaited(_openLore()),
    onOpenResource: _openLoreEntry,
    onMissing: _showLoreMissing,
    onSwitch: _controller.isBusy ? null : () => unawaited(_openWorkPicker()),
    onCollapse: widget.onCollapse,
  );

  @override
  Widget build(BuildContext context) => SidebarFrame(
    controller: _controller,
    labels: widget.labels,
    query: _query,
    resourcesSelected: _tab == _SidebarTab.resources,
    lore: _lore,
    chapters: _visibleChapters,
    rows: _visibleLore,
    commands: _commands,
  );
}
