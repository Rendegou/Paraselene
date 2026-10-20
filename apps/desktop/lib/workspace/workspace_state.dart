// workspace_controller 的 part：持有工作区可变状态，并提供偏好防抖持久化与目录只读刷新。
// 读边界：状态与偏好只经 WorkspaceRepository 读写；正文由 EditingSession 独占，本文件不直接改写作者正文。
// 写边界：偏好先改内存再按 350 毫秒防抖写库，失败只产生提示码并保持 dirty。
// 关键不变量：dispose 之后不再发出通知；关闭或输入锁定后拒绝新的偏好写入；偏好写库失败只产生提示并保持 dirty。
part of 'workspace_controller.dart';

abstract class _WorkspaceState extends ChangeNotifier {
  /// 在持锁屏障内执行动作；实现类负责先 flush 正文与偏好，失败时返回 false。
  Future<bool> persistenceBarrier(Future<void> Function() action);
  _WorkspaceState(this.repository, {EditingSession? editingSession})
    : editing = editingSession ?? EditingSession(repository);

  Completer<void>? _idle;
  Future<bool>? _closeFlight;
  Future<void>? _prefsFlight;
  bool _closed = false;

  final WorkspaceRepository repository;
  final EditingSession editing;
  StreamSubscription<String?>? _learningErrors;
  StreamSubscription<CompanionOutcome>? _companionEvents;
  String? learningFailure;
  String? companionFailure;

  void _listenNative(CompanionService companion, LearningService learning) {
    _learningErrors = learning.errors.listen((error) {
      learningFailure = error;
      if (!_disposed) notifyListeners();
    });
    _companionEvents = companion.events.listen((outcome) {
      companionFailure = outcome.errorCode;
      if (!_disposed) notifyListeners();
    });
  }

  /// Optional native discussion capability, sharing this workspace's writer.
  DiscussionRegistry? discussions;

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

  /// 当前工作区的加载阶段；切换作品或章节期间为 loading。
  WorkspacePhase get phase => _phase;

  /// 仓库模式：真实原生桥接或内存合成演示。
  WorkspaceMode get mode => repository.mode;

  /// 当前作品目录的只读快照。
  List<WorkspaceWork> get works => _works;

  /// Refreshes only catalog rows after a legacy conversion; keeps the editor.
  ///
  /// 转换旧数据后只刷新目录行，不重建当前打开的章节与正文。
  Future<void> refreshDirectory() async {
    await persistenceBarrier(() async {
      final rows = await repository.listWorks();
      if (_disposed) return;
      _works = List.unmodifiable(rows);
      notifyListeners();
    });
  }

  /// 当前作品的未归档章节，按显示顺序排列。
  List<WorkspaceChapter> get chapters => _chapters;

  /// 当前作品的归档章节；重排不改变它们的绝对位置。
  List<WorkspaceChapter> get archivedChapters => _archived;

  /// 当前选中的作品；空目录或加载失败时为 null。
  WorkspaceWork? get currentWork => _currentWork;

  /// 当前打开的章节；作品尚未创建章节时为 null。
  WorkspaceChapter? get currentChapter => _currentChapter;

  /// Exact text of the open chapter; owned by the editing session.
  ///
  /// 正文以 EditingSession 的内存副本为准，可能比最近一次成功保存更新。
  String get body => editing.body;

  /// 最近一次屏障失败的稳定错误码；新请求开始时清空。
  String? get errorCode => _errorCode;

  /// Non-blocking notice code (e.g. `recent_works_damaged`).
  ///
  /// 提示码不阻断操作，例如最近作品损坏或 UI 会话 JSON 非法。
  String? get noticeCode => _noticeCode;

  /// A barrier is running; navigation and window close must wait or retry.
  ///
  /// 屏障运行、已经关闭或仍处于首次加载时为 true。
  bool get isBusy => _busy || _closed || _phase == WorkspacePhase.loading;

  /// Wide-manuscript preference, restored from the per-work UI session.
  ///
  /// 宽栏偏好按作品保存；写入经防抖合并。
  bool get wide => _wide;

  /// Restored scroll position; applied once by the editor after layout.
  ///
  /// 目录切换或会话恢复时记录的滚动偏移，由编辑器在布局完成后应用一次。
  double get pendingScrollTop => _scrollTop;

  /// True once per chapter open until the editor applied the restored offset.
  ///
  /// 每个章节打开后置真，编辑器应用恢复偏移后清除。
  bool get applyScrollPending => _applyScrollPending;

  /// Seals the verified recovery snapshot until the platform exits. Call only
  /// inside recoveryBarrier after the user explicitly accepts exported exit.
  ///
  /// 仅在 recoveryBarrier 内、用户明确选择导出后退出时调用；调用后拒绝新输入并停止偏好定时器。
  void acceptRecoveryExit() {
    _closed = true;
    editing.inputLocked = true;
    _prefsTimer?.cancel();
  }

  /// Records the wide-manuscript preference and schedules persistence.
  ///
  /// 关闭、输入锁定或值未变时忽略；变更后调度防抖写库并通知界面。
  void setWide(bool wide) {
    if (_disposed || _closed || editing.inputLocked || _wide == wide) return;
    _wide = wide;
    _markPrefsDirty();
    notifyListeners();
  }

  /// Records the live scroll offset (fractional, clamped by the backend).
  ///
  /// 非有限值、未打开章节或输入锁定时忽略；偏移不做取整，由仓库钳制。
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
  ///
  /// 只清除待应用标记，不改变已记录的滚动值。
  void markScrollApplied() {
    _applyScrollPending = false;
  }

  // 连续拖动只落一次库；写库失败时 dirty 保持为真，由下一个屏障重试。
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

  // 循环 flush 到所有槽位干净为止，避免 flush 期间产生的新编辑被漏掉。
  Future<void> _drain() async {
    do {
      await editing.flushAll();
      await discussions?.flush();
      await _flushPrefs();
    } while (editing.loadedStates.any((state) => state.dirty) ||
        (discussions?.dirty ?? false) ||
        (_prefsDirty && _currentWork != null));
    editing.inputLocked = true;
  }

  // 损坏的会话 JSON 只记提示码并回退默认偏好，不阻断启动。
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
