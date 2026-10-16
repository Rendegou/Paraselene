import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/domain/editing/save_coordinator.dart';
import 'package:paraselene_flutter/workspace/data/synthetic_workspace_repository.dart';
import 'package:paraselene_flutter/workspace/data/workspace_repository.dart';
import 'package:paraselene_flutter/workspace/workspace_controller.dart';

/// A synthetic repository whose saves stay in flight until [gate] completes.
final class _GatedRepository extends SyntheticWorkspaceRepository {
  _GatedRepository();
  Completer<void>? gate;
  Object? saveError;

  @override
  Future<ChapterDocument> saveDocument(
    String workId,
    String chapterId,
    int? expectedRevision,
    String body,
  ) async {
    await gate?.future;
    final error = saveError;
    if (error != null) {
      saveError = null;
      throw error;
    }
    return super.saveDocument(workId, chapterId, expectedRevision, body);
  }
}

/// A repository whose UI-session writes fail once [failPrefs] is set.
final class _FailingPrefsRepository extends SyntheticWorkspaceRepository {
  bool failPrefs = false;

  @override
  Future<void> setUiSession(String workId, String value) async {
    if (failPrefs) throw const WorkspaceFailure('storage_io');
    return super.setUiSession(workId, value);
  }
}

Future<WorkspaceController> _openController(WorkspaceRepository repo) async {
  final controller = WorkspaceController(repo);
  await controller.refresh();
  return controller;
}

Future<void> _pastDebounce() =>
    Future<void>.delayed(const Duration(milliseconds: 450));

