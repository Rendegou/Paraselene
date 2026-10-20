// 遗留数据原生仓库：旧草稿、旧补丁、记忆/想法、伴侣角色、导入与 reviewed task。
// 读取按 space/work 隔离；写入由 Rust 做 CAS、一次性票据与身份校验；JSON 编解码在此完成。
// 纯 Dart 仓库，不依赖 Flutter，也不直接访问数据库文件。

import 'dart:convert';
import 'reviewed_task_repository.dart';
import '../native/generated/api.dart';

/// Stored pointer in a converted idea payload; space/work are part of identity.
///
/// 转换后想法 payload 中保存的目标指针；space 与 memoryId 共同定位记录，
/// workId 只在小说空间存在。
final class IdeaTargetPointer {
  const IdeaTargetPointer({
    required this.space,
    required this.memoryId,
    this.workId,
  });

  /// 记忆空间标识（personal/novel/learning 等）。
  final String space;

  /// 目标记忆记录 ID。
  final String memoryId;

  /// 小说空间对应的作品 ID；其他空间为 null。
  final String? workId;
}

/// Parses only the author-owned `convertedTo` pointer; malformed payload is
/// reported instead of being treated as "not converted".
///
/// 只解析作者 payload 中的 convertedTo 指针；格式损坏抛
/// [FormatException]（invalid_target），不会被当成“尚未转换”。
IdeaTargetPointer? convertedIdeaTargetPointer(Map<String, dynamic> idea) {
  final payload = idea['payload'];
  final Map<String, dynamic>? fields = switch (payload) {
    final Map<dynamic, dynamic> map => Map<String, dynamic>.from(map),
    final String raw => jsonDecode(raw) as Map<String, dynamic>,
    _ => null,
  };
  final converted = fields?['convertedTo'];
  if (converted is! Map) return null;
  final space = converted['space'];
  final memoryId = converted['memoryId'];
  if (space is! String || memoryId is! String) {
    throw const FormatException('invalid_target');
  }
  return IdeaTargetPointer(
    space: space,
    memoryId: memoryId,
    workId: converted['workId'] as String?,
  );
}

/// One target created from an explicit idea conversion. The pointer is read
/// from the author-owned idea payload and never inferred from titles.
///
/// 由显式想法转换创建的目标视图：指针只从作者 payload 读取，绝不按标题推断。
final class IdeaTargetView {
  const IdeaTargetView({
    required this.space,
    required this.record,
    required this.sources,
  });

  /// 目标所属记忆空间。
  final String space;

  /// 记忆详情中的原始记录。
  final Map<String, dynamic> record;

  /// 已记录出处列表，可能为空。
  final List<dynamic> sources;

  /// 记录中的作品 ID；非小说空间为 null。
  String? get workId => record['workId'] as String?;

  /// 目标标题；缺失时为空字符串。
  String get title => record['title'] as String? ?? '';

  /// 目标摘要；缺失时为空字符串。
  String get summary => record['summary'] as String? ?? '';
}

/// Historical modules borrow the same native writer and scoped identities.
///
/// 历史模块复用同一原生写者与作用域身份；读取按 space/work 隔离，
/// 写入由 Rust 做 CAS、一次性票据与身份校验。
final class LegacyRepository implements ReviewedTaskRepository {
  const LegacyRepository(this.session);
  final CoreSession session;

  /// 丢弃指定旧草稿；不修改正文。
  Future<void> discardDraft(String work, String chapter, String draft) =>
      session.discardLegacyDraft(work: work, chapter: chapter, draft: draft);

  /// 删除记忆记录；updatedAt 作为 CAS 期望参与校验。
  Future<void> deleteMemory(String space, Map<String, dynamic> row) =>
      session.memoryDelete(
        selectedSpace: space,
        work: row['workId'] as String?,
        id: row['id'] as String,
        updatedAt: row['updatedAt'] as String,
      );

  /// 按比较更新（expected 为当前状态）流转旧想法状态。
  Future<void> ideaStatus(Map<String, dynamic> row, String next) =>
      session.ideaStatus(
        id: row['id'] as String,
        expected: row['status'] as String,
        next: next,
      );

  /// 把旧想法显式转换为 personal/novel/learning 目标。
  Future<void> convertIdea(String id, String target) async {
    await session.convertIdea(id: id, target: target);
  }

  /// Target of one converted old idea: exact space/work identity plus recorded
  /// sources. A missing pointer is reported as null, never guessed.
  ///
  /// 读取已转换旧想法的目标：使用精确的 space/work 身份与已记录出处；
  /// 指针缺失返回 null，不按标题猜测。
  Future<IdeaTargetView?> ideaTarget(Map<String, dynamic> idea) async {
    final pointer = convertedIdeaTargetPointer(idea);
    if (pointer == null) return null;
    final detail = await memoryDetail(
      pointer.space,
      pointer.workId,
      pointer.memoryId,
    );
    final record = detail['record'];
    if (record is! Map) throw const FormatException('invalid_target');
    return IdeaTargetView(
      space: pointer.space,
      record: Map<String, dynamic>.from(record),
      sources: detail['sources'] is List ? detail['sources'] as List : const [],
    );
  }

