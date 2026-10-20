// 云生成能力接缝：显式预览、显式确认发送、可取消，不做隐式发送或凭据读取。
// 仅声明接口；额度、付费与错误码语义由原生层和 Rust 承担。

/// Explicit cloud capability. No implicit send, retry, credential read or startup IO.
///
/// 只提供显式云能力：先预览、再确认发送、可取消；不做隐式发送、自动重试、
/// 凭据读取或启动时 IO。
abstract interface class GenerationRepository {
  /// 绑定当前作品/章节作用域；null 表示清空。只改作用域，不发送请求。
  Future<void> activateScope(String? work, String? chapter);

  /// 组装完整预览（模型、预估 token、全部消息）与一次性操作票据；不发送请求。
  Future<Map<String, dynamic>> prepare(Map<String, dynamic> request);

  /// 凭明确认发送已预览请求；[confirmed] 必须为 true 才会真正外发。
  Future<void> send(String work, String preview, {required bool confirmed});

  /// 取消指定操作/票据；不修改作者正文。
  Future<void> cancel(String work, String operation);

  /// 开启或关闭云能力；不读取、不回显已有 Key，关闭后不得外发请求。
  Future<void> setCloudEnabled(bool enabled);

  /// 写入 DeepSeek Key；只写不读，失败以原生错误向上抛出。
  Future<void> setKey(String key);

  /// 删除本机保存的 Key；不读取原值。
  Future<void> deleteKey();
}
