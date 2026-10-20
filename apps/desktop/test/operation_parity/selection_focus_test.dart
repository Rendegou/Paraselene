// R08 选区落点测试：触发时冻结原选区、创建后展开卡片并聚焦草稿、
// 视口底部选段也能看到卡片、收起后焦点回到正文目标末尾、忙碌时拒绝创建。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/cowrite/discussion_panel.dart';
import 'package:paraselene_flutter/cowrite/discussion_repository.dart';
import 'package:paraselene_flutter/cowrite/discussion_thread.dart';
import 'package:paraselene_flutter/editor/editor_input_client.dart';
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

class _DiscussionRepository extends SyntheticWorkspaceRepository
    implements DiscussionRepositoryProvider {
  _DiscussionRepository() : super(withDemo: true);

  final _FakeDiscussions fake = _FakeDiscussions();

  @override
  DiscussionRepository get discussions => fake;
}

class _Fixture {
  _Fixture(this.controller, this.viewport);

  final WorkspaceController controller;
  final EditorViewportState viewport;

  EditorInputClient get client => viewport.controller as EditorInputClient;

  List<DiscussionThread> get threads => controller.discussions!.threads;
}

Future<_Fixture> _pump(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
}) async {
  final controller = await pumpPaperWorkbench(
    tester,
    repository: _DiscussionRepository(),
    size: size,
  );
  final viewport = tester.state<EditorViewportState>(find.byKey(manuscriptKey));
  return _Fixture(controller, viewport);
}

Finder get _inline => find.byKey(const ValueKey('discuss-selection-inline'));

Finder get _draft => find.descendant(
  of: find.byType(DiscussionPanel),
  matching: find.byType(TextField),
);

