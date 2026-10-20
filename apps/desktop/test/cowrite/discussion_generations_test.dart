// 生成运行态生命周期的合成测试：不读凭据、不发送网络请求。
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/cowrite/discussion_generations.dart';
import 'package:paraselene_flutter/cowrite/generation_repository.dart';

class _Source implements GenerationRepository {
  final sending = Completer<void>();
  final cancelled = <(String, String)>[];
  int sendCount = 0;
  bool failCancel = false;
  @override
  Future<void> activateScope(String? work, String? chapter) async {}
  @override
  Future<Map<String, dynamic>> prepare(Map<String, dynamic> request) async =>
      {};
  @override
  Future<void> send(String work, String preview, {required bool confirmed}) {
    expect(confirmed, isTrue);
    sendCount++;
    return sending.future;
  }

  @override
  Future<void> cancel(String work, String operation) async {
    cancelled.add((work, operation));
    if (failCancel) throw StateError('synthetic cancel failure');
  }

  @override
  Future<void> setCloudEnabled(bool enabled) async {}
  @override
  Future<void> setKey(String key) async {}
  @override
  Future<void> deleteKey() async {}
}

Map<String, dynamic> _preview() => {
  'workId': 'work-a',
  'documentId': 'chapter-a',
  'operationId': 'op-a',
  'id': 'preview-a',
  'prepared': {},
};

Future<DiscussionGenerationRun?> _prepare(
  DiscussionGenerations state, {
  Future<Map<String, dynamic>?> Function()? build,
}) => state.prepare(
  thread: 'thread-a',
  draft: 'frozen draft',
  outputLanguage: 'en',
  buildPreview: build ?? () async => _preview(),
);

void main() {
  late _Source source;
  late DiscussionGenerations state;
  setUp(() {
    source = _Source();
    state = DiscussionGenerations(source)..setScope('work-a', 'chapter-a');
  });
  tearDown(() {
    if (!source.sending.isCompleted) source.sending.complete();
    state.dispose();
  });

  test(
    'same-thread send remains single-flight and cancellable until completion',
    () async {
      final run = (await _prepare(state))!;
      final sending = state.send(run);
      expect(state.forThread('thread-a'), same(run));
      expect(run.running, isTrue);
      expect(await state.send(run), isFalse);
      expect(await _prepare(state), isNull);
      expect(source.sendCount, 1);
      await state.cancel(run);
      expect(source.cancelled, [('work-a', 'op-a')]);
      source.sending.complete();
      expect(await sending, isFalse);
      expect(run.running, isFalse);
      expect(run.preview, isNull);
    },
  );

  test(
    'cancel before prepare completes cancels its eventual ticket without sending',
    () async {
      final delayed = Completer<Map<String, dynamic>?>();
      final preparing = _prepare(state, build: () => delayed.future);
      final run = state.forThread('thread-a')!;
      await state.cancel(run);
      expect(source.cancelled, isEmpty);
      delayed.complete(_preview());
      expect(await preparing, isNull);
      expect(source.cancelled, [('work-a', 'op-a')]);
      expect(source.sendCount, 0);
      expect(run.running, isFalse);
    },
  );

  test(
    'late prepare belongs to its frozen old work and cannot send in new scope',
    () async {
      final delayed = Completer<Map<String, dynamic>?>();
      final preparing = _prepare(state, build: () => delayed.future);
      state.setScope('work-b', 'chapter-b');
      delayed.complete(_preview());
      expect(await preparing, isNull);
      expect(source.cancelled, [('work-a', 'op-a')]);
      expect(state.forThread('thread-a'), isNull);
      expect(source.sendCount, 0);
    },
  );

  test(
    'successful send releases preview while retaining frozen author instruction',
    () async {
      final run = (await _prepare(state))!;
      final sending = state.send(run);
      source.sending.complete();
      expect(await sending, isTrue);
      expect(run.running, isFalse);
      expect(run.failed, isFalse);
      expect(run.draft, 'frozen draft');
      expect(run.outputLanguage, 'en');
      expect(run.preview, isNull);
    },
  );

  test(
    'cancellation failure is visible and allows explicit retry of the same operation',
    () async {
      final run = (await _prepare(state))!;
      source.failCancel = true;
      await state.cancel(run);
      expect(run.failed, isTrue);
      expect(run.cancelling, isFalse);
      expect(run.running, isTrue);
      source.failCancel = false;
      await state.cancel(run);
      expect(source.cancelled, [('work-a', 'op-a'), ('work-a', 'op-a')]);
      expect(run.running, isFalse);
      expect(source.sendCount, 0);
    },
  );

  test(
    'scope change during send cannot publish success into a newer chapter',
    () async {
      final run = (await _prepare(state))!;
      final sending = state.send(run);
      state.setScope('work-b', 'chapter-b');
      source.sending.complete();
      expect(await sending, isFalse);
      expect(state.forThread('thread-a'), isNull);
    },
  );
}
