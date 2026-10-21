import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/theme/workbench_theme.dart';
import 'package:paraselene_flutter/theme/workbench_select.dart';
import 'package:paraselene_flutter/l10n/generated/app_localizations.dart';
import 'package:paraselene_flutter/lore/lore_scope_picker.dart';
import 'support/m2_harness.dart';

void main() {
  setUpAll(loadM2Fonts);
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'selector preserves historic values and keyboard focus at $scale',
      (tester) async {
        tester.useSurface(const Size(480, 720));
        String? changed;
        await tester.pumpWidget(
          MaterialApp(
            theme: workbenchTheme(),
            locale: chinese,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 320,
                  child: LoreScopePicker(
                    value: 'historical:unchanged',
                    chapters: const [('chapter', '一段很长的章节标题用于检验自动换行与菜单高度')],
                    onChanged: (value) => changed = value,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final trigger = find.byType(TextButton);
        final initial = tester.getRect(trigger);
        expect(initial.height, greaterThanOrEqualTo(48));
        await tester.tap(trigger);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<CheckedPopupMenuItem<String>>(
                find.byType(CheckedPopupMenuItem<String>).last,
              )
              .checked,
          isTrue,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(changed, isNull);
        final button = tester.widget<TextButton>(trigger);
        expect(button.focusNode!.hasFocus, isTrue);
        expect(tester.getRect(trigger), initial);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        await tester.tap(find.byType(CheckedPopupMenuItem<String>).first);
        await tester.pumpAndSettle();
        expect(changed, 'whole');
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('disabled selector cannot open a menu', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: workbenchTheme(),
        home: Scaffold(
          body: WorkbenchSelect<String>(
            value: 'a',
            items: const [
              DropdownMenuItem(value: 'a', child: Text('Read only')),
            ],
            onChanged: null,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect(find.byType(CheckedPopupMenuItem<String>), findsNothing);
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNull,
    );
  });
  testWidgets(
    'tool input disabled ink and state geometry resolve independently',
    (tester) async {
      final controller = TextEditingController(
        text: 'Read only synthetic text',
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: workbenchTheme(),
          home: Scaffold(
            body: TextField(
              controller: controller,
              enabled: false,
              style: WorkbenchTokens.input,
            ),
          ),
        ),
      );
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.style.fontFamily, WorkbenchTokens.uiFont);
      expect(editable.style.fontSize, 14);
      expect(
        editable.style.color,
        WorkbenchTokens.muted.withValues(alpha: 0.5),
      );
      final theme = workbenchTheme().inputDecorationTheme;
      expect(
        (theme.disabledBorder! as OutlineInputBorder).borderRadius,
        (theme.enabledBorder! as OutlineInputBorder).borderRadius,
      );
      expect(
        (theme.focusedBorder! as OutlineInputBorder).borderRadius,
        (theme.enabledBorder! as OutlineInputBorder).borderRadius,
      );
    },
  );
  for (final switchControl in [false, true]) {
    testWidgets(
      '${switchControl ? 'switch' : 'checkbox'} preserves native state and geometry',
      (tester) async {
        final focus = FocusNode();
        addTearDown(focus.dispose);
        var selected = false;
        var disabled = false;
        late StateSetter update;
        await tester.pumpWidget(
          MaterialApp(
            theme: workbenchTheme(),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return switchControl
                      ? SwitchListTile(
                          focusNode: focus,
                          value: selected,
                          title: const Text('Local choice'),
                          onChanged: disabled
                              ? null
                              : (value) => setState(() => selected = value),
                        )
                      : CheckboxListTile(
                          focusNode: focus,
                          value: selected,
                          title: const Text('Local choice'),
                          onChanged: disabled
                              ? null
                              : (value) => setState(() => selected = value!),
                        );
                },
              ),
            ),
          ),
        );
        final control = switchControl
            ? find.byType(SwitchListTile)
            : find.byType(CheckboxListTile);
        final before = tester.getRect(control);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(control));
        await tester.pumpAndSettle();
        expect(tester.getRect(control), before);
        await mouse.down(tester.getCenter(control));
        await tester.pump();
        expect(tester.getRect(control), before);
        await mouse.up();
        await tester.pumpAndSettle();
        expect(selected, isTrue);
        focus.requestFocus();
        await tester.pumpAndSettle();
        expect(tester.getRect(control), before);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(selected, isFalse);
        update(() => disabled = true);
        await tester.pumpAndSettle();
        await tester.tap(control);
        expect(selected, isFalse);
        expect(tester.getRect(control), before);
        await mouse.removePointer();
      },
    );
  }
}
