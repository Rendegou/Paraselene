import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_editor_spike/c_native.dart';
import 'package:paraselene_editor_spike/c_viewport.dart';
import 'package:paraselene_editor_spike/c_main.dart';
import 'package:paraselene_editor_spike/c_profile.dart';
import 'package:paraselene_editor_spike/spike_fonts.dart';

Future<GlobalKey<CViewportState>> mount(
  WidgetTester tester,
  CNativeEditor editor,
) async {
  final key = GlobalKey<CViewportState>();
  tester.view.physicalSize = const Size(1000, 700);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CViewport(key: key, editor: editor),
      ),
    ),
  );
  key.currentState!.requestFocus();
  await tester.pump();
  return key;
}

void main() {
  setUpAll(loadSpikeFonts);
  for (final fixture in ['heterogeneous', 'heterogeneous-single-line']) {
    testWidgets(
      'lazy $fixture scrolling paints every visible pixel from current raw',
      (tester) async {
        final editor = CNativeEditor(cFixture(fixture));
        final key = await mount(tester, editor);
        final state = key.currentState!;
        for (var i = 0; i < 120; i++) {
          state.scroll.jumpTo(state.scroll.position.maxScrollExtent * i / 119);
          await tester.pump();
          expect(tester.takeException(), isNull);
          final pages = state.scene!.pages;
          expect(pages, isNotEmpty);
          var bottom = 0.0;
          for (final page in pages) {
            expect(
              page.page.text,
              editor.document.raw.substring(page.page.start, page.page.end),
            );
            expect(page.origin.dy, lessThanOrEqualTo(bottom + .1));
            bottom = page.origin.dy + page.page.height;
          }
          final required = (editor.layout.height - state.scroll.offset).clamp(
            0.0,
            700.0,
          );
          expect(bottom + .1, greaterThanOrEqualTo(required));
        }
        await tester.pumpWidget(const SizedBox());
        editor.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      },
    );
  }
  testWidgets('tall viewport leases more than 32 visible painters safely', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1900);
    tester.view.devicePixelRatio = 1;
    final editor = CNativeEditor(
      List.generate(140, (i) => 'unique paragraph $i 月光\r\n').join(),
    );
    final key = GlobalKey<CViewportState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CViewport(key: key, editor: editor),
        ),
      ),
    );
    final state = key.currentState!;
    expect(state.scene!.pages.length, greaterThan(40));
    expect(state.painters.activeEntries, greaterThan(40));
    expect(tester.takeException(), isNull);
    editor.select(TextSelection.collapsed(offset: editor.length));
    state.ensureCaret();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(state.painters.warmEntries, lessThanOrEqualTo(32));
    expect(
      state.painters.length,
      lessThanOrEqualTo(state.painters.activeEntries + 32),
    );
    state.scroll.jumpTo(0);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    editor.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  testWidgets(
    'SLOT and locale probe preserve active native connection and composition',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(const CSpikeApp(autoProfile: false));
      final viewport = tester.state<CViewportState>(find.byType(CViewport));
      viewport.requestFocus();
      await tester.pump();
      final editor = tester.widget<CViewport>(find.byType(CViewport)).editor;
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'ni\r\n',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 2),
        ),
      );
      await tester.pump();
      final before = editor.value;
      final clients = tester.testTextInput.log
          .where((call) => call.method == 'TextInput.setClient')
          .length;
      final stateEchoes = tester.testTextInput.log
          .where((call) => call.method == 'TextInput.setEditingState')
          .length;
      await tester.tap(find.text('Toggle SLOT'));
      await tester.pump();
      await tester.tap(find.text('Locale probe: en'));
      await tester.pumpAndSettle();
      viewport.requestFocus();
      await tester.pump();
      expect(
        tester.testTextInput.log
            .where((call) => call.method == 'TextInput.setEditingState')
            .length,
        stateEchoes,
        reason: 'Toolbar/refocus must not echo an IME-owned composing value',
      );
      expect(editor.value, before);
      expect(editor.focusNode.hasFocus, isTrue);
      expect(
        tester.state<CViewportState>(find.byType(CViewport)),
        same(viewport),
      );
      expect(
        tester.testTextInput.log
            .where((call) => call.method == 'TextInput.setClient')
            .length,
        clients,
      );
      expect(
        tester.testTextInput.log.where(
          (call) => call.method == 'TextInput.clearClient',
        ),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
  testWidgets(
    'one native global client paints bounded pages and global callback selection',
    (tester) async {
      final editor = CNativeEditor(
        List.generate(3000, (i) => 'paragraph$i 合成正文\r\n').join(),
      );
      final key = await mount(tester, editor);
      expect(find.byType(EditableText), findsNothing);
      expect(editor.attached, isTrue);
      expect(key.currentState!.scene!.pages.length, lessThan(30));
      expect(key.currentState!.painters.length, lessThanOrEqualTo(32));
      final raw = editor.document.raw;
      final next = TextEditingValue(
        text: raw.replaceRange(20000, 20000, '你'),
        selection: const TextSelection.collapsed(offset: 20001),
        composing: const TextRange(start: 20000, end: 20001),
      );
      tester.testTextInput.updateEditingValue(next);
      await tester.pump();
      expect(editor.value, next);
      expect(editor.nativeCallbacks, 1);
      final config =
          tester.testTextInput.log
                  .lastWhere((c) => c.method == 'TextInput.setClient')
                  .arguments
              as List;
      expect((config[1] as Map)['viewId'], tester.view.viewId);
      await tester.pumpWidget(const SizedBox());
      editor.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
  testWidgets('keyboard deletion honors grapheme boundaries and global undo', (
    tester,
  ) async {
    final editor = CNativeEditor('a👩‍💻e\u0301\r\nz');
    await mount(tester, editor);
    editor.select(const TextSelection.collapsed(offset: 6));
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(editor.document.raw, 'ae\u0301\r\nz');
    editor.undo();
    expect(editor.document.raw, 'a👩‍💻e\u0301\r\nz');
    editor.select(const TextSelection.collapsed(offset: 8));
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    expect(editor.document.raw, 'a👩‍💻e\u0301z');
    await tester.pumpWidget(const SizedBox());
    editor.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  testWidgets(
    'platform caret inside combining cluster deletes entire grapheme',
    (tester) async {
      final editor = CNativeEditor('ae\u0301z');
      await mount(tester, editor);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'ae\u0301z',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      expect(editor.value.selection.extentOffset, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      expect(editor.document.raw, 'az');
      editor.undo();
      expect(editor.document.raw, 'ae\u0301z');
      await tester.pumpWidget(const SizedBox());
      editor.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
  testWidgets(
    'composition retains keyboard ownership and same viewport survives slot',
    (tester) async {
      final editor = CNativeEditor('abc\r\n');
      final key = await mount(tester, editor);
      final state = key.currentState;
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'abni\r\n',
          selection: TextSelection.collapsed(offset: 4),
          composing: TextRange(start: 2, end: 4),
        ),
      );
      await tester.pump();
      final value = editor.value;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(editor.value, value);
      editor.toggleSlot();
      await tester.pump();
      expect(key.currentState, same(state));
      expect(editor.focusNode.hasFocus, isTrue);
      expect(editor.value, value);
      expect(editor.layout.slots.length, 1);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'ab你\r\n',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      await tester.pump();
      editor.undo();
      expect(editor.document.raw, 'abc\r\n');
      await tester.pumpWidget(const SizedBox());
      editor.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
  testWidgets('clipboard mocks preserve CRLF and failures are visible state', (
    tester,
  ) async {
    final editor = CNativeEditor('abc\r\ndef');
    await mount(tester, editor);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    String? copied;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
        return null;
      }
      if (call.method == 'Clipboard.getData') return {'text': 'x\r\ny'};
      return null;
    });
    editor.select(const TextSelection(baseOffset: 0, extentOffset: 5));
    await editor.clipboard('copy');
    expect(copied, 'abc\r\n');
    await editor.clipboard('paste');
    expect(editor.document.raw, 'x\r\nydef');
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method.startsWith('Clipboard.')) {
        throw PlatformException(code: 'synthetic-denied');
      }
      return null;
    });
    await editor.clipboard('paste');
    expect(editor.error, contains('synthetic-denied'));
    await tester.pump();
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    await tester.pumpWidget(const SizedBox());
    editor.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
