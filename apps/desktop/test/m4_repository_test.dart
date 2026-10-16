import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/workspace/data/real_workspace_repository.dart';
import 'package:paraselene_flutter/workspace/data/synthetic_workspace_repository.dart';
import 'package:paraselene_flutter/workspace/data/workspace_repository.dart';

Matcher code(String value) =>
    throwsA(isA<WorkspaceFailure>().having((e) => e.code, 'code', value));
void contract(String label, Future<WorkspaceRepository> Function() open) {
  test('$label prepared decision rejects changed context and body', () async {
    final r = await open();
    addTearDown(r.close);
    final w = await r.createWork('Review');
    final a = await r.createChapter(w.id, 'A');
    final b = await r.createChapter(w.id, 'B');
    const body = ' e\u0301\r\n😀  ';
    await r.saveDocument(w.id, a.id, null, body);
    final reviewed = await r.prepareConfirmation(w.id, a.id, null, 1);
    expect(reviewed.body.codeUnits, body.codeUnits);
    await r.saveDocument(w.id, b.id, null, 'context');
    await confirmForTest(r, w.id, b.id, null, 1);
    await expectLater(
      r.confirmChapter(w.id, a.id, reviewed.token),
      code('context_conflict'),
    );
    final fresh = await r.prepareConfirmation(w.id, a.id, null, 1);
    await r.saveDocument(w.id, a.id, 1, 'changed');
    await expectLater(
      r.confirmChapter(w.id, a.id, fresh.token),
      code('revision_conflict'),
    );
    for (final raw in [
      '{"schemaVersion":1.0,"scrollTop":0.25}',
      '{"schemaVersion":1}',
    ]) {
      await r.setUiSession(w.id, raw);
      expect(await r.getUiSession(w.id), raw);
    }
    for (final raw in [
      '{"schemaVersion":1,"scrollTop":null}',
      '{"schemaVersion":1,"chapterId":null}',
      '{"schemaVersion":1,"chapterId":5}',
      '{"schemaVersion":1,"wide":"true"}',
      '{"schemaVersion":1,"scrollTop":1e999}',
    ]) {
      await expectLater(r.setUiSession(w.id, raw), code('invalid_input'));
    }
  });
  test(
    '$label two works, CAS, exact text, versions and workspace state',
    () async {
      final r = await open();
      addTearDown(r.close);
      final a = await r.createWork('合成甲');
      final b = await r.createWork('Synthetic B');
      final c = await r.createChapter(a.id, 'one');
      final d = await r.createChapter(a.id, 'two');
      await r.createChapter(b.id, 'one');
      await r.createChapter(b.id, 'two');
      const raw = '  标题\r\ne\u0301\n😀\t\r尾部  ';
      var draft = await r.saveDocument(a.id, c.id, null, raw);
      expect(draft.body.codeUnits, raw.codeUnits);
      expect(draft.revision, 1);
      await expectLater(
        r.saveDocument(a.id, c.id, null, 'stale'),
        code('revision_conflict'),
      );
      draft = await r.saveDocument(a.id, c.id, 1, '');
      expect(draft.body, '');
      expect(draft.revision, 2);
      await expectLater(
        confirmForTest(r, a.id, c.id, null, 2),
        code('invalid_input'),
      );
      draft = await r.saveDocument(a.id, c.id, 2, 'first version');
      final h1 = await confirmForTest(r, a.id, c.id, null, 3);
      expect((await r.loadDocument(a.id, c.id)).revision, 4);
      draft = await r.saveDocument(a.id, c.id, 4, raw);
      expect(draft.baseHeadVersion, h1.headVersionId);
      await expectLater(
        confirmForTest(r, a.id, c.id, 'stale', draft.revision!),
        code('head_conflict'),
      );
      final h2 = await confirmForTest(
        r,
        a.id,
        c.id,
        h1.headVersionId,
        draft.revision!,
      );
      var versions = await r.listVersions(a.id, c.id);
      expect(versions, hasLength(2));
      expect(versions.first.parentVersionId, h1.headVersionId);
      expect(versions.first.body.codeUnits, raw.codeUnits);
      expect(versions.first.isHead, isTrue);
      draft = await r.saveDocument(a.id, c.id, 6, 'discard me');
      await expectLater(
        r.rollbackChapter(a.id, c.id, h1.headVersionId!, h2.headVersionId, 999),
        code('revision_conflict'),
      );
      await r.rollbackChapter(
        a.id,
        c.id,
        h1.headVersionId!,
        h2.headVersionId,
        draft.revision,
      );
      expect((await r.loadDocument(a.id, c.id)).body, 'first version');
      versions = await r.listVersions(a.id, c.id);
      expect(versions, hasLength(2));
      await r.renameChapter(a.id, c.id, 'renamed');
      await r.reorderChapters(a.id, [d.id, c.id]);
      expect((await r.listChapters(a.id)).map((v) => v.id), [d.id, c.id]);
      await expectLater(r.reorderChapters(a.id, [c.id]), code('invalid_input'));
      await r.setChapterArchived(a.id, c.id, true);
      expect((await r.listArchivedChapters(a.id)).single.title, 'renamed');
      expect(await r.listVersions(a.id, c.id), hasLength(2));
      await r.setChapterArchived(a.id, c.id, false);
      expect(await r.listChapters(a.id), hasLength(2));
      expect(await r.listChapters(b.id), hasLength(2));
      await r.selectWork(a.id);
      await r.selectWork(b.id);
      await r.selectWork(a.id);
      final state = await r.workspaceState();
      expect(state.selectedWorkId, a.id);
      expect(state.recentWorks.map((v) => v.id), [a.id, b.id]);
      const ui =
          '{"schemaVersion":1,"chapterId":"c1","wide":true,"scrollTop":42}';
      await r.setUiSession(a.id, ui);
      expect(await r.getUiSession(a.id), ui);
      await expectLater(
        r.setUiSession(a.id, '{"schemaVersion":2}'),
        code('invalid_input'),
      );
      draft = await r.saveDocument(a.id, c.id, null, 'draft');
      await expectLater(
        r.discardDraft(a.id, c.id, 999),
        code('revision_conflict'),
      );
      await r.discardDraft(a.id, c.id, draft.revision);
      expect((await r.loadDocument(a.id, c.id)).body, 'first version');
    },
  );
}

