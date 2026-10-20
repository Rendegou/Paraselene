// 覆盖伴侣窗口网关：configure 请求的版本与外观校验、状态回报与原生 fault 传播。
// 通过 mock method channel 验证 Dart 协议，不代表真实 Win32 伴侣窗口或托盘行为通过。

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/native/companion_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('paraselene/companion/v1');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'native rejection leaves companion disabled and exposes the stable code',
    () async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'companion_unavailable');
      });
      final gateway = NativeCompanionGateway();
      final outcome = await gateway.configure(
        enabled: true,
        appearance: 'moon',
        name: 'fixture',
        openLabel: 'open',
        hideLabel: 'hide',
        quitLabel: 'quit',
      );
      expect(outcome.errorCode, 'companion_unavailable');
      expect(gateway.enabled, isFalse);
    },
  );

  test('runtime native fault disables state and reaches listeners', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {'version': 1, 'visible': true, 'quiet': false},
    );
    final gateway = NativeCompanionGateway();
    await gateway.configure(
      enabled: true,
      appearance: 'moon',
      name: 'fixture',
      openLabel: 'open',
      hideLabel: 'hide',
      quitLabel: 'quit',
    );
    expect(gateway.enabled, isTrue);
    final event = gateway.events.first;
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('fault', 'companion_unavailable'),
      ),
      (_) {},
    );
    expect((await event).errorCode, 'companion_unavailable');
    expect(gateway.enabled, isFalse);
  });
}
