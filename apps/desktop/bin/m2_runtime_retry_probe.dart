import 'dart:convert';
import 'dart:io';

import 'package:paraselene_flutter/native/runtime.dart';

/// Real DLL recovery probe; the caller supplies an absent owned temporary path.
Future<void> main(List<String> args) async {
  if (args.length != 1) throw StateError('source_dll_required');
  final target = File(Platform.environment['PARASELENE_M1_DLL'] ?? '');
  if (!target.isAbsolute || await target.exists()) {
    throw StateError('absent_temporary_dll_path_required');
  }
  final parent = target.parent;
  if (parent.parent.path != Directory.systemTemp.path ||
      !parent.path
          .split(Platform.pathSeparator)
          .last
          .startsWith('paraselene-m2-runtime-')) {
    throw StateError('owned_temporary_directory_required');
  }
  var failed = false;
  try {
    await NativeRuntime.initialize(diagnosticOverride: true);
  } on StateError {
    failed = true;
  }
  if (!failed) throw StateError('missing_dll_did_not_fail');
  await File(args.single).copy(target.path);
  await NativeRuntime.initialize(diagnosticOverride: true);
  stdout.writeln(jsonEncode({'status': 'PASS', 'realDllRetry': true}));
}