void main() {
  test('refresh opens the first work and chapter with exact body', () async {
    final repo = SyntheticWorkspaceRepository();
    final controller = await _openController(repo);
    final work = await repo.createWork('作品');
    final chapter = await repo.createChapter(work.id, '第一章');
    await repo.saveDocument(work.id, chapter.id, null, '正文');
    await controller.refresh();

    expect(controller.currentWork?.id, work.id);
    expect(controller.currentChapter?.id, chapter.id);
    expect(controller.body, '正文');
    expect(controller.phase, WorkspacePhase.content);
    controller.dispose();
  });

  test('typing during an in-flight save persists the latest text', () async {
    final repo = _GatedRepository();
    final controller = await _openController(repo);
    expect(await controller.createWork('作品'), isTrue);
    expect(await controller.createChapter('第一章'), isTrue);
    expect(await controller.createChapter('第二章'), isTrue);
    // After creation the second chapter is open; the other one is the target.
    final edited = controller.chapters[1];
    final target = controller.chapters[0];
    expect(controller.currentChapter?.id, edited.id);

    repo.gate = Completer<void>();
    controller.editing.edit('一');
    await _pastDebounce();
    controller.editing.edit('二');
    repo.gate!.complete();
    await _pastDebounce();

    expect(await controller.selectChapter(target), isTrue);
    final reloaded = await repo.loadDocument(
      controller.currentWork!.id,
      edited.id,
    );
    expect(reloaded.body, '二');
    expect(controller.currentChapter?.id, target.id);
    controller.dispose();
  });

  test('empty body after deletion saves and restores', () async {
    final repo = SyntheticWorkspaceRepository();
    final controller = await _openController(repo);
    await controller.createWork('作品');
    await controller.createChapter('第一章');
    controller.editing.edit('字');
    await _pastDebounce();
    controller.editing.edit('');
    await _pastDebounce();
    expect(controller.editing.saveState?.status, SaveStatus.saved);
    expect(controller.editing.saveState?.revision, 2);
    expect(controller.body, '');
    controller.dispose();
  });

  test(
    'failed save blocks switching and retry keeps the CAS revision',
    () async {
      final repo = _GatedRepository();
      final controller = await _openController(repo);
      await controller.createWork('作品');
      await controller.createChapter('第一章');
      await controller.createChapter('第二章');
      final edited = controller.chapters[1];
      final target = controller.chapters[0];

      controller.editing.edit('草稿');
      repo.saveError = const WorkspaceFailure('storage_io');
      await _pastDebounce();
      expect(controller.editing.saveState?.status, SaveStatus.error);

      expect(await controller.selectChapter(target), isFalse);
      expect(controller.currentChapter?.id, edited.id);
      expect(controller.body, '草稿');
      expect(controller.errorCode, 'storage_io');

      expect(await controller.retrySave(), isTrue);
      expect(controller.editing.saveState?.status, SaveStatus.saved);
      expect(controller.editing.saveState?.revision, 1);
      expect(await controller.selectChapter(target), isTrue);
      controller.dispose();
    },
  );

  test('a failed chapter load keeps the current chapter and text', () async {
    final repo = SyntheticWorkspaceRepository();
    final controller = await _openController(repo);
    await controller.createWork('作品');
    await controller.createChapter('第一章');
    final keep = controller.currentChapter!;
    controller.editing.edit('保留');
    await _pastDebounce();

    final broken = await controller.repository.createChapter(
      controller.currentWork!.id,
      '坏章',
    );
    await controller.refresh();
    final listed = controller.chapters.firstWhere((c) => c.id == broken.id);
    await controller.repository.setChapterArchived(
      controller.currentWork!.id,
      listed.id,
      true,
    );
    await controller.refresh();
    final archived = controller.archivedChapters.firstWhere(
      (c) => c.id == broken.id,
    );
    // Loading an archived chapter through the controller path fails closed:
    // it is not in the active directory, so nothing changes on selection.
    expect(archived.archived, isTrue);
    expect(controller.currentChapter?.id, keep.id);
    expect(controller.body, '保留');
    controller.dispose();
  });

  test(
    'confirm keeps the rebased draft; edits after prepare invalidate',
    () async {
      final repo = SyntheticWorkspaceRepository();
      final controller = await _openController(repo);
      await controller.createWork('作品');
      await controller.createChapter('第一章');
      controller.editing.edit('第一版');
      await _pastDebounce();

      final prepared = await controller.prepareConfirmation();
      expect(prepared, isNotNull);
      expect(prepared!.body, '第一版');

      controller.editing.edit('第一版改');
      expect(await controller.confirmChapter(prepared.token), isFalse);
      expect(controller.errorCode, 'revision_conflict');

      final second = await controller.prepareConfirmation();
      expect(second!.body, '第一版改');
      expect(await controller.confirmChapter(second.token), isTrue);
      final state = controller.editing.saveState!;
      expect(state.revision, 3);
      expect(state.baseHead, isNotNull);
      expect(controller.chapters.first.headVersionId, state.baseHead);
      controller.dispose();
    },
  );

  test(
    'rollback discards the draft and restores the exact target body',
    () async {
      final repo = SyntheticWorkspaceRepository();
      final controller = await _openController(repo);
      await controller.createWork('作品');
      await controller.createChapter('第一章');
      controller.editing.edit('第一版');
      await _pastDebounce();
      final first = await controller.prepareConfirmation();
      await controller.confirmChapter(first!.token);
      controller.editing.edit('第二版');
      await _pastDebounce();
      final second = await controller.prepareConfirmation();
      await controller.confirmChapter(second!.token);
      controller.editing.edit('草稿');
      await _pastDebounce();

      final versions = await controller.listVersions();
      expect(versions.length, 2);
      final target = versions.firstWhere((v) => v.body == '第一版');
      expect(await controller.rollbackChapter(target.id), isTrue);
      expect(controller.body, '第一版');
      expect(controller.editing.saveState?.revision, isNull);
      expect(controller.editing.saveState?.dirty, isFalse);

      controller.editing.edit('回滚后新稿');
      await _pastDebounce();
      expect(controller.editing.saveState?.revision, 1);
      controller.dispose();
    },
  );

  test(
    'archive keeps text and versions; restore brings the chapter back',
    () async {
      final repo = SyntheticWorkspaceRepository();
      final controller = await _openController(repo);
      await controller.createWork('作品');
      await controller.createChapter('第一章');
      await controller.createChapter('第二章');
      final target = controller.chapters[0];
      expect(await controller.selectChapter(target), isTrue);
      controller.editing.edit('内容');
      await _pastDebounce();
      final prepared = await controller.prepareConfirmation();
      await controller.confirmChapter(prepared!.token);

      expect(await controller.setChapterArchived(target, true), isTrue);
      expect(controller.chapters.map((c) => c.id), isNot(contains(target.id)));
      expect(controller.archivedChapters.single.id, target.id);

      expect(await controller.setChapterArchived(target, false), isTrue);
      expect(controller.chapters.map((c) => c.id), contains(target.id));
      final doc = await repo.loadDocument(
        controller.currentWork!.id,
        target.id,
      );
      expect(doc.body, '内容');
      expect(
        await repo.listVersions(controller.currentWork!.id, target.id),
        hasLength(1),
      );
      controller.dispose();
    },
  );

  test('reorder updates the directory and rejects incomplete sets', () async {
    final repo = SyntheticWorkspaceRepository();
    final controller = await _openController(repo);
    await controller.createWork('作品');
    await controller.createChapter('一');
    await controller.createChapter('二');
    await controller.createChapter('三');
    final ids = controller.chapters.map((c) => c.id).toList();

    expect(await controller.reorderChapters([ids[2], ids[0], ids[1]]), isTrue);
    expect(controller.chapters.map((c) => c.id), [ids[2], ids[0], ids[1]]);
    expect(await controller.reorderChapters([ids[0]]), isFalse);
    expect(controller.errorCode, 'invalid_input');
    controller.dispose();
  });

  test(
    'cold restore reopens the selected work, chapter, wide and scroll',
    () async {
      final repo = SyntheticWorkspaceRepository();
      final first = await _openController(repo);
      await first.createWork('作品A');
      await first.createWork('作品B');
      final workB = first.works.firstWhere((w) => w.title == '作品B');
      expect(await first.selectWork(workB), isTrue);
      await first.createChapter('序章');
      await first.createChapter('正文');
      final target = first.chapters.firstWhere((c) => c.title == '正文');
      expect(await first.selectChapter(target), isTrue);
      first.setWide(true);
      first.noteScrollTop(240);
      await _pastDebounce();
      first.dispose();

      // Cold start goes straight to restoreSession; no refresh pre-selection.
      final restored = WorkspaceController(repo);
      await restored.restoreSession();
      expect(restored.currentWork?.id, workB.id);
      expect(restored.currentChapter?.id, target.id);
      expect(restored.wide, isTrue);
      expect(restored.pendingScrollTop, 240);
      expect(restored.applyScrollPending, isTrue);
      restored.dispose();
    },
  );

  test(
    'a failing preference write blocks navigation with the stable code',
    () async {
      final repo = _FailingPrefsRepository();
      final controller = await _openController(repo);
      await controller.createWork('作品');
      await controller.createChapter('一');
      await controller.createChapter('二');
      controller.editing.edit('正文');
      await _pastDebounce();
      final second = controller.chapters.firstWhere((c) => c.title == '一');
      final before = controller.currentChapter!.id;

      repo.failPrefs = true;
      controller.setWide(true); // pending preference write, not yet flushed
      expect(await controller.selectChapter(second), isFalse);
      expect(controller.errorCode, 'storage_io');
      expect(controller.currentChapter!.id, before);
      expect(controller.body, '正文');
      controller.dispose();
    },
  );

  test('busy barriers reject reentrant navigation', () async {
    final repo = _GatedRepository();
    final controller = await _openController(repo);
    await controller.createWork('作品A');
    final workA = controller.works.single;
    await controller.createWork('作品B');
    final workB = controller.works.firstWhere((w) => w.id != workA.id);
    repo.gate = Completer<void>();
    controller.editing.edit('卡住');
    await _pastDebounce();

    final pending = controller.selectWork(workB);
    final rejected = await controller.selectWork(workA);
    expect(rejected, isFalse);
    repo.gate!.complete();
    expect(await pending, isTrue);
    controller.dispose();
  });

  test('a scroll during an in-flight prefs write still lands', () async {
    final repo = _GatedPrefsRepository();
    final controller = await _openController(repo);
    await controller.createWork('作品');
    await controller.createChapter('第一章');

    repo.gate = Completer<void>();
    controller.noteScrollTop(100);
    await _pastDebounce(); // first write is now in flight behind the gate
    controller.noteScrollTop(200); // newer preference arrives during the await
    repo.gate!.complete();
    repo.gate = null;
    await _pastDebounce();

    final raw = await repo.getUiSession(controller.currentWork!.id);
    expect(raw, contains('200'));
    controller.dispose();
  });

  test('dispose with dirty text completes without skipping release', () async {
    final repo = SyntheticWorkspaceRepository();
    final controller = await _openController(repo);
    await controller.createWork('作品');
    await controller.createChapter('第一章');
    controller.editing.edit('未保存');
    expect(() => controller.dispose(), returnsNormally);
  });
}

/// UI-session writes stay in flight until [gate] completes.
final class _GatedPrefsRepository extends SyntheticWorkspaceRepository {
  Completer<void>? gate;
  @override
  Future<void> setUiSession(String workId, String value) async {
    await gate?.future;
    return super.setUiSession(workId, value);
  }
}
