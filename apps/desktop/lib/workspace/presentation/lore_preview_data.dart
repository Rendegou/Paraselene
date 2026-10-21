// 资料预览的不可变展示副本与历史引用解析；无 IO、无数据库写入。
// 历史引用从作者请求快照读取，不以当前资料覆盖冻结依据。
import '../../cowrite/discussion_thread.dart';
import '../../l10n/generated/app_localizations.dart';

/// 侧栏资料行投影出的只读预览数据，全部字段都是展示副本。
class LorePreviewData {
  const LorePreviewData({
    required this.entryId,
    required this.name,
    required this.kind,
    required this.status,
    required this.version,
    required this.origin,
    required this.confirmed,
    required this.body,
  });

  /// 从 `{entry: ..., head: ...}` 行解析预览数据。
  ///
  /// [row] 结构缺失或没有条目 ID 时返回 null：调用方应提示条目缺失，
  /// 不能用其它条目冒充。head 为空时正文为空、版本为 0。
  static LorePreviewData? fromRow(Map<String, dynamic> row) {
    final entry = row['entry'];
    if (entry is! Map) return null;
    final entryId = entry['id'];
    final name = entry['name'];
    if (entryId is! String || entryId.isEmpty || name is! String) return null;
    final head = row['head'];
    final headFields = head is Map ? head : const <String, dynamic>{};
    final version = headFields['version'];
    final body = headFields['body'];
    final origin = headFields['origin'];
    final kind = entry['kind'];
    final status = entry['status'];
    return LorePreviewData(
      entryId: entryId,
      name: name,
      kind: kind is String ? kind : '',
      status: status is String ? status : '',
      version: version is int ? version : 0,
      origin: origin is String && origin.isNotEmpty ? origin : null,
      confirmed: headFields['confirmed'] == true,
      body: body is String ? body : '',
    );
  }

  /// 条目 ID；点击带入时写入讨论线程 attached 的值。
  final String entryId;

  /// 该版本保存的资料名称。
  final String name;

  /// 原生资料类型协议值。
  final String kind;

  /// 原生确认或候选状态协议值。
  final String status;

  /// 当前资料版本；没有 head 时为0。
  final int version;

  /// 版本来源；历史数据缺失时为空。
  final String? origin;

  /// 是否已明确确认，可进入模型材料预览。
  final bool confirmed;

  /// 精确版本的原文副本，不归一化或翻译。
  final String body;
}

/// 在已加载的资料行里按条目 ID 精确查找；找不到返回 null。
Map<String, dynamic>? loreRowById(
  Iterable<Map<String, dynamic>> rows,
  String entryId,
) {
  if (entryId.isEmpty) return null;
  for (final row in rows) {
    final entry = row['entry'];
    if (entry is Map && entry['id'] == entryId) return row;
  }
  return null;
}

/// 历史请求提交时的单条资料引用快照；不随之后编辑的资料变化。
class LoreRequestSnapshot {
  const LoreRequestSnapshot({
    required this.threadId,
    required this.requestIndex,
    required this.requestText,
    required this.name,
    required this.body,
  });

  /// 冻结引用所属的真实线程ID。
  final String threadId;

  /// 请求在作者快照数组中的零起始位置。
  final int requestIndex;

  /// 请求提交时的作者指令副本。
  final String requestText;

  /// 该版本保存的资料名称。
  final String name;

  /// 精确版本的原文副本，不归一化或翻译。
  final String body;
}

/// 收集线程快照里引用过 [entryId] 的历史请求，返回提交时冻结的名称与正文。
///
/// 只读 `thread.snapshot['requests']` 中的作者数据，不查询当前资料，
/// 因此资料之后被编辑也不会覆盖历史依据。
List<LoreRequestSnapshot> loreRequestSnapshots(
  Iterable<DiscussionThread> threads,
  String entryId,
) {
  final snapshots = <LoreRequestSnapshot>[];
  if (entryId.isEmpty) return snapshots;
  for (final thread in threads) {
    final requests = thread.snapshot['requests'];
    if (requests is! List) continue;
    for (var index = 0; index < requests.length; index++) {
      final request = requests[index];
      if (request is! Map) continue;
      final references = request['references'];
      if (references is! List) continue;
      for (final reference in references) {
        if (reference is! Map || reference['id'] != entryId) continue;
        final name = reference['name'];
        final body = reference['body'];
        final text = request['text'];
        snapshots.add(
          LoreRequestSnapshot(
            threadId: thread.id,
            requestIndex: index,
            requestText: text is String ? text : '',
            name: name is String ? name : '',
            body: body is String ? body : '',
          ),
        );
      }
    }
  }
  return snapshots;
}

/// 资料类型的中文本地化标签；未知类型原样显示。
String loreKindLabel(AppLocalizations strings, String kind) {
  return switch (kind) {
    'character' => strings.loreGroupCharacters,
    'world' => strings.loreGroupWorld,
    'location' => strings.loreGroupLocations,
    'timeline' => strings.loreGroupTimeline,
    'taboo' => strings.loreGroupTaboo,
    'style' => strings.loreGroupStyle,
    _ => kind.isEmpty ? strings.loreTitle : kind,
  };
}
