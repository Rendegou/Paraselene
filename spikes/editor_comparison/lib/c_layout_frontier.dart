part of 'c_layout.dart';

/// Synchronous demand layout. There are deliberately no queued reflow jobs.
/// Unmeasured offscreen extents are estimates, never painted text placeholders.
extension CLayoutFrontier on CLayout {
  double _extent(_Paragraph p) {
    if (p.complete) return p.measuredHeight;
    final remaining = p.text.length - p.frontier;
    return p.measuredHeight + math.max(1, (remaining * 20 / width).ceil()) * 37;
  }

  /// Full oracle/debug operation; normal viewport code never calls this.
  void materializeAll() {
    for (final p in _paragraphs) {
      while (!p.complete) {
        _advance(p);
      }
    }
    _position();
  }

  /// Ensures exact local caret geometry, including sequential long-line prefix.
  /// Random access into an unmeasured long paragraph may therefore be costly.
  void ensureOffset(int offset) {
    final p = _paragraphs[_paragraphAt(offset.clamp(0, raw.length))];
    final local = (offset - p.start).clamp(0, p.text.length);
    while (!p.complete && (p.parts.isEmpty || p.frontier <= local)) {
      _advance(p);
    }
    _position();
  }

  /// Resolves every visible pixel before painting. The top raw page anchor and
  /// its pixel displacement remain fixed when an earlier estimate is resolved.
  double prepareViewport(double scroll, double viewportHeight, {int? caret}) {
    CPage? anchor;
    for (final page in pages) {
      if (page.y <= scroll && page.y + page.height > scroll) {
        anchor = page;
        break;
      }
    }
    if (caret != null) ensureOffset(caret);
    var corrected = scroll;
    if (anchor != null) {
      final moved = pages.where((p) => p.start == anchor!.start);
      if (moved.isNotEmpty) corrected += moved.first.y - anchor.y;
    }
    var y = 0.0;
    final active = _paragraphAt(slotOffset);
    for (var index = 0; index < _paragraphs.length; index++) {
      final p = _paragraphs[index];
      if (y > corrected + viewportHeight) break;
      if (y + _extent(p) >= corrected) {
        final needed = corrected + viewportHeight - y;
        while (!p.complete && p.measuredHeight <= needed) {
          _advance(p);
        }
      }
      y += _extent(p);
      if (slot && index == active) y += 76;
    }
    _position();
    final bounded = corrected.clamp(
      0.0,
      math.max(0.0, height - viewportHeight),
    );
    if ((bounded - corrected).abs() > .01) {
      return prepareViewport(bounded.toDouble(), viewportHeight);
    }
    visibleReady = true;
    return corrected;
  }

  void _advance(_Paragraph paragraph) {
    final text = paragraph.text;
    final start = paragraph.frontier;
    final direction = paragraph.direction;
    final key = (text, direction);
    if (start == 0 &&
        text.length <= CLayout.probeUnits &&
        _metrics.containsKey(key)) {
      final hit = _metrics.remove(key)!;
      _metrics[key] = hit;
      paragraph.parts.addAll(hit);
      return;
    }
    final end = CLayout._probeEnd(text, start);
    final probe = painter(text.substring(start, end), direction);
    unitsLaidOut += end - start;
    final lines = probe.computeLineMetrics();
    var cut = end;
    if (lines.length > CLayout.pageLines || end < text.length) {
      final line = lines[math.min(CLayout.pageLines, lines.length - 1)];
      final position = probe.getPositionForOffset(
        Offset(0, line.baseline - line.ascent / 2),
      );
      cut = start + probe.getLineBoundary(position).start;
    }
    // Page height comes from the probe's own line metrics: the page is the
    // probe's first visual lines, and their geometry is identical there.
    final probeHeight = probe.height;
    probe.dispose();
    if (cut <= start && text.isNotEmpty) {
      throw StateError(
        'A visual line exceeds the bounded 1024-unit shaping probe',
      );
    }
    final double pageHeight;
    if (cut == end) {
      pageHeight = probeHeight;
    } else {
      final pageLineCount = math.min(CLayout.pageLines, lines.length - 1);
      final lastPageLine = lines[pageLineCount - 1];
      pageHeight = lastPageLine.baseline + lastPageLine.descent;
    }
    final pageText = text.substring(start, cut);
    paragraph.parts.add(_Part(start, pageText, pageHeight, direction));
    if (paragraph.complete && text.length <= CLayout.probeUnits) {
      _metrics[key] = List.of(paragraph.parts);
      while (_metrics.length > CLayout.metricCacheLimit) {
        _metrics.remove(_metrics.keys.first);
      }
    }
  }
}
