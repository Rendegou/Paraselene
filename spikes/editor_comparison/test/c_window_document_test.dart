import 'dart:math';

import 'package:characters/characters.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_editor_spike/c_window_document.dart';

void main() {
  const exact = '首行\r\n😀👩‍👩‍👧‍👦e\u0301\nالعربية עברית\r\n尾';

  test('global select-all/delete/undo/redo preserves raw UTF-16 exactly', () {
    final document = CWindowDocument(exact * 1000);
    final original = document.raw;
    final selected = TextSelection(
      baseOffset: original.length,
      extentOffset: 0,
    );
    expect(document.select(selected).accepted, isTrue);
    expect(document.globalValue.selection, selected);
    expect(document.window, isNull);
    expect(document.windowUnsupportedReason, isNotNull);
    expect(document.replaceSelection('').accepted, isTrue);
    expect(document.raw, '');
    expect(document.undo().accepted, isTrue);
    expect(document.raw.codeUnits, original.codeUnits);
    expect(document.globalValue.selection, selected);
    expect(document.redo().accepted, isTrue);
    expect(document.raw, '');
  });

  test('bounded windows map raw UTF-16 without splitting graphemes', () {
    final document = CWindowDocument(exact * 4000);
    final boundaries = <int>{0};
    var offset = 0;
    for (final grapheme in document.raw.characters) {
      offset += grapheme.length;
      boundaries.add(offset);
    }
    for (final caret in [0, exact.length * 1700, document.raw.length]) {
      expect(
        document.select(TextSelection.collapsed(offset: caret)).accepted,
        isTrue,
      );
      final window = document.window!;
      expect(window.end - window.start, lessThanOrEqualTo(1024));
      expect(boundaries, containsAll([window.start, window.end]));
      expect(
        window.value.text,
        document.raw.substring(window.start, window.end),
      );
      expect(window.start + window.value.selection.extentOffset, caret);
      expect(identical(document.window, window), isTrue);
    }
  });

  test('single-line 200k input has bounded middle and end contexts', () {
    final document = CWindowDocument('x' * 200000);
    for (final offset in [100000, 200000]) {
      expect(
        document.select(TextSelection.collapsed(offset: offset)).accepted,
        isTrue,
      );
      final window = document.window!;
      expect(window.start, greaterThan(0));
      expect(window.value.text.length, lessThanOrEqualTo(1024));
      expect(window.start + window.value.selection.extentOffset, offset);
    }
  });

  test('repeated text composition keeps its known local window pinned', () {
    final document = CWindowDocument('a' * 100, maxWindowCodeUnits: 32);
    document.select(const TextSelection.collapsed(offset: 50));
    final window = document.window!;
    expect((window.start, window.end), (42, 58));
    final local = window.value.copyWith(
      text: window.value.text.replaceRange(8, 8, 'a'),
      selection: const TextSelection.collapsed(offset: 9),
      composing: const TextRange(start: 8, end: 9),
    );
    expect(
      document.updateFromPlatform(local, expectedWindow: window).accepted,
      isTrue,
    );
    expect(document.raw, 'a' * 101);
    expect(document.globalValue.selection.extentOffset, 51);
    expect(document.globalValue.composing, const TextRange(start: 50, end: 51));
    final pinned = document.window!;
    expect((pinned.start, pinned.end), (42, 59));
    expect(pinned.value, local);
    expect(document.windowUnsupportedReason, isNull);
    expect(
      document.updateFromPlatform(local, expectedWindow: window).accepted,
      isFalse,
    );
    expect(identical(document.window, pinned), isTrue);
    expect(document.raw, 'a' * 101);
    expect(
      document
          .updateFromPlatform(
            pinned.value.copyWith(composing: TextRange.empty),
            expectedWindow: pinned,
          )
          .accepted,
      isTrue,
    );
    expect(document.undo().accepted, isTrue);
    expect(document.raw, 'a' * 100);
    expect(document.globalValue.selection.extentOffset, 50);
    expect(document.canUndo, isFalse);
    expect(document.redo().accepted, isTrue);
    expect(document.raw, 'a' * 101);
    expect(document.globalValue.selection.extentOffset, 51);
    expect(document.globalValue.composing, TextRange.empty);
  });

  test(
    'inactive composing outside context projects to empty without changing global',
    () {
      final document = CWindowDocument('a' * 100, maxWindowCodeUnits: 32);
      for (final composing in [
        const TextRange.collapsed(0),
        const TextRange.collapsed(100),
      ]) {
        final global = TextEditingValue(
          text: document.raw,
          selection: const TextSelection.collapsed(offset: 50),
          composing: composing,
        );
        expect(document.applyGlobalValue(global).accepted, isTrue);
        expect(document.window!.value.composing, TextRange.empty);
        expect(document.globalValue, global);
      }
    },
  );

  test(
    'local replacement changes exact region and preserves reverse affinity',
    () {
      final document = CWindowDocument('a' * 500 + exact + 'z' * 700);
      document.select(const TextSelection.collapsed(offset: 502));
      final window = document.window!;
      final localOffset = 502 - window.start;
      final expected = document.raw.replaceRange(502, 504, '😀');
      final local = window.value.copyWith(
        text: window.value.text.replaceRange(
          localOffset,
          localOffset + 2,
          '😀',
        ),
        selection: TextSelection(
          baseOffset: localOffset + 2,
          extentOffset: localOffset,
          affinity: TextAffinity.upstream,
          isDirectional: true,
        ),
      );
      expect(
        document.updateFromPlatform(local, expectedWindow: window).accepted,
        isTrue,
      );
      expect(document.raw.codeUnits, expected.codeUnits);
      expect(document.globalValue.selection.baseOffset, 504);
      expect(document.globalValue.selection.extentOffset, 502);
      expect(document.globalValue.selection.affinity, TextAffinity.upstream);
      expect(document.globalValue.selection.isDirectional, isTrue);
      expect(
        document.updateFromPlatform(local, expectedWindow: window).accepted,
        isFalse,
      );
    },
  );

  test('paragraph boundary context allows native Backspace over CRLF', () {
    final document = CWindowDocument('${'前' * 800}\r\n后${'末' * 800}');
    document.select(const TextSelection.collapsed(offset: 802));
    final before = document.raw;
    final window = document.window!;
    final caret = window.value.selection.extentOffset;
    expect(window.value.text.substring(caret - 2, caret), '\r\n');
    final local = window.value.copyWith(
      text: window.value.text.replaceRange(caret - 2, caret, ''),
      selection: TextSelection.collapsed(offset: caret - 2),
    );
    expect(document.updateFromPlatform(local).accepted, isTrue);
    expect(document.raw, before.replaceRange(800, 802, ''));
    document.undo();
    expect(document.raw.codeUnits, before.codeUnits);
  });

  test(
    'composition spans LF, pins context, and commits one undo transaction',
    () {
      final document = CWindowDocument('${'a' * 700}\n${'b' * 700}');
      document.select(const TextSelection.collapsed(offset: 700));
      final original = document.raw;
      final initial = document.window!;
      final caret = initial.value.selection.extentOffset;
      var local = initial.value.copyWith(
        text: initial.value.text.replaceRange(caret, caret, 'ni'),
        selection: TextSelection.collapsed(offset: caret + 3),
        composing: TextRange(start: caret, end: caret + 3),
      );
      expect(document.updateFromPlatform(local).accepted, isTrue);
      final composingWindow = document.window!;
      expect(composingWindow.start, initial.start);
      expect(composingWindow.end, initial.end + 2);
      expect(
        document.globalValue.composing,
        const TextRange(start: 700, end: 703),
      );
      expect(
        document.select(const TextSelection.collapsed(offset: 0)).accepted,
        isFalse,
      );
      local = composingWindow.value.copyWith(
        text: composingWindow.value.text.replaceRange(caret, caret + 2, '你'),
        selection: TextSelection.collapsed(offset: caret + 2),
        composing: TextRange(start: caret, end: caret + 2),
      );
      expect(document.updateFromPlatform(local).accepted, isTrue);
      expect(document.window!.start, initial.start);
      expect(
        document
            .updateFromPlatform(
              document.window!.value.copyWith(composing: TextRange.empty),
            )
            .accepted,
        isTrue,
      );
      expect(document.raw, original.replaceRange(700, 700, '你'));
      expect(document.undo().accepted, isTrue);
      expect(document.raw.codeUnits, original.codeUnits);
      expect(document.canUndo, isFalse);
      expect(document.redo().accepted, isTrue);
      expect(document.raw, original.replaceRange(700, 700, '你'));
      expect(document.globalValue.composing, TextRange.empty);
    },
  );

  test(
    'surrogate-half, malformed text and pinned overflow fail atomically',
    () {
      final document = CWindowDocument(
        '😀${'a' * 100}',
        maxWindowCodeUnits: 32,
      );
      final initial = document.globalValue;
      expect(
        document.select(const TextSelection.collapsed(offset: 1)).accepted,
        isFalse,
      );
      expect(
        document.replaceSelection(String.fromCharCode(0xd800)).accepted,
        isFalse,
      );
      expect(document.globalValue, initial);
      expect(document.canUndo, isFalse);
      final window = document.window!;
      final oversized = TextEditingValue(
        text: 'x' * 33,
        selection: const TextSelection.collapsed(offset: 33),
        composing: const TextRange(start: 0, end: 33),
      );
      expect(document.updateFromPlatform(oversized).accepted, isFalse);
      expect(identical(document.window, window), isTrue);
      expect(document.globalValue, initial);
    },
  );

  test(
    'emoji diff expands shared surrogate prefix without losing raw neighbors',
    () {
      final document = CWindowDocument('前😀后\r\n');
      document.select(const TextSelection.collapsed(offset: 3));
      final local = document.window!.value.copyWith(text: '前😃后\r\n');
      expect(document.updateFromPlatform(local).accepted, isTrue);
      expect(document.raw.codeUnits, '前😃后\r\n'.codeUnits);
      document.undo();
      expect(document.raw.codeUnits, '前😀后\r\n'.codeUnits);
    },
  );

  test(
    'active composition overflow cannot switch context or change history',
    () {
      final document = CWindowDocument('a' * 100, maxWindowCodeUnits: 32);
      document.select(const TextSelection.collapsed(offset: 50));
      final original = document.raw;
      final first = document.window!;
      final caret = first.value.selection.extentOffset;
      final composing = first.value.copyWith(
        text: first.value.text.replaceRange(caret, caret, 'n'),
        selection: TextSelection.collapsed(offset: caret + 1),
        composing: TextRange(start: caret, end: caret + 1),
      );
      expect(document.updateFromPlatform(composing).accepted, isTrue);
      final pinned = document.window!;
      final before = document.globalValue;
      final overflow = pinned.value.copyWith(
        text: pinned.value.text.replaceRange(caret, caret + 1, 'n' * 30),
        selection: TextSelection.collapsed(offset: caret + 30),
        composing: TextRange(start: caret, end: caret + 30),
      );
      expect(document.updateFromPlatform(overflow).accepted, isFalse);
      expect(identical(document.window, pinned), isTrue);
      expect(document.globalValue, before);
      expect(document.undo().accepted, isTrue);
      expect(document.raw, original);
      expect(document.globalValue.composing, TextRange.empty);
      expect(document.redo().accepted, isTrue);
      expect(document.raw, original.replaceRange(50, 50, 'n'));
    },
  );

  test(
    'global composition remains authoritative if bounded context unavailable',
    () {
      final document = CWindowDocument('a' * 5000);
      final full = TextEditingValue(
        text: document.raw,
        selection: const TextSelection(baseOffset: 100, extentOffset: 4000),
        composing: const TextRange(start: 100, end: 4000),
      );
      expect(document.applyGlobalValue(full).accepted, isTrue);
      expect(document.globalValue, full);
      expect(document.window, isNull);
      expect(
        document.updateFromPlatform(TextEditingValue.empty).accepted,
        isFalse,
      );
      expect(document.globalValue, full);
      expect(
        document
            .applyGlobalValue(full.copyWith(composing: TextRange.empty))
            .accepted,
        isTrue,
      );
    },
  );

  test(
    'seeded scalar-boundary edits undo/redo exact independent snapshots',
    () {
      final random = Random(715);
      final document = CWindowDocument(exact);
      final snapshots = <String>[exact];
      const tokens = ['😀', '\r\n', '\n', 'e\u0301', '👩‍👩‍👧‍👦', 'ع', '中'];
      var expected = exact;
      for (var iteration = 0; iteration < 80; iteration++) {
        final boundaries = <int>[0];
        var offset = 0;
        for (final rune in expected.runes) {
          offset += rune > 0xffff ? 2 : 1;
          boundaries.add(offset);
        }
        final left = random.nextInt(boundaries.length);
        final right = random.nextInt(boundaries.length);
        final start = boundaries[min(left, right)];
        final end = boundaries[max(left, right)];
        final insert = tokens[random.nextInt(tokens.length)];
        document.select(TextSelection(baseOffset: end, extentOffset: start));
        expect(document.replaceSelection(insert).accepted, isTrue);
        expected =
            expected.substring(0, start) + insert + expected.substring(end);
        expect(document.raw.codeUnits, expected.codeUnits);
        if (expected != snapshots.last) snapshots.add(expected);
      }
      for (final snapshot in snapshots.reversed.skip(1)) {
        expect(document.undo().accepted, isTrue);
        expect(document.raw.codeUnits, snapshot.codeUnits);
      }
      expect(document.canUndo, isFalse);
      for (final snapshot in snapshots.skip(1)) {
        expect(document.redo().accepted, isTrue);
        expect(document.raw.codeUnits, snapshot.codeUnits);
      }
      expect(document.canRedo, isFalse);
    },
  );
}
