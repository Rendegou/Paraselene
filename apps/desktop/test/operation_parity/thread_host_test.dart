// R06 段下讨论宿主测试：同一时间只展开一条线程，其余只留段末标记；
// 收起不丢草稿/标记，切换线程先同步草稿，正文与正文坐标不被讨论界面改写。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/cowrite/discussion_panel.dart';
import 'package:paraselene_flutter/cowrite/discussion_repository.dart';
import 'package:paraselene_flutter/cowrite/discussion_thread.dart';
import 'package:paraselene_flutter/editor/editor_anchor.dart';
import 'package:paraselene_flutter/editor/editor_viewport.dart';
import 'package:paraselene_flutter/workspace/data/synthetic_workspace_repository.dart';
import 'package:paraselene_flutter/workspace/workspace_controller.dart';

import '../support/m2_harness.dart';
import 'paper_harness.dart';

/// 内存讨论仓库：只为 UI 测试提供 listThreads/saveThread，不涉及真实 FFI。
class _FakeDiscussions implements DiscussionRepository {
  final Map<
    String,
    ({String chapter, int revision, Map<String, dynamic> snapshot})
  >
  rows = {};

  @override
  Future<List<Map<String, dynamic>>> listThreads(
    String work,
    String chapter,
  ) async => [
    for (final entry in rows.entries)
      if (entry.value.chapter == chapter)
        <String, dynamic>{
          'threadId': entry.key,
          'documentId': chapter,
          'revision': entry.value.revision,
          'snapshot': entry.value.snapshot,
        },
  ];

  @override
  Future<Map<String, dynamic>> saveThread(
    String work,
    String chapter,
    String id,
    int? revision,
    Map<String, dynamic> snapshot,
  ) async {
    final next = (revision ?? 0) + 1;
    rows[id] = (chapter: chapter, revision: next, snapshot: snapshot);
    return <String, dynamic>{
      'threadId': id,
      'documentId': chapter,
      'revision': next,
      'snapshot': snapshot,
    };
  }

  @override
  Future<List<Map<String, dynamic>>> listOperations(
    String work,
    String chapter,
  ) async => const [];

  @override
  Future<void> applyOperation(
    String work,
    String chapter,
    String id,
    int? revision,
  ) async {}

  @override
  Future<void> rejectOperation(String work, String chapter, String id) async {}
}

/// 在合成工作区上附加讨论能力，使工作台真正创建 DiscussionRegistry。
class _DiscussionRepository extends SyntheticWorkspaceRepository
    implements DiscussionRepositoryProvider {
  _DiscussionRepository() : super(withDemo: true);

  final _FakeDiscussions fake = _FakeDiscussions();

  @override
  DiscussionRepository get discussions => fake;
}

class _Fixture {
  _Fixture(this.controller, this.repository);

  final WorkspaceController controller;
  final _DiscussionRepository repository;

  EditorViewportState viewport(WidgetTester tester) =>
      tester.state<EditorViewportState>(find.byKey(manuscriptKey));

  List<DiscussionThread> get threads => controller.discussions!.threads;

  ValueKey<String> marker(DiscussionThread thread) =>
      ValueKey('thread-marker-open-${thread.id}');
}

Future<_Fixture> _pump(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
}) async {
  final repository = _DiscussionRepository();
  final controller = await pumpPaperWorkbench(
    tester,
    repository: repository,
    size: size,
  );
  return _Fixture(controller, repository);
}

List<DiscussionThread> _seedThreads(_Fixture fixture) {
  final body = fixture.controller.body;
  final secondLine = body.indexOf('\n') + 1;
  final first = fixture.controller.discussions!.create(
    EditorAnchor.capture(body, 0, 2),
  );
  final second = fixture.controller.discussions!.create(
    EditorAnchor.capture(body, 3, 5),
  );
  final third = fixture.controller.discussions!.create(
    EditorAnchor.capture(body, secondLine, secondLine + 2),
  );
  return [first, second, third];
}

