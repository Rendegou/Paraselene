import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import 'generated/api.dart';
import 'generated/frb_generated.dart';

/// Loads only the actual bundled Windows bridge; diagnostic overrides are opt-in.
final class NativeRuntime {
  static Future<void>? _initialization;

  /// Initializes FRB once using an absolute DLL path, failing if unavailable.
  static Future<void> initialize({bool diagnosticOverride = false}) {
    final previous = _initialization;
    if (previous != null) return previous;
    final pending = _initialize(diagnosticOverride);
    _initialization = pending;
    return _resetAfterFailure(pending);
  }

  static Future<void> _resetAfterFailure(Future<void> pending) async {
    try {
      await pending;
    } catch (_) {
      if (identical(_initialization, pending)) _initialization = null;
      rethrow;
    }
  }

  static Future<void> _initialize(bool diagnosticOverride) async {
    if (!Platform.isWindows) throw StateError('windows_required');
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
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(dll.absolute.path),
    );
  }

  /// Rejects incompatible protocol, schema or unsafe backend capabilities.
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
