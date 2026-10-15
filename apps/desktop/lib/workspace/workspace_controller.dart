import 'package:flutter/foundation.dart';

import 'data/workspace_repository.dart';

/// Loading and error are explicit even when previous metadata remains visible.
enum WorkspacePhase { loading, empty, content, error }

/// Coordinates metadata and raw text; newer user intent wins asynchronous races.
final class WorkspaceController extends ChangeNotifier {
  WorkspaceController(this.repository);
  final WorkspaceRepository repository;
  WorkspacePhase _phase = WorkspacePhase.loading;
  List<WorkspaceWork> _works = const [];
  List<WorkspaceChapter> _chapters = const [];
  WorkspaceWork? _currentWork;
  WorkspaceChapter? _currentChapter;
  String _body = '';
  String? _errorCode;
  int _generation = 0;
  bool _disposed = false;
  Future<void>? _closing;
  bool _seedPending = false;

  WorkspacePhase get phase => _phase;
  WorkspaceMode get mode => repository.mode;
  List<WorkspaceWork> get works => _works;
  List<WorkspaceChapter> get chapters => _chapters;
  WorkspaceWork? get currentWork => _currentWork;
  WorkspaceChapter? get currentChapter => _currentChapter;
  String get body => _body;
  String? get errorCode => _errorCode;
  bool get isBusy => _phase == WorkspacePhase.loading;

  bool _active(int generation) => !_disposed && generation == _generation;

  int _begin() {
    final generation = ++_generation;
    _phase = WorkspacePhase.loading;
    _errorCode = null;
    if (!_disposed) notifyListeners();
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

  /// Refreshes the directory and selects its first work if present.
  Future<void> refresh() => _refresh(seed: false);

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
      final works = await repository.listWorks();
      if (!_active(generation)) return;
      _works = List.unmodifiable(works);
      _clearSelection();
      if (works.isEmpty) {
        _phase = WorkspacePhase.empty;
        notifyListeners();
        return;
      }
      await _loadWork(works.first, generation);
    } catch (error) {
      _fail(error, generation);
    }
  }

  void _clearSelection() {
    _chapters = const [];
    _currentWork = null;
    _currentChapter = null;
    _body = '';
  }

  /// Selects a work and loads only its first chapter body, when available.
  Future<void> selectWork(WorkspaceWork work) async {
    if (_disposed) return;
    final generation = _begin();
    _clearSelection();
    try {
      await _loadWork(work, generation);
    } catch (error) {
      _fail(error, generation);
    }
  }

  Future<void> _loadWork(WorkspaceWork work, int generation) async {
    _currentWork = work;
    final chapters = await repository.listChapters(work.id);
    if (!_active(generation)) return;
    _chapters = List.unmodifiable(chapters);
    if (chapters.isEmpty) {
      _phase = WorkspacePhase.content;
      notifyListeners();
      return;
    }
    await _loadChapter(chapters.first, work, generation);
  }

  /// Loads the selected chapter without transforming its Unicode or newlines.
  Future<void> selectChapter(WorkspaceChapter chapter) async {
    if (_disposed || _currentWork == null) return;
    final work = _currentWork!;
    final generation = _begin();
    _currentChapter = chapter;
    _body = '';
    try {
      await _loadChapter(chapter, work, generation);
    } catch (error) {
      _fail(error, generation);
    }
  }

  Future<void> _loadChapter(
    WorkspaceChapter chapter,
    WorkspaceWork work,
    int generation,
  ) async {
    _currentChapter = chapter;
    final text = await repository.loadBody(work.id, chapter.id);
    if (!_active(generation)) return;
    _body = text;
    _phase = WorkspacePhase.content;
    notifyListeners();
  }

  /// Invalidates pending UI responses and releases repository resources once.
  Future<void> close() {
    if (!_disposed) dispose();
    return _closing ??= repository.close();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
