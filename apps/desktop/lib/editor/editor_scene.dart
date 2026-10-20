// 编辑器场景层：把当前布局、选区与滚动位置编译成不可变绘制场景，
// 并维护有界 TextPainter 缓存。绘制阶段只做 canvas 绘制，不做 shaping。
//
// 场景内矩形均为画布坐标（逻辑像素），正文偏移为原始 UTF-16 code unit；
// revision 相等即视为同一帧，避免逐字段深比较。本文件不写库、不修改文档模型。
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'editor_layout.dart';

/// Bounded LRU painter cache. Never disposes a pinned painter, even when the
/// cache exceeds [limit]; pinned entries are released by the next [beginScene].
///
/// 有界 LRU TextPainter 缓存：即使总数超过 [limit] 也不释放本帧被钉住的画者，
/// 钉住项在下一次 beginScene 时统一解除，只有 warm 项参与淘汰。
final class VisiblePainters {
  /// 未钉住画者的数量上限；超出时淘汰最久未使用的 warm 项。
  static const limit = 32;
  final _cache = <(String, TextDirection, double), TextPainter>{};
  final _pinned = <(String, TextDirection, double)>{};

  /// 累计为新画者执行的 shaping 文本量，单位为 UTF-16 code unit。
  int unitsLaidOut = 0;

  /// 缓存中的画者总数（含本帧钉住项）。
  int get length => _cache.length;

  /// 本帧被钉住、不会被淘汰的画者数量。
  int get activeEntries => _pinned.length;

  /// 未被钉住的画者数量，受 [limit] 限制。
  int get warmEntries => _cache.length - _pinned.length;

  /// 开始新的一帧：解除上一帧钉住的所有画者。
  void beginScene() => _pinned.clear();

  /// 取某页缓存的画者；未命中时按布局宽度新建一个。
  ///
  /// [pin] 为 true 时本帧内不会被淘汰，由下一次 beginScene 解除。
  TextPainter get(EditorLayout layout, EditorPage page, {bool pin = false}) {
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
      final key = _cache.keys.firstWhere((k) => !_pinned.contains(k));
      _cache.remove(key)!.dispose();
    }
  }

  /// 释放缓存中的全部画者；调用后缓存不可再用。
  void dispose() {
    for (final p in _cache.values) {
      p.dispose();
    }
    _cache.clear();
    _pinned.clear();
  }
}

/// One shared document-to-viewport translation for paint, hit tests and IME.
///
/// 绘制、命中测试与 IME 几何共用同一个文档到画布的平移；origin 是文档原点在画布
/// 上的位置（逻辑像素），通常水平居中并随滚动向上偏移。
final class EditorTransform {
  const EditorTransform(this.origin);

  /// 文档原点在画布坐标中的位置，单位为逻辑像素。
  final Offset origin;

  /// 把文档坐标换算成画布坐标。
  Offset toCanvas(Offset document) => document + origin;

  /// 把画布坐标换算回文档坐标。
  Offset toDocument(Offset canvas) => canvas - origin;
}

/// A page ready for painting, with its canvas origin.
///
/// 一帧内可直接绘制的单页快照：page 是排版页，painter 由有界缓存持有，
/// origin 为该页左上角在画布上的位置（逻辑像素）。
final class DrawPage {
  const DrawPage(this.page, this.painter, this.origin);

  /// 该绘制项对应的排版页。
  final EditorPage page;

  /// 已排版的页画者；所有权归场景缓存，绘制方不得释放。
  final TextPainter painter;

  /// 该页左上角在画布坐标中的位置，单位为逻辑像素。
  final Offset origin;
}

/// Immutable prepared scene. Revision equality avoids deep comparison in paint.
/// Painter references are owned by the bounded cache; scenes are frame snapshots.
///
/// 不可变的单帧场景快照：绘制、命中与语义读取都只看这一帧的几何，
/// 画者引用归有界缓存所有，场景本身不释放任何对象。
final class EditorScene {
  const EditorScene({
    required this.revision,
    required this.transform,
    required this.pages,
    required this.selection,
    required this.composing,
    required this.caret,
    required this.slots,
    this.sourceMarks = const [],
    this.sourceHits = const [],
  });

  /// 场景版本号；与布局/编辑版本同步递增，用于绘制比较。
  final int revision;

  /// 本帧使用的文档到画布变换。
  final EditorTransform transform;

  /// 本帧实际绘制的页快照，按文档顺序排列。
  final List<DrawPage> pages;

  /// 本帧选区矩形，画布坐标。
  final List<Rect> selection;

  /// 溯源标记下方的下划线矩形，画布坐标。
  final List<Rect> sourceMarks;

  /// 溯源标记的命中区域：(标记下标, 画布矩形) 列表。
  final List<(int, Rect)> sourceHits;

  /// 返回命中所给画布坐标的溯源标记下标，按集合去重。
  List<int> sourceIndicesAt(Offset point) => sourceHits
      .where((hit) => hit.$2.contains(point))
      .map((hit) => hit.$1)
      .toSet()
      .toList();

