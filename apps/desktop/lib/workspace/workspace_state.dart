part of 'workspace_controller.dart';

abstract class _WorkspaceState extends ChangeNotifier {
  _WorkspaceState(this.repository, {EditingSession? editingSession})
    : editing = editingSession ?? EditingSession(repository);

  Completer<void>? _idle;
  Future<bool>? _closeFlight;
  Future<void>? _prefsFlight;
  bool _closed = false;

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
  bool get isBusy => _busy || _closed || _phase == WorkspacePhase.loading;

  /// Wide-manuscript preference, restored from the per-work UI session.
  bool get wide => _wide;

  /// Restored scroll position; applied once by the editor after layout.
  double get pendingScrollTop => _scrollTop;

  /// True once per chapter open until the editor applied the restored offset.
  bool get applyScrollPending => _applyScrollPending;

  /// Seals the verified recovery snapshot until the platform exits. Call only
  /// inside recoveryBarrier after the user explicitly accepts exported exit.
  void acceptRecoveryExit() {
    _closed = true;
    editing.inputLocked = true;
    _prefsTimer?.cancel();
  }

  /// Records the wide-manuscript preference and schedules persistence.
  void setWide(bool wide) {
    if (_disposed || _closed || editing.inputLocked || _wide == wide) return;
    _wide = wide;
    _markPrefsDirty();
    notifyListeners();
  }

  /// Records the live scroll offset (fractional, clamped by the backend).
  void noteScrollTop(double offset) {
    if (_disposed ||
        _closed ||
        editing.inputLocked ||
        _currentChapter == null ||
        !offset.isFinite) {
      return;
    }
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

  Future<void> _flushPrefs() {
    if ((!_prefsDirty || _currentWork == null || _disposed) &&
        _prefsFlight == null) {
      return Future.value();
    }
    return _prefsFlight ??= Future<void>.microtask(_writePrefs);
  }

  Future<void> _writePrefs() async {
    try {
      while (_prefsDirty && !_disposed && _currentWork != null) {
        _prefsTimer?.cancel();
        _prefsTimer = null;
        final work = _currentWork!;
        final version = _prefsVersion;
        final value = jsonEncode({
          'schemaVersion': 1,
          if (_currentChapter != null) 'chapterId': _currentChapter!.id,
          'wide': _wide,
          'scrollTop': _scrollTop,
        });
        await repository.setUiSession(work.id, value);
        if (version == _prefsVersion) _prefsDirty = false;
      }
    } finally {
      _prefsFlight = null;
    }
  }

  Future<void> _drain() async {
    do {
      await editing.flushAll();
      await _flushPrefs();
    } while (editing.loadedStates.any((state) => state.dirty) ||
        (_prefsDirty && _currentWork != null));
    editing.inputLocked = true;
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
