// 覆盖 M4 关闭控制器：脏状态屏障、偏好保存竞态与可重试失败路径。
// 使用合成仓库与可控 Completer，不代表真实 Rust 事务或 Windows 关闭时序通过。

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/workspace/data/synthetic_workspace_repository.dart';
import 'package:paraselene_flutter/workspace/data/workspace_repository.dart';
import 'package:paraselene_flutter/workspace/workspace_controller.dart';

class RaceRepository extends SyntheticWorkspaceRepository {
  Completer<void>? prefsGate;
  Completer<void>? restoreGate;
  Completer<void>? seedGate;
  Completer<void>? loadGate;
  final prefsEntered = Completer<void>();
  final restoreEntered = Completer<void>();
  final seedEntered = Completer<void>();
  final loadEntered = Completer<void>();
  String? brokenWork;
  bool failPrefs = false;
  int activeWrites = 0;
  int maxWrites = 0;
  int closes = 0;
  final writes = <String>[];
  final saved = <String>[];

  @override
  Future<void> setUiSession(String workId, String value) async {
    activeWrites++;
    if (activeWrites > maxWrites) maxWrites = activeWrites;
    if (!prefsEntered.isCompleted) prefsEntered.complete();
    try {
      await prefsGate?.future;
      if (failPrefs) throw const WorkspaceFailure('storage_io');
      writes.add(value);
      await super.setUiSession(workId, value);
    } finally {
      activeWrites--;
    }
  }

  @override
  Future<ChapterDocument> saveDocument(
    String w,
    String c,
    int? r,
    String body,
  ) {
    saved.add(body);
    return super.saveDocument(w, c, r, body);
  }

  @override
  Future<WorkspaceState> workspaceState() async {
    if (!restoreEntered.isCompleted) restoreEntered.complete();
    await restoreGate?.future;
    return super.workspaceState();
  }

  @override
  Future<void> seedDemo() async {
    if (!seedEntered.isCompleted) seedEntered.complete();
    await seedGate?.future;
    await super.seedDemo();
  }

  @override
  Future<ChapterDocument> loadDocument(String w, String c) async {
    if (!loadEntered.isCompleted) loadEntered.complete();
    await loadGate?.future;
    if (w == brokenWork) throw const WorkspaceFailure('storage_io');
    return super.loadDocument(w, c);
  }

  @override
  Future<void> close() async {
    closes++;
    await super.close();
  }
}

Future<WorkspaceController> open(RaceRepository repo) async {
  final work = await repo.createWork('A');
  await repo.createChapter(work.id, 'one');
  await repo.createChapter(work.id, 'two');
  final c = WorkspaceController(repo);
  await c.refresh();
  return c;
}

