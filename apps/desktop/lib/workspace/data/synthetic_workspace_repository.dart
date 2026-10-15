import 'demo_content.dart';
import 'workspace_repository.dart';

/// Asynchronous in-memory fixture; never claims native persistence.
class SyntheticWorkspaceRepository implements WorkspaceRepository {
  SyntheticWorkspaceRepository({bool withDemo = false}) : _seeded = withDemo;
  bool _seeded;
  bool _closed = false;
  static const _work = WorkspaceWork(id: 'demo-work', title: '雨后的书店');
  static const _chapter = WorkspaceChapter(
    id: 'demo-chapter',
    title: '第一章 · 归途',
  );
  @override
  WorkspaceMode get mode => WorkspaceMode.synthetic;

  void _checkOpen() {
    if (_closed) throw const WorkspaceFailure('session_closed');
  }

  @override
  Future<List<WorkspaceWork>> listWorks() async {
    _checkOpen();
    return List.unmodifiable(_seeded ? [_work] : <WorkspaceWork>[]);
  }

  @override
  Future<List<WorkspaceChapter>> listChapters(String workId) async {
    _checkOpen();
    if (!_seeded || workId != _work.id) {
      throw const WorkspaceFailure('work_not_found');
    }
    return List.unmodifiable([_chapter]);
  }

  @override
  Future<String> loadBody(String workId, String chapterId) async {
    await listChapters(workId);
    _checkOpen();
    if (chapterId != _chapter.id) {
      throw const WorkspaceFailure('document_not_found');
    }
    return demoBody;
  }

  @override
  Future<void> seedDemo() async {
    _checkOpen();
    _seeded = true;
  }

  @override
  Future<void> close() async => _closed = true;
}
