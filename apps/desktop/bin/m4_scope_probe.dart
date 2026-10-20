import 'dart:io';

import 'package:paraselene_flutter/native/runtime.dart';

/// Preflight only: never opens a session or mutates a store directory.
Future<void> main(List<String> args) async {
  final testSupport = args.contains('--test');
  final expected = args.where((arg) => arg.startsWith('--error='));
  try {
    await NativeRuntime.initialize(
      diagnosticOverride: true,
      testSupport: testSupport,
    );
    if (expected.isNotEmpty) throw StateError('expected_rejection_missing');
    try {
      await NativeRuntime.initialize(
        diagnosticOverride: true,
        testSupport: !testSupport,
      );
      throw StateError('cached_identity_not_checked');
    } on StateError catch (error) {
      if (error.message != 'bridge_store_scope_mismatch') rethrow;
    }
    stdout.writeln('PASS: matching DLL and cached mismatch rejection');
  } on StateError catch (error) {
    if (expected.length == 1 && error.message == expected.single.substring(8)) {
      stdout.writeln('PASS: rejected ${error.message} before session open');
    } else {
      stderr.writeln('FAIL: ${error.message}');
      exitCode = 1;
    }
  }
}
