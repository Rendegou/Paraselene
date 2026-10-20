// 原生探针的窗口轨迹装饰器：记录窗口控制器调用，便于集成探针断言。
// 仅用于探针诊断，不写入正文或作者数据，也不代表生产窗口行为通过。

import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:window_manager/window_manager.dart';
import 'package:paraselene_flutter/window/desktop_window_controller.dart';

/// Opt-in synthetic-probe diagnostics; never logs manuscript or author data.
DesktopWindowController traceWindow(DesktopWindowController delegate) =>
    _TracedWindow(delegate);

final class _TracedWindow extends DesktopWindowController with WindowListener {
  _TracedWindow(this.delegate) {
    delegate.addListener(notifyListeners);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_pointer);
    windowManager.addListener(this);
  }
  final DesktopWindowController delegate;
  int _events = 0;

  void _log(String event) {
    if (_events++ < 5000) {
      stdout.writeln(
        'WINDOW_TRACE ${DateTime.now().microsecondsSinceEpoch} $event',
      );
    }
  }

  void _pointer(PointerEvent event) {
    if (event is PointerHoverEvent) return;
    _log(
      '${event.runtimeType} x=${event.position.dx} y=${event.position.dy} '
      'buttons=${event.buttons} dx=${event.delta.dx} dy=${event.delta.dy} '
      't=${event.timeStamp.inMicroseconds}',
    );
  }

  Future<void> _bounds(String cause) async {
    try {
      final bounds = await windowManager.getBounds();
      _log(
        '$cause left=${bounds.left} top=${bounds.top} '
        'width=${bounds.width} height=${bounds.height}',
      );
    } catch (error) {
      _log('$cause bounds_error=$error');
    }
  }

  @override
  void onWindowEvent(String eventName) {
    if (const {
      'move',
      'moved',
      'resize',
      'resized',
      'maximize',
      'unmaximize',
    }.contains(eventName)) {
      _log('native_event=$eventName');
      unawaited(_bounds(eventName));
    }
  }

  @override
  bool get available => delegate.available;
  @override
  bool get maximized => delegate.maximized;
  @override
  bool get focused => delegate.focused;
  @override
  bool get actionFailed => delegate.actionFailed;
  @override
  Future<void> initialize() async {
    await delegate.initialize();
    _log('initialized dpr=${windowManager.getDevicePixelRatio()}');
    await _bounds('initialized');
  }

  @override
  Future<void> startDragging() async {
    _log('startDragging begin');
    await delegate.startDragging();
    _log('startDragging end');
    await _bounds('startDragging');
  }

  @override
  Future<void> minimize() => delegate.minimize();
  @override
  Future<void> toggleMaximize() => delegate.toggleMaximize();
  @override
  Future<void> requestClose() => delegate.requestClose();

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_pointer);
    windowManager.removeListener(this);
    delegate.removeListener(notifyListeners);
    delegate.dispose();
    super.dispose();
  }
}
