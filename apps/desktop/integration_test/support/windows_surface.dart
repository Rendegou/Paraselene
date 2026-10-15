import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:ui';

/// Native test-only resize. Never targets a window belonging to another process.
/// https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-setwindowpos
final class WindowsSurface {
  final _user = DynamicLibrary.open('user32.dll');
  final _crt = DynamicLibrary.open('ucrtbase.dll');
  late final _allocate = _crt
      .lookupFunction<
        Pointer<Void> Function(IntPtr, IntPtr),
        Pointer<Void> Function(int, int)
      >('calloc');
  late final _free = _crt
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('free');
  late final _find = _user
      .lookupFunction<
        IntPtr Function(IntPtr, IntPtr, Pointer<Uint16>, Pointer<Uint16>),
        int Function(int, int, Pointer<Uint16>, Pointer<Uint16>)
      >('FindWindowExW');
  late final _process = _user
      .lookupFunction<
        Uint32 Function(IntPtr, Pointer<Uint32>),
        int Function(int, Pointer<Uint32>)
      >('GetWindowThreadProcessId');
  late final _rect = _user
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<Int32>),
        int Function(int, Pointer<Int32>)
      >('GetClientRect');
  late final _position = _user
      .lookupFunction<
        Int32 Function(IntPtr, IntPtr, Int32, Int32, Int32, Int32, Uint32),
        int Function(int, int, int, int, int, int, int)
      >('SetWindowPos');

  late final int handle = _findOwnedWindow();

  int _findOwnedWindow() {
    final name = 'FLUTTER_RUNNER_WIN32_WINDOW'.codeUnits;
    final windowClass = _allocate(name.length + 1, 2).cast<Uint16>();
    final process = _allocate(1, 4).cast<Uint32>();
    if (windowClass == nullptr || process == nullptr) {
      _free(windowClass.cast());
      _free(process.cast());
      throw StateError('allocation_failed');
    }
    try {
      windowClass.asTypedList(name.length).setAll(0, name);
      var window = 0;
      while ((window = _find(0, window, windowClass, nullptr)) != 0) {
        _process(window, process);
        if (process.value == pid) return window;
      }
      throw StateError('owned_window_not_found');
    } finally {
      _free(windowClass.cast());
      _free(process.cast());
    }
  }

  /// Requests asynchronous native resize in physical pixels without activation.
  void resize(int width, int height) {
    if (_position(handle, 0, 0, 0, width, height, 0x4016) == 0) {
      throw StateError('native_resize_failed');
    }
  }

  Size get clientSize {
    final rect = _allocate(4, 4).cast<Int32>();
    if (rect == nullptr) throw StateError('allocation_failed');
    try {
      if (_rect(handle, rect) == 0) throw StateError('native_rect_failed');
      return Size(
        (rect[2] - rect[0]).toDouble(),
        (rect[3] - rect[1]).toDouble(),
      );
    } finally {
      _free(rect.cast());
    }
  }
}
