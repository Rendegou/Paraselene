// 覆盖编辑器布局：冷布局、可见页锚点、真实字体软分页与线程槽位几何。
// 使用离线测试字体在 Flutter 测试绑定中排版，不代表 Windows 真机字体栈或原生渲染通过。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/editor/editor_layout.dart';

Future<void> _loadFonts() async {
  for (final face in const {
    'Notebook Sans': 'NotoSansSC-Regular.ttf',
    'Notebook Serif': 'NotoSerifSC-Regular.ttf',
    'Noto Arabic': 'NotoNaskhArabic.ttf',
  }.entries) {
    final loader = FontLoader(face.key);
    loader.addFont(rootBundle.load('assets/fonts/${face.value}'));
    await loader.load();
  }
}

const _testStyle = TextStyle(
  fontFamily: 'Notebook Serif',
  fontFamilyFallback: ['Notebook Sans', 'Noto Arabic'],
  fontSize: 20,
  height: 1.85,
  color: Color(0xff28231f),
);

String _heterogeneousFixture({bool singleLine = false}) {
  final buffer = StringBuffer();
  var i = 0;
  while (buffer.length < 200000) {
    final number = i++;
    buffer.write('第$number段 ${number * 7919} 月光落在窗边，人物${number % 97}转身望向河岸。');
    for (var j = 0; j < 7 + number % 43; j++) {
      buffer.writeCharCode(0x4e00 + (number * 31 + j * 19) % 20000);
    }
    if (!singleLine) buffer.write(number.isEven ? '\r\n' : '\n');
  }
  return buffer.toString().substring(0, 200000);
}

