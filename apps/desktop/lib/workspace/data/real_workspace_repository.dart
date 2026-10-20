// 真实桥接工作区仓库：把 WorkspaceRepository 契约桥接到 Rust 原生核心会话（FFI），并负责会话打开、校验与关闭。
// 读边界：目录、正文、版本与 UI 会话都经 CoreSession 读取；本文件不做文本归一化，也不改写作者正文。
// 写边界：保存、确认、回滚等变更由原生核心事务 CAS 提交；close 之后禁止再调用，关闭只发生一次。
// 关键不变量：错误统一收敛为 WorkspaceFailure 稳定码；备份演练使用独立临时根，绝不替换当前写入方与正文。
import 'dart:io';
import 'dart:typed_data';
import '../../cowrite/native_discussion_repository.dart';
import '../../cowrite/discussion_repository.dart';
import '../../lore/lore_repository.dart';
import '../../legacy/legacy_repository.dart';
import '../../native/generated/api.dart';
import '../../native/generated/api/models.dart';
import '../../native/runtime.dart';
import 'demo_content.dart';
import 'workspace_repository.dart';

/// Owns a verified synthetic native session. Caller-owned roots survive close.
///
/// 持有已校验的原生合成会话；调用方提供的根目录在关闭时保留，自建根目录会被删除。
final class RealWorkspaceRepository
    implements WorkspaceRepository, DiscussionRepositoryProvider, LoreHost {
  RealWorkspaceRepository._(this._root, this._session, this._deleteRoot);
  final Directory? _root;
  final CoreSession _session;

  /// Shares this repository's single native writer and close lifecycle.
  ///
  /// 与主仓库共享同一个原生写入方和关闭生命周期；仓库关闭后不可再使用。
  @override
  NativeDiscussionRepository get discussions =>
      NativeDiscussionRepository(_session);

  /// 设定资料仓库，与主仓库共享原生会话。
  @override
  LoreRepository get lore => LoreRepository(_session);

  /// 旧版数据转换仓库，与主仓库共享原生会话。
  LegacyRepository get legacy => LegacyRepository(_session);

  /// Full sealed snapshot, distinct from the readable recovery export.
  ///
  /// 导出密封快照用于完整备份；它不同于可读的恢复导出文本，不写作者正文。
  Future<Uint8List> exportBackup() => _session.exportSyntheticBackup();

  /// Restores into a separate temporary synthetic root and closes it afterwards.
  /// The current writer, identity, manuscript and settings are never replaced.
  ///
  /// 返回演练还原后可读的作品数；演练结束即关闭并释放临时会话，当前写入方、身份、正文与设置都不受影响。
  Future<int> rehearseBackup(Uint8List bytes) async {
    final restored = await CoreSession.restoreSyntheticBackup(sealed: bytes);
    try {
      await NativeRuntime.verify(restored);
      return (await restored.listWorks()).length;
    } finally {
      await restored.close();
      restored.dispose();
    }
  }

  final bool _deleteRoot;
  Future<void>? _closing;
  bool _seeded = false;
  String? _demoWorkId;
  String? _demoChapterId;
  Future<void>? _seeding;

  /// 真实桥接模式；内存合成演示不是此实现。
  @override
  WorkspaceMode get mode => WorkspaceMode.realBridge;

  /// Opens the application-owned fixed synthetic store (ADR-004): durable
  /// across processes, DPAPI-sealed for the current Windows user. No caller
  /// root exists and nothing is deleted on close.
  ///
  /// 打开应用自有的固定合成库：跨进程持久并由当前 Windows 用户的 DPAPI 密封；关闭时不删除数据。
  static Future<RealWorkspaceRepository> openOwned({
    bool diagnosticOverride = false,
    bool testSupport = false,
  }) async {
    CoreSession? session;
    try {
      await NativeRuntime.initialize(
        diagnosticOverride: diagnosticOverride,
        testSupport: testSupport,
      );
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
  ///
  /// syntheticRoot 为空时创建临时目录并在关闭时删除；调用方提供的根目录依赖原生合成来源校验。
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

  // 统一把桥接错误收敛为稳定工作区错误码，并拒绝关闭后的调用。
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

  /// 列出作品目录；返回不可变快照，失败抛稳定错误码。
  @override
  Future<List<WorkspaceWork>> listWorks() => _run(
    () async => List.unmodifiable((await _session.listWorks()).map(_work)),
  );

  /// 创建作品并返回元数据；标题原样交给原生核心保存。
  @override
  Future<WorkspaceWork> createWork(String title) =>
      _run(() async => _work(await _session.createWork(title: title)));

  /// 记录所选作品为最近使用项；不改变任何正文。
  @override
  Future<WorkspaceWork> selectWork(String workId) =>
      _run(() async => _work(await _session.selectWork(workId: workId)));

  /// 读取启动状态；原生侧损坏的会话以 warning 码返回。
  @override
  Future<WorkspaceState> workspaceState() => _run(() async {
    final s = await _session.workspaceState();
    return WorkspaceState(
      selectedWorkId: s.selectedWorkId,
      recentWorks: List.unmodifiable(s.recentWorks.map(_work)),
      warning: s.warning,
    );
  });

  /// 列出未归档章节，按原生给出的显示顺序返回。
  @override
  Future<List<WorkspaceChapter>> listChapters(String workId) => _run(
    () async => List.unmodifiable(
      (await _session.listChapters(workId: workId)).map(_chapter),
    ),
  );

  /// 列出归档章节，按原生给出的顺序返回。
  @override
  Future<List<WorkspaceChapter>> listArchivedChapters(String workId) => _run(
    () async => List.unmodifiable(
      (await _session.listArchivedChapters(workId: workId)).map(_chapter),
    ),
  );

  /// 在目录末尾创建章节；标题原样交给原生核心。
  @override
  Future<WorkspaceChapter> createChapter(String workId, String title) => _run(
    () async =>
        _chapter(await _session.createChapter(workId: workId, title: title)),
  );

  /// 只改章节标题元数据，不动正文与版本树。
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

  /// 重排未归档章节；id 集合必须与当前未归档章节一致。
  @override
  Future<void> reorderChapters(String workId, List<String> orderedIds) => _run(
    () => _session.reorderChapters(workId: workId, orderedIds: orderedIds),
  );

  /// 归档或恢复章节；归档不删除正文与历史版本。
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

  /// 读取正文及 CAS 修订与版本头；body 为精确文本。
  @override
  Future<ChapterDocument> loadDocument(String workId, String chapterId) => _run(
    () async =>
        _document(await _session.load(workId: workId, documentId: chapterId)),
  );

  /// 读取章节精确正文；内部先加载完整文档再取 body。
  @override
  Future<String> loadBody(String workId, String chapterId) async =>
      (await loadDocument(workId, chapterId)).body;

  /// 以 expectedRevision 做 CAS 保存；null 表示创建修订 1，冲突返回稳定码。
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

  /// 以 expectedRevision 做 CAS 丢弃工作副本，不删除已确认版本。
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

  /// 只读列出已确认版本，按版本树顺序返回。
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

  /// 生成复核载荷，不确认也不写版本；head 与修订不匹配时抛冲突码。
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

  /// 用复核令牌确认正文为新版本；令牌过期或漂移时返回稳定冲突码。
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

  /// 回滚到指定历史版本；原生核心更新头并丢弃当前工作副本。
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

  /// 读取每作品 UI 会话 JSON 原文；不存在时为 null。
  @override
  Future<String?> getUiSession(String workId) =>
      _run(() => _session.getUiSession(workId: workId));

  /// 覆盖写入每作品 UI 会话 JSON；键与大小由原生核心校验。
  @override
  Future<void> setUiSession(String workId, String value) =>
      _run(() => _session.setUiSession(workId: workId, value: value));

  /// 幂等写入演示作品与章节；并发调用共享同一次写入。
  @override
  Future<void> seedDemo() =>
      _seeding ??= _run(_seedDemo).whenComplete(() => _seeding = null);
  // 先建作品再建章节并保存演示正文；中途失败时保留已建 id，下次调用继续补齐。
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

  /// 关闭原生会话并释放资源；重复调用返回同一个 Future，关闭后其他调用抛 session_closed。
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
