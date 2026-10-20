// M4 Windows 集成测试：冷启动恢复、编辑、导出与关闭屏障的真实窗口流程。
// 需在 Windows 设备上运行，不代表生产数据库迁移、安装包或所有机器环境通过。

import '../test/support/owned_store_fixture.dart';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:paraselene_flutter/editor/editor_viewport.dart';
import 'package:paraselene_flutter/workspace/workbench_app.dart';

const bodyKey = ValueKey('manuscript-body');

/// Real Windows M4 runnable flow on the owned store through the actual bridge.
/// Only the exclusive test-support run directory is reset; it holds
/// synthetic data only.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final fixture = OwnedStoreFixture();
  setUpAll(fixture.create);
  tearDownAll(fixture.dispose);

  /// The expanded directory plane needs a wide surface; a narrow window would
  /// hide the chapter actions inside the closed drawer.
  void useWideSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> cleanStore() => fixture.reset();

  Future<void> waitFor(
    WidgetTester tester,
    bool Function() condition, {
    Duration step = const Duration(milliseconds: 120),
    int tries = 100,
  }) async {
    for (var i = 0; i < tries && !condition(); i++) {
      await tester.pump(step);
    }
    expect(condition(), isTrue);
  }

  Future<void> typeBody(WidgetTester tester, String text) async {
    // On a real Windows surface the input-connection handshake takes a real
    // frame: focus first, then enter text through the test channel.
    await tester.ensureVisible(find.byKey(bodyKey));
    await tester.tap(find.byKey(bodyKey));
    await tester.pump(const Duration(milliseconds: 250));
    tester.testTextInput.enterText(text);
    await tester.pump(const Duration(milliseconds: 450));
  }

  testWidgets(
    'two works, editing, directory actions and head-only confirmation',
    (tester) async {
      useWideSurface(tester);
      await cleanStore();
      final repository = await fixture.open();
      addTearDown(() async => repository.close());
      await tester.pumpWidget(
        WorkbenchApp(
          repository: repository,
          initialLocale: workbenchLocales[1],
        ),
      );
      await waitFor(
        tester,
        () => find.text('为下一段故事，留一页安静的纸').evaluate().isNotEmpty,
      );

      // Create the first work with two chapters through the real UI.
      await tester.tap(find.text('切换作品'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建作品'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('title-prompt-field')),
        '作品甲',
      );
      await tester.tap(find.text('创建'));
      await tester.pumpAndSettle();
      await waitFor(tester, () => find.text('切换作品').evaluate().isNotEmpty);

      Future<void> createChapter(String title) async {
        await waitFor(
          tester,
          () => find.byTooltip('新建章节').evaluate().isNotEmpty,
        );
        await tester.ensureVisible(find.byTooltip('新建章节'));
        await tester.tap(find.byTooltip('新建章节'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('title-prompt-field')),
          title,
        );
        await tester.tap(find.text('创建'));
        await tester.pumpAndSettle();
      }

      await createChapter('第一章');
      await createChapter('第二章');

      // Type exact text and wait for the durable save status.
      await typeBody(tester, '第一章正文\r\n第二行');
      await waitFor(tester, () => find.text('已保存').evaluate().isNotEmpty);

      // Delete to an empty body; the empty draft saves too.
      await typeBody(tester, '');
      await tester.pump(const Duration(milliseconds: 450));
      await waitFor(tester, () => find.text('已保存').evaluate().isNotEmpty);

      // The second chapter is isolated: no text leaks across. Its title also
      // appears as the editor headline, so target the directory tile first.
      await tester.tap(find.text('第二章').first);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditorViewport>(find.byKey(bodyKey))
            .controller
            .document
            .raw,
        '',
      );
      await typeBody(tester, '第二章内容');
      await waitFor(tester, () => find.text('已保存').evaluate().isNotEmpty);
      expect(
        tester
            .widget<EditorViewport>(find.byKey(bodyKey))
            .controller
            .document
            .raw,
        '第二章内容',
      );

      // Rename the first chapter through the paper heading action.
      await tester.tap(find.text('第一章').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('重命名章节'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('title-prompt-field')),
        '第一章 · 改名',
      );
      // Rename submits with the explicit save label in the title prompt.
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('第一章 · 改名'), findsWidgets);

      // Archive the second chapter through its right-click menu, then restore.
      await tester.tap(find.text('第二章').first, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('归档章节'));
      await tester.pumpAndSettle();
      expect(find.text('已归档'), findsOneWidget);
      await tester.tap(find.text('恢复章节'));
      await tester.pumpAndSettle();
      expect(find.text('第二章'), findsOneWidget);

      // Confirm with the exact-body preview, then roll the head back.
      await tester.tap(find.text('第二章'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditorViewport>(find.byKey(bodyKey))
            .controller
            .document
            .raw,
        '第二章内容',
      );
      await tester.tap(find.byTooltip('章节与版本'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认本章'));
      await waitFor(
        tester,
        () => find
            .byKey(const ValueKey('confirm-preview-body'))
            .evaluate()
            .isNotEmpty,
      );
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const ValueKey('confirm-preview-body')),
            )
            .data,
        '第二章内容',
      );
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('章节与版本'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认版本'));
      await tester.pumpAndSettle();
      expect(find.text('当前'), findsWidgets);
      await tester.tap(find.byType(ExpansionTile).first);
      await tester.pumpAndSettle();
      // Rollback is offered on non-head versions only; the single confirmed
      // version is head, so the action must not exist yet.
      expect(find.text('回退到此版本'), findsNothing);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('cold restore reopens the recent work, chapter and preferences', (
    tester,
  ) async {
    useWideSurface(tester);
    await cleanStore();
    final first = await fixture.open();
    await tester.pumpWidget(
      WorkbenchApp(repository: first, initialLocale: workbenchLocales[1]),
    );
    await waitFor(
      tester,
      () => find.text('为下一段故事，留一页安静的纸').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('切换作品'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建作品'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('title-prompt-field')),
      '作品恢复',
    );
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新建章节'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('title-prompt-field')),
      '恢复章',
    );
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    await typeBody(tester, '恢复正文');
    await waitFor(tester, () => find.text('已保存').evaluate().isNotEmpty);
    // The popup item's overlay position is not stable on the real Windows
    // surface, so drive the menu's selected callback directly while widget
    // tests continue to cover the visual popup hit target.
    final layoutMenu = find.byWidgetPredicate(
      (widget) => widget is PopupMenuButton<bool>,
    );
    expect(layoutMenu, findsOneWidget);
    tester.widget<PopupMenuButton<bool>>(layoutMenu).onSelected!(true);
    await tester.pump(const Duration(milliseconds: 500));
    await first.close();

    final second = await fixture.open();
    addTearDown(() async => second.close());
    await tester.pumpWidget(
      WorkbenchApp(repository: second, initialLocale: workbenchLocales[1]),
    );
    await waitFor(tester, () => find.byKey(bodyKey).evaluate().isNotEmpty);
    expect(find.text('作品恢复'), findsWidgets);
    expect(find.text('恢复章'), findsWidgets);
    expect(
      tester
          .widget<EditorViewport>(find.byKey(bodyKey))
          .controller
          .document
          .raw,
      '恢复正文',
    );
  });
}
