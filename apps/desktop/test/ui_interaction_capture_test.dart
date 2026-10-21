import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/cowrite/discussion_panel.dart';
import 'package:paraselene_flutter/editor/editor_anchor.dart';
import 'package:paraselene_flutter/theme/workbench_theme.dart';
import 'operation_parity/paper_harness.dart';
import 'operation_parity/review_fixes_test.dart' show ReviewRepository;
import 'support/m2_harness.dart';

void main() {
  testWidgets('capture real discussion surface and control geometry', (
    tester,
  ) async {
    final previousShadows = debugDisableShadows;
    debugDisableShadows = false;
    addTearDown(() {
      debugDisableShadows = previousShadows;
    });
    final narrow = Platform.environment['UI_CAPTURE_NARROW'] == '1';
    await loadM2Fonts();
    final controller = await pumpPaperWorkbench(
      tester,
      repository: ReviewRepository(),
      size: narrow ? const Size(680, 900) : const Size(1440, 900),
      textScale: narrow ? 2 : 1,
    );
    final registry = controller.discussions!;
    final thread = registry.create(EditorAnchor.capture(controller.body, 0, 4));
    await tester.pump();
    await tester.tap(find.byKey(ValueKey('thread-marker-open-${thread.id}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byType(DiscussionPanel), findsOneWidget);
    final field = find.descendant(
      of: find.byType(DiscussionPanel),
      matching: find.byType(TextField),
    );
    final button = find.widgetWithText(TextButton, '对比');
    final rect = tester.getRect(button);
    final phase = Platform.environment['UI_CAPTURE_PHASE'] ?? 'after';
    Future<void> capture(String name) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('paper-capture-root')),
      );
      await tester.runAsync(() async {
        final rendered = await boundary.toImage();
        final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory('../../build/ui-interaction-20261021');
        await dir.create(recursive: true);
        await File(
          '${dir.path}/$phase-$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        rendered.dispose();
      });
    }

    await capture('empty');
    await tester.tap(field);
    await capture('focus');
    await tester.enterText(field, '合成讨论：保留雨声，调整这一段的节奏。');
    await capture('draft');
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(button));
    await capture('hover');
    await mouse.down(tester.getCenter(button));
    await capture('pressed');
    await mouse.up();
    expect(tester.getRect(button), rect);
    final theme = workbenchTheme();
    debugPrint(
      'UI_GEOMETRY $phase button=$rect card=${theme.cardTheme.color} tint=${theme.cardTheme.surfaceTintColor} textMinimum=${theme.textButtonTheme.style!.minimumSize!.resolve({})}',
    );
    await mouse.removePointer();
    await tester.tap(find.byTooltip('收起讨论'));
    await tester.pump();
    expect(find.byType(DiscussionPanel), findsNothing);
    await tester.tap(find.byKey(ValueKey('thread-marker-open-${thread.id}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.widget<TextField>(field).controller!.text, contains('合成讨论'));
    await capture('reopen');
    if (!narrow) {
      await tester.tap(find.byTooltip('章节讨论'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      await capture('dialog');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await capture('menu');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await registry.flush();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.editing.flushAll();
    controller.dispose();
    debugDisableShadows = previousShadows;
  });
}
