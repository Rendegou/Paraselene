import '../../workspace/data/workspace_repository.dart';

/// Persistence state; error/conflict require an explicit retry.
enum SaveStatus { dirty, saving, saved, conflict, error }

/// Immutable exact-text snapshot. Sequences and generation are monotonic counts.
final class SaveState {
  const SaveState({
    required this.document,
    required this.generation,
    this.editSequence = 0,
    this.savedSequence = 0,
    this.status = SaveStatus.saved,
    this.errorCode,
  });

  final ChapterDocument document;
  final int generation;
  final int editSequence;
  final int savedSequence;
  final SaveStatus status;
  final String? errorCode;
  String get workId => document.workId;
  String get documentId => document.documentId;
  String get body => document.body;
  int? get revision => document.revision;
  String? get baseHead => document.baseHeadVersion;
  String? get head => document.headVersionId;
  String? get hash => document.contentHash;
  bool get dirty => editSequence != savedSequence;

  /// Replaces selected fields; null errorCode explicitly clears a failure.
  SaveState copyWith({
    ChapterDocument? document,
    int? editSequence,
    int? savedSequence,
    SaveStatus? status,
    String? errorCode,
  }) => SaveState(
    document: document ?? this.document,
    generation: generation,
    editSequence: editSequence ?? this.editSequence,
    savedSequence: savedSequence ?? this.savedSequence,
    status: status ?? this.status,
    errorCode: errorCode,
  );
}
