// 作者拥有的讨论线程快照模型：草稿、冻结选段、活动锚点、引用与版本。
// 关键不变量：持久化时剔除服务端 operation 派生的 request 并把 candidate 置空；
// 锚点坐标以 UTF-16 code unit 计，失效锚点保留冻结原文，只把 valid 置为 false。

import '../editor/editor_anchor.dart';

/// Author-owned state. Operation-derived requests and candidates are excluded.
///
/// 作者拥有的线程状态：草稿、冻结选段、活动锚点、引用与作者版本。
/// 服务端操作派生的 request 与 candidate 不进入作者快照，持久化时会被剔除。
final class DiscussionThread {
  DiscussionThread({
    required this.id,
    required this.chapter,
    required this.snapshot,
    this.revision,
    this.generation = 0,
    this.savedGeneration = -1,
  });

  /// 从存储行恢复线程；revision 作为下一次 CAS 期望，savedGeneration 归零表示已落盘。
  factory DiscussionThread.fromRow(Map<String, dynamic> row) =>
      DiscussionThread(
        id: row['threadId'] as String,
        chapter: row['documentId'] as String,
        snapshot: Map<String, dynamic>.from(row['snapshot'] as Map),
        revision: row['revision'] as int,
        savedGeneration: 0,
      );

  /// 从当前编辑器锚点创建线程：冻结选段原文与基准正文，作为不可变引用源。
  factory DiscussionThread.create(
    String id,
    String chapter,
    EditorAnchor anchor,
  ) => DiscussionThread(
    id: id,
    chapter: chapter,
    snapshot: {
      'schemaVersion': 1,
      'id': id,
      'chapterId': chapter,
      'draft': '',
      'target': {
        'chapterId': chapter,
        'from': anchor.baseFrom,
        'to': anchor.baseTo,
        'text': anchor.text,
        'baseBody': anchor.baseBody,
      },
      'anchor': {'from': anchor.from, 'to': anchor.to, 'valid': anchor.valid},
      'attached': <String>[],
      'requests': <dynamic>[],
      'candidate': null,
      'versions': <dynamic>[],
      'view': 'discussion',
      'compare': false,
    },
  );

  /// Whole-chapter discussion: no frozen quotation and no anchor. Generation
  /// still requires a selection, so these threads are discussion-only.
  ///
  /// 整章讨论没有冻结引文与锚点；生成仍需要选段，因此这类线程只用于讨论。
  factory DiscussionThread.createChapter(String id, String chapter) =>
      DiscussionThread(
        id: id,
        chapter: chapter,
        snapshot: {
          'schemaVersion': 1,
          'id': id,
          'chapterId': chapter,
          'draft': '',
          'target': null,
          'anchor': null,
          'attached': <String>[],
          'requests': <dynamic>[],
          'candidate': null,
          'versions': <dynamic>[],
          'view': 'discussion',
          'compare': false,
        },
      );

  /// 线程全局唯一 ID。
  final String id;

  /// 所属章节文档 ID。
  final String chapter;

  /// 作者快照 JSON，结构随 schemaVersion 演进。
  Map<String, dynamic> snapshot;

  /// 服务端 CAS 版本；null 表示尚未落盘。
  int? revision;

  /// 本地修改代数，每次 [update] 递增。
  int generation;

  /// 最近一次成功保存时的代数，用于判断是否脏。
  int savedGeneration;

  /// 是否存在未保存到本地的修改。
  bool get dirty => generation != savedGeneration;

  /// 草稿是否还有待发送内容。
  bool get draftPending => draft.isNotEmpty;

  /// 是否为整章讨论（没有冻结选段）。
  bool get isChapter => snapshot['target'] == null;

  /// 作者草稿文本。
  String get draft => snapshot['draft'] as String;

  /// 活动锚点是否仍能唯一落到原选段；失效线程仍可编辑，但不能生成。
  bool get valid => (snapshot['anchor'] as Map?)?['valid'] == true;

  /// 活动锚点的结束偏移，以 UTF-16 code unit 计；整章讨论为 0。
  int get offset => ((snapshot['anchor'] as Map?)?['to'] as int?) ?? 0;

  /// 由冻结选段与活动坐标重建 [EditorAnchor]；整章讨论或字段缺失时返回 null。
  EditorAnchor? get anchor {
    final target = snapshot['target'] as Map?;
    final current = snapshot['anchor'] as Map?;
    if (target == null || current == null) return null;
    return EditorAnchor(
      from: current['from'] as int,
      to: current['to'] as int,
      text: target['text'] as String,
      baseBody: target['baseBody'] as String,
      baseFrom: target['from'] as int,
      baseTo: target['to'] as int,
      valid: current['valid'] as bool,
    );
  }

  /// 合并字段变更并递增本地代数；只改内存，不触发落盘。
  void update(Map<String, dynamic> fields) {
    snapshot = {...snapshot, ...fields};
    generation++;
  }

  /// Never writes a server projection back into the author snapshot.
  ///
  /// 只输出作者数据：剔除含 operationId 的服务端派生 request，并把 candidate 置空。
  Map<String, dynamic> persistenceSnapshot() => {
    ...snapshot,
    'requests': (snapshot['requests'] as List)
        .where(
          (request) => request is Map && !request.containsKey('operationId'),
        )
        .toList(),
    'candidate': null,
  };
}
