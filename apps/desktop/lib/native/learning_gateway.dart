// 学习练习原生网关：只暴露固定 open 方法，不提供通用执行、脚本或路径能力。
// 不写库；错误通过返回值与 errors 流暴露稳定错误码。

import 'dart:async';
import 'package:flutter/services.dart';
import '../legacy/learning_service.dart';

/// No generic execute/evaluate/script/path methods are exposed to Flutter.
///
/// 只暴露固定 open 方法，不提供通用执行、脚本或路径能力；不写库。
final class NativeLearningGateway implements LearningService {
  NativeLearningGateway() {
    _channel.setMethodCallHandler((call) async {
      // 原生故障只广播错误码，不影响其他能力。
      if (call.method == 'fault') _errors.add('learning_unavailable');
    });
  }
  final _errors = StreamController<String?>.broadcast(sync: true);

  /// 原生故障码流；null 表示最近一次调用成功。
  @override
  Stream<String?> get errors => _errors.stream;
  static const _channel = MethodChannel('paraselene/learning/v1');

  /// 打开隔离练习窗口；返回稳定错误码，null 表示成功。
  @override
  Future<String?> open({required String locale, required String title}) async {
    try {
      await _channel.invokeMethod<void>('open', {
        'locale': locale,
        'title': title,
      });
      _errors.add(null);
      return null;
    } on PlatformException catch (failure) {
      // 原生错误码直接作为稳定错误返回。
      return failure.code;
    } on MissingPluginException {
      return 'learning_unavailable';
    }
  }
}
