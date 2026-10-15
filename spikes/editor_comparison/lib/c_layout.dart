import 'dart:math' as math;
import 'package:characters/characters.dart';
import 'package:flutter/painting.dart';

part 'c_layout_frontier.dart';

/// Prototype typography, measured in logical pixels. Raw delimiters stay raw.
const cBodyStyle = TextStyle(
  fontFamily: 'Notebook Serif',
  fontFamilyFallback: ['Notebook Sans', 'Noto Arabic'],
  fontSize: 20,
  height: 1.85,
  color: Color(0xff28231f),
);

/// A bounded shaped page, with global raw UTF-16 coordinates and document y.
final class CPage {
  const CPage(this.start, this.text, this.y, this.height, this.direction);
  final int start;
  final String text;
  final double y;
  final double height;
  final TextDirection direction;
  int get end => start + text.length;
}

final class _Part {
  const _Part(this.offset, this.text, this.height, this.direction);
  final int offset;
  final String text;
  final double height;
  final TextDirection direction;
}

final class _Paragraph {
  _Paragraph(this.start, this.end, this.text, [List<_Part>? retained])
    : parts = retained ?? [],
      direction = cDirection(text);
  final int start;
  final int end;
  final String text;
  final TextDirection direction;
  final List<_Part> parts;
  int get frontier =>
      parts.isEmpty ? 0 : parts.last.offset + parts.last.text.length;
  bool get complete => parts.isNotEmpty && frontier == text.length;
  double get measuredHeight => parts.fold(0.0, (y, part) => y + part.height);
  _Paragraph shift(int delta) =>
      _Paragraph(start + delta, end + delta, text, parts);
}

/// Indexes hard paragraphs, retaining untouched shapes after a minimal edit.
///
/// Native input uses the full document. Only shaping is split into bounded
/// pages on demand. A changed long paragraph retains its safe shaped prefix.
/// Bidi context can differ at soft-page boundaries; this is a feasibility risk.
final class CLayout {
  CLayout({this.width = 760});
  final double width;
  static const probeUnits = 1024;
  static const pageLines = 12;
  static const metricCacheLimit = 128;
  final _metrics = <(String, TextDirection), List<_Part>>{};
  List<_Paragraph> _paragraphs = [];
  List<CPage> pages = [];
  List<Rect> slots = [];
  String raw = '';
  double height = 0;
  bool slot = false;
  int slotOffset = 0;
  int unitsLaidOut = 0;
  int lastUpdateUnits = 0;
  int lastRebuiltParagraphs = 0;
  int get metricCacheEntries => _metrics.length;
  int get pendingParagraphs => _paragraphs.where((p) => !p.complete).length;
  int get pendingUtf16Units =>
      _paragraphs.fold(0, (n, p) => n + p.text.length - p.frontier);
  bool get fullyMeasured => pendingParagraphs == 0;
  int revision = 0;
  bool visibleReady = false;

  void update(String next, {bool? showSlot, int? slotAnchor}) {
    final beforeUnits = unitsLaidOut;
    lastRebuiltParagraphs = 0;
    if (_paragraphs.isEmpty) {
      _paragraphs = _parse(next, 0, next.length, true);
    } else if (next != raw) {
      _replaceChangedParagraphs(next);
    }
    raw = next;
    slot = showSlot ?? slot;
    slotOffset = (slotAnchor ?? slotOffset).clamp(0, next.length);
    _position();
    revision++;
    visibleReady = false;
    lastUpdateUnits = unitsLaidOut - beforeUnits;
  }

