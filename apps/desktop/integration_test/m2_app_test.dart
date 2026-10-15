import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:paraselene_flutter/workspace/data/demo_content.dart';
import 'package:paraselene_flutter/workspace/data/real_workspace_repository.dart';
import 'package:paraselene_flutter/workspace/workbench_app.dart';

import 'support/windows_surface.dart';

const evidence = r'D:\MyAgent\paraselene-flutter\docs\evidence\m2';
const bodyKey = ValueKey('manuscript-body');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real Windows workbench language, native resize and directory', (
    tester,
  ) async {
    final repository = await RealWorkspaceRepository.open();
    try {
      await tester.pumpWidget(
        WorkbenchApp(
          repository: repository,
          initialLocale: workbenchLocales[1],
        ),
      );
      await waitFor(tester, () => find.text('创建示例材料').evaluate().isNotEmpty);
      expect(find.text('REAL · Rust 桥接'), findsOneWidget);
      await tester.tap(find.text('创建示例材料'));
      await waitFor(tester, () => find.byKey(bodyKey).evaluate().isNotEmpty);
      expect(tester.widget<SelectableText>(find.byKey(bodyKey)).data, demoBody);
      final window = WindowsSurface();
      final sizes = <String, Object>{};
      for (final width in [1400, 800, 1200]) {
        final before = window.clientSize;
        window.resize(width, 900);
        await waitFor(tester, () => window.clientSize.width != before.width);
        sizes['$width'] = {
          'width': window.clientSize.width,
          'height': window.clientSize.height,
        };
        expect(
          tester.widget<SelectableText>(find.byKey(bodyKey)).data,
          demoBody,
        );
      }
      await capture(tester, 'windows-real-zh.png');
      await chooseLanguage(tester, '界面语言', 'English');
      expect(find.text('Writing workspace'), findsOneWidget);
      expect(tester.widget<SelectableText>(find.byKey(bodyKey)).data, demoBody);
      await capture(tester, 'windows-real-en.png');
      await chooseLanguage(tester, 'Interface language', '简体中文');
      expect(find.text('写作工作台'), findsOneWidget);
      await File('$evidence/windows-report.json').writeAsString(
        jsonEncode({
          'status': 'PASS',
          'backend': 'REAL',
          'data': 'synthetic',
          'cloudEnabled': false,
          'languageSwitchPreservedBody': true,
          'nativeClientSizes': sizes,
          'devicePixelRatio': tester.view.devicePixelRatio,
        }),
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await repository.close();
    }
  });
}

Future<void> waitFor(WidgetTester tester, bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 25));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (predicate()) {
      await tester.pump(const Duration(milliseconds: 300));
      return;
    }
  }
  throw StateError('windows_acceptance_timeout');
}

Future<void> chooseLanguage(
  WidgetTester tester,
  String menu,
  String label,
) async {
  await tester.ensureVisible(find.text(menu));
  await tester.tap(find.text(menu));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text(label).last);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('workbench-capture')),
  );
  final image = await boundary.toImage(pixelRatio: 1);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$evidence/$name').writeAsBytes(bytes!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}
