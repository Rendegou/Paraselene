import 'dart:convert';
import 'demo_content.dart';
import 'workspace_repository.dart';
part 'synthetic_confirmation.dart';

/// Explicit in-memory fixture. Hashes and persistence require the real bridge.
class SyntheticWorkspaceRepository implements WorkspaceRepository {
  SyntheticWorkspaceRepository({bool withDemo = false}) {
    if (withDemo) _addDemo();
  }
  final _works = <String, WorkspaceWork>{};
  final _chapters = <String, WorkspaceChapter>{};
  final _owners = <String, String>{};
  final _documents = <String, ChapterDocument>{};
  final _versions = <String, List<VersionEntry>>{};
  final _ui = <String, String>{};
  final _recent = <String>[];
  String? _selected;
  int _id = 0;
  bool _closed = false;
  @override
  WorkspaceMode get mode => WorkspaceMode.synthetic;
  void _checkOpen() {
    if (_closed) throw const WorkspaceFailure('session_closed');
  }

  WorkspaceWork _work(String id) {
    _checkOpen();
    return _works[id] ?? (throw const WorkspaceFailure('work_not_found'));
  }

  WorkspaceChapter _chapter(String work, String id) {
    _work(work);
    final chapter = _chapters[id];
    if (chapter == null) throw const WorkspaceFailure('document_not_found');
    if (_owners[id] != work) throw const WorkspaceFailure('identity_mismatch');
    return chapter;
  }

  String _title(String title) {
    if (title.trim().isEmpty) throw const WorkspaceFailure('invalid_input');
    return title.trim();
  }

  @override
  Future<List<WorkspaceWork>> listWorks() async {
    _checkOpen();
    return List.unmodifiable(_works.values);
  }

  @override
  Future<WorkspaceWork> createWork(String title) async {
    _checkOpen();
    final work = WorkspaceWork(id: 'work-${++_id}', title: _title(title));
    _works[work.id] = work;
    return work;
  }

  @override
  Future<WorkspaceWork> selectWork(String workId) async {
    final work = _work(workId);
    _selected = workId;
    _recent.remove(workId);
    _recent.insert(0, workId);
    if (_recent.length > 10) _recent.removeLast();
    return work;
  }

  @override
  Future<WorkspaceState> workspaceState() async {
    _checkOpen();
    return WorkspaceState(
      selectedWorkId: _selected,
      recentWorks: List.unmodifiable(_recent.map((id) => _works[id]!)),
    );
  }

  List<WorkspaceChapter> _directory(String workId, bool archived) {
    _work(workId);
    final result =
        _chapters.values
            .where((c) => _owners[c.id] == workId && c.archived == archived)
            .toList()
          ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return List.unmodifiable(result);
  }

  @override
  Future<List<WorkspaceChapter>> listChapters(String workId) async =>
      _directory(workId, false);
  @override
  Future<List<WorkspaceChapter>> listArchivedChapters(String workId) async =>
      _directory(workId, true);
  @override
  Future<WorkspaceChapter> createChapter(String workId, String title) async {
    _work(workId);
    final chapter = WorkspaceChapter(
      id: 'chapter-${++_id}',
      title: _title(title),
      orderIndex: _owners.values.where((v) => v == workId).length,
    );
    _chapters[chapter.id] = chapter;
    _owners[chapter.id] = workId;
    _documents[chapter.id] = ChapterDocument(
      workId: workId,
      documentId: chapter.id,
      body: '',
    );
    _versions[chapter.id] = [];
    return chapter;
  }

  WorkspaceChapter _replace(
    WorkspaceChapter c, {
    String? title,
    int? order,
    bool? archived,
    String? head,
    bool replaceHead = false,
  }) {
    return _chapters[c.id] = WorkspaceChapter(
      id: c.id,
      title: title ?? c.title,
      orderIndex: order ?? c.orderIndex,
      archived: archived ?? c.archived,
      headVersionId: replaceHead ? head : c.headVersionId,
    );
  }

  @override
  Future<WorkspaceChapter> renameChapter(
    String workId,
    String chapterId,
    String title,
  ) async => _replace(_chapter(workId, chapterId), title: _title(title));
  @override
  Future<void> reorderChapters(String workId, List<String> orderedIds) async {
    final active = _directory(workId, false);
    if (orderedIds.length != active.length ||
        orderedIds.toSet().length != active.length ||
        !active.every((c) => orderedIds.contains(c.id))) {
      throw const WorkspaceFailure('invalid_input');
    }
    for (var i = 0; i < orderedIds.length; i++) {
      _replace(_chapters[orderedIds[i]]!, order: active[i].orderIndex);
    }
  }

  @override
  Future<WorkspaceChapter> setChapterArchived(
    String workId,
    String chapterId,
    bool archived,
  ) async => _replace(_chapter(workId, chapterId), archived: archived);
  @override
  Future<ChapterDocument> loadDocument(String workId, String chapterId) async {
    _chapter(workId, chapterId);
    return _documents[chapterId]!;
  }

  @override
  Future<String> loadBody(String workId, String chapterId) async =>
      (await loadDocument(workId, chapterId)).body;
  void _cas(ChapterDocument d, int? revision) {
    if (d.revision != revision) {
      throw const WorkspaceFailure('revision_conflict');
    }
  }

