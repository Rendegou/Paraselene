import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'data/workspace_repository.dart';
import 'editing_session.dart';

/// Loading and error are explicit even when previous metadata remains visible.
enum WorkspacePhase { loading, empty, content, error }

/// Coordinates works, chapters, editing and preferences behind one busy
/// barrier: a failed flush keeps the current identity, text and revision in
/// place, and retry/export stay reachable. Newer user intent wins races.
final class WorkspaceController extends ChangeNotifier {
  WorkspaceController(this.repository, {EditingSession? editingSession})
    : editing = editingSession ?? EditingSession(repository);

  final WorkspaceRepository repository;
  final EditingSession editing;

  WorkspacePhase _phase = WorkspacePhase.loading;
  List<WorkspaceWork> _works = const [];
  List<WorkspaceChapter> _chapters = const [];
  List<WorkspaceChapter> _archived = const [];
  WorkspaceWork? _currentWork;
  WorkspaceChapter? _currentChapter;
  String? _errorCode;
  String? _noticeCode;
  bool _busy = false;
  bool _disposed = false;
  int _generation = 0;
  bool _seedPending = false;

  bool _wide = false;
  double _scrollTop = 0;
  bool _applyScrollPending = false;
  bool _prefsDirty = false;
  int _prefsVersion = 0;
  Timer? _prefsTimer;
  static const _prefsDebounce = Duration(milliseconds: 350);

  WorkspacePhase get phase => _phase;
  WorkspaceMode get mode => repository.mode;
  List<WorkspaceWork> get works => _works;
  List<WorkspaceChapter> get chapters => _chapters;
  List<WorkspaceChapter> get archivedChapters => _archived;
  WorkspaceWork? get currentWork => _currentWork;
  WorkspaceChapter? get currentChapter => _currentChapter;

  /// Exact text of the open chapter; owned by the editing session.
  String get body => editing.body;
  String? get errorCode => _errorCode;

  /// Non-blocking notice code (e.g. `recent_works_damaged`).
  String? get noticeCode => _noticeCode;

  /// A barrier is running; navigation and window close must wait or retry.
  bool get isBusy => _busy || _phase == WorkspacePhase.loading;

  /// Wide-manuscript preference, restored from the per-work UI session.
  bool get wide => _wide;

  /// Restored scroll position; applied once by the editor after layout.
  double get pendingScrollTop => _scrollTop;

  /// True once per chapter open until the editor applied the restored offset.
  bool get applyScrollPending => _applyScrollPending;

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
    if (_disposed || _busy) return false;
    _busy = true;
    _errorCode = null;
    notifyListeners();
    try {
      if (flush) {
        await editing.flushAll();
        await _flushPrefs();
      }
      await action();
      return true;
    } catch (error) {
      _errorCode = error is WorkspaceFailure
          ? error.code
          : 'workspace_unavailable';
      return false;
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Refreshes the directory behind the barrier and selects the first work.
  Future<void> refresh() async {
    await _barrier(() => _refresh(seed: false));
  }

  /// Creates an explicit synthetic fixture through the injected repository.
  Future<void> seedDemo() => _refresh(seed: true);

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
    await repository.selectWork(work.id);
    final chapters = await repository.listChapters(work.id);
    final archived = await repository.listArchivedChapters(work.id);
    if (!_active(generation)) return;
    _currentWork = work;
    _chapters = List.unmodifiable(chapters);
    _archived = List.unmodifiable(archived);
    final prefs = restore ? await _loadPrefs(work.id) : null;
    if (!_active(generation)) return;
    if (chapters.isEmpty) {
      if (editing.hasOpenChapter) editing.release();
      _clearChapterOnly();
      _phase = WorkspacePhase.content;
      notifyListeners();
      return;
    }
    final preferred = prefs?.chapterId == null
        ? null
        : chapters.where((c) => c.id == prefs!.chapterId).firstOrNull;
    await _openChapter(preferred ?? chapters.first, generation);
    if (prefs != null && _active(generation)) {
      _wide = prefs.wide;
      _scrollTop = preferred == null ? 0 : prefs.scrollTop;
      _applyScrollPending = true;
      notifyListeners();
    }
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

  /// Records the wide-manuscript preference and schedules persistence.
  void setWide(bool wide) {
    if (_wide == wide) return;
    _wide = wide;
    _markPrefsDirty();
    notifyListeners();
  }

  /// Records the live scroll offset (fractional, clamped by the backend).
  void noteScrollTop(double offset) {
    if (_currentChapter == null || !offset.isFinite) return;
    _scrollTop = offset;
    _markPrefsDirty();
  }

  /// The editor applied the restored scroll offset after layout.
  void markScrollApplied() {
    _applyScrollPending = false;
  }

  void _markPrefsDirty() {
    _prefsDirty = true;
    _prefsVersion++;
    _prefsTimer?.cancel();
    _prefsTimer = Timer(_prefsDebounce, () => unawaited(_flushPrefsSafely()));
  }

  /// A background preference failure becomes a visible notice and stays dirty
  /// so the next barrier retries it; navigation still blocks there.
  Future<void> _flushPrefsSafely() async {
    try {
      await _flushPrefs();
    } catch (error) {
      _noticeCode = error is WorkspaceFailure ? error.code : 'prefs_failed';
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _flushPrefs() async {
    _prefsTimer?.cancel();
    _prefsTimer = null;
    if (!_prefsDirty) return;
    final work = _currentWork;
    if (work == null) return;
    final value = jsonEncode({
      'schemaVersion': 1,
      if (_currentChapter != null) 'chapterId': _currentChapter!.id,
      'wide': _wide,
      'scrollTop': _scrollTop,
    });
    // Clear dirty only when no newer preference arrived during the await:
    // a scroll event in the window must not lose its pending write.
    final version = _prefsVersion;
    await repository.setUiSession(work.id, value);
    if (version == _prefsVersion) _prefsDirty = false;
  }

  Future<_Prefs?> _loadPrefs(String workId) async {
    final raw = await repository.getUiSession(workId);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      return _Prefs(
        chapterId: json['chapterId'] is String
            ? json['chapterId'] as String
            : null,
        wide: json['wide'] == true,
        scrollTop: (json['scrollTop'] as num?)?.toDouble() ?? 0,
      );
    } on FormatException {
      _noticeCode = 'invalid_ui_session';
      return null;
    }
  }

  // ------------------------------------------------------------------
  // Close barrier
  // ------------------------------------------------------------------

  /// Two-phase close: flush text and preferences, then release the repository.
  /// Failure keeps the window open; the draft stays in memory for export.
  Future<bool> closeBarrier() => _barrier(() async {
    await repository.close();
  });

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

final class _Prefs {
  const _Prefs({this.chapterId, required this.wide, required this.scrollTop});
  final String? chapterId;
  final bool wide;
  final double scrollTop;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