  /// 本帧 IME 组合区间矩形，画布坐标。
  final List<Rect> composing;

  /// 本帧光标矩形，画布坐标；焦点不在编辑器时也保留供 IME 上报。
  final Rect caret;

  /// 本帧可见的宿主槽矩形，画布坐标。
  final List<Rect> slots;
  @override
  bool operator ==(Object other) =>
      other is EditorScene && other.revision == revision;
  @override
  int get hashCode => revision.hashCode;

  /// 把画布坐标命中成全局 UTF-16 偏移；命中不到时退化为首/末页的页内位置，
  /// 结果始终夹在该页文本范围内。
  int hit(Offset viewport) {
    if (pages.isEmpty) return 0;
    DrawPage nearest = pages.first;
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

/// Computes caret geometry from a painted page.
///
/// 用已绘制的页画者计算全局偏移 [offset] 处的光标矩形；返回画布坐标，
/// 宽度固定 2 像素，高度取该位置的整行高度。
Rect caretAt(TextPainter painter, EditorPage page, int offset, Offset origin) {
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

/// Builds an immutable scene from the current layout and editing state.
///
/// 根据当前布局、缓存、编辑状态与滚动位置构建不可变场景：只收录与视口相交的页，
/// 并同时计算选区、组合、溯源标记、光标与宿主槽矩形。画者所有权归 [cache]。
EditorScene buildScene({
  required EditorLayout layout,
  required VisiblePainters cache,
  required TextEditingValue value,
  required Size viewport,
  required double scroll,
  required int revision,
  List<TextRange> sourceRanges = const [],
}) {
  final transform = EditorTransform(
    Offset((viewport.width - layout.width) / 2, -scroll),
  );
  final draw = <DrawPage>[];
  final selection = <Rect>[];
  final composing = <Rect>[];
  final sourceMarks = <Rect>[];
  final sourceHits = <(int, Rect)>[];
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
    draw.add(DrawPage(page, painter, origin));
    for (final (index, range) in sourceRanges.indexed) {
      final boxes = _boxes(painter, page, range, origin);
      sourceMarks.addAll(boxes);
      sourceHits.addAll(boxes.map((box) => (index, box)));
    }
    selection.addAll(_boxes(painter, page, value.selection, origin));
    composing.addAll(_boxes(painter, page, value.composing, origin));
    if (i == caretPage) {
      caret = caretAt(painter, page, value.selection.extentOffset, origin);
    }
  }
  if (!draw.any((d) => identical(d.page, layout.pages[caretPage]))) {
    final page = layout.pages[caretPage];
    caret = caretAt(
      cache.get(layout, page),
      page,
      value.selection.extentOffset,
      transform.toCanvas(Offset(0, page.y)),
    );
  }
  final visibleSlots = (layout.slot || layout.threadSlots.isNotEmpty)
      ? layout.slots
            .where(
              (r) => r.bottom >= scroll && r.top <= scroll + viewport.height,
            )
            .map((r) => r.shift(transform.origin))
            .toList()
      : <Rect>[];
  return EditorScene(
    revision: revision,
    transform: transform,
    pages: List.unmodifiable(draw),
    selection: List.unmodifiable(selection),
    composing: List.unmodifiable(composing),
    sourceMarks: List.unmodifiable(sourceMarks),
    sourceHits: List.unmodifiable(sourceHits),
    caret: caret,
    slots: List.unmodifiable(visibleSlots),
  );
}

List<Rect> _boxes(
  TextPainter painter,
  EditorPage page,
  TextRange range,
  Offset origin,
) {
  // 只截取与当前页相交的部分，选区、组合与溯源区间都可能跨页。
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

/// Dumb painter: all shaping, geometry and allocations happen before paint().
///
/// 哑绘制器：所有 shaping、几何计算与内存分配都在 paint() 之前完成，
/// paint 只做 canvas 调用；shouldRepaint 仅比较场景 revision。
final class ScenePainter extends CustomPainter {
  ScenePainter(this.scene, this.focused);

  /// 本帧要绘制的不可变场景；绘制期间不再重新布局。
  final EditorScene scene;

  /// 编辑器是否持有焦点；为 true 时才绘制光标。
  final bool focused;
  // 原版写作主题：选区 #dce5f4，光标使用强调色 #49659c，段下讨论宿主保持浅灰绿。
  final _selection = Paint()..color = const Color(0xffdce5f4);
  final _ink = Paint()..color = const Color(0xff49659c);
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
    }
    for (final box in scene.sourceMarks) {
      canvas.drawLine(box.bottomLeft, box.bottomRight, _underline);
    }
    for (final box in scene.composing) {
      canvas.drawLine(box.bottomLeft, box.bottomRight, _underline);
    }
    if (focused) canvas.drawRect(scene.caret, _ink);
  }

  @override
  bool shouldRepaint(ScenePainter oldDelegate) => oldDelegate.scene != scene;
}
