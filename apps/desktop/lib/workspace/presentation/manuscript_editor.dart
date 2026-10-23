// 手稿编辑会话：协调原生输入、精确选区、讨论展示和出处读取的生命周期。
// 保存通知不重置正文，切章才重置展示状态；全局快捷键不得穿透输入法或模态。
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../cowrite/discussion_panel.dart';
import '../../cowrite/discussion_thread.dart';
import '../../editor/editor_anchor.dart';
import '../../editor/editor_session_adapter.dart';
import '../../editor/editor_viewport.dart';
import '../../theme/workbench_theme.dart';
import '../workspace_controller.dart';
import 'chapter_find.dart';
import 'editor_action_registry.dart';
import 'manuscript_body.dart';
import 'manuscript_sources.dart';
import 'manuscript_thread_hosts.dart';
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
  final _findKey = GlobalKey<ChapterFindBarState>();
  EditorSessionAdapter? _adapter;
  late ManuscriptSources _sources;
  late ManuscriptThreadHosts _hosts;
  bool _findOpen = false;
  int? _hostEpoch;
  TextSelection? _lastSelection;
  EditorViewportState? _viewport;
  int? _pendingSelectionCollapse;
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
      style: WorkbenchTokens.body,
    );
    _hosts = ManuscriptThreadHosts(
      workspace: widget.controller,
      client: _adapter!.client,
      onReveal: (id) {
        if (mounted) _viewport?.revealThread(id);
      },
    )..addListener(_changed);
    _sources = ManuscriptSources(
      workspace: widget.controller,
      client: _adapter!.client,
      context: () => context,
      isMounted: () => mounted,
    )..addListener(_changed);
    _adapter!.addListener(_onAdapterChanged);
    widget.controller.discussions?.addListener(_onDiscussionsChanged);
    _hostEpoch = widget.controller.editing.contentEpoch;
    _lastSelection = null;
    _pendingSelectionCollapse = null;
    _collapseScheduled = false;
    _bindActions();
    _hosts.sync();
  }

  void _bindActions() {
    widget.actions.bind(
      editor: _adapter?.client,
      onFind: _toggleFind,
      onChapterDiscussion: _openChapterDiscussion,
      onOpenThread: _openThread,
      onDiscussSelection: _discussSelection,
      onRefreshSources: () => _sources.sync(force: true),
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
      _releaseAdapter();
      _initAdapter();
    } else if (oldWidget.actions != widget.actions) {
      _bindActions();
    }
  }

  void _releaseAdapter() {
    _sources.removeListener(_changed);
    _sources.dispose();
    _hosts.removeListener(_changed);
    _hosts.dispose();
    _adapter?.removeListener(_onAdapterChanged);
    _adapter?.dispose();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_globalKey);
    if (_adapter != null) widget.actions.unbind(_adapter!.client);
    widget.controller.discussions?.removeListener(_onDiscussionsChanged);
    _releaseAdapter();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _onAdapterChanged() {
    final epoch = widget.controller.editing.contentEpoch;
    if (_hostEpoch != epoch) {
      _hostEpoch = epoch;
      _hosts.reset();
      _lastSelection = null;
      _pendingSelectionCollapse = null;
      _collapseScheduled = false;
      widget.controller.discussions?.setActiveThread(null);
    }
    _sources.sync();
    _hosts.sync();
    _updateSelection();
    _changed();
  }

  void _onDiscussionsChanged() {
    _hosts.sync();
    widget.actions.setThreads(
      widget.controller.discussions?.threads ?? const [],
    );
    _changed();
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
      if (_hosts.activeId != null) {
        _hosts.collapse();
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
      if (widget.controller.editing.saveState?.errorCode == null) rethrow;
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
    if (!mounted) return;
    if (title != null) await widget.controller.renameChapter(chapter, title);
    if (!mounted) return;
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

                child: DiscussionPanel(
                  inDialog: true,
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
    _hosts.activate(thread);
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
    // 同一选段不重复建线程：锚点区间一致的有效讨论直接重开，
    // 避免同一句话在目录里堆积多条互相孤立的记录。
    final existing = registry.threads.where(
      (thread) =>
          !thread.isChapter &&
          thread.valid &&
          thread.anchor?.from == start &&
          thread.anchor?.to == end,
    );
    if (existing.isNotEmpty) {
      _hosts.activate(existing.first);
      return;
    }
    final thread = registry.create(
      EditorAnchor.capture(client.document.raw, start, end),
    );
    // 新建线程立即成为唯一展开的段下卡片，作者可以直接输入。
    _hosts.activate(thread, focusDraft: true);
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

  @override
  Widget build(BuildContext context) {
    final adapter = _adapter!;
    adapter.client.readOnly = widget.controller.isBusy;
    _schedulePendingCollapse();
    final busy = widget.controller.isBusy;
    if (widget.actions.busy != busy) {
      scheduleMicrotask(() => widget.actions.setBusy(busy));
    }
    return ManuscriptBody(
      presentation: ManuscriptPresentation(
        controller: widget.controller,
        labels: widget.labels,
        wide: widget.wide,
        adapter: adapter,
        sources: _sources,
        hosts: _hosts,
        findKey: _findKey,
        findOpen: _findOpen,
        onCloseFind: _closeFind,
        onRename: _renameChapter,
        onChapterDiscussion: _openChapterDiscussion,
        onDiscussSelection: _discussSelection,
        onStateReady: (state) => _viewport = state,
      ),
    );
  }
}