void main() {
  testWidgets('三条线程只展开一条，其余标记可分别点击，收起恢复纸面高度', (tester) async {
    final fixture = await _pump(tester);
    final threads = _seedThreads(fixture);
    await fixture.controller.discussions!.flush();
    await tester.pump();

    final viewport = fixture.viewport(tester);
    final baseline = viewport.controller.layout.height;
    expect(fixture.threads, hasLength(3));
    expect(
      viewport.controller.layout.threadSlots.every((slot) => slot.height == 0),
      isTrue,
      reason: '未展开时任何线程都不占正文高度',
    );
    for (final thread in threads) {
      expect(find.byKey(fixture.marker(thread)), findsOneWidget);
    }

    await tester.tap(find.byKey(fixture.marker(threads.first)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final panel = tester.widget<DiscussionPanel>(find.byType(DiscussionPanel));
    expect(panel.thread.id, threads.first.id);
    expect(find.byType(DiscussionPanel), findsOneWidget);
    expect(find.byKey(fixture.marker(threads.first)), findsNothing);
    expect(
      find.byKey(fixture.marker(threads[1])),
      findsOneWidget,
      reason: '同一段第二个线程的标记仍独立可达',
    );
    expect(find.byKey(fixture.marker(threads[2])), findsOneWidget);
    final expanded = fixture.viewport(tester).controller.layout;
    expect(expanded.height, greaterThan(baseline));
    expect(
      expanded.threadSlots
          .where((slot) => slot.id == threads.first.id)
          .single
          .height,
      greaterThan(0),
    );
    expect(
      expanded.threadSlots
          .where((slot) => slot.id != threads.first.id)
          .every((slot) => slot.height == 0),
      isTrue,
    );

    await tester.tap(find.byIcon(Icons.unfold_less));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(DiscussionPanel), findsNothing);
    expect(
      fixture.viewport(tester).controller.layout.height,
      closeTo(baseline, 2),
    );
    for (final thread in threads) {
      expect(find.byKey(fixture.marker(thread)), findsOneWidget);
    }

    await disposePaperController(fixture.controller);
  });

  testWidgets('切换线程先保存草稿，收起后重开草稿仍在，正文坐标不变', (tester) async {
    final fixture = await _pump(tester);
    final threads = _seedThreads(fixture);
    final body = fixture.controller.body;
    final editor = fixture.viewport(tester).controller;
    final historyBefore = editor.document.raw;
    await fixture.controller.discussions!.flush();
    await tester.pump();

    await tester.tap(find.byKey(fixture.marker(threads.first)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final draftField = find.descendant(
      of: find.byType(DiscussionPanel),
      matching: find.byType(TextField),
    );
    await tester.enterText(draftField, '第一稿');
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(fixture.marker(threads[1])));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.widget<DiscussionPanel>(find.byType(DiscussionPanel)).thread.id,
      threads[1].id,
    );
    expect(threads.first.draft, '第一稿');

    await tester.tap(find.byIcon(Icons.unfold_less));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(fixture.marker(threads.first)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final reopenedDraft = find.descendant(
      of: find.byType(DiscussionPanel),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(reopenedDraft).controller!.text, '第一稿');
    expect(fixture.controller.body, body);
    expect(fixture.viewport(tester).controller.document.raw, historyBefore);

    await disposePaperController(fixture.controller);
  });

  testWidgets('切换章节收起段下卡片并清空旧章节槽位', (tester) async {
    final fixture = await _pump(tester);
    final threads = _seedThreads(fixture);
    await fixture.controller.discussions!.flush();
    await tester.pump();
    await tester.tap(find.byKey(fixture.marker(threads.first)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(DiscussionPanel), findsOneWidget);

    final created = await fixture.controller.createChapter('第二章');
    expect(created, isTrue, reason: 'error=${fixture.controller.errorCode}');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(fixture.controller.currentChapter?.title, '第二章');
    expect(find.byType(DiscussionPanel), findsNothing);
    expect(fixture.controller.discussions!.threads, isEmpty);
    expect(fixture.viewport(tester).controller.layout.threadSlots, isEmpty);
    expect(find.byKey(fixture.marker(threads.first)), findsNothing);

    await disposePaperController(fixture.controller);
  });
}
