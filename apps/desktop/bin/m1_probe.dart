import 'dart:convert';
import 'dart:io';

import 'package:paraselene_flutter/probe/probe.dart';

/// CLI entry point using the same real-FFI acceptance probe as the application.
Future<void> main(List<String> args) async {
  try {
    final report = await runM1Probe(diagnosticOverride: true);
    stdout.writeln(jsonEncode(report.toJson()));
  } catch (error) {
    stderr.writeln('M1 acceptance FAIL: ${error.runtimeType}');
    exitCode = 1;
  }
}
