// EditorLayout 的按需（前沿）排版扩展：同步推进有界探针的测量。
//
// 不排队后台重排任务，排版严格同步；未测量的屏幕外高度只是估算值，
// 绝不把占位文本画进正文。偏移为原始 UTF-16 code unit，高度为逻辑像素。
part of 'editor_layout.dart';

/// Synchronous demand layout. There are deliberately no queued reflow jobs.
/// Unmeasured offscreen extents are estimates, never painted text placeholders.
///
/// 同步按需排版扩展：普通视口只测量可见部分，未测量段落用估算高度参与定位；
/// 测量推进后由 prepareViewport 修正滚动位置，保持顶部页锚点的像素位移不变。
extension EditorLayoutFrontier on EditorLayout {
  double _extent(_Paragraph p) {
    if (p.complete) return p.measuredHeight;
    final remaining = p.text.length - p.frontier;
    return p.measuredHeight + math.max(1, (remaining * 20 / width).ceil()) * 37;
  }

  /// Full oracle/debug operation; normal viewport code never calls this.
  ///
  /// 全量物化所有段落，仅供 oracle 与调试；正常视口代码不调用。
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
  ///
  /// 确保 [offset] 处有精确的局部光标几何，包括长行的顺序前缀测量；
  /// 因此对未测量的长段落随机访问可能很昂贵。
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
  ///
  /// 绘制前把可见像素全部解析为精确测量；较早的估算被解析后，顶部原始页锚点
  /// 及其像素位移保持固定，因此返回的是修正后的滚动偏移。
  double prepareViewport(double scroll, double viewportHeight, {int? caret}) {
    EditorPage? anchor;
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
      y += _hostHeight(index);
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
    // 整段不超过单个探针预算时可直接复用已测形状缓存，命中后移到 LRU 尾部。
    if (start == 0 &&
        text.length <= EditorLayout.probeUnits &&
        _metrics.containsKey(key)) {
      final hit = _metrics.remove(key)!;
      _metrics[key] = hit;
      paragraph.parts.addAll(hit);
      return;
    }
    final end = EditorLayout._probeEnd(text, start);
    final probe = painter(text.substring(start, end), direction);
    unitsLaidOut += end - start;
    final lines = probe.computeLineMetrics();
    var cut = end;
    // 探针预算或页行数上限决定一页内容；在完整可视行边界截断，避免同一视觉行
    // 跨页导致行高失真。
    if (lines.length > EditorLayout.pageLines || end < text.length) {
      final line = lines[math.min(EditorLayout.pageLines, lines.length - 1)];
      final position = probe.getPositionForOffset(
        Offset(0, line.baseline - line.ascent / 2),
      );
      cut = start + probe.getLineBoundary(position).start;
    }
    final probeHeight = probe.height;
    probe.dispose();
    if (cut <= start && text.isNotEmpty) {
      // 单个视觉行超出探针预算时无法再前进；抛出后由视口退化为纯文本占位。
      throw StateError(
        'A visual line exceeds the bounded 1024-unit shaping probe',
      );
    }
    final double pageHeight;
    if (cut == end) {
      pageHeight = probeHeight;
    } else {
      final pageLineCount = math.min(EditorLayout.pageLines, lines.length - 1);
      final lastPageLine = lines[pageLineCount - 1];
      pageHeight = lastPageLine.baseline + lastPageLine.descent;
    }
    final pageText = text.substring(start, cut);
    paragraph.parts.add(_Part(start, pageText, pageHeight, direction));
    if (paragraph.complete && text.length <= EditorLayout.probeUnits) {
      _metrics[key] = List.of(paragraph.parts);
      while (_metrics.length > EditorLayout.metricCacheLimit) {
        _metrics.remove(_metrics.keys.first);
      }
    }
  }
}