void main() {
  for (final failPreferences in [true, false]) {
    test(
      'two synchronous listeners share failed close flight (prefs=$failPreferences)',
      () async {
        final repo = ReentrantRepository();
        final c = await open(repo);
        repo.failNextPrefs = failPreferences;
        repo.failNextClose = !failPreferences;
        c.setWide(true);
        Future<bool>? fromFirst;
        Future<bool>? fromSecond;
        void firstListener() {
          if (c.isBusy && fromFirst == null) fromFirst = c.closeBarrier();
        }

        void secondListener() {
          if (c.isBusy && fromSecond == null) fromSecond = c.closeBarrier();
        }

        c.addListener(firstListener);
        c.addListener(secondListener);
        final outer = c.closeBarrier();
        expect(await outer, isFalse);
        expect(identical(fromFirst, outer), isTrue);
        expect(identical(fromSecond, outer), isTrue);
        expect(await fromFirst!, isFalse);
        expect(await fromSecond!, isFalse);
        expect(repo.closeAttempts, failPreferences ? 0 : 1);
        expect(repo.closes, 0);
        expect(c.wide, isTrue);
        expect(c.errorCode, 'storage_io');
        c.removeListener(firstListener);
        c.removeListener(secondListener);
        // Only this explicit subsequent request may retry and close.
        expect(await c.closeBarrier(), isTrue);
        expect(repo.closeAttempts, failPreferences ? 1 : 2);
        expect(repo.closes, 1);
        c.dispose();
      },
    );
  }

  test(
    'timer and navigation share one prefs drain including late scroll/text',
    () async {
      final repo = RaceRepository();
      final c = await open(repo);
      final first = c.currentChapter!;
      repo.prefsGate = Completer<void>();
      c.noteScrollTop(12.5);
      await repo.prefsEntered.future; // debounce writer owns the flight
      final navigation = c.selectChapter(c.chapters.last);
      await Future<void>.delayed(Duration.zero);
      c.noteScrollTop(99.75);
      c.editing.edit('late text during preferences await');
      repo.prefsGate!.complete();
      expect(await navigation, isTrue);
      expect(repo.maxWrites, 1);
      expect(jsonDecode(repo.writes.last)['scrollTop'], 99.75);
      expect(jsonDecode(repo.writes.last)['chapterId'], first.id);
      expect(repo.saved.last, 'late text during preferences await');
      c.dispose();
    },
  );

  test(
    'prefs failure preserves identity and late text; next retry drains',
    () async {
      final repo = RaceRepository();
      final c = await open(repo);
      final first = c.currentChapter!;
      repo.prefsGate = Completer<void>();
      repo.failPrefs = true;
      c.setWide(true);
      final navigation = c.selectChapter(c.chapters.last);
      await repo.prefsEntered.future;
      c.noteScrollTop(42.25);
      c.editing.edit('retained');
      repo.prefsGate!.complete();
      expect(await navigation, isFalse);
      expect(c.currentChapter!.id, first.id);
      expect(c.body, 'retained');
      expect(c.wide, isTrue);
      expect(c.pendingScrollTop, 42.25);
      repo.failPrefs = false;
      expect(await c.selectChapter(c.chapters.last), isTrue);
      expect(repo.saved.last, 'retained');
      c.dispose();
    },
  );

  test(
    'failed work body load preserves old identity directory and preferences',
    () async {
      final repo = RaceRepository();
      final c = await open(repo);
      final old = c.currentWork!;
      final chapter = c.currentChapter!;
      c.editing.edit('old body');
      c.setWide(true);
      c.noteScrollTop(13.5);
      final other = await repo.createWork('B');
      await repo.createChapter(other.id, 'other');
      repo.brokenWork = other.id;
      expect(await c.selectWork(other), isFalse);
      expect(c.currentWork!.id, old.id);
      expect(c.currentChapter!.id, chapter.id);
      expect(c.editing.document!.workId, old.id);
      expect(c.chapters.first.id, chapter.id);
      expect(c.body, 'old body');
      expect(c.wide, isTrue);
      expect(c.pendingScrollTop, 13.5);
      expect((await repo.workspaceState()).selectedWorkId, old.id);
      c.dispose();
    },
  );

  test(
    'restore rejects navigation; duplicate close waits then drains',
    () async {
      final repo = RaceRepository();
      final work = await repo.createWork('A');
      await repo.createChapter(work.id, 'one');
      repo.restoreGate = Completer<void>();
      final c = WorkspaceController(repo);
      final restore = c.restoreSession();
      await repo.restoreEntered.future;
      expect(await c.selectWork(work), isFalse);
      final close = c.closeBarrier();
      final duplicate = c.closeBarrier();
      expect(identical(close, duplicate), isTrue);
      expect(repo.closes, 0);
      repo.restoreGate!.complete();
      await restore;
      expect(await close, isTrue);
      expect(repo.closes, 1);
      c.dispose();
    },
  );

  test(
    'close rechecks late body and scroll while prefs writer is awaited',
    () async {
      final repo = RaceRepository();
      final c = await open(repo);
      repo.prefsGate = Completer<void>();
      c.noteScrollTop(1.5);
      final close = c.closeBarrier();
      await repo.prefsEntered.future;
      c.editing.edit('last input before close');
      c.noteScrollTop(81.125);
      expect(repo.closes, 0);
      repo.prefsGate!.complete();
      expect(await close, isTrue);
      expect(repo.saved.last, 'last input before close');
      expect(jsonDecode(repo.writes.last)['scrollTop'], 81.125);
      expect(repo.maxWrites, 1);
      expect(c.editing.inputLocked, isTrue);
      c.dispose();
    },
  );

  test('a synchronous preference exception can be retried', () async {
    final repo = SyncPrefsRepository();
    final c = await open(repo);
    c.setWide(true);
    expect(await c.closeBarrier(), isFalse);
    expect(c.wide, isTrue);
    expect(c.errorCode, 'storage_io');
    repo.fail = false;
    expect(await c.closeBarrier(), isTrue);
    expect(jsonDecode(repo.writes.last)['wide'], isTrue);
    c.dispose();
  });

  test('seed uses busy barrier and close waits for completion', () async {
    final repo = RaceRepository();
    final c = WorkspaceController(repo);
    repo.seedGate = Completer<void>();
    final seed = c.seedDemo();
    await repo.seedEntered.future;
    final close = c.closeBarrier();
    expect(repo.closes, 0);
    repo.seedGate!.complete();
    await seed;
    expect(await close, isTrue);
    expect(repo.closes, 1);
    c.dispose();
  });

  test('recovery freezes exact memory until exit decision completes', () async {
    final repo = RaceRepository();
    final c = await open(repo);
    c.editing.edit('export snapshot');
    final gate = Completer<void>();
    final recovery = c.recoveryBarrier(() async {
      await gate.future;
    });
    c.editing.edit('must not enter while readOnly');
    expect(c.body, 'export snapshot');
    expect(await c.selectChapter(c.chapters.last), isFalse);
    gate.complete();
    expect(await recovery, isTrue);
    c.editing.edit('editable again');
    expect(c.body, 'editable again');
    await c.closeBarrier();
    c.dispose();
  });
}

class SyncPrefsRepository extends RaceRepository {
  bool fail = true;
  @override
  Future<void> setUiSession(String workId, String value) {
    if (fail) throw const WorkspaceFailure('storage_io');
    return super.setUiSession(workId, value);
  }
}

class ReentrantRepository extends RaceRepository {
  bool failNextPrefs = false;
  bool failNextClose = false;
  int closeAttempts = 0;

  @override
  Future<void> setUiSession(String workId, String value) {
    if (failNextPrefs) {
      failNextPrefs = false;
      throw const WorkspaceFailure('storage_io');
    }
    return super.setUiSession(workId, value);
  }

  @override
  Future<void> close() {
    closeAttempts++;
    if (failNextClose) {
      failNextClose = false;
      throw const WorkspaceFailure('storage_io');
    }
    return super.close();
  }
}
