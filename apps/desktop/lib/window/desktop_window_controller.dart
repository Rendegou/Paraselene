// 窗口壳控制器：抽象窗口能力并给出 Windows window_manager 适配实现。
//
// 只负责窗口效果与状态刷新（最小化、最大化、拖动、关闭请求）；关闭请求一律交给
// 原生保存守卫决定，适配器绝不直接 destroy()。失败只记录诊断并置 actionFailed，
// 不向调用方抛出；标题栏隐藏失败时回退系统标题栏，保证窗口仍可操作。
import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// Window effects only. Close requests must still pass the native save guard.
///
/// 只暴露窗口效果与状态；关闭请求只是请求，是否退出仍须通过原生保存守卫。
abstract class DesktopWindowController extends ChangeNotifier {
  /// 窗口插件是否可用；初始化失败后为 false，界面应退回系统标题栏。
  bool get available;

  /// 窗口当前是否最大化。
  bool get maximized;

  /// 窗口当前是否处于聚焦状态。
  bool get focused;

  /// 最近一次窗口操作是否失败，供界面提示。
  bool get actionFailed;

  /// 初始化窗口插件并安装监听；幂等，可安全地重复 await。
  Future<void> initialize();

  /// 最小化窗口；失败只置 actionFailed。
  Future<void> minimize();

  /// 在最大化与还原之间切换并刷新状态。
  Future<void> toggleMaximize();

  /// 开始系统拖动；由标题栏拖动区调用。
  Future<void> startDragging();

  /// 请求关闭窗口；真正的退出决定由原生保存守卫作出。
  Future<void> requestClose();
}

/// Windows plugin adapter; never owns a close decision or calls destroy().
///
/// Windows 插件适配器：用 window_manager 实现窗口效果与状态刷新；
/// 不拥有关闭决策，也绝不调用 destroy()。
final class ManagedDesktopWindow extends DesktopWindowController
    with WindowListener {
  bool _available = false;
  bool _maximized = false;
  bool _focused = true;
  bool _failed = false;
  bool _disposed = false;
  bool _initialized = false;
  bool _frameRequested = false;
  Future<void>? _restoringFrame;
  int _refreshSequence = 0;
  Future<void>? _initializing;

  @override
  bool get available => _available;
  @override
  bool get maximized => _maximized;
  @override
  bool get focused => _focused;
  @override
  bool get actionFailed => _failed;

  @override
  Future<void> initialize() =>
      _initializing ??
      (_initialized || _disposed
          ? Future<void>.value()
          : _initializing = _initialize().whenComplete(
              () => _initializing = null,
            ));

  Future<void> _initialize() async {
    try {
      await windowManager.ensureInitialized();
      if (_disposed) return;
      windowManager.addListener(this);
      await windowManager.setMinimumSize(const Size(360, 280));
      if (_disposed) return;
      _available = true;
      notifyListeners();
      if (_disposed) return;
      _frameRequested = true;
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      if (_disposed) {
        await _restoreFrame();
        return;
      }
      await _refresh();
      _initialized = true;
    } catch (error, stack) {
      developer.log(
        'window_shell_initialize_failed',
        error: error,
        stackTrace: stack,
      );
      // Keep reachable controls until the system frame has been restored.
      await _restoreFrame();
      _available = false;
      _failed = true;
      _initialized = true;
      windowManager.removeListener(this);
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _restoreFrame() =>
      _restoringFrame ??= windowManager.setTitleBarStyle(TitleBarStyle.normal);

  Future<void> _run(Future<void> Function() action) async {
    if (_disposed) return;
    try {
      await action();
      _failed = false;
    } catch (error, stack) {
      _failed = true;
      developer.log('window_action_failed', error: error, stackTrace: stack);
    }
    if (!_disposed) notifyListeners();
  }

  @override
  Future<void> minimize() => _run(windowManager.minimize);
  @override
  Future<void> startDragging() => _run(windowManager.startDragging);
  @override
  Future<void> requestClose() => _run(windowManager.close);
  @override
  Future<void> toggleMaximize() => _run(() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
    await _refresh();
  });

  Future<void> _refresh() async {
    final sequence = ++_refreshSequence;
    final maximized = await windowManager.isMaximized();
    if (_disposed || sequence != _refreshSequence) return;
    final focused = await windowManager.isFocused();
    if (_disposed || sequence != _refreshSequence) return;
    _maximized = maximized;
    _focused = focused;
    notifyListeners();
  }

  @override
  void onWindowEvent(String eventName) {
    if (const {
      'maximize',
      'unmaximize',
      'restore',
      'focus',
      'blur',
    }.contains(eventName)) {
      unawaited(_run(_refresh));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshSequence++;
    windowManager.removeListener(this);
    if (_frameRequested) {
      unawaited(
        _restoreFrame().catchError((Object error, StackTrace stack) {
          developer.log(
            'window_frame_restore_failed',
            error: error,
            stackTrace: stack,
          );
        }),
      );
    }
    super.dispose();
  }
}
