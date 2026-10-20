// M1 验收探针入口：对新建的标记临时合成库运行真实 DLL 并汇总报告。
//
// 报告只含状态、计数与 content hash，不含正文、根路径、凭据或作者元数据；
// 无论成功失败都会关闭会话、结清作业并删除临时库，不写作者数据库。
import 'dart:io';

import '../native/generated/api.dart';
import '../native/runtime.dart';
import 'assertions.dart';
import 'documents.dart';
import 'jobs.dart';

/// Safe acceptance result: no body, root path, credentials or author metadata.
///
/// 可安全记录或传输的验收摘要：仅含 content hash、revision 与检查项清单，
/// 不含正文、路径、凭据或作者元数据。
final class ProbeReport {
  const ProbeReport(this.contentHash, this.revision);

  /// 重开验证后得到的正文内容 hash。
  final String contentHash;

  /// 重开验证后得到的 CAS revision 字符串。
  final String revision;

  /// 输出稳定 JSON 形状；status 恒为 PASS，失败由调用方生成其它报告。
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
///
/// 初始化原生运行时并新建带标记的临时合成库，跑文档与作业探针，再重开验证精确
/// 文本与 hash；无论成功失败都会清理会话、作业与临时目录。
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
  // 先验证缺少标记与错误标记都会被拒绝，再写入正确标记，确保合成根校验真实生效。
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
