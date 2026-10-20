// 讨论持久化接缝：作者快照与服务端操作保持分离。
// 仅定义接口，不依赖 Flutter、IO 或数据库；实现负责 CAS revision 与稳定错误。

/// Persistence seam: author snapshots and server operations stay separate.
abstract interface class DiscussionRepository {
  /// 读取章节全部作者线程快照行，按作品与章节隔离。
  Future<List<Map<String, dynamic>>> listThreads(String work, String chapter);

  /// 以 [revision] 做 CAS 保存作者快照；null 表示新建，返回含新 revision 的行。
  Future<Map<String, dynamic>> saveThread(
    String work,
    String chapter,
    String id,
    int? revision,
    Map<String, dynamic> snapshot,
  );

  /// 读取服务端生成操作（请求、候选与状态）投影，不修改作者快照。
  Future<List<Map<String, dynamic>>> listOperations(
    String work,
    String chapter,
  );

  /// 采纳指定操作到编辑稿；[revision] 为正文 CAS 期望，由原生层原子提交。
  Future<void> applyOperation(
    String work,
    String chapter,
    String id,
    int? revision,
  );

  /// 只拒绝服务端操作，不修改正文，也不影响线程内未发送草稿。
  Future<void> rejectOperation(String work, String chapter, String id);
}

/// Optional capability on a workspace sharing its existing native writer.
///
/// 工作区可选能力：复用已有原生写者，不额外打开会话。
abstract interface class DiscussionRepositoryProvider {
  DiscussionRepository get discussions;
}
