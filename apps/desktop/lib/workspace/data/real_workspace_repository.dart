import 'dart:io';
import '../../native/generated/api.dart';
import '../../native/generated/api/models.dart';
import '../../native/runtime.dart';
import 'demo_content.dart';
import 'workspace_repository.dart';

/// Owns a verified synthetic native session. Caller-owned roots survive close.
final class RealWorkspaceRepository implements WorkspaceRepository {
  RealWorkspaceRepository._(this._root, this._session, this._deleteRoot);
  final Directory? _root;
  final CoreSession _session;
  final bool _deleteRoot;
  Future<void>? _closing;
  bool _seeded = false;
  String? _demoWorkId;
  String? _demoChapterId;
  Future<void>? _seeding;
  @override
  WorkspaceMode get mode => WorkspaceMode.realBridge;

  /// Opens the application-owned fixed synthetic store (ADR-004): durable
  /// across processes, DPAPI-sealed for the current Windows user. No caller
  /// root exists and nothing is deleted on close.
  static Future<RealWorkspaceRepository> openOwned({
    bool diagnosticOverride = false,
  }) async {
    CoreSession? session;
    try {
      await NativeRuntime.initialize(diagnosticOverride: diagnosticOverride);
      session = await CoreSession.openOwnedSynthetic();
      await NativeRuntime.verify(session);
      return RealWorkspaceRepository._(null, session, false);
    } catch (error) {
      if (session != null) {
        await session.close();
        session.dispose();
      }
      throw _failure(error);
    }
  }

  /// Existing roots must already satisfy the native synthetic provenance guard.
  static Future<RealWorkspaceRepository> open({
    bool diagnosticOverride = false,
    Directory? syntheticRoot,
  }) async {
    Directory? root;
    CoreSession? session;
    final owned = syntheticRoot == null;
    try {
      await NativeRuntime.initialize(diagnosticOverride: diagnosticOverride);
      root =
          syntheticRoot ??
          await Directory.systemTemp.createTemp('paraselene-m1-');
      if (owned) {
        await File(
          '${root.path}/M1_SYNTHETIC_ONLY',
        ).writeAsString('paraselene-m1-synthetic-v1\n', flush: true);
      }
      session = await CoreSession.openSynthetic(root: root.path);
      await NativeRuntime.verify(session);
      return RealWorkspaceRepository._(root, session, owned);
    } catch (error) {
      try {
        if (session != null) await session.close();
      } finally {
        session?.dispose();
        if (owned && root != null) await root.delete(recursive: true);
      }
      throw _failure(error);
    }
  }

  static WorkspaceFailure _failure(Object error) {
    if (error is WorkspaceFailure) return error;
    if (error is BridgeError) return WorkspaceFailure(error.code);
    if (error is StateError) return WorkspaceFailure(error.message.toString());
    return const WorkspaceFailure('bridge_unavailable');
  }

  Future<T> _run<T>(Future<T> Function() action) async {
    if (_closing != null) throw const WorkspaceFailure('session_closed');
    try {
      return await action();
    } catch (error) {
      throw _failure(error);
    }
  }

