// 覆盖讨论注册表的线程/快照分离：章节讨论与选区线程互不混写，服务端操作不写入作者快照。
// 使用内存假仓库验证 Dart 状态，不代表真实 FFI、持久化或并发窗口行为通过。

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/cowrite/discussion_registry.dart';
import 'package:paraselene_flutter/cowrite/discussion_repository.dart';
import 'package:paraselene_flutter/editor/editor_anchor.dart';

class _Repository implements DiscussionRepository {
  final saved = <Map<String, dynamic>>[];
  Completer<void>? gate;
  bool fail = false;
  @override
  Future<List<Map<String, dynamic>>> listThreads(String w, String c) async =>
      [];
  @override
  Future<List<Map<String, dynamic>>> listOperations(String w, String c) async =>
      [];
  @override
  Future<Map<String, dynamic>> saveThread(
    String w,
    String c,
    String id,
    int? revision,
    Map<String, dynamic> snapshot,
  ) async {
    if (fail) throw StateError('synthetic write failure');
    final currentGate = gate;
    gate = null;
    if (currentGate != null) await currentGate.future;
    saved.add(snapshot);
    return {'revision': (revision ?? 0) + 1};
  }

  @override
  Future<void> applyOperation(String w, String c, String id, int? r) async {}
  @override
  Future<void> rejectOperation(String w, String c, String id) async {}
}

void main() {
  test(
    'draft edited during CAS write is saved again with next revision',
    () async {
      final repository = _Repository();
      final registry = DiscussionRegistry(repository);
      addTearDown(registry.dispose);
      await registry.open('work', 'chapter');
      final thread = registry.create(EditorAnchor.capture('a👩\r\né é', 0, 1));
      registry.editDraft(thread.id, 'first');
      final gate = repository.gate = Completer<void>();
      final saving = registry.flush();
      registry.editDraft(thread.id, 'second');
      gate.complete();
      await saving;
      expect(repository.saved.map((row) => row['draft']), ['first', 'second']);
      expect(thread.revision, 2);
      expect(registry.dirty, isFalse);
    },
  );

  test(
    'failed navigation retains unsent draft and previous chapter identity',
    () async {
      final repository = _Repository();
      final registry = DiscussionRegistry(repository);
      addTearDown(registry.dispose);
      await registry.open('work', 'old');
      final thread = registry.create(EditorAnchor.capture('same', 0, 4));
      registry.editDraft(thread.id, 'retained');
      repository.fail = true;
      await expectLater(registry.open('other', 'new'), throwsStateError);
      expect(registry.chapter, 'old');
      expect(registry.threads.single.draft, 'retained');
      expect(registry.error, 'discussion_save_failed');
      repository.fail = false;
      await registry.flush();
      await registry.open('other', 'new');
      expect(registry.threads, isEmpty);
    },
  );

  test('server operations never enter persisted author snapshot', () async {
    final repository = _Repository();
    final registry = DiscussionRegistry(repository);
    addTearDown(registry.dispose);
    await registry.open('w', 'c');
    final thread = registry.create(EditorAnchor.capture('body', 0, 4));
    thread.update({
      'requests': [
        {'id': 'author', 'text': 'kept'},
        {'id': 'server', 'operationId': 'op'},
      ],
      'candidate': {'replacement': 'derived'},
    });
    await registry.flush();
    expect(repository.saved.single['requests'], [
      {'id': 'author', 'text': 'kept'},
    ]);
    expect(repository.saved.single['candidate'], isNull);
  });

  test(
    'chapter discussion has no target and is reused after creation',
    () async {
      final repository = _Repository();
      final registry = DiscussionRegistry(repository);
      addTearDown(registry.dispose);
      await registry.open('work', 'chapter');
      final first = registry.chapterThread();
      expect(first.isChapter, isTrue);
      expect(first.snapshot['target'], isNull);
      expect(first.snapshot['anchor'], isNull);
      expect(first.valid, isFalse);
      final second = registry.chapterThread();
      expect(identical(first, second), isTrue);
      expect(registry.threads, hasLength(1));
      expect(registry.byId(first.id), same(first));
      registry.editDraft(first.id, '讨论整章');
      await registry.flush();
      final saved = repository.saved.single;
      expect(saved['target'], isNull);
      expect(saved['anchor'], isNull);
      expect(saved['draft'], '讨论整章');
      expect(saved['requests'], isEmpty);
      expect(saved['candidate'], isNull);
    },
  );

  test('chapter discussion is separate from selection threads', () async {
    final repository = _Repository();
    final registry = DiscussionRegistry(repository);
    addTearDown(registry.dispose);
    await registry.open('work', 'chapter');
    final selection = registry.create(EditorAnchor.capture('正文', 0, 2));
    final chapter = registry.chapterThread();
    expect(registry.threads, hasLength(2));
    expect(selection.isChapter, isFalse);
    expect(chapter.isChapter, isTrue);
    expect(registry.chapterThread(), same(chapter));
    expect(registry.byId(selection.id), same(selection));
  });
}
