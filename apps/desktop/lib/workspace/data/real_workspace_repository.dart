import 'dart:io';

import '../../native/generated/api.dart';
import '../../native/generated/api/models.dart';
import '../../native/runtime.dart';
import 'demo_content.dart';
import 'workspace_repository.dart';

/// Owns one verified native session and its newly created synthetic-only root.
final class RealWorkspaceRepository implements WorkspaceRepository {
  RealWorkspaceRepository._(this._root, this._session);
  final Directory _root;
  final CoreSession _session;
  Future<void>? _closing;
  bool _seeded = false;
  String? _demoWorkId;
  String? _demoChapterId;
  Future<void>? _seeding;

  @override
  WorkspaceMode get mode => WorkspaceMode.realBridge;

  /// Fails closed if the actual DLL or handshake is unavailable.
  static Future<RealWorkspaceRepository> open({
    bool diagnosticOverride = false,
  }) async {
    Directory? root;
    CoreSession? session;
    try {
      await NativeRuntime.initialize(diagnosticOverride: diagnosticOverride);
      root = await Directory.systemTemp.createTemp('paraselene-m1-');
      await File(
        '${root.path}/M1_SYNTHETIC_ONLY',
      ).writeAsString('paraselene-m1-synthetic-v1\n', flush: true);
      session = await CoreSession.openSynthetic(root: root.path);
      await NativeRuntime.verify(session);
      return RealWorkspaceRepository._(root, session);
    } catch (error) {
      try {
        if (session != null) await session.close();
      } finally {
        session?.dispose();
        if (root != null) await root.delete(recursive: true);
      }
      throw _failure(error);
    }
  }

  static WorkspaceFailure _failure(Object error) {
    if (error is WorkspaceFailure) return error;
    if (error is BridgeError) return WorkspaceFailure(error.code);
    if (error is StateError) return WorkspaceFailure(error.message.toString());
    return const WorkspaceFailure('bridge_unavailable');
  }

  Future<T> _run<T>(Future<T> Function() action) async {
    if (_closing != null) throw const WorkspaceFailure('session_closed');
    try {
      return await action();
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<List<WorkspaceWork>> listWorks() => _run(() async {
    final works = await _session.listWorks();
    return List.unmodifiable(
      works.map((work) => WorkspaceWork(id: work.id, title: work.title)),
    );
  });

  @override
  Future<List<WorkspaceChapter>> listChapters(String workId) => _run(() async {
    final chapters = await _session.listChapters(workId: workId);
    return List.unmodifiable(
      chapters.map(
        (chapter) => WorkspaceChapter(id: chapter.id, title: chapter.title),
      ),
    );
  });

  @override
  Future<String> loadBody(String workId, String chapterId) => _run(() async {
    final document = await _session.load(workId: workId, documentId: chapterId);
    return document.body;
  });

  @override
  Future<void> seedDemo() =>
      _seeding ??= _run(_seedDemo).whenComplete(() => _seeding = null);

  Future<void> _seedDemo() async {
    if (_seeded) return;
    // Each successful native stage survives a later failure in this session.
    // The bridge has separate commits; this is resumable, not atomic.
    _demoWorkId ??= (await _session.createWork(title: '雨后的书店')).id;
    _demoChapterId ??= (await _session.createChapter(
      workId: _demoWorkId!,
      title: '第一章 · 归途',
    )).id;
    await _session.save(
      workId: _demoWorkId!,
      documentId: _demoChapterId!,
      body: demoBody,
    );
    _seeded = true;
  }

  @override
  Future<void> close() => _closing ??= _cleanup();

  Future<void> _cleanup() async {
    try {
      await _session.close();
    } finally {
      _session.dispose();
      await _root.delete(recursive: true);
    }
  }
}