  static WorkspaceWork _work(BridgeWork w) =>
      WorkspaceWork(id: w.id, title: w.title);
  static WorkspaceChapter _chapter(BridgeChapter c) => WorkspaceChapter(
    id: c.id,
    title: c.title,
    headVersionId: c.headVersionId,
    orderIndex: c.orderIndex,
    archived: c.archived,
  );
  static ChapterDocument _document(BridgeDocument d) => ChapterDocument(
    workId: d.workId,
    documentId: d.documentId,
    body: d.body,
    revision: d.revision,
    baseHeadVersion: d.baseHeadVersion,
    headVersionId: d.headVersionId,
    contentHash: d.contentHash,
  );
  @override
  Future<List<WorkspaceWork>> listWorks() => _run(
    () async => List.unmodifiable((await _session.listWorks()).map(_work)),
  );
  @override
  Future<WorkspaceWork> createWork(String title) =>
      _run(() async => _work(await _session.createWork(title: title)));
  @override
  Future<WorkspaceWork> selectWork(String workId) =>
      _run(() async => _work(await _session.selectWork(workId: workId)));
  @override
  Future<WorkspaceState> workspaceState() => _run(() async {
    final s = await _session.workspaceState();
    return WorkspaceState(
      selectedWorkId: s.selectedWorkId,
      recentWorks: List.unmodifiable(s.recentWorks.map(_work)),
      warning: s.warning,
    );
  });
  @override
  Future<List<WorkspaceChapter>> listChapters(String workId) => _run(
    () async => List.unmodifiable(
      (await _session.listChapters(workId: workId)).map(_chapter),
    ),
  );
  @override
  Future<List<WorkspaceChapter>> listArchivedChapters(String workId) => _run(
    () async => List.unmodifiable(
      (await _session.listArchivedChapters(workId: workId)).map(_chapter),
    ),
  );
  @override
  Future<WorkspaceChapter> createChapter(String workId, String title) => _run(
    () async =>
        _chapter(await _session.createChapter(workId: workId, title: title)),
  );
  @override
  Future<WorkspaceChapter> renameChapter(
    String workId,
    String chapterId,
    String title,
  ) => _run(
    () async => _chapter(
      await _session.renameChapter(
        workId: workId,
        documentId: chapterId,
        title: title,
      ),
    ),
  );
  @override
  Future<void> reorderChapters(String workId, List<String> orderedIds) => _run(
    () => _session.reorderChapters(workId: workId, orderedIds: orderedIds),
  );
  @override
  Future<WorkspaceChapter> setChapterArchived(
    String workId,
    String chapterId,
    bool archived,
  ) => _run(
    () async => _chapter(
      await _session.setChapterArchived(
        workId: workId,
        documentId: chapterId,
        archived: archived,
      ),
    ),
  );
  @override
  Future<ChapterDocument> loadDocument(String workId, String chapterId) => _run(
    () async =>
        _document(await _session.load(workId: workId, documentId: chapterId)),
  );
  @override
  Future<String> loadBody(String workId, String chapterId) async =>
      (await loadDocument(workId, chapterId)).body;
  @override
  Future<ChapterDocument> saveDocument(
    String workId,
    String chapterId,
    int? expectedRevision,
    String body,
  ) => _run(
    () async => _document(
      await _session.save(
        workId: workId,
        documentId: chapterId,
        expectedRevision: expectedRevision,
        body: body,
      ),
    ),
  );
  @override
  Future<void> discardDraft(
    String workId,
    String chapterId,
    int? expectedRevision,
  ) => _run(
    () => _session.discardDraft(
      workId: workId,
      documentId: chapterId,
      expectedRevision: expectedRevision,
    ),
  );
  @override
  Future<List<VersionEntry>> listVersions(String workId, String chapterId) =>
      _run(
        () async => List.unmodifiable(
          (await _session.listVersions(
            workId: workId,
            documentId: chapterId,
          )).map(
            (v) => VersionEntry(
              id: v.id,
              documentId: v.documentId,
              body: v.body,
              origin: v.origin,
              createdAt: v.createdAt,
              isHead: v.isHead,
              parentVersionId: v.parentVersionId,
            ),
          ),
        ),
      );
  @override
  Future<PreparedConfirmation> prepareConfirmation(
    String workId,
    String chapterId,
    String? expectedHead,
    int expectedRevision,
  ) => _run(() async {
    final review = await _session.prepareConfirmation(
      workId: workId,
      documentId: chapterId,
      expectedHead: expectedHead,
      expectedRevision: expectedRevision,
    );
    return PreparedConfirmation(body: review.body, token: review.token);
  });
  @override
  Future<WorkspaceChapter> confirmChapter(
    String workId,
    String chapterId,
    String reviewToken,
  ) => _run(
    () async => _chapter(
      await _session.confirmChapter(
        workId: workId,
        documentId: chapterId,
        reviewToken: reviewToken,
      ),
    ),
  );
  @override
  Future<WorkspaceChapter> rollbackChapter(
    String workId,
    String chapterId,
    String versionId,
    String? expectedHead,
    int? expectedRevision,
  ) => _run(
    () async => _chapter(
      await _session.rollbackChapter(
        workId: workId,
        documentId: chapterId,
        versionId: versionId,
        expectedHead: expectedHead,
        expectedRevision: expectedRevision,
      ),
    ),
  );
  @override
  Future<String?> getUiSession(String workId) =>
      _run(() => _session.getUiSession(workId: workId));
  @override
  Future<void> setUiSession(String workId, String value) =>
      _run(() => _session.setUiSession(workId: workId, value: value));
  @override
  Future<void> seedDemo() =>
      _seeding ??= _run(_seedDemo).whenComplete(() => _seeding = null);
  Future<void> _seedDemo() async {
    if (_seeded) return;
    _demoWorkId ??= (await _session.createWork(title: '雨后的书店')).id;
    _demoChapterId ??= (await _session.createChapter(
      workId: _demoWorkId!,
      title: '第一章 · 归途',
    )).id;
    await _session.save(
      workId: _demoWorkId!,
      documentId: _demoChapterId!,
      body: demoBody,
    );
    _seeded = true;
  }

  @override
  Future<void> close() => _closing ??= _cleanup();
  Future<void> _cleanup() async {
    try {
      await _session.close();
    } finally {
      _session.dispose();
      final root = _root;
      if (_deleteRoot && root != null) await root.delete(recursive: true);
    }
  }
}
