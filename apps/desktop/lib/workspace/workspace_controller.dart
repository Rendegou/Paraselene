// 工作区控制器：聚合作品目录、章节导航、正文编辑会话、每作品 UI 偏好与原生伴写能力。
// 读边界：目录、正文与版本只经 WorkspaceRepository 读取；界面展示的正文以 EditingSession 的内存副本为准。
// 写边界：所有变更都串行经过同一个持久化屏障，先 flush 正文与偏好再执行动作，失败时保留当前身份与脏文本。
// 关键不变量：至多一个屏障在跑；generation 过期的异步结果必须丢弃；窗口关闭只能走 closeBarrier。
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'data/workspace_repository.dart';
import 'editing_session.dart';
import '../cowrite/discussion_repository.dart';
import '../cowrite/discussion_registry.dart';
import '../cowrite/generation_repository.dart';
import '../legacy/companion_service.dart';
import '../legacy/learning_service.dart';

part 'workspace_state.dart';
part 'workspace_cowrite.dart';
part 'workspace_close.dart';

/// Loading and error are explicit even when previous metadata remains visible.
///
/// 工作区加载阶段；加载中与失败都是显式状态，此时仍可能显示上一次的元数据。
enum WorkspacePhase { loading, empty, content, error }

/// Coordinates works, chapters, editing and preferences behind one busy
/// barrier: a failed flush keeps the current identity, text and revision in
/// place, and retry/export stay reachable. Newer user intent wins races.
///
/// 工作区协调器：把作品、章节、编辑与偏好收敛到同一个串行屏障之后。
/// 动作失败时保留当前作品、章节与脏文本，并暴露稳定错误码；较新的用户意图通过 generation 取代旧的异步结果。
final class WorkspaceController extends _WorkspaceState
    with _CowriteOperations, _WorkspaceClose {
  /// Holds the normal flush barrier for full backup or other explicit local work.
  ///
  /// 在持锁屏障内执行本地全量备份等显式操作；动作失败时返回 false 并保留错误码。
  @override
  Future<bool> persistenceBarrier(Future<void> Function() action) =>
      _barrier(action);

  /// 创建控制器并订阅原生伴写与学习服务的事件流。
  ///
  /// 仓库实现 DiscussionRepositoryProvider 时同时建立讨论注册表；未注入的服务使用不可用占位实现。
  WorkspaceController(
    super.repository, {
    super.editingSession,
    this.companion = const UnavailableCompanionService(),
    this.learning = const UnavailableLearningService(),
  }) {
    _listenNative(companion, learning);
    final source = repository;
    if (source case final DiscussionRepositoryProvider provider) {
      discussions = DiscussionRegistry(provider.discussions);
      _discussionBody = editing.body;
      editing.addListener(_mapDiscussionBody);
    }
  }
  final CompanionService companion;
  final LearningService learning;

  bool _active(int generation) => !_disposed && generation == _generation;

  // 每次导航开启新一代；过期的异步结果凭代号失配被丢弃，避免旧加载覆盖新选择。
  int _begin() {
    final generation = ++_generation;
    _phase = WorkspacePhase.loading;
    _errorCode = null;
    notifyListeners();
    return generation;
  }

  void _fail(Object error, int generation) {
    if (!_active(generation)) return;
    _errorCode = error is WorkspaceFailure
        ? error.code
        : 'workspace_unavailable';
    _phase = WorkspacePhase.error;
    notifyListeners();
  }

  /// Serial barrier: flush text and preferences before the action; any
  /// failure keeps the current chapter and surfaces the stable code.
  @override
  Future<bool> _barrier(
    Future<void> Function() action, {
    bool flush = true,
  }) async {
    if (_disposed || _busy || _closed) return false;
    _busy = true;
    final idle = _idle = Completer<void>();
    _errorCode = null;
    notifyListeners();
    try {
      if (flush) {
        await _drain();
      }
      if (_disposed) return false;
      editing.inputLocked = true;
      await action();
      return true;
    } catch (error) {
      _errorCode = error is WorkspaceFailure
          ? error.code
          : 'workspace_unavailable';
      return false;
    } finally {
      editing.inputLocked = _closed;
      _busy = false;
      _idle = null;
      idle.complete();
      if (!_disposed) notifyListeners();
    }
  }

  /// Refreshes the directory behind the barrier and selects the first work.
  ///
  /// 刷新目录后自动选中第一部作品；屏障内失败时保留现有选择并记录错误码。
  Future<void> refresh() async {
    await _barrier(() => _refresh(seed: false));
  }

  /// Creates an explicit synthetic fixture through the injected repository.
  ///
  /// 通过注入的仓库显式创建演示数据；控制器自身不直接访问数据库。
  Future<void> seedDemo() async {
    await _barrier(() => _refresh(seed: true));
  }

  Future<void> _refresh({required bool seed}) async {
    if (_disposed) return;
    if (seed) _seedPending = true;
    final generation = _begin();
    try {
      if (_seedPending) {
        await repository.seedDemo();
        _seedPending = false;
      }
      if (!_active(generation)) return;
      await _loadWorks(generation);
    } catch (error) {
      _fail(error, generation);
    }
  }

  Future<void> _loadWorks(int generation) async {
    final works = await repository.listWorks();
    if (!_active(generation)) return;
    _works = List.unmodifiable(works);
    if (works.isEmpty) {
      _clearSelection();
      _phase = WorkspacePhase.empty;
      notifyListeners();
      return;
    }
    await _openWork(works.first, generation, restore: false);
  }

  /// Cold start: restore the selected or most recent work, then its per-work
  /// chapter/wide/scroll preferences. Damaged records surface a notice code.
  ///
  /// 损坏的 UI 会话只产生提示码而不阻断启动；选中的作品不可用时回退到目录中的第一部作品。
  Future<void> restoreSession() async {
    await _barrier(_restoreSession);
  }

  Future<void> _restoreSession() async {
    if (_disposed) return;
    final generation = _begin();
    try {
      final state = await repository.workspaceState();
      if (!_active(generation)) return;
      _noticeCode = state.warning;
      final works = await repository.listWorks();
      if (!_active(generation)) return;
      _works = List.unmodifiable(works);
      if (works.isEmpty) {
        _phase = WorkspacePhase.empty;
        notifyListeners();
        return;
      }
      final targetId =
          state.selectedWorkId ??
          state.recentWorks.map((w) => w.id).firstOrNull;
      final target =
          works.where((w) => w.id == targetId).firstOrNull ?? works.first;
      await _openWork(target, generation, restore: true);
    } catch (error) {
      _fail(error, generation);
    }
  }

  /// Selects a work behind the barrier and records it as most recent.
  ///
  /// 记录所选作品为最近使用项；切换失败时保留原作品与正文并返回 false。
  Future<bool> selectWork(WorkspaceWork work) => _barrier(() async {
    await _openWork(work, ++_generation, restore: true);
  });

  Future<void> _openWork(
    WorkspaceWork work,
    int generation, {
    required bool restore,
  }) async {
    final chapters = await repository.listChapters(work.id);
    final archived = await repository.listArchivedChapters(work.id);
    final prefs = restore ? await _loadPrefs(work.id) : null;
    if (!_active(generation)) return;
    final preferred = chapters
        .where((c) => c.id == prefs?.chapterId)
        .firstOrNull;
    final chapter = preferred ?? chapters.firstOrNull;
    // Publish the directory before the body load so navigation can observe
    // the new chapter list during the load await. A load failure rolls the
    // directory back to the previous work.
    final previousWork = _currentWork;
    final previousChapter = _currentChapter;
    final previousChapters = _chapters;
    final previousArchived = _archived;
    final previousPhase = _phase;
    _currentWork = work;
    _chapters = List.unmodifiable(chapters);
    _archived = List.unmodifiable(archived);
    _phase = WorkspacePhase.content;
    notifyListeners();
    ChapterDocument? loaded;
    try {
      loaded = chapter == null
          ? null
          : await repository.loadDocument(work.id, chapter.id);
      await discussions?.open(work.id, chapter?.id);
    } catch (_) {
      _currentWork = previousWork;
      _currentChapter = previousChapter;
      _chapters = previousChapters;
      _archived = previousArchived;
      _phase = previousPhase;
      rethrow;
    }
    if (!_active(generation)) return;
    await repository.selectWork(work.id);
    if (!_active(generation)) return;
    if (chapter == null && editing.hasOpenChapter) editing.release();
    _currentChapter = chapter;
    _wide = prefs?.wide ?? false;
    _scrollTop = preferred == null ? 0 : prefs?.scrollTop ?? 0;
    _applyScrollPending = chapter != null;
    if (loaded != null) {
      _discussionBody = loaded.body;
      editing.adopt(loaded);
    }
    notifyListeners();
  }

  /// Switches chapters behind the barrier; the previous text is flushed first.
  ///
  /// 切换前先 flush 当前正文；章节切换同样递增 generation，过期的加载结果不再应用。
  Future<bool> selectChapter(WorkspaceChapter chapter) => _barrier(() async {
    final work = _currentWork;
    if (work == null) return;
    await _openChapter(chapter, ++_generation);
    _markPrefsDirty();
  });

  Future<void> _openChapter(WorkspaceChapter chapter, int generation) async {
    final loaded = await repository.loadDocument(_currentWork!.id, chapter.id);
    await discussions?.open(_currentWork!.id, chapter.id);
    if (!_active(generation)) return;
    _discussionBody = loaded.body;
    editing.adopt(loaded);
    _currentChapter = chapter;
    _scrollTop = 0;
    _applyScrollPending = false;
    _phase = WorkspacePhase.content;
    notifyListeners();
  }

  void _clearSelection() {
    _chapters = const [];
    _archived = const [];
    _currentWork = null;
    _clearChapterOnly();
  }

  void _clearChapterOnly() {
    _currentChapter = null;
  }

  // ------------------------------------------------------------------
  // Directory mutations
  // ------------------------------------------------------------------

  /// Creates a work and opens it.
  ///
  /// 创建成功后立即在屏障内打开新作品；标题原样传给仓库，不做语言或空白归一化。
  Future<bool> createWork(String title) => _barrier(() async {
    final work = await repository.createWork(title);
    final generation = ++_generation;
    final works = await repository.listWorks();
    if (!_active(generation)) return;
    _works = List.unmodifiable(works);
    await _openWork(work, generation, restore: false);
  });

  /// Creates a chapter at the directory end and opens it.
  ///
  /// 新章节追加在目录末尾并立即打开，随后标记偏好待写入。
  Future<bool> createChapter(String title) => _barrier(() async {
    final work = _currentWork;
    if (work == null) return;
    final chapter = await repository.createChapter(work.id, title);
    await _reloadChapters(work.id);
    await _openChapter(chapter, ++_generation);
    _markPrefsDirty();
  });

  /// Renames a chapter; the version tree is untouched.
  ///
  /// 只修改章节标题元数据，不触碰工作副本与版本树。
  Future<bool> renameChapter(WorkspaceChapter chapter, String title) =>
      _barrier(() async {
        await repository.renameChapter(_currentWork!.id, chapter.id, title);
        await _reloadChapters(_currentWork!.id);
      });

  /// Reorders exactly the non-archived chapter ids; archived chapters keep
  /// their absolute positions on the server.
  ///
  /// orderedIds 必须恰好覆盖全部未归档章节 id；归档章节的绝对位置由仓库保持。
  Future<bool> reorderChapters(List<String> orderedIds) => _barrier(() async {
    await repository.reorderChapters(_currentWork!.id, orderedIds);
    await _reloadChapters(_currentWork!.id);
  });

  /// Archives or restores a chapter. Archiving the open chapter moves to the
  /// first remaining active chapter after the flush succeeded.
  ///
  /// 屏障先 flush 正文再归档或恢复；归档的若是当前章节，则切到第一篇剩余章节或释放编辑会话。
  Future<bool> setChapterArchived(WorkspaceChapter chapter, bool archived) =>
      _barrier(() async {
        final work = _currentWork!;
        await repository.setChapterArchived(work.id, chapter.id, archived);
        await _reloadChapters(work.id);
        if (archived && _currentChapter?.id == chapter.id) {
          if (_chapters.isEmpty) {
            _clearChapterOnly();
            editing.release();
          } else {
            await _openChapter(_chapters.first, ++_generation);
          }
          _markPrefsDirty();
        }
      });

  Future<void> _reloadChapters(String workId) async {
    final chapters = await repository.listChapters(workId);
    final archived = await repository.listArchivedChapters(workId);
    if (_disposed) return;
    _chapters = List.unmodifiable(chapters);
    _archived = List.unmodifiable(archived);
    final current = _currentChapter;
    if (current != null) {
      _currentChapter =
          chapters.where((c) => c.id == current.id).firstOrNull ?? current;
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Confirmation and rollback
  // ------------------------------------------------------------------

  /// Flushes and prepares the exact-body review for the confirmation dialog.
  ///
  /// 返回 null 表示 flush 失败；成功时返回绑定正文、head 与修订号的复核载荷。
  Future<PreparedConfirmation?> prepareConfirmation() async {
    PreparedConfirmation? prepared;
    final ok = await _barrier(() async {
      prepared = await editing.prepareConfirmation();
    });
    return ok ? prepared : null;
  }

  /// Confirms exactly the reviewed token; the draft is kept and rebased.
  ///
  /// 复核令牌只对 prepare 时提交的正文与版本有效；令牌过期以稳定错误码失败，确认成功后重新加载目录。
  Future<bool> confirmChapter(String reviewToken) => _barrier(() async {
    await editing.confirm(reviewToken);
    await _reloadChapters(_currentWork!.id);
  });

  /// Rolls back to an existing version; the working copy is discarded.
  ///
  /// 回滚丢弃当前工作副本并替换为历史版本正文；flush 失败时不执行回滚。
  Future<bool> rollbackChapter(String versionId) => _barrier(() async {
    await editing.rollback(versionId);
    await _reloadChapters(_currentWork!.id);
  });

  /// Lists confirmed versions of the open chapter for preview.
  ///
  /// 只读查询已确认版本，不触发 flush 或写库；没有打开章节时返回空列表。
  Future<List<VersionEntry>> listVersions() {
    final work = _currentWork;
    final chapter = _currentChapter;
    if (work == null || chapter == null) return Future.value(const []);
    return repository.listVersions(work.id, chapter.id);
  }

  /// Retries the retained draft with the same CAS revision. Never flushes
  /// first: the barrier itself would re-throw the stored failure.
  ///
  /// 用同一 CAS 修订重试当前打开章节的保留草稿；屏障不先 flush，避免再次抛出同一失败。
  Future<bool> retrySave() => _barrier(() => editing.retrySave(), flush: false);

  /// 释放原生订阅、讨论注册表与编辑会话；脏槽位不会静默丢弃，调试构建会输出告警。
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_companionEvents?.cancel());
    unawaited(_learningErrors?.cancel());
    _generation++;
    _prefsTimer?.cancel();
    editing.removeListener(_mapDiscussionBody);
    discussions?.dispose();
    try {
      editing.dispose();
    } on StateError {
      // A dirty slot must never be dropped silently, but a stuck dispose must
      // not skip releasing listeners and native resources either (teardown,
      // hot reload). The retained dirty text stays visible in loadedStates.
      assert(() {
        debugPrint('workspace_disposed_with_dirty_text');
        return true;
      }());
    }
    super.dispose();
  }
}
