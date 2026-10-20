// 覆盖写作功能界面：章节计数与重命名、分页签搜索、作品筛选、整章讨论与导出入口。
// widget 测试只验证 Dart 交互与本地化，不代表真实持久化、FFI 或 Windows 窗口通过。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/cowrite/discussion_repository.dart';
import 'package:paraselene_flutter/editor/editor_viewport.dart';
import 'package:paraselene_flutter/workspace/data/demo_content.dart';
import 'package:paraselene_flutter/workspace/data/synthetic_workspace_repository.dart';

import 'support/m2_harness.dart';

final class _FakeDiscussions implements DiscussionRepository {
  final saved = <Map<String, dynamic>>[];
  final rows = <Map<String, dynamic>>[];
  var revision = 0;

  @override
  Future<List<Map<String, dynamic>>> listThreads(
    String work,
    String chapter,
  ) async => rows;

  @override
  Future<List<Map<String, dynamic>>> listOperations(
    String work,
    String chapter,
  ) async => [];

  @override
  Future<Map<String, dynamic>> saveThread(
    String work,
    String chapter,
    String id,
    int? expected,
    Map<String, dynamic> snapshot,
  ) async {
    revision = (expected ?? revision) + 1;
    saved.add(snapshot);
    return {'revision': revision};
  }

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

/// Adds the discussion capability to the synthetic workspace fixture.
final class _DiscussionRepository extends SyntheticWorkspaceRepository
    implements DiscussionRepositoryProvider {
  _DiscussionRepository() : super(withDemo: true);
  final fake = _FakeDiscussions();
  @override
  DiscussionRepository get discussions => fake;
}

/// 编辑器里的精确正文，用稳定 key 找生产编辑面。
String? _rawBody(WidgetTester tester) {
  final viewport = tester.widget<EditorViewport>(find.byKey(manuscriptKey));
  return viewport.controller.document.raw;
}

Finder _dialogText(String text) =>
    find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

void main() {
  // 安装真实字体度量；默认测试字体是等宽方块，英文长文案会挤爆工具栏布局。
  setUpAll(loadM2Fonts);

  testWidgets('chapter heading shows code-point count and renames explicitly', (
    tester,
  ) async {
    tester.useSurface(const Size(1440, 900));
    await tester.pumpWorkbench();
    expect(find.textContaining('78 字'), findsOneWidget);
    expect(find.text('本章结束'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget);
    expect(find.text('重做'), findsOneWidget);

    await tester.tap(find.text('重命名章节'));
    await tester.flushWorkbench();
    final field = find.byKey(const ValueKey('title-prompt-field'));
    expect(field, findsOneWidget);
    final prompt = tester.widget<TextField>(field);
    // 打开即全选原标题，直接输入就会替换，不需要先手动删除。
    expect(prompt.controller!.text, '第一章 · 归途');
    expect(
      prompt.controller!.selection,
      TextSelection(
        baseOffset: 0,
        extentOffset: prompt.controller!.text.length,
      ),
    );
    // 重命名按用途显示“保存”，新建作品/章节仍显示“创建”。
    expect(_dialogText('保存'), findsOneWidget);
    expect(_dialogText('创建'), findsNothing);

    await tester.enterText(field, '新的第一章');
    await tester.tap(_dialogText('保存'));
    await tester.flushWorkbench();
    expect(find.text('新的第一章'), findsWidgets);
    expect(find.text('第一章 · 归途'), findsNothing);
    // 目录重命名只改元数据，不改作者正文。
    expect(_rawBody(tester), demoBody);
  });

  testWidgets('rename prompt rejects an empty title and Escape cancels', (
    tester,
  ) async {
    tester.useSurface(const Size(1440, 900));
    await tester.pumpWorkbench();
    await tester.tap(find.text('重命名章节'));
    await tester.flushWorkbench();
    final field = find.byKey(const ValueKey('title-prompt-field'));

    await tester.enterText(field, '   ');
    await tester.tap(_dialogText('保存'));
    await tester.flushWorkbench();
    // 空标题校验保持：对话框不关闭，显示稳定提示。
    expect(field, findsOneWidget);
    expect(find.text('标题不能为空'), findsOneWidget);
    expect(find.text('第一章 · 归途'), findsWidgets);

    // Escape 取消：直接输入过的文字不生效，标题与正文都保持不变。
    await tester.enterText(field, '不应保存的标题');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.flushWorkbench();
    expect(field, findsNothing);
    expect(find.text('不应保存的标题'), findsNothing);
    expect(find.text('第一章 · 归途'), findsWidgets);
    expect(_rawBody(tester), demoBody);
  });

  testWidgets('tab search narrows its own object and recovers with one tap', (
    tester,
  ) async {
    tester.useSurface(const Size(1440, 900));
    await tester.pumpWorkbench();
    final search = find.byKey(const ValueKey('sidebar-search-field'));
    // 章节页签的搜索占位是“搜索章节”，不是作品搜索。
    expect(find.text('搜索章节'), findsOneWidget);
    await tester.enterText(search, '不存在的标题');
    await tester.flushWorkbench();
    expect(find.text('没有匹配的章节。'), findsOneWidget);
    expect(find.byKey(const ValueKey('chapter-demo-chapter')), findsNothing);

    // 有输入时提供一键清空，清空后目录立刻恢复。
    expect(find.byKey(const ValueKey('sidebar-search-clear')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sidebar-search-clear')));
    await tester.flushWorkbench();
    expect(find.text('没有匹配的章节。'), findsNothing);
    expect(find.byKey(const ValueKey('chapter-demo-chapter')), findsOneWidget);

    // 资料页签的占位与空态只针对资料对象。
    await tester.tap(find.text('资料').first);
    await tester.flushWorkbench();
    expect(find.text('搜索资料'), findsOneWidget);
    await tester.enterText(search, '不存在');
    await tester.flushWorkbench();
    expect(find.text('没有匹配的资料。'), findsOneWidget);
    expect(find.text('没有匹配的章节。'), findsNothing);

    // 切回章节页签会清空旧筛选词，资料搜索不影响章节与作品。
    await tester.tap(find.text('章节').first);
    await tester.flushWorkbench();
    expect(find.text('搜索章节'), findsOneWidget);
    expect(find.byKey(const ValueKey('chapter-demo-chapter')), findsOneWidget);
    expect(find.text('没有匹配的章节。'), findsNothing);
  });

  testWidgets('work picker search filters works and keeps its actions', (
    tester,
  ) async {
    final repository = SyntheticWorkspaceRepository(withDemo: true);
    await repository.createWork('另一部作品');
    tester.useSurface(const Size(1440, 900));
    await tester.pumpWorkbench(repository: repository);
    await tester.activate('切换作品');
    final search = find.byKey(const ValueKey('work-picker-search'));
    expect(search, findsOneWidget);
    expect(find.byKey(const ValueKey('work-demo-work')), findsOneWidget);
    expect(find.text('另一部作品'), findsOneWidget);

    await tester.enterText(search, '雨后');
    await tester.flushWorkbench();
    expect(find.byKey(const ValueKey('work-demo-work')), findsOneWidget);
    expect(find.text('另一部作品'), findsNothing);

    await tester.enterText(search, '不存在的作品');
    await tester.flushWorkbench();
    expect(find.text('没有匹配的作品。'), findsOneWidget);
    expect(find.byKey(const ValueKey('work-demo-work')), findsNothing);
    // 无匹配时仍保留“新建作品/关闭”动作。
    expect(find.text('新建作品'), findsOneWidget);
    expect(find.text('关闭'), findsOneWidget);

    // 一键清空后恢复完整作品列表。
    expect(
      find.byKey(const ValueKey('work-picker-search-clear')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('work-picker-search-clear')));
    await tester.flushWorkbench();
    expect(find.byKey(const ValueKey('work-demo-work')), findsOneWidget);
    expect(find.text('另一部作品'), findsOneWidget);
  });

  testWidgets('english locale scopes search hints and rename save action', (
    tester,
  ) async {
    tester.useSurface(const Size(1440, 900));
    await tester.pumpWorkbench(locale: const Locale('en'));
    expect(find.text('Search chapters'), findsOneWidget);
    await tester.tap(find.text('Materials'));
    await tester.flushWorkbench();
    expect(find.text('Search materials'), findsOneWidget);
    await tester.tap(find.text('Chapters'));
    await tester.flushWorkbench();

    await tester.tap(find.text('Rename chapter'));
    await tester.flushWorkbench();
    final field = find.byKey(const ValueKey('title-prompt-field'));
    expect(field, findsOneWidget);
    expect(_dialogText('Save'), findsOneWidget);
    expect(_dialogText('Create'), findsNothing);

    // Enter 提交保存，目录标题随之更新。
    await tester.enterText(field, 'Renamed chapter');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.flushWorkbench();
    expect(find.text('Renamed chapter'), findsWidgets);
  });

  testWidgets('whole-chapter discussion persists without a selection target', (
    tester,
  ) async {
    final repository = _DiscussionRepository();
    tester.useSurface(const Size(1440, 900));
    await tester.pumpWorkbench(repository: repository);
    expect(find.text('章节讨论'), findsWidgets);

    await tester.tap(find.text('章节讨论').first);
    await tester.flushWorkbench();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('未发草稿'), findsOneWidget);

    // The author snapshot is written by the ordinary debounce; no model call.
    await tester.pump(const Duration(milliseconds: 400));
    expect(repository.fake.saved, isNotEmpty);
    expect(repository.fake.saved.last['target'], isNull);
    expect(repository.fake.saved.last['anchor'], isNull);

    await tester.tapAt(const Offset(4, 4));
    await tester.flushWorkbench();
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('讨论记录 · 1'), findsOneWidget);

    await tester.tap(find.text('讨论记录 · 1'));
    await tester.flushWorkbench();
    expect(find.text('全章讨论'), findsOneWidget);
  });

  testWidgets('whole-chapter dialog stays usable in a narrow window', (
    tester,
  ) async {
    final repository = _DiscussionRepository();
    tester.useSurface(const Size(360, 720));
    await tester.pumpWorkbench(repository: repository);
    await tester.tap(find.byTooltip('更多'));
    await tester.flushWorkbench();
    await tester.tap(find.text('章节讨论').last);
    await tester.flushWorkbench();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('未发草稿'), findsOneWidget);
  });

  testWidgets('Ctrl+F opens the in-chapter find bar', (tester) async {
    tester.useSurface(const Size(1440, 900));
    await tester.pumpWorkbench();
    expect(find.text('下一处'), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.flushWorkbench();
    expect(find.text('下一处'), findsOneWidget);
    expect(find.widgetWithText(TextField, '查找当前章'), findsOneWidget);
  });

  testWidgets('export entry is present but recovery keeps its own flow', (
    tester,
  ) async {
    tester.useSurface(const Size(1440, 900));
    await tester.pumpWorkbench();
    expect(find.text('导出'), findsOneWidget);
    expect(find.text('本章结束'), findsOneWidget);
  });
}