void main() {
  test(
    'actual DLL caller-owned synthetic root survives close and reopens',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'paraselene-m1-m4-reopen-',
      );
      addTearDown(() => root.delete(recursive: true));
      await File(
        '${root.path}/M1_SYNTHETIC_ONLY',
      ).writeAsString('paraselene-m1-synthetic-v1\n');
      var r = await RealWorkspaceRepository.open(
        diagnosticOverride: true,
        syntheticRoot: root,
      );
      final w = await r.createWork('Persistent synthetic');
      final c = await r.createChapter(w.id, 'Empty draft');
      await r.saveDocument(w.id, c.id, null, '');
      await r.close();
      expect(await root.exists(), isTrue);
      r = await RealWorkspaceRepository.open(
        diagnosticOverride: true,
        syntheticRoot: root,
      );
      try {
        final document = await r.loadDocument(w.id, c.id);
        expect(document.body, '');
        expect(document.revision, 1);
      } finally {
        await r.close();
      }
    },
  );
  contract(
    'actual DLL',
    () => RealWorkspaceRepository.open(diagnosticOverride: true),
  );
  contract('synthetic fixture', () async => SyntheticWorkspaceRepository());
}

// Test-only convenience; production UI must retain the preview until the decision.
Future<WorkspaceChapter> confirmForTest(
  WorkspaceRepository r,
  String work,
  String chapter,
  String? head,
  int revision,
) async {
  final review = await r.prepareConfirmation(work, chapter, head, revision);
  return r.confirmChapter(work, chapter, review.token);
}
