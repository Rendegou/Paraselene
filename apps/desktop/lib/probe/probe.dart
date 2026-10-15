import 'dart:io';

import '../native/generated/api.dart';
import '../native/runtime.dart';
import 'assertions.dart';
import 'documents.dart';
import 'jobs.dart';

/// Safe acceptance result: no body, root path, credentials or author metadata.
final class ProbeReport {
  const ProbeReport(this.contentHash, this.revision);
  final String contentHash;
  final String revision;

  Map<String, Object> toJson() => {
    'status': 'PASS',
    'syntheticOnly': true,
    'cloudEnabled': false,
    'apiVersion': 1,
    'schemaVersion': 12,
    'works': 2,
    'chapters': 1,
    'contentHash': contentHash,
    'revision': revision,
    'checks': [
      'unicode_reopen',
      'revision_conflict',
      'identity_mismatch',
      'session_closed',
      'cloud_disabled',
      'cancelled',
      'closed',
      'bounded_notifications',
      'authoritative_status',
      'unsubscribe',
      'invalid_synthetic_root',
    ],
  };
}

/// Runs the actual DLL against a new marked temporary synthetic database.
Future<ProbeReport> runM1Probe({bool diagnosticOverride = false}) async {
  await NativeRuntime.initialize(diagnosticOverride: diagnosticOverride);
  final root = await Directory.systemTemp.createTemp('paraselene-m1-');
  final sessions = <CoreSession>[];
  final jobs = ProbeJobs();
  try {
    await _prepareRoot(root);
    final first = await CoreSession.openSynthetic(root: root.path);
    sessions.add(first);
    await NativeRuntime.verify(first);
    final second = await CoreSession.openSynthetic(root: root.path);
    sessions.add(second);
    final document = await probeDocuments(first, second);
    await expectBridgeError('cloud_disabled', first.send);
    await jobs.exercise(first);
    await first.close();
    await expectBridgeError('session_closed', first.listWorks);
    await second.close();
    final reopened = await CoreSession.openSynthetic(root: root.path);
    sessions.add(reopened);
    await NativeRuntime.verify(reopened);
    final loaded = await reopened.load(
      workId: document['workId']! as String,
      documentId: document['chapterId']! as String,
    );
    require(loaded.body == syntheticBody, 'reopen_exact_text');
    require(loaded.contentHash == document['contentHash'], 'reopen_hash');
    return ProbeReport(loaded.contentHash!, loaded.revision!.toString());
  } finally {
    await _cleanup(root, sessions, jobs);
  }
}

Future<void> _prepareRoot(Directory root) async {
  final marker = File('${root.path}/M1_SYNTHETIC_ONLY');
  await expectBridgeError(
    'invalid_synthetic_root',
    () => CoreSession.openSynthetic(root: root.path),
  );
  await marker.writeAsString('invalid marker', flush: true);
  await expectBridgeError(
    'invalid_synthetic_root',
    () => CoreSession.openSynthetic(root: root.path),
  );
  await marker.writeAsString('paraselene-m1-synthetic-v1\n', flush: true);
}

Future<void> _cleanup(
  Directory root,
  List<CoreSession> sessions,
  ProbeJobs jobs,
) async {
  try {
    try {
      await Future.wait(
        sessions.map((session) => session.close()),
        eagerError: false,
      );
    } finally {
      await jobs.settle();
    }
  } finally {
    for (final session in sessions) {
      session.dispose();
    }
    await root.delete(recursive: true);
  }
}
