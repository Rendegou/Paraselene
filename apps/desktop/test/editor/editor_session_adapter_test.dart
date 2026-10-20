// 覆盖编辑会话适配器：冻结拒绝、正文/布局初始化、编辑转发与内容代际重置。
// 使用假仓库与合成会话，不代表真实 FFI 会话或原生输入事件通过。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/editor/editor_session_adapter.dart';
import 'package:paraselene_flutter/workspace/editing_session.dart';
import 'package:paraselene_flutter/workspace/data/workspace_repository.dart';

class _FakeRepository implements WorkspaceRepository {
  final Map<String, ChapterDocument> _docs = {};
  int _revision = 1;

  void seed(String workId, String docId, String body) {
    _docs['$workId/$docId'] = ChapterDocument(
      workId: workId,
      documentId: docId,
      body: body,
      revision: _revision,
    );
  }

  ChapterDocument doc(String workId, String docId) => _docs['$workId/$docId']!;

  @override
  Future<ChapterDocument> loadDocument(String workId, String docId) async {
    final doc = _docs['$workId/$docId'];
    if (doc == null) throw const WorkspaceFailure('not_found');
    return doc;
  }

  @override
  Future<ChapterDocument> saveDocument(
    String workId,
    String chapterId,
    int? expectedRevision,
    String body,
  ) async {
    _revision++;
    final doc = ChapterDocument(
      workId: workId,
      documentId: chapterId,
      body: body,
      revision: _revision,
    );
    _docs['$workId/$chapterId'] = doc;
    return doc;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
      '${invocation.memberName} not implemented in test',
    );
  }
}

void main() {
  const style = TextStyle(
    fontFamily: 'Notebook Serif',
    fontSize: 20,
    height: 1.85,
    color: Color(0xff28231f),
  );

  group('EditorSessionAdapter', () {
    test('session freeze rejects native callbacks before a widget rebuild', () {
      final repo = _FakeRepository();
      repo.seed('work1', 'doc1', '原稿\r\n👩‍💻');
      final session = EditingSession(repo);
      session.adopt(repo.doc('work1', 'doc1'));
      final adapter = EditorSessionAdapter(session: session, style: style);
      addTearDown(() {
        adapter.dispose();
        session.dispose();
      });
      session.inputLocked = true;
      adapter.client.updateEditingValue(
        const TextEditingValue(
          text: 'late native text',
          selection: TextSelection.collapsed(offset: 16),
        ),
      );
      expect(adapter.client.document.raw, session.body);
      expect(session.body, '原稿\r\n👩‍💻');
    });

    test('initializes with session body', () {
      final repo = _FakeRepository();
      repo.seed('work1', 'doc1', 'hello world');
      final session = EditingSession(repo);
      session.adopt(repo.doc('work1', 'doc1'));
      final adapter = EditorSessionAdapter(session: session, style: style);
      addTearDown(adapter.dispose);
      addTearDown(session.dispose);

      expect(adapter.client.document.raw, 'hello world');
      expect(adapter.session.body, 'hello world');
    });

    test('forwards edits to session', () async {
      final repo = _FakeRepository();
      repo.seed('work1', 'doc1', 'hello');
      final session = EditingSession(repo);
      session.adopt(repo.doc('work1', 'doc1'));
      final adapter = EditorSessionAdapter(session: session, style: style);
      addTearDown(() async {
        await session.flushAll();
        adapter.dispose();
        session.dispose();
      });

      adapter.client.select(const TextSelection.collapsed(offset: 5));
      adapter.client.replace(' world');
      expect(adapter.client.document.raw, 'hello world');
      expect(adapter.session.body, 'hello world');
    });

    test('resets on contentEpoch change', () async {
      final repo = _FakeRepository();
      repo.seed('work1', 'doc1', 'chapter 1');
      final session = EditingSession(repo);
      session.adopt(repo.doc('work1', 'doc1'));
      final adapter = EditorSessionAdapter(session: session, style: style);
      addTearDown(() async {
        await session.flushAll();
        adapter.dispose();
        session.dispose();
      });

      adapter.client.select(const TextSelection.collapsed(offset: 9));
      adapter.client.replace(' edited');
      expect(adapter.client.document.raw, 'chapter 1 edited');

      await session.flushAll();
      repo.seed('work1', 'doc2', 'chapter 2');
      session.adopt(repo.doc('work1', 'doc2'));
      expect(adapter.client.document.raw, 'chapter 2');
      expect(adapter.session.body, 'chapter 2');
    });

    test('notifies listeners on session change', () {
      final repo = _FakeRepository();
      repo.seed('work1', 'doc1', 'hello');
      final session = EditingSession(repo);
      session.adopt(repo.doc('work1', 'doc1'));
      final adapter = EditorSessionAdapter(session: session, style: style);
      addTearDown(adapter.dispose);
      addTearDown(session.dispose);

      var notified = false;
      adapter.addListener(() => notified = true);

      repo.seed('work1', 'doc2', 'world');
      session.adopt(repo.doc('work1', 'doc2'));
      expect(notified, isTrue);
    });

    test('notifies listeners on client change', () async {
      final repo = _FakeRepository();
      repo.seed('work1', 'doc1', 'hello');
      final session = EditingSession(repo);
      session.adopt(repo.doc('work1', 'doc1'));
      final adapter = EditorSessionAdapter(session: session, style: style);
      addTearDown(() async {
        await session.flushAll();
        adapter.dispose();
        session.dispose();
      });

      var notified = false;
      adapter.addListener(() => notified = true);

      adapter.client.select(const TextSelection.collapsed(offset: 5));
      adapter.client.replace(' world');
      expect(notified, isTrue);
    });

    test('updateWidth changes layout width', () {
      final repo = _FakeRepository();
      repo.seed('work1', 'doc1', 'hello');
      final session = EditingSession(repo);
      session.adopt(repo.doc('work1', 'doc1'));
      final adapter = EditorSessionAdapter(session: session, style: style);
      addTearDown(adapter.dispose);
      addTearDown(session.dispose);

      expect(adapter.client.layout.width, 760);
      adapter.updateWidth(600);
      expect(adapter.client.layout.width, 600);
    });
  });
}
