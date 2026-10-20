// 内存合成工作区仓库：为演示与组件测试实现 WorkspaceRepository，不访问文件、数据库或 FFI。
// 读边界：目录、正文、版本与 UI 会话都保存在进程内映射中，进程退出即丢失。
// 写边界：保存、确认、回滚等变更只改内存；哈希、持久化与真实事务语义必须由原生桥接保证，本实现不冒充。
// 关键不变量：关闭后所有调用抛 session_closed；CAS 修订与版本头冲突使用与真实仓库相同的稳定错误码。
import 'dart:convert';
import 'demo_content.dart';
import 'workspace_repository.dart';
part 'synthetic_confirmation.dart';

/// Explicit in-memory fixture. Hashes and persistence require the real bridge.
///
/// 显式内存夹具：哈希与持久化需要真实桥接，本实现只用于演示与测试。
class SyntheticWorkspaceRepository implements WorkspaceRepository {
  /// 创建空仓库；withDemo 为真时同时写入内置演示作品与章节。
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

  /// 合成模式；界面据此显示演示提示。
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

  /// 列出内存中的作品；返回不可变快照。
  @override
  Future<List<WorkspaceWork>> listWorks() async {
    _checkOpen();
    return List.unmodifiable(_works.values);
  }

  /// 创建作品；标题去除首尾空白，空标题抛 invalid_input。
  @override
  Future<WorkspaceWork> createWork(String title) async {
    _checkOpen();
    final work = WorkspaceWork(id: 'work-${++_id}', title: _title(title));
    _works[work.id] = work;
    return work;
  }

  /// 记录最近使用作品，最多保留 10 条；未知作品抛 work_not_found。
  @override
  Future<WorkspaceWork> selectWork(String workId) async {
    final work = _work(workId);
    _selected = workId;
    _recent.remove(workId);
    _recent.insert(0, workId);
    if (_recent.length > 10) _recent.removeLast();
    return work;
  }

  /// 返回内存中的选中作品与最近作品列表，不产生警告码。
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

  /// 列出未归档章节，按 orderIndex 升序返回。
  @override
  Future<List<WorkspaceChapter>> listChapters(String workId) async =>
      _directory(workId, false);

  /// 列出归档章节，按 orderIndex 升序返回。
  @override
  Future<List<WorkspaceChapter>> listArchivedChapters(String workId) async =>
      _directory(workId, true);

  /// 在目录末尾创建章节；标题去除首尾空白，空标题抛 invalid_input。
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

  // 元数据以整体替换发布，避免版本头或顺序出现半更新状态。
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

  /// 只改标题元数据；版本树保持不变。
  @override
  Future<WorkspaceChapter> renameChapter(
    String workId,
    String chapterId,
    String title,
  ) async => _replace(_chapter(workId, chapterId), title: _title(title));

  /// orderedIds 必须与未归档章节 id 集合完全一致，否则抛 invalid_input；归档章节位置不变。
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

  /// 归档或恢复章节，不删除正文与已确认版本。
  @override
  Future<WorkspaceChapter> setChapterArchived(
    String workId,
    String chapterId,
    bool archived,
  ) async => _replace(_chapter(workId, chapterId), archived: archived);

  /// 读取内存中的文档快照；未知章节或身份不匹配抛稳定码。
  @override
  Future<ChapterDocument> loadDocument(String workId, String chapterId) async {
    _chapter(workId, chapterId);
    return _documents[chapterId]!;
  }

  /// 读取章节精确正文。
  @override
  Future<String> loadBody(String workId, String chapterId) async =>
      (await loadDocument(workId, chapterId)).body;
  void _cas(ChapterDocument d, int? revision) {
    if (d.revision != revision) {
      throw const WorkspaceFailure('revision_conflict');
    }
  }

  /// 以 expectedRevision 做 CAS 保存并递增修订号；冲突抛 revision_conflict。
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

  /// 以 CAS 丢弃工作副本并恢复到当前头版本；无头版本时正文为空。
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

  /// 列出已确认版本，isHead 由当前章节头动态计算。
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

  /// 生成内存复核令牌；不写版本，head 或修订不匹配时抛稳定冲突码。
  @override
  Future<PreparedConfirmation> prepareConfirmation(
    String workId,
    String chapterId,
    String? expectedHead,
    int expectedRevision,
  ) async => _prepareReview(workId, chapterId, expectedHead, expectedRevision);

  /// 用令牌把正文确认为新版本；空正文抛 invalid_input，令牌漂移抛稳定冲突码。
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

  /// 回滚到指定历史版本；head 或修订不匹配、版本不存在时抛稳定错误码。
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

  /// 读取作品的内存 UI 会话 JSON；未知作品抛 work_not_found。
  @override
  Future<String?> getUiSession(String workId) async {
    _work(workId);
    return _ui[workId];
  }

  /// 写入 UI 会话 JSON；只接受 schemaVersion 1 与白名单键，超长或非法抛 invalid_input。
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

  /// 幂等写入内置演示作品与章节；已存在时不做任何事。
  @override
  Future<void> seedDemo() async {
    _checkOpen();
    if (!_works.containsKey('demo-work')) _addDemo();
  }

  /// 标记仓库关闭；之后所有读写调用抛 session_closed。
  @override
  Future<void> close() async => _closed = true;
}
