// 手稿编辑工作区：按原 TS 版纸面排版组合章节标题、正文编辑器与章末操作。
//
// 读边界：正文来自 EditingSession；本文件只把编辑事件转给会话，并镜像 contentEpoch 的变化。
// 写边界：Ctrl+S 触发 flushAll；保存状态更新不得重置编辑器或改写作者正文。
// 关键不变量：编辑器只在 contentEpoch 变化时重置；忙碌时编辑器只读；IME 组合期间不抢全局快捷键；
// 顶层工具栏通过 EditorActionRegistry 触发查找/讨论，避免把工具条塞进纸面。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../cowrite/discussion_panel.dart';
import '../../cowrite/discussion_thread.dart';
import '../../editor/editor_anchor.dart';
import '../../editor/editor_session_adapter.dart';
import '../../editor/editor_source_mark.dart';
import '../../editor/editor_thread_slot.dart';
import '../../editor/editor_viewport.dart';
import '../../lore/source_mark_controller.dart';
import '../../theme/workbench_theme.dart';
import '../data/real_workspace_repository.dart';
import '../workspace_controller.dart';
import 'chapter_find.dart';
import 'editor_action_registry.dart';
import 'source_navigation.dart';
import 'workbench_chrome.dart';
import 'workbench_dialogs.dart';

/// M3 production editing surface — custom raw UTF-16 editor with incremental
/// layout, bounded IME context, and full native input integration. Author text
/// is never normalized, trimmed or rewritten on save-status updates; the editor
/// is reset only when [contentEpoch] moves (open/confirm/rollback).
///
/// 手稿编辑面；作者正文永不归一化、裁剪，也不因保存状态更新而重写。
class ManuscriptEditor extends StatefulWidget {
  const ManuscriptEditor({
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

  /// 专注模式下的最外层退出动作；为空表示当前没有可退出的专注层。
  final VoidCallback? onExitFocus;

  @override
  State<ManuscriptEditor> createState() => _ManuscriptEditorState();
}

class _ManuscriptEditorState extends State<ManuscriptEditor> {
  final GlobalKey<ChapterFindBarState> _findKey =
      GlobalKey<ChapterFindBarState>();
  EditorSessionAdapter? _adapter;
  SourceMarkController? _sources;
  (String, String, String?)? _sourceScope;
  // 打开关联资料失败时保留当时点开的标记，便于在正文头部显式重试。
  List<EditorSourceMark>? _openFailedMarks;
  bool _findOpen = false;

  /// 当前在段下展开的讨论线程；为空表示只看段末标记。
  String? _activeThreadId;

  /// 展开卡片实测高度，按线程 id 缓存；未测量前使用保守估算。
  final Map<String, double> _hostHeights = {};

  /// 上次提交给排版的槽位签名，避免同内容反复触发全文重新定位。
  String _hostSignature = '';

  /// 上次正文代次；章节切换后收起所有段下讨论并清空高度缓存。
  int? _hostEpoch;

  /// 选区快捷入口使用最近一次合法选区；工具栏获得焦点导致选区折叠时仍能
  /// 精确冻结作者最初选中的 UTF-16 区间。
  TextSelection? _lastSelection;

  /// 新建线程后等待自动聚焦草稿的线程 id；只对首个面板实例生效。
  String? _autofocusThreadId;

  /// 视口状态引用；用于把新展开的讨论卡片滚动到可见范围。
  EditorViewportState? _viewport;

  /// 屏障/只读期间取消的临时选区，等待解锁后把光标折叠到原选区末尾。
  int? _pendingSelectionCollapse;

  /// 是否已为待折叠选区排过帧回调，避免 build 期间重复排队。
  bool _collapseScheduled = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_globalKey);
    _initAdapter();
  }

