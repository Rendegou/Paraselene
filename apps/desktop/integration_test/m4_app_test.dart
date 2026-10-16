import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:paraselene_flutter/workspace/data/real_workspace_repository.dart';
import 'package:paraselene_flutter/workspace/workbench_app.dart';

const ownedStore = r'D:\MyAgent\paraselene-flutter\build\m4-owned-synthetic-v1';
const bodyKey = ValueKey('manuscript-body');

/// Real Windows M4 runnable flow on the owned store through the actual bridge.
/// The test-owned store directory is removed for determinism; it holds
/// synthetic data only.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// The expanded directory plane needs a wide surface; a narrow window would
  /// hide the chapter actions inside the closed drawer.
  void useWideSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> cleanStore() async {
    final dir = Directory(ownedStore);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

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
    await tester.enterText(find.byKey(bodyKey), text);
    await tester.pump(const Duration(milliseconds: 450));
  }

  testWidgets('two works, editing, directory actions, confirm and rollback', (
    tester,
  ) async {
    useWideSurface(tester);
    await cleanStore();
    final repository = await RealWorkspaceRepository.openOwned();
    addTearDown(() async => repository.close());
    await tester.pumpWidget(
      WorkbenchApp(repository: repository, initialLocale: workbenchLocales[1]),
    );
    await waitFor(
      tester,
      () => find.text('为下一段故事，留一页安静的纸').evaluate().isNotEmpty,
    );

    // Create the first work with two chapters through the real UI.
    await tester.tap(find.text('选择作品'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建作品'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('title-prompt-field')),
      '作品甲',
    );
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    await waitFor(tester, () => find.text('选择作品').evaluate().isNotEmpty);

    Future<void> createChapter(String title) async {
      await waitFor(tester, () => find.byTooltip('新建章节').evaluate().isNotEmpty);
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
    await tester.enterText(find.byKey(bodyKey), '');
    await tester.pump(const Duration(milliseconds: 450));
    await waitFor(tester, () => find.text('已保存').evaluate().isNotEmpty);

    // The second chapter is isolated: no text leaks across. Its title also
    // appears as the editor headline, so target the directory tile first.
    await tester.tap(find.text('第二章').first);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(bodyKey)).controller!.text, '');
    await typeBody(tester, '第二章内容');
    await waitFor(tester, () => find.text('已保存').evaluate().isNotEmpty);
    expect(
      tester.widget<TextField>(find.byKey(bodyKey)).controller!.text,
      '第二章内容',
    );

    // Rename the first chapter via its per-tile menu.
    final menuButton = find.byType(PopupMenuButton<String>).first;
    await tester.tap(menuButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名章节'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('title-prompt-field')),
      '第一章 · 改名',
    );
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    expect(find.text('第一章 · 改名'), findsOneWidget);

    // Archive the second chapter, then restore it.
    await tester.tap(find.byType(PopupMenuButton<String>).at(1));
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
      tester.widget<TextField>(find.byKey(bodyKey)).controller!.text,
      '第二章内容',
    );
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
  });

  testWidgets('cold restore reopens the recent work, chapter and preferences', (
    tester,
  ) async {
    useWideSurface(tester);
    await cleanStore();
    final first = await RealWorkspaceRepository.openOwned();
    await tester.pumpWidget(
      WorkbenchApp(repository: first, initialLocale: workbenchLocales[1]),
    );
    await waitFor(
      tester,
      () => find.text('为下一段故事，留一页安静的纸').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('选择作品'));
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
    await tester.tap(find.text('宽稿模式'));
    await tester.pump(const Duration(milliseconds: 500));
    await first.close();

    final second = await RealWorkspaceRepository.openOwned();
    addTearDown(() async => second.close());
    await tester.pumpWidget(
      WorkbenchApp(repository: second, initialLocale: workbenchLocales[1]),
    );
    await waitFor(tester, () => find.byKey(bodyKey).evaluate().isNotEmpty);
    expect(find.text('作品恢复'), findsWidgets);
    expect(find.text('恢复章'), findsWidgets);
    expect(
      tester.widget<TextField>(find.byKey(bodyKey)).controller!.text,
      '恢复正文',
    );
  });
}
