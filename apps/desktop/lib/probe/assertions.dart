// M1 验收探针断言：任何合同不满足立即抛 StateError，不输出合成正文内容。
//
// 只读诊断工具，不写库、不接触作者数据；用于把真实 DLL 的行为收敛成稳定断言。
import '../native/generated/api/models.dart';

/// Stops acceptance on a failed contract without exposing synthetic text.
///
/// 合同不满足时立即以 [contract] 作为 StateError 消息终止验收；
/// 断言消息只含合同名，绝不暴露合成正文。
void require(bool condition, String contract) {
  if (!condition) throw StateError(contract);
}

/// Requires the stable typed Rust failure, never an arbitrary exception.
///
/// 要求操作以稳定类型的 BridgeError 失败且错误码等于 [code]；其它异常或
/// 意外成功都会转成 StateError 并终止验收。
Future<void> expectBridgeError(
  String code,
  Future<Object?> Function() action,
) async {
  try {
    await action();
  } on BridgeError catch (error) {
    require(error.code == code, 'wrong_error_$code');
    return;
  }
  throw StateError('missing_error_$code');
}
