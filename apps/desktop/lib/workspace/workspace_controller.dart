import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'data/workspace_repository.dart';
import 'editing_session.dart';

part 'workspace_state.dart';

/// Loading and error are explicit even when previous metadata remains visible.
enum WorkspacePhase { loading, empty, content, error }

/// Coordinates works, chapters, editing and preferences behind one busy
/// barrier: a failed flush keeps the current identity, text and revision in
/// place, and retry/export stay reachable. Newer user intent wins races.
final class WorkspaceController extends _WorkspaceState {
  WorkspaceController(super.repository, {super.editingSession});

  bool _active(int generation) => !_disposed && generation == _generation;

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
  Future<void> refresh() async {
    await _barrier(() => _refresh(seed: false));
  }

  /// Creates an explicit synthetic fixture through the injected repository.
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
    if (loaded != null) editing.adopt(loaded);
    notifyListeners();
  }

  /// Switches chapters behind the barrier; the previous text is flushed first.
  Future<bool> selectChapter(WorkspaceChapter chapter) => _barrier(() async {
    final work = _currentWork;
    if (work == null) return;
    await _openChapter(chapter, ++_generation);
    _markPrefsDirty();
  });

  Future<void> _openChapter(WorkspaceChapter chapter, int generation) async {
    await editing.open(_currentWork!.id, chapter);
    if (!_active(generation)) return;
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
  Future<bool> createWork(String title) => _barrier(() async {
    final work = await repository.createWork(title);
    final generation = ++_generation;
    final works = await repository.listWorks();
    if (!_active(generation)) return;
    _works = List.unmodifiable(works);
    await _openWork(work, generation, restore: false);
  });

  /// Creates a chapter at the directory end and opens it.
  Future<bool> createChapter(String title) => _barrier(() async {
    final work = _currentWork;
    if (work == null) return;
    final chapter = await repository.createChapter(work.id, title);
    await _reloadChapters(work.id);
    await _openChapter(chapter, ++_generation);
    _markPrefsDirty();
  });

  /// Renames a chapter; the version tree is untouched.
  Future<bool> renameChapter(WorkspaceChapter chapter, String title) =>
      _barrier(() async {
        await repository.renameChapter(_currentWork!.id, chapter.id, title);
        await _reloadChapters(_currentWork!.id);
      });

  /// Reorders exactly the non-archived chapter ids; archived chapters keep
  /// their absolute positions on the server.
  Future<bool> reorderChapters(List<String> orderedIds) => _barrier(() async {
    await repository.reorderChapters(_currentWork!.id, orderedIds);
    await _reloadChapters(_currentWork!.id);
  });

  /// Archives or restores a chapter. Archiving the open chapter moves to the
  /// first remaining active chapter after the flush succeeded.
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
  Future<PreparedConfirmation?> prepareConfirmation() async {
    PreparedConfirmation? prepared;
    final ok = await _barrier(() async {
      prepared = await editing.prepareConfirmation();
    });
    return ok ? prepared : null;
  }

  /// Confirms exactly the reviewed token; the draft is kept and rebased.
  Future<bool> confirmChapter(String reviewToken) => _barrier(() async {
    await editing.confirm(reviewToken);
    await _reloadChapters(_currentWork!.id);
  });

  /// Rolls back to an existing version; the working copy is discarded.
  Future<bool> rollbackChapter(String versionId) => _barrier(() async {
    await editing.rollback(versionId);
    await _reloadChapters(_currentWork!.id);
  });

  /// Lists confirmed versions of the open chapter for preview.
  Future<List<VersionEntry>> listVersions() {
    final work = _currentWork;
    final chapter = _currentChapter;
    if (work == null || chapter == null) return Future.value(const []);
    return repository.listVersions(work.id, chapter.id);
  }

  /// Retries the retained draft with the same CAS revision. Never flushes
  /// first: the barrier itself would re-throw the stored failure.
  Future<bool> retrySave() => _barrier(() => editing.retrySave(), flush: false);

  // ------------------------------------------------------------------
  // Preferences (per-work UI session)
  // ------------------------------------------------------------------

  // ------------------------------------------------------------------
  // Close barrier
  // ------------------------------------------------------------------

  /// Two-phase close: flush text and preferences, then release the repository.
  /// Failure keeps the window open; the draft stays in memory for export.
  Future<bool> closeBarrier() =>
      _closeFlight ??= Future<bool>.microtask(_closeBarrier);

  Future<bool> _closeBarrier() async {
    try {
      while (_busy) {
        await _idle!.future;
      }
      if (_closed) return true;
      return await _barrier(() async {
        await repository.close();
        _closed = true;
      });
    } finally {
      _closeFlight = null;
    }
  }

  /// Runs recovery with a stable memory snapshot, including its exit decision.
  Future<bool> recoveryBarrier(Future<void> Function() action) =>
      _barrier(action, flush: false);

  /// Releases repository resources once. Not a persistence barrier: callers
  /// closing the window must go through [closeBarrier] instead.
  Future<void> close() async {
    _prefsTimer?.cancel();
    if (!_disposed) dispose();
    await repository.close();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _prefsTimer?.cancel();
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
