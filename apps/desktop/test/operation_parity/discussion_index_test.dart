// R07 讨论索引与线程保存错误测试：窄窗也能打开完整索引，索引列出本章全部
// 线程（含失效与草稿），重开按真实 ID、不新建相似线程；失效线程在临时面板中
// 显示冻结引文与历史，保存失败保留脏草稿并可重试，冷启动读回原草稿。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// 内存讨论仓库；[failNext] 用于注入一次线程保存失败。
class _FakeDiscussions implements DiscussionRepository {
  final Map<
    String,
    ({String chapter, int revision, Map<String, dynamic> snapshot})
  >
  rows = {};
  bool failNext = false;
  int saves = 0;

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
    saves++;
    if (failNext) {
      failNext = false;
      throw StateError('synthetic discussion write failure');
    }
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

class _DiscussionRepository extends SyntheticWorkspaceRepository
    implements DiscussionRepositoryProvider {
  _DiscussionRepository() : super(withDemo: true);

  final _FakeDiscussions fake = _FakeDiscussions();

  @override
  DiscussionRepository get discussions => fake;
}

class _Fixture {
  _Fixture(this.controller, this.repository, this.viewport);

  final WorkspaceController controller;
  final _DiscussionRepository repository;
  final EditorViewportState viewport;

  List<DiscussionThread> get threads => controller.discussions!.threads;

  /// 建立三条线程：两条有效选段、一条失效选段；返回时已落盘。
  Future<List<DiscussionThread>> seed() async {
    final registry = controller.discussions!;
    final body = controller.body;
    final secondLine = body.indexOf('\n') + 1;
    final first = registry.create(EditorAnchor.capture(body, 0, 2));
    final second = registry.create(EditorAnchor.capture(body, 3, 5));
    final third = registry.create(
      EditorAnchor.capture(body, secondLine, secondLine + 2),
    );
    registry.editDraft(first.id, '第一条草稿');
    registry.editDraft(third.id, '失效线程草稿');
    final anchor = Map<String, dynamic>.from(third.snapshot['anchor'] as Map)
      ..['valid'] = false;
    third.update({'anchor': anchor});
    await registry.flush();
    return [first, second, third];
  }
}

Future<_Fixture> _pump(WidgetTester tester) async {
  final repository = _DiscussionRepository();
  final controller = await pumpPaperWorkbench(
    tester,
    repository: repository,
    size: const Size(360, 720),
  );
  final viewport = tester.state<EditorViewportState>(find.byKey(manuscriptKey));
  return _Fixture(controller, repository, viewport);
}

/// 顶栏索引入口按 tooltip 定位，避免与段末讨论标记的 forum 图标混淆。
Finder _indexButton = find.byTooltip('讨论记录 · 3');

Finder _marker(DiscussionThread thread) =>
    find.byKey(ValueKey('thread-marker-open-${thread.id}'));

Finder _entry(DiscussionThread thread) =>
    find.byKey(ValueKey('discussion-index-entry-${thread.id}'));

void main() {
  testWidgets('窄窗索引列出本章全部线程，重开不新建且不改线程数据', (tester) async {
    final fixture = await _pump(tester);
    final seeded = await fixture.seed();
    await tester.pump();
    final ids = fixture.threads.map((thread) => thread.id).toList();
    expect(ids, hasLength(3));

    await tester.tap(_indexButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.byKey(const ValueKey('discussion-index-panel')),
      findsOneWidget,
    );
    expect(find.text('讨论记录 · 3'), findsOneWidget);
    for (final thread in seeded) {
      expect(_entry(thread), findsOneWidget);
    }
    // 未发草稿与失效状态都在索引内明示，不被顶栏入口掩盖。
    expect(find.textContaining('有未发草稿'), findsWidgets);
    expect(find.textContaining('选段已变化'), findsWidgets);

    // 打开一条已存在的有效线程：仍为同一 ID 与同一草稿，没有隐式新建。
    await tester.tap(_entry(seeded.first));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(fixture.threads, hasLength(3));
    expect(fixture.threads.map((thread) => thread.id), unorderedEquals(ids));
    expect(
      fixture.threads
          .firstWhere((thread) => thread.id == seeded.first.id)
          .draft,
      '第一条草稿',
    );
    expect(fixture.controller.body, isNotEmpty);

    // 内容与线程数量在打开索引/展开面板后保持不变。
    expect(fixture.repository.fake.rows.length, 3, reason: '索引只读，不写回新线程');
  });

  testWidgets('失效线程临时面板显示冻结引文与历史，Escape 关闭后焦点回正文', (tester) async {
    final fixture = await _pump(tester);
    final seeded = await fixture.seed();
    await tester.pump();
    final frozenText =
        ((seeded[2].snapshot['target'] as Map)['text'] as String?) ?? '';
    expect(frozenText, isNotEmpty);

    await tester.tap(_indexButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(_entry(seeded[2]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(DiscussionPanel), findsOneWidget);
    final panel = tester.widget<DiscussionPanel>(find.byType(DiscussionPanel));
    expect(panel.thread.id, seeded[2].id);
    expect(find.text(frozenText), findsOneWidget, reason: '显示冻结引文原文');
    expect(find.textContaining('选段已变化'), findsOneWidget);
    expect(find.textContaining('历史记录'), findsWidgets);
    // 可见关闭入口存在，不依赖只能点遮罩关闭。
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.text('失效线程草稿'), findsWidgets);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(DiscussionPanel), findsNothing);
    expect(fixture.viewport.controller.focusNode.hasFocus, isTrue);
    // 关闭面板不产生新线程，也不改写草稿。
    expect(fixture.threads, hasLength(3));
    expect(
      fixture.threads.firstWhere((thread) => thread.id == seeded[2].id).draft,
      '失效线程草稿',
    );
  });

  testWidgets('线程保存失败保留脏草稿并可重试，冷启动读回原草稿', (tester) async {
    final fixture = await _pump(tester);
    final seeded = await fixture.seed();
    await tester.pump();
    final thread = fixture.threads.firstWhere(
      (item) => item.id == seeded[0].id,
    );
    // 先展开该线程的面板，保存失败提示出现在草稿卡片里。
    await tester.tap(_marker(thread));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(DiscussionPanel), findsOneWidget);

    fixture.repository.fake.failNext = true;
    fixture.controller.discussions!.editDraft(thread.id, '重试前的草稿');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.byKey(const ValueKey('discussion-save-failed')),
      findsOneWidget,
    );
    expect(find.textContaining('讨论保存失败'), findsOneWidget);
    expect(find.byKey(const ValueKey('discussion-save-retry')), findsOneWidget);
    expect(
      fixture.threads.firstWhere((item) => item.id == thread.id).draft,
      '重试前的草稿',
    );

    await tester.tap(find.byKey(const ValueKey('discussion-save-retry')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('discussion-save-failed')), findsNothing);
    expect(fixture.repository.fake.rows, hasLength(3));

    // 冷启动：同一仓库重建控制器后仍读回草稿与三个线程。
    await fixture.controller.discussions!.flush();
    final work = fixture.controller.currentWork!;
    await tester.pumpWidget(const SizedBox.shrink());
    await fixture.controller.editing.flushAll();
    fixture.controller.dispose();
    final restarted = WorkspaceController(fixture.repository);
    await restarted.restoreSession();
    addTearDown(restarted.dispose);
    expect(restarted.currentWork?.id, work.id);
    final restored = restarted.discussions!.threads;
    expect(restored, hasLength(3));
    expect(
      restored.firstWhere((item) => item.id == seeded[0].id).draft,
      '重试前的草稿',
    );
  });
}