  void _initAdapter() {
    _adapter = EditorSessionAdapter(
      session: widget.controller.editing,
      style: const TextStyle(
        fontFamily: WorkbenchTokens.serifFont,
        fontFamilyFallback: [
          WorkbenchTokens.uiFont,
          WorkbenchTokens.fallbackFont,
        ],
        fontSize: 20,
        height: 1.85,
        color: WorkbenchTokens.ink,
      ),
    );
    _adapter!.addListener(_onAdapterChanged);
    widget.controller.discussions?.addListener(_onDiscussionsChanged);
    _activeThreadId = null;
    _hostHeights.clear();
    _hostSignature = '';
    _hostEpoch = widget.controller.editing.contentEpoch;
    _lastSelection = null;
    _autofocusThreadId = null;
    _pendingSelectionCollapse = null;
    _collapseScheduled = false;
    _bindActions();
    _syncHosts();
    _initSources();
  }

  /// 把查找、讨论与选区状态注册给顶层工具栏；重复调用幂等。
  void _bindActions() {
    widget.actions.bind(
      editor: _adapter?.client,
      onFind: _toggleFind,
      onChapterDiscussion: _openChapterDiscussion,
      onOpenThread: _openThread,
      onDiscussSelection: _discussSelection,
      onRefreshSources: () => _syncSources(force: true),
    );
    widget.actions.setThreads(
      widget.controller.discussions?.threads ?? const [],
    );
    _updateSelection();
  }