  /// CAS update; the native layer also renames a converted novel project.
  ///
  /// 按记录 updatedAt 做 CAS 更新标题/摘要；小说空间的目标同时修改作品标题。
  Future<void> updateIdeaTarget(
    IdeaTargetView target,
    String title,
    String summary,
  ) => correctMemory(target.space, target.record, title, summary);

  Map<String, dynamic> _object(String value) =>
      jsonDecode(value) as Map<String, dynamic>;

  /// 读取章节历史：确认问题、旧草稿、补丁、派生摘要与重建任务。
  Future<Map<String, dynamic>> history(String work, String chapter) async =>
      _object(await session.novelHistory(work: work, chapter: chapter));

  /// 采纳旧补丁；revision 为正文 CAS 期望，block 为 null 表示整补丁。
  Future<void> applyPatch(
    String work,
    String chapter,
    String patch,
    int? revision,
    int? block,
  ) async {
    await session.applyLegacyPatch(
      work: work,
      chapter: chapter,
      patchId: patch,
      revision: revision,
      block: block == null ? null : BigInt.from(block),
    );
  }

  /// 按空间列出记忆；小说空间必须带 work，其他空间忽略 work。
  Future<List<Map<String, dynamic>>> memories(
    String space,
    String? work,
  ) async =>
      (jsonDecode(await session.memoryList(selectedSpace: space, work: work))
              as List)
          .cast<Map<String, dynamic>>();

  /// 读取记忆详情：记录、出处与链接。
  Future<Map<String, dynamic>> memoryDetail(
    String space,
    String? work,
    String id,
  ) async => _object(
    await session.memoryDetail(selectedSpace: space, work: work, id: id),
  );

  /// 在指定空间新建记忆。
  Future<void> createMemory(
    String space,
    String? work,
    String title,
    String summary,
  ) async {
    await session.memoryCreate(
      selectedSpace: space,
      work: work,
      title: title,
      summary: summary,
    );
  }

  /// 以记录的 updatedAt 做 CAS 修正标题/摘要。
  Future<void> correctMemory(
    String space,
    Map<String, dynamic> row,
    String title,
    String summary,
  ) => session.memoryCorrect(
    selectedSpace: space,
    work: row['workId'] as String?,
    id: row['id'] as String,
    updatedAt: row['updatedAt'] as String,
    title: title,
    summary: summary,
  );

  /// 读取伴侣角色配置。
  Future<Map<String, dynamic>> character() async =>
      _object(await session.characterConfig());

  /// 保存角色配置；只含名称/外观/语音，字段校验在原生层完成。
  Future<void> saveCharacter(Map<String, dynamic> value) async {
    await session.saveCharacter(json: jsonEncode(value));
  }

  /// 导出角色包；名称不进入角色包。
  Future<String> exportCharacter() => session.exportCharacterPack();

  /// 导入角色包；字段校验在原生层完成。
  Future<void> importCharacter(String json) async {
    await session.importCharacterPack(json: json);
  }

  /// Preview is held by Rust for five minutes and is consumed once on confirm.
  ///
  /// 预览由 Rust 持有五分钟，只解析不写库；确认时消费同一份原生解析结果。
  Future<Map<String, dynamic>> previewImport(
    String source,
    String text,
  ) async => _object(await session.previewImport(source: source, text: text));

  /// 取消预览并释放票据；不创建任何导入记录。
  Future<void> cancelImport(String token) => session.cancelImport(token: token);

  /// 确认导入并返回导入的会话数量；票据一次性，过期或重复使用会失败。
  Future<int> confirmImport(String token) =>
      session.confirmImport(token: token);

  /// 本地全文检索已导入会话，返回命中与高亮片段。
  Future<Map<String, dynamic>> searchImported(String text) async =>
      _object(await session.searchImported(text: text));

  /// 读取导入会话中指定序号的消息原文。
  Future<List<dynamic>> importedSource(String sessionId, int sequence) async =>
      jsonDecode(
            await session.importedSource(
              session: sessionId,
              sequence: sequence,
            ),
          )
          as List;

  /// 取下一个未保存为来源的旧想法候选；skip 只在本地跳过。
  Future<Map<String, dynamic>?> ideaCandidate(int skip) async =>
      jsonDecode(await session.ideaCandidate(skip: skip))
          as Map<String, dynamic>?;

  /// 确认候选并保存为来源；以 sessionId 与 messageSeq 定位。
  Future<void> confirmIdea(Map<String, dynamic> candidate, String title) =>
      session.confirmIdea(
        session: candidate['sessionId'] as String,
        sequence: candidate['messageSeq'] as int,
        title: title,
      );

  /// 读取导入会话完整原文。
  Future<String> importedOriginal(String sessionId) =>
      session.importedOriginal(session: sessionId);

  /// 组装 reviewed task 预览材料；不发送请求。
  @override
  Future<Map<String, dynamic>> prepareTask(
    Map<String, dynamic> request,
  ) async => _object(
    await session.prepareReviewedTask(requestJson: jsonEncode(request)),
  );

  /// 发送已预览任务；confirmed 固定为 true，因为发送前已显式确认。
  @override
  Future<Map<String, dynamic>> sendTask(String work, String id) async =>
      _object(
        await session.sendReviewedTask(work: work, id: id, confirmed: true),
      );

  /// 取消或释放 reviewed task 票据。
  @override
  Future<void> cancelTask(String work, String id) =>
      session.cancelReviewedTask(work: work, id: id);
}
