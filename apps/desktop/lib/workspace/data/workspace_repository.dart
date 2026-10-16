/// Distinguishes an actual native bridge from an in-memory demonstration.
enum WorkspaceMode { realBridge, synthetic }

/// Immutable work metadata; titles retain their original language.
final class WorkspaceWork {
  const WorkspaceWork({required this.id, required this.title});
  final String id;
  final String title;
}

/// Immutable chapter metadata, loaded separately from its body.
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
final class PreparedConfirmation {
  const PreparedConfirmation({required this.body, required this.token});
  final String body;
  final String token;
}

/// Stable machine-readable failure; presentation owns localization.
final class WorkspaceFailure implements Exception {
  const WorkspaceFailure(this.code);
  final String code;
  @override
  String toString() => 'WorkspaceFailure($code)';
}

/// Work/chapter metadata, exact-body access and versioned persistence with
/// explicit asynchronous ownership. All mutating calls go through the core
/// transactional CAS; conflict codes are stable ASCII (`revision_conflict`,
/// `head_conflict`, `base_conflict`, `context_conflict`, `invalid_input`,
/// `not_found`, `identity_mismatch`, `session_closed`).
abstract interface class WorkspaceRepository {
  WorkspaceMode get mode;

  // Works and session-level state.
  Future<List<WorkspaceWork>> listWorks();
  Future<WorkspaceWork> createWork(String title);
  Future<WorkspaceWork> selectWork(String workId);
  Future<WorkspaceState> workspaceState();

  // Chapter directory; reorder takes exactly the non-archived chapter ids.
  Future<List<WorkspaceChapter>> listChapters(String workId);
  Future<List<WorkspaceChapter>> listArchivedChapters(String workId);
  Future<WorkspaceChapter> createChapter(String workId, String title);
  Future<WorkspaceChapter> renameChapter(
    String workId,
    String chapterId,
    String title,
  );
  Future<void> reorderChapters(String workId, List<String> orderedIds);
  Future<WorkspaceChapter> setChapterArchived(
    String workId,
    String chapterId,
    bool archived,
  );

  // Working copies; `expectedRevision: null` creates revision 1.
  Future<String> loadBody(String workId, String chapterId);
  Future<ChapterDocument> loadDocument(String workId, String chapterId);
  Future<ChapterDocument> saveDocument(
    String workId,
    String chapterId,
    int? expectedRevision,
    String body,
  );
  Future<void> discardDraft(
    String workId,
    String chapterId,
    int? expectedRevision,
  );

  // Immutable version tree.
  Future<List<VersionEntry>> listVersions(String workId, String chapterId);
  Future<PreparedConfirmation> prepareConfirmation(
    String workId,
    String chapterId,
    String? expectedHead,
    int expectedRevision,
  );
  Future<WorkspaceChapter> confirmChapter(
    String workId,
    String chapterId,
    String reviewToken,
  );
  Future<WorkspaceChapter> rollbackChapter(
    String workId,
    String chapterId,
    String versionId,
    String? expectedHead,
    int? expectedRevision,
  );

  // Per-work UI session JSON (validated keys/size server-side).
  Future<String?> getUiSession(String workId);
  Future<void> setUiSession(String workId, String value);

  Future<void> seedDemo();
  Future<void> close();
}
