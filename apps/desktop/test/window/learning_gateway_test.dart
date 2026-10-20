// 覆盖学习窗口网关：open 请求参数校验、稳定错误码映射与 fault 传播。
// mock method channel 验证 Dart 协议，不代表真实 WebView2 沙箱或原生清理通过。

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/native/learning_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('paraselene/learning/v1');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'pending navigation is not reported as opened before native completion',
    () async {
      final gateway = NativeLearningGateway();
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'learning_unavailable');
      });
      expect(
        await gateway.open(locale: 'en', title: 'fixture'),
        'learning_unavailable',
      );
    },
  );

  test(
    'runtime failure reaches listeners and a successful reopen clears it',
    () async {
      final gateway = NativeLearningGateway();
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      final fault = gateway.errors.first;
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('fault', 'learning_cleanup_failed'),
        ),
        (_) {},
      );
      expect(await fault, 'learning_unavailable');
      final reopened = gateway.errors.first;
      expect(await gateway.open(locale: 'en', title: 'fixture'), isNull);
      expect(await reopened, isNull);
    },
  );
}