  @override
  Future<ChapterDocument> saveDocument(
    String workId,
    String chapterId,
    int? expectedRevision,
    String body,
  ) async {
    _chapter(workId, chapterId);
    final d = _documents[chapterId]!;
    _cas(d, expectedRevision);
    return _documents[chapterId] = ChapterDocument(
      workId: workId,
      documentId: chapterId,
      body: body,
      revision: (d.revision ?? 0) + 1,
      baseHeadVersion: d.baseHeadVersion,
      headVersionId: d.headVersionId,
    );
  }

  @override
  Future<void> discardDraft(
    String workId,
    String chapterId,
    int? expectedRevision,
  ) async {
    _chapter(workId, chapterId);
    final d = _documents[chapterId]!;
    _cas(d, expectedRevision);
    _restore(workId, chapterId, d.headVersionId);
  }

  @override
  Future<List<VersionEntry>> listVersions(
    String workId,
    String chapterId,
  ) async {
    final chapter = _chapter(workId, chapterId);
    return List.unmodifiable(
      _versions[chapterId]!.map(
        (v) => VersionEntry(
          id: v.id,
          documentId: v.documentId,
          body: v.body,
          origin: v.origin,
          createdAt: v.createdAt,
          parentVersionId: v.parentVersionId,
          isHead: v.id == chapter.headVersionId,
        ),
      ),
    );
  }

  void _head(ChapterDocument d, String? expectedHead) {
    if (d.headVersionId != expectedHead) {
      throw const WorkspaceFailure('head_conflict');
    }
  }

  @override
  Future<PreparedConfirmation> prepareConfirmation(
    String workId,
    String chapterId,
    String? expectedHead,
    int expectedRevision,
  ) async => _prepareReview(workId, chapterId, expectedHead, expectedRevision);
  @override
  Future<WorkspaceChapter> confirmChapter(
    String workId,
    String chapterId,
    String reviewToken,
  ) async {
    final d = _checkedReview(workId, chapterId, reviewToken);
    final expectedHead = d.headVersionId;
    if (d.body.trim().isEmpty) throw const WorkspaceFailure('invalid_input');
    final version = VersionEntry(
      id: 'version-${++_id}',
      documentId: chapterId,
      body: d.body,
      origin: 'author',
      createdAt: DateTime.now().toUtc().toIso8601String(),
      isHead: true,
      parentVersionId: expectedHead,
    );
    _versions[chapterId]!.insert(0, version);
    _replace(_chapters[chapterId]!, head: version.id, replaceHead: true);
    _documents[chapterId] = ChapterDocument(
      workId: workId,
      documentId: chapterId,
      body: d.body,
      revision: d.revision! + 1,
      baseHeadVersion: version.id,
      headVersionId: version.id,
    );
    return _chapters[chapterId]!;
  }

  void _restore(String workId, String chapterId, String? versionId) {
    final body = versionId == null
        ? ''
        : _versions[chapterId]!.firstWhere((v) => v.id == versionId).body;
    _replace(_chapters[chapterId]!, head: versionId, replaceHead: true);
    _documents[chapterId] = ChapterDocument(
      workId: workId,
      documentId: chapterId,
      body: body,
      baseHeadVersion: versionId,
      headVersionId: versionId,
    );
  }

  @override
  Future<WorkspaceChapter> rollbackChapter(
    String workId,
    String chapterId,
    String versionId,
    String? expectedHead,
    int? expectedRevision,
  ) async {
    _chapter(workId, chapterId);
    final d = _documents[chapterId]!;
    _head(d, expectedHead);
    _cas(d, expectedRevision);
    if (!_versions[chapterId]!.any((v) => v.id == versionId)) {
      throw const WorkspaceFailure('not_found');
    }
    _restore(workId, chapterId, versionId);
    return _chapters[chapterId]!;
  }

  @override
  Future<String?> getUiSession(String workId) async {
    _work(workId);
    return _ui[workId];
  }

  @override
  Future<void> setUiSession(String workId, String value) async {
    _work(workId);
    try {
      final json = jsonDecode(value);
      if (utf8.encode(value).length > 65536 ||
          json is! Map<String, dynamic> ||
          json['schemaVersion'] != 1 ||
          json.keys.any(
            (k) => ![
              'schemaVersion',
              'chapterId',
              'wide',
              'scrollTop',
            ].contains(k),
          )) {
        throw const FormatException();
      }
      final scroll = json['scrollTop'];
      if ((json.containsKey('chapterId') && json['chapterId'] is! String) ||
          (json.containsKey('wide') && json['wide'] is! bool) ||
          (json.containsKey('scrollTop') &&
              (scroll is! num ||
                  !scroll.isFinite ||
                  scroll < 0 ||
                  scroll > 10000000))) {
        throw const FormatException();
      }
    } on FormatException {
      throw const WorkspaceFailure('invalid_input');
    }
    _ui[workId] = value;
  }

  void _addDemo() {
    const work = WorkspaceWork(id: 'demo-work', title: '雨后的书店');
    const chapter = WorkspaceChapter(id: 'demo-chapter', title: '第一章 · 归途');
    _works[work.id] = work;
    _chapters[chapter.id] = chapter;
    _owners[chapter.id] = work.id;
    _documents[chapter.id] = const ChapterDocument(
      workId: 'demo-work',
      documentId: 'demo-chapter',
      body: demoBody,
      revision: 1,
    );
    _versions[chapter.id] = [];
  }

  @override
  Future<void> seedDemo() async {
    _checkOpen();
    if (!_works.containsKey('demo-work')) _addDemo();
  }

  @override
  Future<void> close() async => _closed = true;
}
