// 原生关闭守卫：把 Windows WM_CLOSE 转到与框架退出请求相同的决策回调。
//
// 通道名 'paraselene/native_close'；原生侧调用 requestClose，只有回调返回 exit
// 时才真正关闭窗口。守卫启用失败时 ready 以 StateError('native_close_guard_unavailable')
// 结束，上层在 ready 完成前不得打开任何作者会话。
import 'dart:ui' show AppExitResponse;

import 'package:flutter/services.dart';

/// Routes native WM_CLOSE to the same decision used by framework exit requests.
/// No session may open until [ready] confirms the Windows guard is enabled.
///
/// 把原生 WM_CLOSE 路由到与框架退出请求相同的决策回调；[ready] 成功完成之前
/// 不得打开任何作者会话，否则存在绕过保存检查的风险。
final class NativeCloseGuard {
  /// 注册通道处理器并立即启用守卫；原生 requestClose 只在回调返回 exit 时放行。
  NativeCloseGuard(Future<AppExitResponse> Function() request) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'requestClose') throw MissingPluginException();
      return await request() == AppExitResponse.exit;
    });
    ready = _enable();
  }

  static const _channel = MethodChannel('paraselene/native_close');

  /// 守卫启用完成的 Future；失败表示原生侧不可用，调用方必须阻止打开会话。
  late final Future<void> ready;

  Future<void> _enable() async {
    if (await _channel.invokeMethod<bool>('enable') != true) {
      throw StateError('native_close_guard_unavailable');
    }
  }

  /// 移除通道处理器；重复调用安全，之后不再响应原生关闭请求。
  void dispose() => _channel.setMethodCallHandler(null);
}
