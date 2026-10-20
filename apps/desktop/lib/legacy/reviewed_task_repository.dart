// reviewed task 持久化接缝：固定任务种类的预览、发送与取消。
// 实现不得隐式发送；发送必须发生在显式确认之后。

/// Fixed native reviewed tasks; implementations must never implicitly send.
///
/// 固定种类的 reviewed task 接缝；实现不得隐式发送，发送必须发生在显式确认之后。
abstract interface class ReviewedTaskRepository {
  /// 组装预览材料与票据；不发送请求。
  Future<Map<String, dynamic>> prepareTask(Map<String, dynamic> request);

  /// 发送已预览任务，返回场景、草稿或摘要结果。
  Future<Map<String, dynamic>> sendTask(String work, String id);

  /// 释放票据或取消进行中的任务。
  Future<void> cancelTask(String work, String id);
}