void main() {
  testWidgets('工具栏抢焦点折叠选区后，仍按冻结区间创建线程并聚焦草稿', (tester) async {
    final fixture = await _pump(tester);
    final client = fixture.client;
    final body = client.document.raw;
    expect(body.length, greaterThan(8));

    client.select(const TextSelection(baseOffset: 0, extentOffset: 4));
    await tester.pump();
    expect(_inline, findsOneWidget);

    // 模拟点击顶栏按钮导致编辑器失焦、选区先折叠：点击仍应使用冻结区间。
    client.select(const TextSelection.collapsed(offset: 0));
    await tester.tap(_inline);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(fixture.threads, hasLength(1));
    final thread = fixture.threads.single;
    final target = thread.snapshot['target']! as Map<String, dynamic>;
    expect(target['from'], 0);
    expect(target['to'], 4);
    expect(target['text'], body.substring(0, 4));
    expect(find.byType(DiscussionPanel), findsOneWidget);
    expect(_draft, findsOneWidget);
    // 新建后直接可输入：草稿输入框持有焦点。
    expect(tester.widget<TextField>(_draft).focusNode!.hasFocus, isTrue);
    // 创建讨论不修改正文，也不消费正文 undo。
    expect(client.document.raw, body);
    expect(client.document.canUndo, isFalse);
    expect(
      client.value.selection,
      const TextSelection(baseOffset: 0, extentOffset: 4),
    );

    await disposePaperController(fixture.controller);
  });

  testWidgets('视口底部选段：卡片滚动露出且底部不被视口遮挡', (tester) async {
    final fixture = await _pump(tester);
    final client = fixture.client;
    final editor = fixture.viewport;
    client.load(longBody());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final body = client.document.raw;
    final scroll = editor.scroll;
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    // 选中最后一段靠后的文字，确保选区在视口底部附近。
    client.select(
      TextSelection(
        baseOffset: body.length - 24,
        extentOffset: body.length - 20,
      ),
    );
    await tester.pump();
    expect(_inline, findsOneWidget);
    await tester.tap(_inline);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(fixture.threads, hasLength(1));
    final thread = fixture.threads.single;
    final anchor = thread.anchor!;
    Rect? card;
    for (final geometry in editor.controller.layout.threadGeometry) {
      if (geometry.id == thread.id) card = geometry.rect;
    }
    expect(card, isNotNull);
    final viewBottom =
        scroll.offset + tester.getSize(find.byKey(manuscriptKey)).height;
    // 卡片底部在视口内（允许 1 像素取整误差），作者能看到输入区。
    expect(
      editor.headerExtent + card!.bottom,
      lessThanOrEqualTo(viewBottom + 1),
    );
    expect(scroll.offset, greaterThan(0));
    expect(anchor.to, body.length - 20);
    expect(client.document.raw, body);

    await disposePaperController(fixture.controller);
  });

  testWidgets('收起卡片后焦点回正文目标末尾，正文与线程草稿保留', (tester) async {
    final fixture = await _pump(tester);
    final client = fixture.client;
    final body = client.document.raw;
    client.select(const TextSelection(baseOffset: 2, extentOffset: 6));
    await tester.pump();
    await tester.tap(_inline);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final thread = fixture.threads.single;
    expect(tester.widget<TextField>(_draft).focusNode!.hasFocus, isTrue);
    await tester.enterText(_draft, '保留的草稿');
    await tester.pump(const Duration(milliseconds: 400));
    expect(fixture.threads.single.draft, '保留的草稿');

    await tester.tap(find.byIcon(Icons.unfold_less).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(DiscussionPanel), findsNothing);
    expect(fixture.threads, hasLength(1));
    expect(fixture.threads.single.draft, '保留的草稿');
    expect(client.focusNode.hasFocus, isTrue);
    expect(client.value.selection.isCollapsed, isTrue);
    expect(client.value.selection.extentOffset, thread.anchor!.to);
    expect(client.document.raw, body);
    expect(
      find.byKey(ValueKey('thread-marker-open-${thread.id}')),
      findsOneWidget,
    );

    await disposePaperController(fixture.controller);
  });

  testWidgets('Shift 键盘扩选后出现就近入口，可创建讨论', (tester) async {
    final fixture = await _pump(tester);
    final client = fixture.client;
    fixture.viewport.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(client.value.selection.isCollapsed, isFalse);
    expect(_inline, findsOneWidget);
    await tester.tap(_inline);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(fixture.threads, hasLength(1));
    final target =
        fixture.threads.single.snapshot['target']! as Map<String, dynamic>;
    expect(target['from'], 0);
    expect(target['to'], 4);

    await disposePaperController(fixture.controller);
  });

  testWidgets('鼠标拖选出现就近入口；忙碌时点击不创建线程', (tester) async {
    final fixture = await _pump(tester);
    final client = fixture.client;
    final editor = fixture.viewport;
    // 用长正文保证首行有足够文字，拖拽才会产生非折叠选区。
    client.load(longBody(paragraphs: 4));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // 从首行文字的实际位置开始拖拽，保证命中正文而不是空白页边。
    final scene = editor.scene!;
    final caret = scene.caret;
    final viewportRect = tester.getRect(find.byKey(manuscriptKey));
    final start =
        viewportRect.topLeft +
        Offset(
          caret.left + scene.transform.origin.dx + 2,
          editor.headerExtent + caret.center.dy,
        );
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(client.value.selection.isCollapsed, isFalse);
    expect(_inline, findsOneWidget);

    client.select(const TextSelection(baseOffset: 0, extentOffset: 4));
    await tester.pump();
    fixture.controller.editing.inputLocked = true;
    await tester.tap(_inline);
    await tester.pump(const Duration(milliseconds: 400));
    expect(fixture.threads, isEmpty);
    // 只读屏障期间先挂起，解锁引起重绘后把光标折叠到原选区末尾。
    fixture.controller.editing.inputLocked = false;
    fixture.controller.setWide(!fixture.controller.wide);
    await tester.pump();
    await tester.pump();
    expect(client.value.selection.isCollapsed, isTrue);
    expect(client.value.selection.extentOffset, 4);

    await disposePaperController(fixture.controller);
  });
}
