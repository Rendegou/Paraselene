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
  const WorkspaceChapter({required this.id, required this.title});
  final String id;
  final String title;
}

/// Stable machine-readable failure; presentation owns localization.
final class WorkspaceFailure implements Exception {
  const WorkspaceFailure(this.code);
  final String code;
  @override
  String toString() => 'WorkspaceFailure($code)';
}

/// Metadata and exact-body access with explicit asynchronous ownership.
abstract interface class WorkspaceRepository {
  WorkspaceMode get mode;
  Future<List<WorkspaceWork>> listWorks();
  Future<List<WorkspaceChapter>> listChapters(String workId);
  Future<String> loadBody(String workId, String chapterId);
  Future<void> seedDemo();
  Future<void> close();
}
