// Native widget geometry/state contracts. No FFI, author data or network.
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/theme/workbench_theme.dart';

void main() {
  for (final icon in [false, true]) {
    testWidgets('${icon ? 'icon' : 'text'} plate stays inside its 48px hit box', (
      tester,
    ) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: workbenchTheme(),
          home: Scaffold(
            body: Center(
              child: icon
                  ? IconButton(
                      focusNode: focus,
                      onPressed: () {
                        calls++;
                      },
                      icon: const Icon(Icons.add),
                    )
                  : TextButton(
                      focusNode: focus,
                      onPressed: () {
                        calls++;
                      },
                      child: const Text('Action'),
                    ),
            ),
          ),
        ),
      );
      final control = icon ? find.byType(IconButton) : find.byType(TextButton);
      final plate = find
          .descendant(of: control, matching: find.byType(Material))
          .first;
      final before = tester.getRect(control);
      final visible = tester.getRect(plate);
      expect(before.height, greaterThanOrEqualTo(48));
      expect(before.width, greaterThanOrEqualTo(48));
      expect(visible.height, 32);
      expect(visible.width, lessThanOrEqualTo(before.width));
      // Transparent top padding remains clickable; it is outside the paint plate.
      await tester.tapAt(Offset(before.center.dx, before.top + 2));
      expect(calls, 1);
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(before.center);
      await tester.pumpAndSettle();
      expect(tester.getRect(plate), visible);
      await mouse.down(before.center);
      await tester.pump();
      expect(tester.getRect(plate), visible);
      await mouse.up();
      focus.requestFocus();
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isTrue);
      final material = tester.widget<Material>(plate);
      expect(
        (material.shape! as OutlinedBorder).side.color,
        WorkbenchTokens.accent,
      );
      expect(tester.getRect(plate), visible);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(calls, 3);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('disabled button retains semantics and cannot activate', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        theme: workbenchTheme(),
        home: Scaffold(
          body: TextButton(onPressed: null, child: const Text('Unavailable')),
        ),
      ),
    );
    final node = tester.getSemantics(find.byType(TextButton));
    expect(node.hasFlag(SemanticsFlag.hasEnabledState), isTrue);
    expect(node.hasFlag(SemanticsFlag.isEnabled), isFalse);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    final style = workbenchTheme().textButtonTheme.style!;
    final disabled = {
      WidgetState.disabled,
      WidgetState.hovered,
      WidgetState.focused,
    };
    expect(style.overlayColor!.resolve(disabled), Colors.transparent);
    expect(style.side!.resolve(disabled)!.color, Colors.transparent);
    expect(
      style.foregroundColor!.resolve(disabled),
      isNot(WorkbenchTokens.ink),
    );
    semantics.dispose();
  });

  testWidgets('large labels grow without overflow or shrinking text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: workbenchTheme(),
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: SizedBox(
              width: 180,
              child: TextButton(
                onPressed: () {},
                child: const Text('Preview complete discussion materials'),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(TextButton)).height, greaterThan(48));
  });
}