  @override
  void didUpdateWidget(ManuscriptEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.actions != widget.actions) {
      oldWidget.actions.unbind(_adapter!.client);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.discussions?.removeListener(_onDiscussionsChanged);
      _adapter?.removeListener(_onAdapterChanged);
      _adapter?.dispose();
      _initAdapter();
    } else if (oldWidget.actions != widget.actions) {
      _bindActions();
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_globalKey);
    if (_adapter != null) widget.actions.unbind(_adapter!.client);
    _sources?.removeListener(_sourceChanged);
    _sources?.dispose();
    widget.controller.discussions?.removeListener(_onDiscussionsChanged);
    _adapter?.removeListener(_onAdapterChanged);
    _adapter?.dispose();
    super.dispose();
  }

  void _onAdapterChanged() {
    final epoch = widget.controller.editing.contentEpoch;
    if (_hostEpoch != epoch) {
      // 打开/确认/回滚会换掉正文身份，旧章节的展开态与高度不沿用。
      _hostEpoch = epoch;
      _activeThreadId = null;
      _hostHeights.clear();
      _hostSignature = '';
      _lastSelection = null;
      _autofocusThreadId = null;
      _pendingSelectionCollapse = null;
      _collapseScheduled = false;
      widget.controller.discussions?.setActiveThread(null);
    }
    _syncSources();
    _syncHosts();
    _updateSelection();
    if (mounted) setState(() {});
  }

  void _onDiscussionsChanged() {
    _syncHosts();
    widget.actions.setThreads(
      widget.controller.discussions?.threads ?? const [],
    );
    if (mounted) setState(() {});
  }

  /// 选区长度按 Unicode 码点上报，与章节字数/查找位置口径一致。
  void _updateSelection() {
    final client = _adapter?.client;
    if (client == null) return;
    final selection = client.value.selection;
    if (selection.isCollapsed) {
      widget.actions.setSelection(0);
      return;
    }
    final raw = client.document.raw;
    final start = selection.start.clamp(0, raw.length);
    final end = selection.end.clamp(start, raw.length);
    if (start == end) {
      widget.actions.setSelection(0);
      return;
    }
    // 记录最近一次合法选区：顶栏按钮拿焦点时 Flutter 可能先折叠正文选区，
    // 创建讨论仍以作者最初选中的区间为准。
    _lastSelection = TextSelection(baseOffset: start, extentOffset: end);
    widget.actions.setSelection(raw.substring(start, end).runes.length);
  }

  void _initSources() {
    _sources?.removeListener(_sourceChanged);
    _sources?.dispose();
    final repository = widget.controller.repository;
    // 真实仓库经 lore 暴露读取器；合成测试仓库实现 SourceMarkHost 即可注入
    // 受控的 loading/empty/error 响应，正文装饰因此不需要伪造整个真实仓库。
    final SourceMarkRepository? loader;
    if (repository is RealWorkspaceRepository) {
      loader = repository.lore;
    } else if (repository is SourceMarkHost) {
      loader = (repository as SourceMarkHost).sourceMarks;
    } else {
      loader = null;
    }
    _sources = loader == null ? null : SourceMarkController(loader);
    _sources?.addListener(_sourceChanged);
    _sourceScope = null;
    _openFailedMarks = null;
    _syncSources();
  }

  void _sourceChanged() {
    if (mounted) setState(() {});
  }

  // 来源标记按作品、文档与版本作用域加载；作用域未变时不重复请求。
  void _syncSources({bool force = false}) {
    final doc = widget.controller.editing.document;
    final scope = doc == null
        ? null
        : (doc.workId, doc.documentId, doc.headVersionId);
    if (!force && scope == _sourceScope) return;
    _sourceScope = scope;
    if (doc == null) {
      _sources?.clear();
      return;
    }
    final source = _sources;
    if (source != null) {
      unawaited(
        source.load(
          doc.workId,
          doc.documentId,
          doc.headVersionId,
          _adapter!.client.document.raw,
        ),
      );
    }
  }

  List<EditorSourceMark> get _marks {
    final doc = widget.controller.editing.document;
    return _sources?.visible(
          doc?.workId,
          doc?.documentId,
          doc?.headVersionId,
          _adapter!.client.document.raw,
        ) ??
        const [];
  }

  Future<void> _openMarks(List<EditorSourceMark> marks) async {
    final current = _marks;
    marks = marks.where(current.contains).toList();
    if (marks.isEmpty) return;
    try {
      await openMarkedLore(context, widget.controller, _adapter!.client, marks);
      if (mounted) {
        setState(() => _openFailedMarks = null);
        _syncSources(force: true);
      }
    } catch (_) {
      // 打开关联资料失败时显式提示并允许重试；失败不阻塞正文，也不改正文。
      if (mounted) setState(() => _openFailedMarks = marks);
    }
  }

  /// 出处装饰的四种状态：加载中 / 无出处 / 加载失败 / 有内容。
  Widget? _sourceStatus(List<EditorSourceMark> marks) {
    final sources = _sources;
    if (sources == null) return null;
    final doc = widget.controller.editing.document;
    final state = sources.stateFor(
      doc?.workId,
      doc?.documentId,
      doc?.headVersionId,
      _adapter!.client.document.raw,
    );
    final strings = widget.labels.strings;
    switch (state) {
      case SourceMarkState.loading:
        return _sourceNote(
          key: const ValueKey('source-marks-loading'),
          text: strings.sourceMarksLoading,
        );
      case SourceMarkState.error:
        return _sourceNote(
          key: const ValueKey('source-marks-retry'),
          text: strings.sourceMarksFailed,
          color: WorkbenchTokens.warning,
          onTap: () => _syncSources(force: true),
        );
      case SourceMarkState.empty:
        return _sourceNote(
          key: const ValueKey('source-marks-empty'),
          text: strings.sourceMarksEmpty,
        );
      case SourceMarkState.content:
        return PopupMenuButton<int>(
          key: const ValueKey('source-marks-menu'),
          tooltip: strings.manuscriptSources,
          enabled: !widget.controller.isBusy,
          onSelected: (index) => _openMarks([marks[index]]),
          itemBuilder: (_) => [
            for (var i = 0; i < marks.length; i++)
              PopupMenuItem(value: i, child: Text(marks[i].name)),
          ],
          child: Text(
            strings.manuscriptSources,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: WorkbenchTokens.ui(size: 12, color: WorkbenchTokens.accent),
          ),
        );
    }
  }

  /// 12px 的轻量状态文字；错误态可点击重试，并用 liveRegion 让读屏立即播报。
  Widget _sourceNote({
    required Key key,
    required String text,
    Color? color,
    VoidCallback? onTap,
  }) {
    final label = Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: WorkbenchTokens.ui(
        size: 12,
        color: color ?? WorkbenchTokens.muted,
      ),
    );
    if (onTap == null) {
      return Semantics(key: key, liveRegion: true, child: label);
    }
    return Semantics(
      liveRegion: true,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: key,
          onTap: onTap,
          borderRadius: BorderRadius.circular(WorkbenchTokens.overlayRadius),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 4,
              vertical: 2,
            ),
            child: label,
          ),
        ),
      ),
    );
  }

  /// 打开关联资料失败：显式错误 + 重试入口，正文仍可继续写。
  Widget _sourceOpenFailure() {
    final strings = widget.labels.strings;
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 6),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 15,
            color: WorkbenchTokens.warning,
          ),
          Text(
            strings.sourceOpenFailed,
            style: WorkbenchTokens.ui(size: 12, color: WorkbenchTokens.warning),
          ),
          TextButton(
            key: const ValueKey('source-open-retry'),
            onPressed: () {
              final failed = _openFailedMarks;
              if (failed != null) unawaited(_openMarks(failed));
            },
            child: Text(strings.sourceOpenRetry),
          ),
        ],
      ),
    );
  }

  /// 段下讨论同一时间只展开一条线程：展开的卡片占目标段末高度，
  /// 其余有效线程只保留高度为 0 的段末标记，不占正文空间。
  void _syncHosts() {
    final client = _adapter?.client;
    if (client == null) return;
    final registry = widget.controller.discussions;
    final threads = registry?.threads ?? const <DiscussionThread>[];
    if (_activeThreadId != null &&
        !threads.any(
          (thread) =>
              thread.id == _activeThreadId && !thread.isChapter && thread.valid,
        )) {
      final previous = _activeThreadId;
      _activeThreadId = null;
      if (registry?.activeThreadId == previous) registry?.setActiveThread(null);
    }
    final slots = <EditorThreadSlot>[
      for (final thread in threads)
        if (!thread.isChapter && thread.valid)
          EditorThreadSlot(
            id: thread.id,
            offset: thread.offset.clamp(0, client.length),
            height: thread.id == _activeThreadId
                ? (_hostHeights[thread.id] ?? 260)
                : 0,
          ),
    ];
    final signature = slots
        .map((slot) => '${slot.id}:${slot.offset}:${slot.height}')
        .join('|');
    if (signature == _hostSignature) return;
    _hostSignature = signature;
    client.layout.setThreadSlots(slots);
  }

  /// 展开指定线程的段下卡片；切换前先把当前草稿同步给注册表。
  void _activateThread(DiscussionThread thread, {bool focusDraft = false}) {
    final registry = widget.controller.discussions;
    if (registry == null || thread.isChapter || !thread.valid) return;
    unawaited(registry.flush().catchError((Object _) {}));
    if (!mounted) return;
    setState(() {
      _activeThreadId = thread.id;
      _autofocusThreadId = focusDraft ? thread.id : null;
    });
    registry.setActiveThread(thread.id);
    _syncHosts();
    final anchor = thread.anchor;
    final client = _adapter?.client;
    if (anchor != null && client != null) {
      final start = anchor.from.clamp(0, client.length);
      final end = anchor.to.clamp(start, client.length);
      client.select(TextSelection(baseOffset: start, extentOffset: end));
    }
    // 卡片高度在下一帧才测量完成；先安排一次露出，渲染后再按真实高度修正。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _activeThreadId != thread.id) return;
      _viewport?.revealThread(thread.id);
    });
  }

  /// 收起当前段下卡片，保留线程、草稿与标记，并把焦点交还正文目标末尾。
  void _collapseActiveThread() {
    final registry = widget.controller.discussions;
    final thread = _activeThread();
    if (registry?.activeThreadId == thread?.id) {
      registry?.setActiveThread(null);
    }
    // 收起不是取消：先把作者草稿刷入注册表，再只改展示态。
    unawaited(registry?.flush().catchError((Object _) {}));
    setState(() {
      _activeThreadId = null;
      _autofocusThreadId = null;
    });
    _syncHosts();
    final client = _adapter?.client;
    if (client == null) return;
    final end = thread?.anchor;
    if (end != null) {
      final offset = end.to.clamp(0, client.length);
      client.select(TextSelection.collapsed(offset: offset));
    }
    client.focusNode.requestFocus();
  }

  DiscussionThread? _activeThread() {
    final id = _activeThreadId;
    if (id == null) return null;
    for (final thread
        in widget.controller.discussions?.threads ??
            const <DiscussionThread>[]) {
      if (thread.id == id) return thread;
    }
    return null;
  }

  /// 收起线程的段末标记：每个线程独立命中区域，点击展开对应卡片。
  Widget _threadMarker(BuildContext context, String id) {
    return Tooltip(
      message: widget.labels.strings.discussionSelection,
      child: Material(
        color: WorkbenchTokens.hover,
        shape: const CircleBorder(),
        child: InkWell(
          key: ValueKey('thread-marker-open-$id'),
          customBorder: const CircleBorder(),
          onTap: () {
            for (final thread
                in widget.controller.discussions?.threads ??
                    const <DiscussionThread>[]) {
              if (thread.id == id) {
                _activateThread(thread);
                break;
              }
            }
          },
          child: const SizedBox(
            width: 24,
            height: 24,
            child: Icon(Icons.forum_outlined, size: 14),
          ),
        ),
      ),
    );
  }

  /// 卡片实测高度回填到排版槽位；只有高度变化超过半个像素才触发重排。
  void _onHostMeasured(String id, double height) {
    if (!mounted || id != _activeThreadId) return;
    final previous = _hostHeights[id];
    if (previous != null && (height - previous).abs() < 0.5) return;
    _hostHeights[id] = height;
    setState(() {});
    _syncHosts();
    // 卡片按真实高度重排后再次露出，保证输入区不会被视口底边遮挡。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _activeThreadId == id) _viewport?.revealThread(id);
    });
  }

  /// 当前主焦点是否落在可编辑文本内，以及是否处于输入法组字。
  ///
  /// 窗口级快捷键不能仅凭正文编辑器“没有组字”就抢占按键：重命名、
  /// 资料编辑、讨论草稿等输入框同样属于最内层，快捷键应先交还它们。
  ({bool editable, bool composing}) _focusedEditable() {
    final primary = FocusManager.instance.primaryFocus;
    final editable = primary?.context
        ?.findAncestorWidgetOfExactType<EditableText>();
    return (
      editable: editable != null,
      composing:
          editable != null &&
          editable.controller.value.composing.isValid &&
          !editable.controller.value.composing.isCollapsed,
    );
  }

  /// Window-level shortcuts mirror the original writing shell: Ctrl+F opens
  /// in-chapter find, Ctrl+S flushes the exact text. IME composition keeps
  /// every key, and editable dialogs are left alone.
  bool _globalKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    // 浮动菜单/对话框是更新的路由，窗口级快捷键和层级退出都不能越过它们；
    // 这些层由各自路由处理 Escape，避免一次按键退出多层。
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    final editable = _focusedEditable();
    if (editable.composing || (_adapter?.client.composing ?? false)) {
      return false;
    }
    final keyboard = HardwareKeyboard.instance;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      // 从最内层逐层退出：查找 → 已展开讨论 → 专注；每层只退一层。
      if (_findOpen) {
        _closeFind();
        return true;
      }
      if (_activeThreadId != null) {
        _collapseActiveThread();
        return true;
      }
      final exitFocus = widget.onExitFocus;
      if (exitFocus != null) {
        exitFocus();
        return true;
      }
      return false;
    }
    if (!keyboard.isControlPressed || keyboard.isAltPressed) return false;
    // 其他输入框中的 Ctrl+F/Ctrl+S 属于该控件自身或系统，不在这里抢占。
    if (editable.editable) return false;
    final client = _adapter?.client;
    if (client == null) return false;
    if (event.logicalKey == LogicalKeyboardKey.keyF) {
      if (_findOpen) {
        _findKey.currentState?.focusInput();
      } else {
        setState(() => _findOpen = true);
        widget.actions.setFindOpen(true);
      }
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyS) {
      unawaited(_saveNow());
      return true;
    }
    return false;
  }

  Future<void> _saveNow() async {
    try {
      await widget.controller.editing.flushAll();
    } catch (_) {
      /* 保存状态条保留稳定错误码。 */
    }
    if (mounted) setState(() {});
  }

  void _toggleFind() {
    setState(() => _findOpen = !_findOpen);
    widget.actions.setFindOpen(_findOpen);
  }

  void _closeFind() {
    setState(() => _findOpen = false);
    widget.actions.setFindOpen(false);
    _adapter?.client.focusNode.requestFocus();
  }

  Future<void> _renameChapter() async {
    final chapter = widget.controller.currentChapter;
    if (chapter == null) return;
    final s = widget.labels.strings;
    final title = await showTitlePrompt(
      context: context,
      labels: widget.labels,
      title: s.renameChapter,
      fieldLabel: s.chapterTitleLabel,
      initial: chapter.title,
    );
    if (title != null) await widget.controller.renameChapter(chapter, title);
    _adapter?.client.focusNode.requestFocus();
  }

  void _openChapterDiscussion() {
    final registry = widget.controller.discussions;
    if (registry == null) return;
    final thread = registry.chapterThread();
    unawaited(_openThreadDialog(thread));
  }

  /// 整章/失效线程的临时面板；关闭（按钮或 Escape）后焦点回正文。
  Future<void> _openThreadDialog(DiscussionThread thread) async {
    final registry = widget.controller.discussions;
    final work = registry?.work;
    final chapter = registry?.chapter;
    final previous = registry?.activeThreadId;
    registry?.setActiveThread(thread.id);
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          // The panel must stay usable in narrow windows and at large text scales.
          final size = MediaQuery.sizeOf(dialogContext);
          return AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) => Dialog(
              insetPadding: const EdgeInsets.all(16),
              child: SizedBox(
                width: size.width > 592 ? 560 : null,
                height: size.height > 592 ? 560 : null,
                child: DiscussionPanel(
                  thread: thread,
                  workspace: widget.controller,
                  onCollapse: () => Navigator.of(dialogContext).pop(),
                ),
              ),
            ),
          );
        },
      );
    } finally {
      if (registry != null &&
          registry.work == work &&
          registry.chapter == chapter &&
          registry.activeThreadId == thread.id) {
        registry.setActiveThread(
          previous != null && registry.byId(previous) != null ? previous : null,
        );
      }
    }
    // 面板关闭后把焦点还给正文；目标已失效时也不跳到旧坐标。
    if (mounted) _adapter?.client.focusNode.requestFocus();
  }

  /// 打开已有讨论：整章或锚点失效的线程进临时对话框，有效段下线程就地展开。
  void _openThread(DiscussionThread thread) {
    if (thread.isChapter || !thread.valid) {
      unawaited(_openThreadDialog(thread));
      return;
    }
    _activateThread(thread);
  }

  void _discussSelection() {
    final client = _adapter?.client;
    final registry = widget.controller.discussions;
    if (client == null || registry == null) return;
    if (client.composing) return;
    var selection = client.value.selection;
    if (selection.isCollapsed) {
      final frozen = _lastSelection;
      if (frozen == null || frozen.isCollapsed) return;
      selection = frozen;
    }
    final start = selection.start.clamp(0, client.length);
    final end = selection.end.clamp(start, client.length);
    if (start == end) return;
    // 点击/提交时重新校验：忙碌、只读或屏障期间不创建线程；取消这次临时
    // 选区时把光标折叠到原选区末尾（只读期间先挂起，解锁后由帧回调补做）。
    if (widget.controller.isBusy ||
        widget.controller.editing.inputLocked ||
        client.readOnly) {
      _pendingSelectionCollapse = end;
      _schedulePendingCollapse();
      return;
    }
    final thread = registry.create(
      EditorAnchor.capture(client.document.raw, start, end),
    );
    // 新建线程立即成为唯一展开的段下卡片，作者可以直接输入。
    _activateThread(thread, focusDraft: true);
  }

  /// 屏障解锁后把取消的临时选区折叠到原选区末尾；每次 build 都尝试一次，
  /// 只读期间只保留挂起状态，不强行改正文/选区。
  void _schedulePendingCollapse() {
    if (_pendingSelectionCollapse == null || _collapseScheduled) return;
    _collapseScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _collapseScheduled = false;
      final client = _adapter?.client;
      final offset = _pendingSelectionCollapse;
      if (!mounted || client == null || offset == null || client.readOnly) {
        return;
      }
      _pendingSelectionCollapse = null;
      client.select(TextSelection.collapsed(offset: offset));
    });
  }

  /// 选区旁的就近“讨论这段”入口；不占常驻工具栏高度。
  Widget _selectionAction(BuildContext context, Rect caretRect) {
    final label = widget.labels.strings.discussSelection;
    return Material(
      color: WorkbenchTokens.toolbar,
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(WorkbenchTokens.overlayRadius),
      child: InkWell(
        key: const ValueKey('discuss-selection-inline'),
        borderRadius: BorderRadius.circular(WorkbenchTokens.overlayRadius),
        onTap: _discussSelection,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.forum_outlined,
                size: 14,
                color: WorkbenchTokens.accent,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: WorkbenchTokens.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double get _paperWidth => widget.wide
      ? WorkbenchTokens.wideWidth
      : WorkbenchTokens.comfortableWidth;

  double get _textWidth => widget.wide
      ? WorkbenchTokens.wideWidth - 96
      : WorkbenchTokens.comfortableWidth - 96;

  @override
  Widget build(BuildContext context) {
    final adapter = _adapter!;
    final marks = _marks;
    final strings = widget.labels.strings;
    final chapter = widget.controller.currentChapter;
    final work = widget.controller.currentWork;
    final characterCount = adapter.client.document.raw.runes.length;
    adapter.client.readOnly = widget.controller.isBusy;
    _schedulePendingCollapse();
    final busy = widget.controller.isBusy;
    if (widget.actions.busy != busy) {
      scheduleMicrotask(() => widget.actions.setBusy(busy));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_findOpen)
          Align(
            alignment: AlignmentDirectional.topEnd,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(0, 8, 48, 0),
              child: Material(
                color: Colors.white,
                elevation: 4,
                shadowColor: Colors.black.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(
                  WorkbenchTokens.overlayRadius,
                ),
                child: SizedBox(
                  width: 460,
                  child: ChapterFindBar(
                    key: _findKey,
                    editor: adapter.client,
                    chapterId: chapter?.id,
                    onClose: _closeFind,
                  ),
                ),
              ),
            ),
          ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: _paperWidth),
              child: EditorViewport(
                key: const ValueKey('manuscript-body'),
                controller: adapter.client,
                maxTextWidth: _textWidth,
                // 标题、正文与章末共用一个 ScrollPosition：标题随纸面滚走，
                // 章末紧接正文最后一行，而不是固定到窗口底部。
                documentHeader: _paperHeader(
                  title: chapter?.title ?? widget.labels(strings.chooseChapter),
                  meta: widget.labels(
                    strings.chapterMeta(work?.title ?? '', characterCount),
                  ),
                  renameLabel: strings.renameChapter,
                  onRename: chapter == null || busy
                      ? null
                      : () => unawaited(_renameChapter()),
                  sourceStatus: _sourceStatus(marks),
                  sourceOpenFailure: _openFailedMarks == null
                      ? null
                      : _sourceOpenFailure(),
                ),
                documentFooter: _paperFooter(
                  chapterEnd: strings.chapterEnd,
                  undoLabel: strings.undo,
                  redoLabel: strings.redo,
                  discussionLabel: strings.chapterDiscussion,
                  onUndo: adapter.client.document.canUndo
                      ? adapter.client.undo
                      : null,
                  onRedo: adapter.client.document.canRedo
                      ? adapter.client.redo
                      : null,
                  onDiscussion:
                      widget.controller.discussions == null ||
                          busy ||
                          chapter == null
                      ? null
                      : _openChapterDiscussion,
                ),
                restoreScrollOffset: widget.controller.applyScrollPending
                    ? widget.controller.pendingScrollTop
                    : null,
                restoreScrollToken: widget.controller.editing.contentEpoch,
                onScrollRestored: widget.controller.markScrollApplied,
                onScrollOffset: widget.controller.noteScrollTop,
                sourceMarks: marks,
                sourceBody: adapter.client.document.raw,
                onOpenSources: _openMarks,
                editorLabel: strings.editorAccessibleLabel,
                renderingFailureLabel: strings.editorRenderingUnsupported,
                discussionBuilder: widget.controller.discussions == null
                    ? null
                    : (context, id) {
                        final active = _activeThread();
                        if (active == null || active.id != id) {
                          return const SizedBox.shrink();
                        }
                        return DiscussionPanel(
                          thread: active,
                          workspace: widget.controller,
                          onCollapse: _collapseActiveThread,
                          autofocusDraft: _autofocusThreadId == active.id,
                        );
                      },
                discussionMarkerBuilder: _threadMarker,
                onThreadHostMeasured: _onHostMeasured,
                selectionActionBuilder: _selectionAction,
                onStateReady: (state) => _viewport = state,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 纸面标题区：与正文共用滚动坐标，滚动后自然离开视口。
  Widget _paperHeader({
    required String title,
    required String meta,
    required String renameLabel,
    required VoidCallback? onRename,
    required Widget? sourceStatus,
    required Widget? sourceOpenFailure,
  }) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(48, 60, 48, 42),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
            ),
            if (onRename != null) ...[
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 10),
                child: _TextAction(
                  label: renameLabel,
                  accent: true,
                  onPressed: onRename,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Flexible(
              child: Text(
                meta,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: WorkbenchTokens.ui(
                  size: 12,
                  color: WorkbenchTokens.muted,
                  height: 1.6,
                ),
              ),
            ),
            if (sourceStatus != null) ...[
              const SizedBox(width: 12),
              Flexible(child: sourceStatus),
            ],
          ],
        ),
        if (sourceOpenFailure != null) sourceOpenFailure,
      ],
    ),
  );

  /// 纸面章末：位于正文最后一行之后，随文档一起滚动。
  Widget _paperFooter({
    required String chapterEnd,
    required String undoLabel,
    required String redoLabel,
    required String discussionLabel,
    required VoidCallback? onUndo,
    required VoidCallback? onRedo,
    required VoidCallback? onDiscussion,
  }) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(48, 14, 48, 24),
    child: Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: WorkbenchTokens.stroke)),
      ),
      padding: const EdgeInsetsDirectional.only(top: 14),
      child: Wrap(
        spacing: 14,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            chapterEnd,
            style: WorkbenchTokens.ui(size: 12, color: WorkbenchTokens.muted),
          ),
          _TextAction(label: undoLabel, onPressed: onUndo),
          _TextAction(label: redoLabel, onPressed: onRedo),
          if (onDiscussion != null)
            _TextAction(label: discussionLabel, onPressed: onDiscussion),
        ],
      ),
    ),
  );
}

/// 纸面内的文字操作：13px、悬停浅灰底，无 Material 按钮外观。
class _TextAction extends StatelessWidget {
  const _TextAction({
    required this.label,
    required this.onPressed,
    this.accent = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final color = !enabled
        ? WorkbenchTokens.muted.withValues(alpha: 0.5)
        : accent
        ? WorkbenchTokens.accent
        : WorkbenchTokens.muted;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(WorkbenchTokens.radius),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(WorkbenchTokens.radius),
        hoverColor: WorkbenchTokens.hover,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 8,
            vertical: 4,
          ),
          child: Text(label, style: WorkbenchTokens.ui(size: 13, color: color)),
        ),
      ),
    );
  }
}
