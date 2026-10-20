// 原生运行时初始化：校验 Windows 环境、定位并加载随身 paraselene_bridge.dll，
// 只初始化一次 FRB，并通过握手校验 API/数据库 schema 与安全能力。
// 本文件不写业务库；初始化失败清空缓存以便重试，store scope 不匹配直接拒绝。

import 'dart:io';
import 'dart:ffi' as ffi;

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import 'generated/api.dart';
import 'generated/frb_generated.dart';

/// Loads only the actual bundled Windows bridge; diagnostic overrides are opt-in.
///
/// 只加载随包分发的 Windows 桥接 DLL；诊断覆盖仅在显式参数下生效。
/// 初始化幂等且可在失败后重试；store scope 与运行模式不匹配时拒绝继续。
final class NativeRuntime {
  static Future<void>? _initialization;
  static int? _storeScope;

  /// Initializes FRB once using an absolute DLL path, failing if unavailable.
  ///
  /// 并发调用共享同一次初始化；失败会清空缓存，允许下次重试。
  /// [testSupport] 与 [diagnosticOverride] 仅测试/诊断使用；运行模式与 DLL 的
  /// store scope 不匹配时抛 bridge_store_scope_mismatch。
  static Future<void> initialize({
    bool diagnosticOverride = false,
    bool testSupport = false,
  }) async {
    final previous = _initialization;
    if (previous != null) {
      await previous;
    } else {
      final pending = _initialize(diagnosticOverride, testSupport);
      _initialization = pending;
      await _resetAfterFailure(pending);
    }
    if (_storeScope != (testSupport ? 2 : 1)) {
      throw StateError('bridge_store_scope_mismatch');
    }
  }

  static Future<void> _resetAfterFailure(Future<void> pending) async {
    try {
      await pending;
    } catch (_) {
      // 失败后清空缓存以便重试；若已被新的初始化替换则保持不变。
      if (identical(_initialization, pending)) _initialization = null;
      rethrow;
    }
  }

  static Future<void> _initialize(
    bool diagnosticOverride,
    bool testSupport,
  ) async {
    if (!Platform.isWindows) throw StateError('windows_required');
    // 诊断覆盖只在显式开启时生效；正常运行只加载随身 DLL。
    final override = diagnosticOverride
        ? Platform.environment['PARASELENE_M1_DLL']
        : null;
    final bundled =
        '${File(Platform.resolvedExecutable).parent.path}'
        '${Platform.pathSeparator}paraselene_bridge.dll';
    final dll = File(override ?? bundled);
    if (!dll.isAbsolute || !await dll.exists()) {
      throw StateError('bridge_dll_missing');
    }
    final library = ffi.DynamicLibrary.open(dll.absolute.path);
    // 加载前先读取 DLL 的 store scope 标记，确保测试与生产存储不会混用。
    final scope = library.lookupFunction<ffi.Uint32 Function(), int Function()>(
      'paraselene_bridge_store_scope_v1',
    )();
    if (scope != (testSupport ? 2 : 1) ||
        (testSupport && (!diagnosticOverride || override == null))) {
      throw StateError('bridge_store_scope_mismatch');
    }
    if (testSupport &&
        !RegExp(
          r'^[0-9a-f]{32}$',
        ).hasMatch(Platform.environment['PARASELENE_M4_RUN_ID'] ?? '')) {
      // 测试模式必须携带 32 位十六进制运行 ID，用于隔离测试存储。
      throw StateError('test_scope_invalid');
    }
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(dll.absolute.path),
    );
    _storeScope = scope;
  }

  /// Rejects incompatible protocol, schema or unsafe backend capabilities.
  ///
  /// 握手必须满足：apiVersion 为 1、schemaVersion 为 12、仅合成存储且云能力关闭；
  /// 任一不满足抛 bridge_contract_mismatch，不继续使用该会话。
  static Future<void> verify(CoreSession session) async {
    final handshake = await session.handshake();
    if (handshake.apiVersion != 1 ||
        handshake.schemaVersion != 12 ||
        !handshake.syntheticOnly ||
        handshake.cloudEnabled) {
      throw StateError('bridge_contract_mismatch');
    }
  }
}
