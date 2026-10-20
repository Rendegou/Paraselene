// 保存状态值对象：不可变的精确正文快照与单调计数。
//
// 错误与冲突状态必须显式重试，不会自动清除；本文件不写库、无 IO。
// dirty 由编辑序号与已保存序号之差判定，不比较正文内容。
import '../../workspace/data/workspace_repository.dart';

/// Persistence state; error/conflict require an explicit retry.
///
/// 持久化状态：dirty 与 saving 表示仍有文本未落盘；conflict 与 error 必须显式重试，
/// 不会自动清除。
enum SaveStatus {
  /// 正文已修改但尚未提交保存。
  dirty,

  /// 保存请求正在飞行中。
  saving,

  /// 最新正文已确认落盘。
  saved,

  /// 后端报告 CAS 冲突，需要上层或用户显式重试。
  conflict,

  /// 保存失败（非冲突），需要显式重试。
  error,
}

/// Immutable exact-text snapshot. Sequences and generation are monotonic counts.
///
/// 单篇文档的不可变保存快照：正文逐字保留，序号与装载代号都是单调计数。
final class SaveState {
  const SaveState({
    required this.document,
    required this.generation,
    this.editSequence = 0,
    this.savedSequence = 0,
    this.status = SaveStatus.saved,
    this.errorCode,
  });

  /// 精确正文与后端身份/revision/hash 的快照。
  final ChapterDocument document;

  /// 槽位装载代号，每次 hydrate 递增，用于识别新旧快照。
  final int generation;

  /// 单调编辑计数，每次正文变更递增。
  final int editSequence;

  /// 已确认落盘所对应的编辑计数。
  final int savedSequence;

  /// 当前持久化状态。
  final SaveStatus status;

  /// 稳定错误码；为 null 表示没有未解决的失败。
  final String? errorCode;

  /// 所属作品 ID。
  String get workId => document.workId;

  /// 文档/章节 ID。
  String get documentId => document.documentId;

  /// 精确正文文本。
  String get body => document.body;

  /// 后端 CAS revision；新文档尚未保存时为 null。
  int? get revision => document.revision;

  /// 提交时所基于的 head 版本。
  String? get baseHead => document.baseHeadVersion;

  /// 保存后返回的 head 版本。
  String? get head => document.headVersionId;

  /// 后端确认的内容 hash；正文又变脏时可能为 null。
  String? get hash => document.contentHash;

  /// 是否还有未落盘的编辑。
  bool get dirty => editSequence != savedSequence;

  /// Replaces selected fields; null errorCode explicitly clears a failure.
  ///
  /// 替换指定字段；除 document 与 generation 外的参数为 null 时保持原值，
  /// errorCode 显式传 null 会清除失败状态。
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
