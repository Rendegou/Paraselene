import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_editor_spike/c_layout.dart';
import 'package:paraselene_editor_spike/c_scene.dart';
import 'package:paraselene_editor_spike/c_profile.dart';
import 'package:paraselene_editor_spike/spike_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadSpikeFonts);
  test(
    'incremental reflow geometry matches full painter after middle edits',
    () {
      for (final source in [
        '月光 word boundary and punctuation; ' * 200,
        'a👩‍💻e\u0301 mixed words; ' * 240,
        'العربية English אבג 123 月光؛ ' * 180,
      ]) {
        final layout = CLayout()
          ..update(source)
          ..materializeAll();
        final at = layout.pages[layout.pages.length ~/ 2].start;
        final next = source.replaceRange(at, at, '字 ');
        layout.update(next);
        layout.materializeAll();
        final cache = CVisiblePainters();
        final reference = layout.painter(next, cDirection(next));
        for (final page in layout.pages) {
          final actual = cCaret(
            cache.get(layout, page),
            page,
            page.start,
            Offset(0, page.y),
          );
          final expected = reference.getOffsetForCaret(
            TextPosition(offset: page.start),
            const Rect.fromLTWH(0, 0, 2, 37),
          );
          expect(
            (actual.topLeft - expected).distance,
            lessThan(.1),
            reason: 'incremental page ${page.start}',
          );
        }
        cache.dispose();
        reference.dispose();
      }
    },
  );
  test('cold heterogeneous document shapes only visible exact paragraphs', () {
    final raw = cFixture('heterogeneous');
    final layout = CLayout()..update(raw);
    expect(layout.unitsLaidOut, 0);
    expect(layout.pendingUtf16Units, greaterThan(190000));
    layout.prepareViewport(0, 700, caret: 0);
    expect(layout.visibleReady, isTrue);
    expect(layout.unitsLaidOut, lessThan(10000));
    expect(layout.pendingParagraphs, greaterThan(1000));
    for (final page in layout.pages) {
      expect(raw.substring(page.start, page.end), page.text);
    }
  });
  test(
    'long paragraph edit retains prefix and invalidates unmeasured tail',
    () {
      final raw = cFixture('heterogeneous-single-line');
      final layout = CLayout()..update(raw);
      layout.prepareViewport(0, 700, caret: 0);
      expect(layout.unitsLaidOut, lessThan(10000));
      layout.ensureOffset(100000);
      final retained = layout.pages.first.text;
      final before = layout.unitsLaidOut;
      layout.update(raw.replaceRange(100000, 100000, '字'));
      layout.ensureOffset(100001);
      expect(layout.unitsLaidOut - before, lessThan(10000));
      expect(layout.pages.first.text, retained);
      expect(layout.pendingUtf16Units, greaterThan(90000));
      for (final page in layout.pages) {
        expect(layout.raw.substring(page.start, page.end), page.text);
      }
    },
  );
  test('visible page raw anchor survives resolving an earlier estimate', () {
    final raw = '${'i ' * 300}\nsecond visible paragraph\n';
    final layout = CLayout()..update(raw);
    layout.ensureOffset(raw.indexOf('second'));
    final anchor = layout.pages.first;
    final scroll = anchor.y + 5;
    final corrected = layout.prepareViewport(scroll, 10, caret: 0);
    final moved = layout.pages.firstWhere((p) => p.start == anchor.start);
    expect(corrected - moved.y, closeTo(5, .01));
    expect(moved.text, anchor.text);
  });
  test('real-font soft-page boundaries match full paragraph geometry', () {
    final failures = <String>[];
    for (final raw in [
      '月光照在窗边 characters with spaces and punctuation,。' * 80,
      'a👩‍💻e\u0301 月光 mixed words; ' * 100,
      'العربية English אבג 123 月光؛ ' * 100,
    ]) {
      final layout = CLayout()
        ..update(raw)
        ..materializeAll();
      expect(layout.pages.length, greaterThan(1));
      final cache = CVisiblePainters();
      final reference = layout.painter(raw, cDirection(raw));
      for (final page in layout.pages) {
        for (final offset in [page.start, page.start + 1, page.end - 1]) {
          if (offset > 0 &&
              offset < raw.length &&
              raw.codeUnitAt(offset) >= 0xdc00 &&
              raw.codeUnitAt(offset) <= 0xdfff) {
            continue;
          }
          final owner = layout.pages[layout.pageAtOffset(offset)];
          final actual = cCaret(
            cache.get(layout, owner),
            owner,
            offset,
            Offset(0, owner.y),
          );
          final expected = reference.getOffsetForCaret(
            TextPosition(offset: offset),
            const Rect.fromLTWH(0, 0, 2, 37),
          );
          if ((actual.topLeft - expected).distance > .1) {
            failures.add(
              '${cDirection(raw)} offset=$offset pageStart=${page.start} actual=${actual.topLeft} full=$expected',
            );
          }
        }
      }
      reference.dispose();
      cache.dispose();
    }
    expect(
      failures,
      isEmpty,
      reason:
          'Soft-page shaping fidelity is a required feasibility gate; mismatches remain visible.',
    );
  });
  test(
    'raw CRLF delimiters and final empty row are retained without hidden gaps',
    () {
      const raw = 'one\r\ntwo\n';
      final layout = CLayout()
        ..update(raw)
        ..materializeAll();
      expect(layout.raw, raw);
      expect(layout.pages.map((p) => p.start), [0, 5, 9]);
      expect(layout.pages.map((p) => p.text), ['one', 'two', '']);
      final reference = layout.painter(raw, TextDirection.ltr);
      expect(layout.height, closeTo(reference.height, .01));
      reference.dispose();
    },
  );
  test('SLOT occupies one real gap and toggling never mutates raw', () {
    final layout = CLayout()
      ..update('a\r\nb\n')
      ..materializeAll();
    final height = layout.height;
    layout.update(layout.raw, showSlot: true, slotAnchor: layout.raw.length);
    expect(layout.slots.length, 1);
    expect(layout.slots.single.top, height);
    expect(layout.height, height + 76);
    expect(layout.lastUpdateUnits, 0);
    layout.update(layout.raw, showSlot: false);
    expect(layout.height, height);
    expect(layout.raw, 'a\r\nb\n');
  });
  test('heterogeneous edit reuses untouched paragraphs and bounds caches', () {
    final raw = cFixture('heterogeneous');
    final layout = CLayout()
      ..update(raw)
      ..materializeAll();
    expect(
      layout.metricCacheEntries,
      lessThanOrEqualTo(CLayout.metricCacheLimit),
    );
    final at = raw.length ~/ 2;
    layout.update(raw.replaceRange(at, at, '字'));
    layout.materializeAll();
    expect(layout.lastRebuiltParagraphs, lessThanOrEqualTo(2));
    expect(layout.lastUpdateUnits, lessThan(2048));
    expect(
      layout.pages.every((p) => p.text.length <= CLayout.probeUnits),
      isTrue,
    );
    expect(layout.pages.first.start, 0);
    expect(
      layout.pages.last.end,
      layout.raw.endsWith('\n') ? layout.raw.length : layout.raw.length,
    );
  });
  test('long single paragraph page ranges are contiguous and bounded', () {
    final raw = cFixture('heterogeneous-single-line');
    final layout = CLayout()
      ..update(raw)
      ..materializeAll();
    var end = 0;
    for (final page in layout.pages) {
      expect(page.start, end);
      expect(page.text.length, lessThanOrEqualTo(CLayout.probeUnits));
      final painter = layout.painter(page.text, page.direction);
      expect(
        painter.computeLineMetrics().length,
        lessThanOrEqualTo(CLayout.pageLines),
      );
      painter.dispose();
      end = page.end;
    }
    expect(end, raw.length);
    expect(layout.pages.map((p) => p.text).join(), raw);
  });
  test(
    'small LTR CRLF emoji combining and mixed RTL geometry matches full painter',
    () {
      for (final raw in [
        'abc def',
        'abc\r\ndef\r\n',
        'x👩‍💻e\u0301y',
        'English العربية אבג e\u0301',
        'العربية English 👩‍💻',
      ]) {
        final layout = CLayout()
          ..update(raw)
          ..materializeAll();
        final cache = CVisiblePainters();
        final reference = layout.painter(raw, cDirection(raw));
        for (var offset = 0; offset <= raw.length; offset++) {
          // CRLF has one painted delimiter; surrogate halves are not legal carets.
          if (offset > 0 && raw.codeUnitAt(offset - 1) == 13) continue;
          if (offset < raw.length &&
              raw.codeUnitAt(offset) >= 0xdc00 &&
              raw.codeUnitAt(offset) <= 0xdfff) {
            continue;
          }
          final page = layout.pages[layout.pageAtOffset(offset)];
          final actual = cCaret(
            cache.get(layout, page),
            page,
            offset,
            Offset(0, page.y),
          );
          final expected = reference.getOffsetForCaret(
            TextPosition(offset: offset),
            const Rect.fromLTWH(0, 0, 2, 37),
          );
          expect(
            actual.topLeft.dx,
            closeTo(expected.dx, .01),
            reason: '$raw / $offset x',
          );
          expect(
            actual.topLeft.dy,
            closeTo(expected.dy, .01),
            reason: '$raw / $offset y',
          );
        }
        reference.dispose();
        cache.dispose();
      }
    },
  );
  test(
    'empty document has one editable row; giant grapheme fails explicitly',
    () {
      final layout = CLayout()
        ..update('')
        ..materializeAll();
      expect(layout.pages.length, 1);
      expect(layout.height, greaterThan(0));
      expect(
        () => CLayout()
          ..update('e${'\u0301' * 1100}')
          ..materializeAll(),
        throwsStateError,
      );
    },
  );
  test('shared transform round trips document and viewport', () {
    const transform = CTransform(Offset(120, -3456));
    const point = Offset(75.5, 3812.25);
    expect(transform.toDocument(transform.toCanvas(point)), point);
  });
}
