import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'c_layout.dart';

/// Active scene leases plus at most [limit] warm LRU painters.
/// Never disposes a painter retained by the active scene, including when an
/// offscreen caret is shaped after the frame. The next scene retires its lease.
final class CVisiblePainters {
  static const limit = 32;
  final _cache = <(String, TextDirection, double), TextPainter>{};
  final _pinned = <(String, TextDirection, double)>{};
  int unitsLaidOut = 0;
  int get length => _cache.length;
  int get activeEntries => _pinned.length;
  int get warmEntries => _cache.length - _pinned.length;
  void beginScene() {
    _pinned.clear();
  }

  TextPainter get(CLayout layout, CPage page, {bool pin = false}) {
    final key = (page.text, page.direction, layout.width);
    if (pin) _pinned.add(key);
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit;
      _trim();
      return hit;
    }
    final painter = layout.painter(page.text, page.direction);
    unitsLaidOut += page.text.length;
    _cache[key] = painter;
    _trim();
    return painter;
  }

  void _trim() {
    while (warmEntries > limit) {
      final key = _cache.keys.firstWhere((key) => !_pinned.contains(key));
      _cache.remove(key)!.dispose();
    }
  }

  void dispose() {
    for (final p in _cache.values) {
      p.dispose();
    }
    _cache.clear();
    _pinned.clear();
  }
}

/// One shared document-to-viewport translation for paint, hit tests and IME.
final class CTransform {
  const CTransform(this.origin);
  final Offset origin;
  Offset toCanvas(Offset document) => document + origin;
  Offset toDocument(Offset canvas) => canvas - origin;
}

final class CDrawPage {
  const CDrawPage(this.page, this.painter, this.origin);
  final CPage page;
  final TextPainter painter;
  final Offset origin;
}

/// Immutable prepared scene. Revision equality avoids deep comparison in paint.
/// Painter references are owned by the bounded cache; scenes are frame snapshots.
final class CScene {
  const CScene({
    required this.revision,
    required this.transform,
    required this.pages,
    required this.selection,
    required this.composing,
    required this.caret,
    required this.slots,
    required this.slotLabel,
  });
  final int revision;
  final CTransform transform;
  final List<CDrawPage> pages;
  final List<Rect> selection;
  final List<Rect> composing;
  final Rect caret;
  final List<Rect> slots;
  final TextPainter slotLabel;
  @override
  bool operator ==(Object other) =>
      other is CScene && other.revision == revision;
  @override
  int get hashCode => revision.hashCode;

  int hit(Offset viewport) {
    if (pages.isEmpty) return 0;
    CDrawPage nearest = pages.first;
    for (final page in pages) {
      if (viewport.dy >= page.origin.dy) nearest = page;
      if (viewport.dy < page.origin.dy + page.page.height) break;
    }
    final local = viewport - nearest.origin;
    final position = nearest.painter.getPositionForOffset(local);
    return nearest.page.start +
        position.offset.clamp(0, nearest.page.text.length);
  }
}

/// Computes selection/caret geometry outside paint, using the painted pages.
CScene cBuildScene({
  required CLayout layout,
  required CVisiblePainters cache,
  required TextEditingValue value,
  required Size viewport,
  required double scroll,
  required int revision,
  required TextPainter slotLabel,
}) {
  final transform = CTransform(
    Offset((viewport.width - layout.width) / 2, -scroll),
  );
  final draw = <CDrawPage>[], selection = <Rect>[], composing = <Rect>[];
  Rect caret = Rect.fromLTWH(transform.origin.dx, -scroll, 2, 37);
  final caretPage = layout.pageAtOffset(value.selection.extentOffset);
  cache.beginScene();
  for (var i = 0; i < layout.pages.length; i++) {
    final page = layout.pages[i];
    if (page.y + page.height < scroll || page.y > scroll + viewport.height) {
      continue;
    }
    final painter = cache.get(layout, page, pin: true);
    final origin = transform.toCanvas(Offset(0, page.y));
    draw.add(CDrawPage(page, painter, origin));
    selection.addAll(_boxes(painter, page, value.selection, origin));
    composing.addAll(_boxes(painter, page, value.composing, origin));
    if (i == caretPage) {
      caret = cCaret(painter, page, value.selection.extentOffset, origin);
    }
  }
  // Geometry is still available for an offscreen caret, without retaining a
  // whole-document RenderEditable or a whole-paragraph TextPainter.
  if (!draw.any((d) => identical(d.page, layout.pages[caretPage]))) {
    final page = layout.pages[caretPage];
    caret = cCaret(
      cache.get(layout, page),
      page,
      value.selection.extentOffset,
      transform.toCanvas(Offset(0, page.y)),
    );
  }
  final visibleSlots = layout.slot
      ? layout.slots
            .where(
              (r) => r.bottom >= scroll && r.top <= scroll + viewport.height,
            )
            .map((r) => r.shift(transform.origin))
            .toList()
      : <Rect>[];
  return CScene(
    revision: revision,
    transform: transform,
    pages: List.unmodifiable(draw),
    selection: List.unmodifiable(selection),
    composing: List.unmodifiable(composing),
    caret: caret,
    slots: List.unmodifiable(visibleSlots),
    slotLabel: slotLabel,
  );
}

List<Rect> _boxes(
  TextPainter painter,
  CPage page,
  TextRange range,
  Offset origin,
) {
  if (!range.isValid ||
      range.isCollapsed ||
      range.end <= page.start ||
      range.start >= page.end) {
    return [];
  }
  return painter
      .getBoxesForSelection(
        TextSelection(
          baseOffset: math.max(range.start, page.start) - page.start,
          extentOffset: math.min(range.end, page.end) - page.start,
        ),
      )
      .map((box) => box.toRect().shift(origin))
      .toList();
}

Rect cCaret(TextPainter painter, CPage page, int offset, Offset origin) {
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

/// Dumb painter: all shaping, geometry and allocations happen before paint().
final class CScenePainter extends CustomPainter {
  CScenePainter(this.scene, this.focused);
  final CScene scene;
  final bool focused;
  final _selection = Paint()..color = const Color(0xffc5d7e9);
  final _ink = Paint()..color = const Color(0xff305b7e);
  final _slot = Paint()..color = const Color(0xffe4e8df);
  final _underline = Paint()
    ..color = const Color(0xff2c5c83)
    ..strokeWidth = 1.5;
  @override
  void paint(Canvas canvas, Size size) {
    for (final box in scene.selection) {
      canvas.drawRect(box, _selection);
    }
    for (final page in scene.pages) {
      page.painter.paint(canvas, page.origin);
    }
    for (final slot in scene.slots) {
      canvas.drawRect(slot, _slot);
      scene.slotLabel.paint(canvas, slot.topLeft);
    }
    for (final box in scene.composing) {
      canvas.drawLine(box.bottomLeft, box.bottomRight, _underline);
    }
    if (focused) canvas.drawRect(scene.caret, _ink);
  }

  @override
  bool shouldRepaint(CScenePainter oldDelegate) => oldDelegate.scene != scene;
}
