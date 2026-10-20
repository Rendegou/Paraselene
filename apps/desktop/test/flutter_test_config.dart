// 全局测试配置：为 widget 测试安装关闭确认通道的 mock，避免依赖原生 runner。
// mock 只验证 Dart 关闭决策，绝不代表原生 WM_CLOSE 拦截或保存屏障通过。

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests verify Dart close decisions; this mock never proves native WM_CLOSE.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('paraselene/native_close'),
        (call) async => call.method == 'enable' ? true : null,
      );
  await testMain();
}
