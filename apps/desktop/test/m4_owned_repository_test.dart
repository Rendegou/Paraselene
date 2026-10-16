import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/workspace/data/real_workspace_repository.dart';
import 'package:paraselene_flutter/workspace/data/workspace_repository.dart';

/// ADR-004 owned store through the real DLL: lifecycle, exact cross-session
/// restore and error mapping. The fixed test-owned store directory is removed
/// before and after the test; it holds synthetic data only.
void main() {
  const storePath =
      r'D:\MyAgent\paraselene-flutter\build\m4-owned-synthetic-v1';

  setUp(() {
    final dir = Directory(storePath);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  tearDown(() {
    final dir = Directory(storePath);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('owned repository persists exact state across real sessions', () async {
    final first = await RealWorkspaceRepository.openOwned(
      diagnosticOverride: true,
    );
    expect(first.mode, WorkspaceMode.realBridge);
    final work = await first.createWork('持久作品');
    final chapter = await first.createChapter(work.id, '第一章');
    final saved = await first.saveDocument(
      work.id,
      chapter.id,
      null,
      '跨进程正文\r\n第二行',
    );
    expect(saved.revision, 1);
    await first.selectWork(work.id);
    await first.setUiSession(
      work.id,
      '{"schemaVersion":1,"chapterId":"${chapter.id}","scrollTop":7}',
    );
    await first.close();

    final second = await RealWorkspaceRepository.openOwned(
      diagnosticOverride: true,
    );
    final state = await second.workspaceState();
    expect(state.selectedWorkId, work.id);
    expect(state.recentWorks.map((w) => w.id), contains(work.id));
    final restored = await second.loadDocument(work.id, chapter.id);
    expect(restored.body, '跨进程正文\r\n第二行');
    expect(restored.revision, 1);
    expect(
      await second.getUiSession(work.id),
      '{"schemaVersion":1,"chapterId":"${chapter.id}","scrollTop":7}',
    );
    await second.close();
  });

  test(
    'owned repository maps unknown works and conflicts to stable codes',
    () async {
      final repo = await RealWorkspaceRepository.openOwned(
        diagnosticOverride: true,
      );
      expect(
        () => repo.selectWork('missing-work'),
        throwsA(
          isA<WorkspaceFailure>().having((f) => f.code, 'code', 'not_found'),
        ),
      );
      final work = await repo.createWork('错误映射');
      final chapter = await repo.createChapter(work.id, '章');
      await repo.saveDocument(work.id, chapter.id, null, 'v1');
      expect(
        () => repo.saveDocument(work.id, chapter.id, 9, 'stale'),
        throwsA(
          isA<WorkspaceFailure>().having(
            (f) => f.code,
            'code',
            'revision_conflict',
          ),
        ),
      );
      await repo.close();
      expect(
        () => repo.listWorks(),
        throwsA(
          isA<WorkspaceFailure>().having(
            (f) => f.code,
            'code',
            'session_closed',
          ),
        ),
      );
    },
  );
}