  void _replaceChangedParagraphs(String next) {
    var prefix = 0;
    while (prefix < raw.length &&
        prefix < next.length &&
        raw.codeUnitAt(prefix) == next.codeUnitAt(prefix)) {
      prefix++;
    }
    var oldEnd = raw.length, newEnd = next.length;
    while (oldEnd > prefix &&
        newEnd > prefix &&
        raw.codeUnitAt(oldEnd - 1) == next.codeUnitAt(newEnd - 1)) {
      oldEnd--;
      newEnd--;
    }
    final first = _paragraphAt(prefix), last = _paragraphAt(oldEnd);
    final delta = next.length - raw.length;
    final stop = _paragraphs[last].end + delta;
    final previous = _paragraphs[first];
    final replacement = _parse(
      next,
      previous.start,
      stop,
      last == _paragraphs.length - 1,
    );
    // Reflow starts one whole page before the edit: a trailing word/cluster or
    // bidi run may affect the preceding line. Never draw the invalidated tail.
    if (replacement.isNotEmpty &&
        previous.direction == replacement.first.direction) {
      final safe = previous.parts
          .takeWhile((p) => previous.start + p.offset + p.text.length < prefix)
          .toList();
      if (safe.isNotEmpty) safe.removeLast();
      replacement.first.parts.addAll(safe);
    }
    _paragraphs = [
      ..._paragraphs.take(first),
      ...replacement,
      ..._paragraphs.skip(last + 1).map((p) => p.shift(delta)),
    ];
  }

  int _paragraphAt(int offset) {
    var low = 0, high = _paragraphs.length - 1;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (_paragraphs[mid].start <= offset) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }

  List<_Paragraph> _parse(String text, int start, int stop, bool eof) {
    final result = <_Paragraph>[];
    var offset = start;
    while (offset < stop) {
      final lf = text.indexOf('\n', offset);
      final end = lf < 0 || lf >= stop ? stop : lf + 1;
      var contentEnd = end;
      if (contentEnd > offset && text.codeUnitAt(contentEnd - 1) == 10) {
        contentEnd--;
        if (contentEnd > offset && text.codeUnitAt(contentEnd - 1) == 13) {
          contentEnd--;
        }
      }
      result.add(_Paragraph(offset, end, text.substring(offset, contentEnd)));
      offset = end;
    }
    if (eof && (stop == 0 || text.codeUnitAt(stop - 1) == 10)) {
      result.add(_Paragraph(stop, stop, ''));
    }
    lastRebuiltParagraphs += result.length;
    return result;
  }

  static int _probeEnd(String text, int start) {
    if (text.length - start <= probeUnits) return text.length;
    final range = CharacterRange.at(text, start);
    var end = start;
    while (range.moveNext()) {
      if (range.current.length + end - start > probeUnits) break;
      end += range.current.length;
    }
    if (end == start) {
      throw StateError('One grapheme exceeds the bounded shaping probe');
    }
    return end;
  }

  void _position() {
    final nextPages = <CPage>[], nextSlots = <Rect>[];
    var y = 0.0;
    final active = _paragraphAt(slotOffset);
    for (var index = 0; index < _paragraphs.length; index++) {
      final paragraph = _paragraphs[index];
      for (final part in paragraph.parts) {
        nextPages.add(
          CPage(
            paragraph.start + part.offset,
            part.text,
            y,
            part.height,
            part.direction,
          ),
        );
        y += part.height;
      }
      y += _extent(paragraph) - paragraph.measuredHeight;
      if (slot && index == active) {
        if (paragraph.complete) nextSlots.add(Rect.fromLTWH(0, y, width, 76));
        y += 76;
      }
    }
    pages = List.unmodifiable(nextPages);
    slots = List.unmodifiable(nextSlots);
    height = y;
  }

  TextPainter painter(String text, TextDirection direction) => TextPainter(
    text: TextSpan(text: text, style: cBodyStyle),
    textDirection: direction,
  )..layout(maxWidth: width);

  int pageAtOffset(int offset) {
    var low = 0, high = pages.length - 1;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (pages[mid].start <= offset) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }
}

/// First strong Arabic/Hebrew character sets the hard paragraph base direction.
/// This prototype heuristic is not a Unicode bidi paragraph-direction service.
TextDirection cDirection(String text) {
  for (final rune in text.runes) {
    if ((rune >= 0x590 && rune <= 0x8ff)) return TextDirection.rtl;
    if ((rune >= 65 && rune <= 90) ||
        (rune >= 97 && rune <= 122) ||
        rune >= 0x2e80) {
      return TextDirection.ltr;
    }
  }
  return TextDirection.ltr;
}
