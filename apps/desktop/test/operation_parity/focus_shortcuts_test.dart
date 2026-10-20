// R10 焦点层级测试：窗口级快捷键只在最内层允许的位置生效，Escape 逐层退出。
//
// 覆盖正文 Ctrl+F/Ctrl+S、重命名对话框隔离、讨论卡 Escape 与专注模式退出；
// 不启动真实 IME 与桌面窗口，组合输入的真实物理行为仍标记为未测。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/cowrite/discussion_panel.dart';
import 'package:paraselene_flutter/cowrite/discussion_repository.dart';
import 'package:paraselene_flutter/editor/editor_anchor.dart';
import 'package:paraselene_flutter/editor/editor_viewport.dart';
import 'package:paraselene_flutter/workspace/data/synthetic_workspace_repository.dart';
import 'package:paraselene_flutter/workspace/data/workspace_repository.dart';

import '../support/m2_harness.dart';
import 'paper_harness.dart';

/// 内存讨论仓库：只为焦点层级测试提供 listThreads/saveThread，不涉及真实 FFI。
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

/// 记录保存次数的合成仓库，用来断言对话框内的 Ctrl+S 没有越过最内层。
final class _CountingRepository extends SyntheticWorkspaceRepository {
  _CountingRepository() : super(withDemo: true);
  int saves = 0;

  @override
  Future<ChapterDocument> saveDocument(
    String workId,
    String chapterId,
    int? expectedRevision,
    String body,
  ) {
    saves += 1;
    return super.saveDocument(workId, chapterId, expectedRevision, body);
  }
}

Future<void> _ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

Future<void> _escape(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pump();
  // 对话框/卡片的关闭动画与 postFrame 焦点回迁需要多帧。
  await tester.pump(const Duration(milliseconds: 300));
}

EditorViewportState _viewport(WidgetTester tester) =>
    tester.state<EditorViewportState>(find.byKey(manuscriptKey));

void main() {
  testWidgets('Ctrl+F opens find from the body and Escape closes it', (
    tester,
  ) async {
    final controller = await pumpPaperWorkbench(tester);
    final viewport = _viewport(tester);
    viewport.requestFocus();
    await tester.pump();

    await _ctrl(tester, LogicalKeyboardKey.keyF);
    expect(find.text('下一处'), findsOneWidget);
    expect(find.widgetWithText(TextField, '查找当前章'), findsOneWidget);

    await _escape(tester);
    expect(find.text('下一处'), findsNothing);
    // 关闭查找回正文，不重置原文。
    expect(viewport.controller.focusNode.hasFocus, isTrue);
    expect(controller.body, contains('雨后的书店'));

    await disposePaperController(controller);
  });

  testWidgets('rename dialog keeps Ctrl+F and Ctrl+S away from the body', (
    tester,
  ) async {
    final repository = _CountingRepository();
    final controller = await pumpPaperWorkbench(tester, repository: repository);
    _viewport(tester).requestFocus();
    controller.editing.edit('${controller.body}临时输入');
    await tester.pump();

    await tester.tap(find.text('重命名章节'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(repository.saves, 0);

    await _ctrl(tester, LogicalKeyboardKey.keyF);
    expect(find.text('下一处'), findsNothing, reason: '对话框内不打开正文查找');
    await _ctrl(tester, LogicalKeyboardKey.keyS);
    await tester.pump(const Duration(milliseconds: 20));
    expect(repository.saves, 0, reason: '对话框内不越过最内层保存正文');

    // Escape 只关闭重命名对话框，不触发其他层；关闭后焦点回正文。
    await _escape(tester);
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.byType(AlertDialog), findsNothing);
    expect(_viewport(tester).controller.focusNode.hasFocus, isTrue);

    // 防抖保存随后由编辑器自身完成，验证没有丢失草稿。
    await tester.pump(const Duration(milliseconds: 400));
    expect(repository.saves, 1);
    await disposePaperController(controller);
  });

  testWidgets('Escape collapses one expanded discussion without losing it', (
    tester,
  ) async {
    final controller = await pumpPaperWorkbench(
      tester,
      repository: _DiscussionRepository(),
    );
    final registry = controller.discussions!;
    final thread = registry.create(EditorAnchor.capture(controller.body, 0, 4));
    await tester.pump();

    final marker = find.byKey(ValueKey('thread-marker-open-${thread.id}'));
    expect(marker, findsOneWidget);
    await tester.tap(marker);
    await tester.pump();
    expect(find.byType(DiscussionPanel), findsOneWidget);

    await _escape(tester);
    await tester.pump();
    expect(find.byType(DiscussionPanel), findsNothing);
    // 收起只改展示态：线程、标记都在，焦点回正文。
    expect(registry.threads, hasLength(1));
    expect(marker, findsOneWidget);
    expect(_viewport(tester).controller.focusNode.hasFocus, isTrue);

    await registry.flush();
    await disposePaperController(controller);
  });

  testWidgets('Escape exits focus mode only after find is closed', (
    tester,
  ) async {
    final controller = await pumpPaperWorkbench(tester);

    await tester.tap(find.byTooltip('专注模式'));
    await tester.pump();
    expect(find.text('幻月'), findsNothing, reason: '专注模式隐藏侧栏');

    await _ctrl(tester, LogicalKeyboardKey.keyF);
    expect(find.text('下一处'), findsOneWidget);
    await _escape(tester);
    expect(find.text('下一处'), findsNothing);
    expect(find.text('幻月'), findsNothing, reason: '第一次 Escape 只退查找层');

    await _escape(tester);
    expect(find.text('幻月'), findsOneWidget);
    expect(find.byTooltip('专注模式'), findsOneWidget);

    await disposePaperController(controller);
  });
}
