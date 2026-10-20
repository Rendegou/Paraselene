// 工作区数据层接口与值对象：定义目录元数据、工作副本、版本树与每作品 UI 会话的读写契约。
// 读边界：正文按作品与章节按需读取，返回的 body 是精确文本，禁止归一化或翻译。
// 写边界：所有变更经 Rust 核心事务 CAS 提交，错误码必须稳定可本地化；本文件只声明接口，不实现 IO。
// 关键不变量：expectedRevision 为 null 表示创建修订 1；版本头与修订号同时参与冲突判定。
/// Distinguishes an actual native bridge from an in-memory demonstration.
///
/// 仓库模式：真实原生桥接或内存合成演示；调用方不得把合成模式当作已接数据库。
enum WorkspaceMode { realBridge, synthetic }

/// Immutable work metadata; titles retain their original language.
///
/// 作品元数据：id 与标题来自仓库快照；标题保留作者原文语言，不翻译。
final class WorkspaceWork {
  const WorkspaceWork({required this.id, required this.title});
  final String id;
  final String title;
}

/// Immutable chapter metadata, loaded separately from its body.
///
/// 章节元数据：正文按需单独加载；orderIndex 只在未归档章节之间有序。
final class WorkspaceChapter {
  const WorkspaceChapter({
    required this.id,
    required this.title,
    this.headVersionId,
    this.orderIndex = 0,
    this.archived = false,
  });
  final String id;
  final String title;
  final String? headVersionId;
  final int orderIndex;
  final bool archived;
}

/// Exact working text with the CAS revision and head lineage.
///
/// 精确工作正文快照：revision 用于 CAS，headVersionId 指向最近确认版本；body 不得归一化。
final class ChapterDocument {
  const ChapterDocument({
    required this.workId,
    required this.documentId,
    required this.body,
    this.revision,
    this.baseHeadVersion,
    this.headVersionId,
    this.contentHash,
  });
  final String workId;
  final String documentId;
  final String body;
  final int? revision;
  final String? baseHeadVersion;
  final String? headVersionId;
  final String? contentHash;
}

/// Immutable confirmed version; `body` is the exact historical text.
///
/// 已确认版本条目：body 是历史精确正文，createdAt 为仓库给出的时间字符串。
final class VersionEntry {
  const VersionEntry({
    required this.id,
    required this.documentId,
    required this.body,
    required this.origin,
    required this.createdAt,
    required this.isHead,
    this.parentVersionId,
  });
  final String id;
  final String documentId;
  final String body;
  final String origin;
  final String createdAt;
  final bool isHead;
  final String? parentVersionId;
}

/// Runtime selection, most-recent-first works and an optional warning code.
///
/// 工作区启动状态：最近作品顺序、选中作品与可选警告码；警告不阻断启动。
final class WorkspaceState {
  const WorkspaceState({
    required this.recentWorks,
    this.selectedWorkId,
    this.warning,
  });
  final String? selectedWorkId;
  final List<WorkspaceWork> recentWorks;
  final String? warning;
}

/// Display `body` before asking for approval; return `token` unchanged afterwards.
///
/// 确认复核载荷：界面向用户展示 body 后原样回传 token，token 绑定正文、head 与修订号。
final class PreparedConfirmation {
  const PreparedConfirmation({required this.body, required this.token});
  final String body;
  final String token;
}

/// Stable machine-readable failure; presentation owns localization.
///
/// 工作区失败：code 为稳定的 ASCII 机器码，由表现层负责本地化，不在此拼用户文案。
final class WorkspaceFailure implements Exception {
  const WorkspaceFailure(this.code);
  final String code;
  @override
  /// 调试字符串只暴露错误码，不包含作者正文或私有路径。
  String toString() => 'WorkspaceFailure($code)';
}

