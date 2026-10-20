// 讨论与云生成的原生仓库：复用工作区的 CoreSession，不新开写者、不负责关闭会话。
// JSON 编解码在此完成；CAS、作者数据隔离与服务端投影边界由原生层和 Rust 保证。

import 'dart:convert';
import '../native/generated/api.dart';
import 'discussion_repository.dart';
import 'generation_repository.dart';

/// Borrows the workspace session; never opens a second writer or owns close.
///
/// 借用工作区已有的 CoreSession：不新开写者、不负责关闭会话；
/// 参数与返回值的 JSON/Map 在本层转换，原生错误直接向上抛出。
final class NativeDiscussionRepository
    implements DiscussionRepository, GenerationRepository {
  const NativeDiscussionRepository(this.session);
  final CoreSession session;
  List<Map<String, dynamic>> _rows(String json) => (jsonDecode(json) as List)
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList();

  /// 读取章节线程快照行；JSON 数组解码为 Map 列表。
  @override
  Future<List<Map<String, dynamic>>> listThreads(
    String work,
    String chapter,
  ) async =>
      _rows(await session.listThreads(workId: work, documentId: chapter));

  /// CAS 保存作者快照：快照编码为 JSON 交给原生层，返回含新 revision 的行。
  @override
  Future<Map<String, dynamic>> saveThread(
    String work,
    String chapter,
    String id,
    int? revision,
    Map<String, dynamic> snapshot,
  ) async => Map<String, dynamic>.from(
    jsonDecode(
          await session.saveThread(
            workId: work,
            documentId: chapter,
            threadId: id,
            expectedRevision: revision,
            snapshotJson: jsonEncode(snapshot),
          ),
        )
        as Map,
  );

  /// 读取服务端操作投影，不修改作者快照。
  @override
  Future<List<Map<String, dynamic>>> listOperations(
    String work,
    String chapter,
  ) async =>
      _rows(await session.listOperations(workId: work, documentId: chapter));

  /// 采纳操作；revision 为正文 CAS 期望，原子提交由原生层完成。
  @override
  Future<void> applyOperation(
    String work,
    String chapter,
    String id,
    int? revision,
  ) => session.applyOperation(
    workId: work,
    documentId: chapter,
    operationId: id,
    expectedRevision: revision,
  );

  /// 拒绝操作；不改正文，也不影响线程内未发送草稿。
  @override
  Future<void> rejectOperation(String work, String chapter, String id) =>
      session.rejectOperation(
        workId: work,
        documentId: chapter,
        operationId: id,
      );

  /// 绑定云生成作用域；null 表示清空，不发送请求。
  @override
  Future<void> activateScope(String? work, String? chapter) =>
      session.activateGenerationScope(work: work, chapter: chapter);

  /// 预览编码为 JSON 后交给原生层，返回预览与票据；不发送。
  @override
  Future<Map<String, dynamic>> prepare(Map<String, dynamic> request) async =>
      Map<String, dynamic>.from(
        jsonDecode(
              await session.prepareGeneration(requestJson: jsonEncode(request)),
            )
            as Map,
      );

  /// 确认发送已预览请求；confirmed 由调用方显式传 true。
  @override
  Future<void> send(String work, String preview, {required bool confirmed}) =>
      session.sendGeneration(
        work: work,
        previewId: preview,
        confirmed: confirmed,
      );

  /// 取消指定操作/票据。
  @override
  Future<void> cancel(String work, String operation) =>
      session.cancelGeneration(work: work, operationId: operation);

  /// 开关云能力，不读取已有 Key。
  @override
  Future<void> setCloudEnabled(bool enabled) =>
      session.setCloudEnabled(value: enabled);

  /// 写入 Key，只写不读。
  @override
  Future<void> setKey(String key) => session.setDeepseekKey(key: key);

  /// 删除已保存的 Key，不读取原值。
  @override
  Future<void> deleteKey() => session.deleteDeepseekKey();
}
