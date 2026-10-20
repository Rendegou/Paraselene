// 覆盖桌面标题栏：键盘可达性、焦点循环、拖动/双击最大化、关闭确认与窄窗口布局。
// widget 测试只验证 Dart 交互决策，不代表真实 Windows 非客户区或 DWM 行为通过。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/l10n/generated/app_localizations.dart';
import 'package:paraselene_flutter/window/desktop_title_bar.dart';
import 'package:paraselene_flutter/window/desktop_window_controller.dart';
import 'package:paraselene_flutter/workspace/data/synthetic_workspace_repository.dart';
import 'package:paraselene_flutter/workspace/workbench_app.dart';

class WindowFixture extends DesktopWindowController {
  @override
  bool available = true;
  @override
  bool maximized = false;
  @override
  bool focused = true;
  @override
  bool actionFailed = false;
  int minimizes = 0;
  int closes = 0;
  int drags = 0;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> minimize() async {
    minimizes++;
  }

  @override
  Future<void> requestClose() async {
    closes++;
  }

  @override
  Future<void> startDragging() async {
    drags++;
  }

  @override
  Future<void> toggleMaximize() async {
    maximized = !maximized;
    notifyListeners();
  }
}

Future<void> mountBar(
  WidgetTester tester,
  WindowFixture window, {
  Locale locale = const Locale('en'),
  bool rtl = false,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale), highContrast: true),
          child: Directionality(
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            child: Align(
              alignment: Alignment.topCenter,
              child: ListenableBuilder(
                listenable: window,
                builder: (context, _) => DesktopTitleBar(
                  controller: window,
                  title: '中文 manuscript title ' * 10,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<Set<String>> traverseCaptions(WidgetTester tester) async {
  final reached = <String>{};
  for (var step = 0; step < 30; step++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    for (final label in ['Minimize', 'Maximize', 'Close window']) {
      final node = tester.getSemantics(find.bySemanticsLabel(label));
      if (node.getSemanticsData().hasFlag(SemanticsFlag.isFocused)) {
        reached.add(label);
      }
    }
    if (reached.length == 3) break;
  }
  return reached;
}

void main() {
  testWidgets('workbench captions are reachable by keyboard traversal', (
    tester,
  ) async {
    final repository = SyntheticWorkspaceRepository();
    await repository.createWork('Synthetic keyboard traversal');
    final window = WindowFixture();
    await tester.pumpWidget(
      WorkbenchApp(
        repository: repository,
        initialLocale: const Locale('en'),
        windowController: window,
      ),
    );
    await tester.pumpAndSettle();
    final reached = await traverseCaptions(tester);
    expect(reached, {'Minimize', 'Maximize', 'Close window'});
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(window.closes, 1);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    final reverseReached = await traverseCaptions(tester);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(reverseReached, {'Minimize', 'Maximize', 'Close window'});
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('modal dialog retains its forward and reverse focus loop', (
    tester,
  ) async {
    final repository = SyntheticWorkspaceRepository();
    await repository.createWork('Synthetic modal focus');
    await tester.pumpWidget(
      WorkbenchApp(
        repository: repository,
        initialLocale: const Locale('en'),
        windowController: WindowFixture(),
      ),
    );
    await tester.pumpAndSettle();
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    final dialog = showDialog<void>(
      context: navigator.context,
      builder: (context) => AlertDialog(
        title: const Text('Synthetic modal'),
        actions: [
          TextButton(onPressed: () {}, child: const Text('First action')),
          TextButton(onPressed: () {}, child: const Text('Second action')),
        ],
      ),
    );
    await tester.pumpAndSettle();
    for (final reverse in [false, true]) {
      if (reverse) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      }
      for (var step = 0; step < 8; step++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          FocusManager.instance.primaryFocus!.context!
              .findAncestorWidgetOfExactType<AlertDialog>(),
          isNotNull,
        );
      }
      if (reverse) {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      }
    }
    navigator.pop();
    await tester.pumpAndSettle();
    await dialog;
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('only title gestures drag and double click toggles maximize', (
    tester,
  ) async {
    final window = WindowFixture();
    await mountBar(tester, window);
    await tester.drag(find.byType(WindowDragRegion), const Offset(90, 40));
    expect(window.drags, 1);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(WindowDragRegion));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(find.byType(WindowDragRegion));
    await tester.pumpAndSettle();
    expect(window.maximized, isTrue);
    await tester.drag(find.byTooltip('Close window'), const Offset(-90, 30));
    expect(window.drags, 1);
    expect(window.closes, 0);
  });

  testWidgets('workbench shell provides an overlay outside its Navigator', (
    tester,
  ) async {
    final repository = SyntheticWorkspaceRepository();
    await repository.createWork('Synthetic shell title');
    final window = WindowFixture();
    await tester.pumpWidget(
      WorkbenchApp(
        repository: repository,
        initialLocale: const Locale('en'),
        windowController: window,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DesktopTitleBar), findsOneWidget);
    final closeNode = tester.getSemantics(
      find.bySemanticsLabel('Close window'),
    );
    expect(
      closeNode.getSemanticsData().hasFlag(SemanticsFlag.isFocusable),
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await tester.longPress(find.byTooltip('Close window'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('caption actions, state, drag exclusion and keyboard close', (
    tester,
  ) async {
    final window = WindowFixture();
    await mountBar(tester, window);
    await tester.tap(find.byTooltip('Minimize'));
    expect(window.minimizes, 1);
    expect(window.drags, 0);
    await tester.tap(find.byTooltip('Maximize'));
    await tester.pump();
    expect(find.byTooltip('Restore'), findsOneWidget);
    await tester.tap(find.byTooltip('Restore'));
    await tester.pump();
    expect(window.maximized, isFalse);
    // Focus caption close directly, then use the normal keyboard activation path.
    final close = tester.widget<IconButton>(
      find.descendant(
        of: find.byTooltip('Close window'),
        matching: find.byType(IconButton),
      ),
    );
    final focus = Focus.of(tester.element(find.byIcon(Icons.close)));
    focus.requestFocus();
    await tester.pump();
    final focusedNode = tester.getSemantics(
      find.bySemanticsLabel('Close window'),
    );
    expect(
      focusedNode.getSemanticsData().hasFlag(SemanticsFlag.isFocusable),
      isTrue,
    );
    expect(
      focusedNode.getSemanticsData().hasFlag(SemanticsFlag.isFocused),
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(close.onPressed, isNotNull);
    expect(window.closes, 1);
    expect(window.drags, 0);
  });

  for (final rtl in [false, true]) {
    for (final locale in [
      const Locale('en'),
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    ]) {
      for (final width in [360.0, 900.0]) {
        testWidgets(
          'caption semantics and scaled layout $locale RTL=$rtl width=$width',
          (tester) async {
            tester.view.physicalSize = Size(width, 600);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            await mountBar(
              tester,
              WindowFixture(),
              locale: locale,
              rtl: rtl,
              scale: 2,
            );
            final labels = locale.languageCode == 'en'
                ? ['Minimize', 'Maximize', 'Close window']
                : ['最小化', '最大化', '关闭窗口'];
            for (final label in labels) {
              final node = tester.getSemantics(find.bySemanticsLabel(label));
              expect(
                node.getSemanticsData().hasAction(SemanticsAction.tap),
                isTrue,
              );
              expect(node.rect.width, greaterThanOrEqualTo(44));
              expect(node.rect.height, greaterThanOrEqualTo(44));
              expect(
                node.getSemanticsData().hasFlag(SemanticsFlag.isFocusable),
                isTrue,
              );
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