/// Work/chapter metadata, exact-body access and versioned persistence with
/// explicit asynchronous ownership. All mutating calls go through the core
/// transactional CAS; conflict codes are stable ASCII (`revision_conflict`,
/// `head_conflict`, `base_conflict`, `context_conflict`, `invalid_input`,
/// `not_found`, `identity_mismatch`, `session_closed`).
///
/// 工作区读写接口：目录、正文、版本与 UI 会话全部通过异步调用访问。
///
/// 所有变更走核心事务 CAS；调用方必须处理稳定冲突码并保留脏文本。
abstract interface class WorkspaceRepository {
  /// 当前仓库模式；真实桥接与合成演示的界面提示不同。
  WorkspaceMode get mode;

  // Works and session-level state.
  /// 列出作品目录；顺序由仓库决定。
  Future<List<WorkspaceWork>> listWorks();

  /// 创建作品并返回仓库生成的 id；标题原样保存。
  Future<WorkspaceWork> createWork(String title);

  /// 记录所选作品为最近使用项。
  Future<WorkspaceWork> selectWork(String workId);

  /// 读取启动状态；损坏的会话数据以 warning 码返回而不抛出。
  Future<WorkspaceState> workspaceState();

  // Chapter directory; reorder takes exactly the non-archived chapter ids.
  /// 列出未归档章节，按显示顺序排列。
  Future<List<WorkspaceChapter>> listChapters(String workId);

  /// 列出归档章节；它们的绝对位置不受重排影响。
  Future<List<WorkspaceChapter>> listArchivedChapters(String workId);

  /// 在目录末尾创建章节并返回元数据。
  Future<WorkspaceChapter> createChapter(String workId, String title);

  /// 只修改章节标题元数据，不动正文与版本树。
  Future<WorkspaceChapter> renameChapter(
    String workId,
    String chapterId,
    String title,
  );

  /// 重排未归档章节；orderedIds 必须与这些章节的 id 集合完全一致。
  Future<void> reorderChapters(String workId, List<String> orderedIds);

  /// 归档或恢复章节；归档不删除正文与历史版本。
  Future<WorkspaceChapter> setChapterArchived(
    String workId,
    String chapterId,
    bool archived,
  );

  // Working copies; `expectedRevision: null` creates revision 1.
  /// 读取章节的精确正文；返回文本不得归一化。
  Future<String> loadBody(String workId, String chapterId);

  /// 读取正文及 CAS 修订与版本头；这是保存与确认的前置快照。
  Future<ChapterDocument> loadDocument(String workId, String chapterId);

  /// 以 expectedRevision 做 CAS 保存；null 表示创建修订 1，冲突时返回稳定错误码。
  Future<ChapterDocument> saveDocument(
    String workId,
    String chapterId,
    int? expectedRevision,
    String body,
  );

  /// 用 expectedRevision 做 CAS 丢弃工作副本；不删除已确认版本。
  Future<void> discardDraft(
    String workId,
    String chapterId,
    int? expectedRevision,
  );

  // Immutable version tree.
  /// 只读列出已确认版本，供预览与回滚选择。
  Future<List<VersionEntry>> listVersions(String workId, String chapterId);

  /// 生成绑定正文、head 与修订号的复核令牌；此时不确认、不写版本。
  Future<PreparedConfirmation> prepareConfirmation(
    String workId,
    String chapterId,
    String? expectedHead,
    int expectedRevision,
  );

  /// 用复核令牌把正文确认为新版本；令牌过期或修订漂移时返回稳定冲突码。
  Future<WorkspaceChapter> confirmChapter(
    String workId,
    String chapterId,
    String reviewToken,
  );

  /// 回滚到指定历史版本并更新头；调用方应丢弃当前工作副本。
  Future<WorkspaceChapter> rollbackChapter(
    String workId,
    String chapterId,
    String versionId,
    String? expectedHead,
    int? expectedRevision,
  );

  // Per-work UI session JSON (validated keys/size server-side).
  /// 读取每作品 UI 会话 JSON 原文；键与大小由仓库校验。
  Future<String?> getUiSession(String workId);

  /// 覆盖写入每作品 UI 会话 JSON；由仓库校验键与大小。
  Future<void> setUiSession(String workId, String value);

  /// 显式写入演示数据；只应由演示入口触发。
  Future<void> seedDemo();

  /// 释放仓库持有的原生资源；之后不得再调用其他方法。
  Future<void> close();
}