Rect _caretAt(TextPainter painter, EditorPage page, int offset, Offset origin) {
  final position = TextPosition(
    offset: (offset - page.start).clamp(0, page.text.length),
  );
  final point = painter.getOffsetForCaret(
    position,
    const Rect.fromLTWH(0, 0, 2, 37),
  );
  final height = painter.getFullHeightForCaret(
    position,
    const Rect.fromLTWH(0, 0, 2, 37),
  );
  return Rect.fromLTWH(origin.dx + point.dx, origin.dy + point.dy, 2, height);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);

  test(
    'incremental reflow geometry matches full painter after middle edits',
    () {
      for (final source in [
        '月光 word boundary and punctuation; ' * 200,
        'a👩‍💻e\u0301 mixed words; ' * 240,
        'العربية English אבג 123 月光؛ ' * 180,
      ]) {
        final layout = EditorLayout(style: _testStyle)
          ..update(source)
          ..materializeAll();
        final at = layout.pages[layout.pages.length ~/ 2].start;
        final next = source.replaceRange(at, at, '字 ');
        layout.update(next);
        layout.materializeAll();
        final reference = layout.painter(next, textDirection(next));
        addTearDown(reference.dispose);
        for (final page in layout.pages) {
          final pagePainter = layout.painter(page.text, page.direction);
          addTearDown(pagePainter.dispose);
          final actual = _caretAt(
            pagePainter,
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
      }
    },
  );

  test('cold heterogeneous document shapes only visible exact paragraphs', () {
    final raw = _heterogeneousFixture();
    final layout = EditorLayout(style: _testStyle)..update(raw);
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
      final raw = _heterogeneousFixture(singleLine: true);
      final layout = EditorLayout(style: _testStyle)..update(raw);
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
    final layout = EditorLayout(style: _testStyle)..update(raw);
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
      final layout = EditorLayout(style: _testStyle)
        ..update(raw)
        ..materializeAll();
      expect(layout.pages.length, greaterThan(1));
      final reference = layout.painter(raw, textDirection(raw));
      addTearDown(reference.dispose);
      for (final page in layout.pages) {
        for (final offset in [page.start, page.start + 1, page.end - 1]) {
          if (offset > 0 &&
              offset < raw.length &&
              raw.codeUnitAt(offset) >= 0xdc00 &&
              raw.codeUnitAt(offset) <= 0xdfff) {
            continue;
          }
          final owner = layout.pages[layout.pageAtOffset(offset)];
          final ownerPainter = layout.painter(owner.text, owner.direction);
          addTearDown(ownerPainter.dispose);
          final actual = _caretAt(
            ownerPainter,
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
              '${textDirection(raw)} offset=$offset pageStart=${page.start} actual=${actual.topLeft} full=$expected',
            );
          }
        }
      }
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
      final layout = EditorLayout(style: _testStyle)
        ..update(raw)
        ..materializeAll();
      expect(layout.raw, raw);
      expect(layout.pages.map((p) => p.start), [0, 5, 9]);
      expect(layout.pages.map((p) => p.text), ['one', 'two', '']);
      final reference = layout.painter(raw, TextDirection.ltr);
      addTearDown(reference.dispose);
      expect(layout.height, closeTo(reference.height, .01));
    },
  );

  test('SLOT occupies one real gap and toggling never mutates raw', () {
    final layout = EditorLayout(style: _testStyle)
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
    final raw = _heterogeneousFixture();
    final layout = EditorLayout(style: _testStyle)
      ..update(raw)
      ..materializeAll();
    expect(
      layout.metricCacheEntries,
      lessThanOrEqualTo(EditorLayout.metricCacheLimit),
    );
    final at = raw.length ~/ 2;
    layout.update(raw.replaceRange(at, at, '字'));
    layout.materializeAll();
    expect(layout.lastRebuiltParagraphs, lessThanOrEqualTo(2));
    expect(layout.lastUpdateUnits, lessThan(2048));
    expect(
      layout.pages.every((p) => p.text.length <= EditorLayout.probeUnits),
      isTrue,
    );
    expect(layout.pages.first.start, 0);
    expect(
      layout.pages.last.end,
      layout.raw.endsWith('\n') ? layout.raw.length : layout.raw.length,
    );
  });

  test('long single paragraph page ranges are contiguous and bounded', () {
    final raw = _heterogeneousFixture(singleLine: true);
    final layout = EditorLayout(style: _testStyle)
      ..update(raw)
      ..materializeAll();
    var end = 0;
    for (final page in layout.pages) {
      expect(page.start, end);
      expect(page.text.length, lessThanOrEqualTo(EditorLayout.probeUnits));
      final painter = layout.painter(page.text, page.direction);
      addTearDown(painter.dispose);
      expect(
        painter.computeLineMetrics().length,
        lessThanOrEqualTo(EditorLayout.pageLines),
      );
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
        final layout = EditorLayout(style: _testStyle)
          ..update(raw)
          ..materializeAll();
        final reference = layout.painter(raw, textDirection(raw));
        addTearDown(reference.dispose);
        for (var offset = 0; offset <= raw.length; offset++) {
          if (offset > 0 && raw.codeUnitAt(offset - 1) == 13) continue;
          if (offset < raw.length &&
              raw.codeUnitAt(offset) >= 0xdc00 &&
              raw.codeUnitAt(offset) <= 0xdfff) {
            continue;
          }
          final page = layout.pages[layout.pageAtOffset(offset)];
          final pagePainter = layout.painter(page.text, page.direction);
          addTearDown(pagePainter.dispose);
          final actual = _caretAt(pagePainter, page, offset, Offset(0, page.y));
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
      }
    },
  );

  test(
    'empty document has one editable row; giant grapheme fails explicitly',
    () {
      final layout = EditorLayout(style: _testStyle)
        ..update('')
        ..materializeAll();
      expect(layout.pages.length, 1);
      expect(layout.height, greaterThan(0));
      expect(
        () => EditorLayout(style: _testStyle)
          ..update('e${'\u0301' * 1100}')
          ..materializeAll(),
        throwsStateError,
      );
    },
  );
}
