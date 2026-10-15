import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:paraselene_editor_spike/candidate_a.dart';

Widget harness(
  GlobalKey<EditableCandidateAState> key, {
  String text = '首段😀\r\n第二段 e\u0301 العربية',
  bool discussion = false,
  TextDirection direction = TextDirection.ltr,
}) => MaterialApp(
  home: Directionality(
    textDirection: direction,
    child: SizedBox(
      width: 600,
      height: 400,
      child: EditableCandidateA(
        key: key,
        initialText: text,
        onValue: (_) {},
        showDiscussion: discussion,
      ),
    ),
  ),
);

void main() {
  registerComposition();
  registerSlot();
  registerHistory();
  registerClipboard();
  registerLimits();
}

void registerComposition() {
  testWidgets('raw CRLF emoji and composition survive layout/locale rebuild', (
    tester,
  ) async {
    final key = GlobalKey<EditableCandidateAState>();
    await tester.pumpWidget(harness(key));
    final state = key.currentState!;
    final controller = state.controller;
    final focus = state.focusNode;
    final scroll = state.scrollController;
    focus.requestFocus();
    await tester.pump();
    final value = TextEditingValue(
      text: controller.text,
      // A native composition keeps the insertion caret within its range.
      // The old selection 0..4 extended outside composing 0..2, so Flutter's
      // selection setter legitimately cleared composition before the rebuild.
      selection: const TextSelection.collapsed(offset: 2),
      composing: const TextRange(start: 0, end: 2),
    );
    tester.testTextInput.updateEditingValue(value);
    await tester.pump();
    expect(
      controller.value,
      value,
      reason: 'composition exists before rebuild',
    );
    await tester.pumpWidget(harness(key, direction: TextDirection.rtl));
    expect(identical(state, key.currentState), isTrue);
    expect(identical(controller, key.currentState!.controller), isTrue);
    expect(identical(focus, key.currentState!.focusNode), isTrue);
    expect(identical(scroll, key.currentState!.scrollController), isTrue);
    expect(controller.value, value);
    expect(controller.text.contains('\r\n'), isTrue);
  });
}

void registerSlot() {
  testWidgets(
    'LF replacement consumes layout space with equal UTF-16 offsets',
    (tester) async {
      final key = GlobalKey<EditableCandidateAState>();
      const source = 'first paragraph\nsecond paragraph';
      await tester.pumpWidget(harness(key, text: source));
      final editable = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      final before = editable.renderEditable
          .getLocalRectForCaret(const TextPosition(offset: source.length))
          .top;
      await tester.pumpWidget(harness(key, text: source, discussion: true));
      expect(
        find.byKey(const ValueKey('candidate-a-inline-slot')),
        findsOneWidget,
      );
      final slot = tester.getRect(
        find.byKey(const ValueKey('candidate-a-inline-slot')),
      );
      expect(slot.height, 96);
      final render = editable.renderEditable;
      final projection = render.text!.toPlainText();
      expect(key.currentState!.controller.text, source);
      expect(projection, 'first paragraph\ufffcsecond paragraph');
      expect(projection.length, source.length);
      final after = render
          .getLocalRectForCaret(TextPosition(offset: projection.length))
          .top;
      expect(after - before, greaterThanOrEqualTo(90));
      expect(projection.indexOf('second'), source.indexOf('second'));
      final bodyCaret = render.getLocalRectForCaret(
        TextPosition(offset: source.indexOf('second')),
      );
      expect(
        bodyCaret.top,
        greaterThanOrEqualTo(
          slot.bottom - tester.getTopLeft(find.byType(EditableText)).dy,
        ),
      );
      final hit = render.getPositionForPoint(
        render.localToGlobal(bodyCaret.center),
      );
      expect(hit.offset, source.indexOf('second'));
    },
  );
}

void registerHistory() {
  testWidgets(
    'native select all delete undo restores exact source',
    (tester) async {
      final key = GlobalKey<EditableCandidateAState>();
      const source = '中文😀\r\nZ\u0301\u200dالعربية';
      await tester.pumpWidget(harness(key, text: source));
      key.currentState!.focusNode.requestFocus();
      await tester.pump();
      // UndoHistory coalesces using a 500ms throttle.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump(const Duration(milliseconds: 600));
      expect(key.currentState!.controller.text, isEmpty);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(key.currentState!.controller.text, source);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

void registerClipboard() {
  testWidgets(
    'CRLF slot Ctrl+C emits exact source to platform clipboard channel',
    (tester) async {
      final key = GlobalKey<EditableCandidateAState>();
      const source = '首段😀\r\n正文';
      await tester.pumpWidget(harness(key, text: source, discussion: true));
      final state = key.currentState!;
      state.focusNode.requestFocus();
      await tester.pump();
      String? copiedText;
      // Observe the framework's outbound platform payload; this widget test
      // does not exercise the Windows clipboard service or native paste.
      observeClipboardWrites(tester, (text) => copiedText = text);
      final render = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;
      expect(render.text!.toPlainText(), '首段😀\r\ufffc正文');
      expect(render.text!.toPlainText().length, source.length);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pump();
      expect(
        state.controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: source.length),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(copiedText, source);
      expect(state.controller.text, source);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

void observeClipboardWrites(WidgetTester tester, ValueChanged<String> onWrite) {
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      final text = (call.arguments as Map<Object?, Object?>)['text'] as String;
      onWrite(text);
    }
    if (call.method == 'Clipboard.hasStrings') {
      return <String, Object>{'value': false};
    }
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
}

void registerLimits() {
  testWidgets('no LF cannot allocate a source-preserving inline slot', (
    tester,
  ) async {
    final key = GlobalKey<EditableCandidateAState>();
    await tester.pumpWidget(
      harness(key, text: 'single paragraph', discussion: true),
    );
    expect(find.byKey(const ValueKey('candidate-a-inline-slot')), findsNothing);
    expect(key.currentState!.controller.text, 'single paragraph');
  });

  for (final size in [10000, 200000]) {
    testWidgets('loads exact $size UTF-16 units without normalization', (
      tester,
    ) async {
      final key = GlobalKey<EditableCandidateAState>();
      final source = '文' * (size - 7) + '\r\n😀e\u0301Z';
      expect(source.length, size);
      await tester.pumpWidget(harness(key, text: source));
      expect(key.currentState!.controller.text, source);
      expect(tester.takeException(), isNull);
    });
  }
}
