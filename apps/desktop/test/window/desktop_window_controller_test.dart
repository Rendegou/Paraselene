// 覆盖桌面窗口控制器：关闭请求不越权销毁、可用性恢复与延迟释放。
// mock window_manager 通道验证协议，不代表真实 Win32 窗口生命周期通过。

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/window/desktop_window_controller.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('window_manager');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  var maximized = false;
  var failHidden = false;
  Completer<void>? pending;
  Completer<void>? pendingHidden;

  setUp(() {
    calls.clear();
    maximized = false;
    failHidden = false;
    pending = null;
    pendingHidden = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'setMinimumSize') await pending?.future;
      if (call.method == 'setTitleBarStyle' &&
          (call.arguments as Map)['titleBarStyle'] == 'hidden') {
        await pendingHidden?.future;
      }
      if (call.method == 'setTitleBarStyle' &&
          (call.arguments as Map)['titleBarStyle'] == 'hidden' &&
          failHidden) {
        throw PlatformException(code: 'hidden_failed');
      }
      if (call.method == 'maximize') maximized = true;
      if (call.method == 'unmaximize') maximized = false;
      if (call.method == 'isMaximized') return maximized;
      if (call.method == 'isFocused') return true;
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('close requests close, never destroy or a second close owner', () async {
    final window = ManagedDesktopWindow();
    addTearDown(window.dispose);
    await window.initialize();
    await window.requestClose();
    expect(calls.where((c) => c.method == 'close'), hasLength(1));
    expect(
      calls.any((c) => c.method == 'destroy' || c.method == 'setPreventClose'),
      isFalse,
    );
    await window.toggleMaximize();
    expect(window.maximized, isTrue);
    await window.toggleMaximize();
    expect(window.maximized, isFalse);
  });

  test(
    'initialization is shared and late disposal never hides the frame',
    () async {
      pending = Completer<void>();
      final window = ManagedDesktopWindow();
      final first = window.initialize();
      final second = window.initialize();
      expect(identical(first, second), isTrue);
      // Reach the pending minimum-size platform response.
      await Future<void>.delayed(Duration.zero);
      window.dispose();
      pending!.complete();
      await first;
      expect(calls.any((c) => c.method == 'setTitleBarStyle'), isFalse);
      expect(windowManager.listeners, isNot(contains(window)));
      await window.requestClose();
      expect(calls.any((c) => c.method == 'close'), isFalse);
    },
  );

  test(
    'disposal during hidden response restores frame without late queries',
    () async {
      pendingHidden = Completer<void>();
      final window = ManagedDesktopWindow();
      final initialization = window.initialize();
      await Future<void>.delayed(Duration.zero);
      expect(calls.where((c) => c.method == 'setTitleBarStyle'), hasLength(1));
      window.dispose();
      pendingHidden!.complete();
      await initialization;
      expect(
        calls
            .where((c) => c.method == 'setTitleBarStyle')
            .map((c) => (c.arguments as Map)['titleBarStyle']),
        ['hidden', 'normal'],
      );
      expect(calls.any((c) => c.method == 'isMaximized'), isFalse);
    },
  );

  test('scheduled disposal after availability restores the frame', () async {
    final window = ManagedDesktopWindow();
    window.addListener(() => scheduleMicrotask(window.dispose));
    await window.initialize();
    expect(
      calls
          .where((c) => c.method == 'setTitleBarStyle')
          .map((c) => (c.arguments as Map)['titleBarStyle']),
      ['hidden', 'normal'],
    );
    expect(windowManager.listeners, isNot(contains(window)));
  });

  test(
    'hidden-frame failure restores system controls and removes listener',
    () async {
      failHidden = true;
      final window = ManagedDesktopWindow();
      addTearDown(window.dispose);
      await window.initialize();
      expect(window.available, isFalse);
      expect(window.actionFailed, isTrue);
      expect(windowManager.listeners, isNot(contains(window)));
      final styles = calls
          .where((c) => c.method == 'setTitleBarStyle')
          .map((c) => (c.arguments as Map)['titleBarStyle']);
      expect(styles, ['hidden', 'normal']);
    },
  );
}
