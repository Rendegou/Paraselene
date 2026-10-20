// 编辑器分页排版：把正文按硬换行切成段落，再按有界探针切成可绘制的页。
//
// 只做 shaping 与几何计算，不绘制、不接触 IME；宽度为逻辑像素，
// 所有偏移为原始 UTF-16 code unit。每页带全局起始偏移与文档 y 坐标。
// 未测量段落的高度是估算值，测量推进后由前沿扩展维持页锚点的像素位置稳定。
// 本文件不写库、不修改正文。
import 'dart:math' as math;
import 'package:characters/characters.dart';
import 'package:flutter/painting.dart';
import 'editor_thread_slot.dart';

part 'editor_layout_frontier.dart';

/// A bounded shaped page, with global raw UTF-16 coordinates and document y.
///
/// 一段已塑造、可直接绘制的正文页：偏移为全局原始 UTF-16 code unit，
/// y 与 height 为文档坐标和高度（逻辑像素）。
final class EditorPage {
  const EditorPage(this.start, this.text, this.y, this.height, this.direction);

  /// 该页在完整正文中的起始偏移，单位为全局 UTF-16 code unit。
  final int start;

  /// 该页从正文中切出的原始片段。
  final String text;

  /// 该页在文档坐标系中的顶部 y 坐标，单位为逻辑像素。
  final double y;

  /// 该页的测量高度，单位为逻辑像素。
  final double height;

  /// 该页所属段落的基础排版方向。
  final TextDirection direction;

  /// 该页终点（不含），单位为全局 UTF-16 code unit。
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
  _Paragraph(
    this.start,
    this.end,
    this.text,
    this.direction, [
    List<_Part>? retained,
  ]) : parts = retained ?? [];
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
      _Paragraph(start + delta, end + delta, text, direction, parts);
}

/// Indexes hard paragraphs, retaining untouched shapes after a minimal edit.
///
/// Only shaping is split into bounded pages on demand. A changed long paragraph
/// retains its safe shaped prefix. Bidi context can differ at soft-page
/// boundaries; this is a feasibility risk inherited from the M3 spike.
///
/// 按硬换行建段落的排版模型：只重建变更过的段落，未触碰的段落保留已有形状。
/// 长段落按需分页是有界探针实验，软分页边界处的 bidi 上下文可能与整段排版不同，
/// 这是自 M3 原型延续下来的可行性风险。
final class EditorLayout {
  EditorLayout({this.width = 760, required this.style});

  /// 正文可用的排版宽度，单位为逻辑像素。
  final double width;

  /// 正文排版与测量使用的文本样式。
  final TextStyle style;

  /// 单次 shaping 探针最多容纳的 UTF-16 code unit 数。
  static const probeUnits = 1024;

  /// 单页最多容纳的视觉行数。
  static const pageLines = 12;

  /// 整段形状缓存最多保留的段落数。
  static const metricCacheLimit = 128;
  final _metrics = <(String, TextDirection), List<_Part>>{};
  List<_Paragraph> _paragraphs = [];

  /// 按文档顺序排列的已测量页；未测量段落暂时不在其中。
  List<EditorPage> pages = [];

  /// 当前可绘制的宿主槽矩形（文档坐标）；未测量段落不产生槽。
  List<Rect> slots = [];

  /// 讨论宿主锚点列表，偏移为原始 UTF-16 code unit。
  List<EditorThreadSlot> threadSlots = const [];

  /// 已测量宿主的精确矩形（文档坐标）。
  List<EditorSlotGeometry> threadGeometry = const [];

  /// 最近一次排版对应的原始正文。
  String raw = '';

  /// 当前文档总高度，含未测量段落的估算，单位为逻辑像素。
  double height = 0;

  /// 是否显示选区末尾的讨论槽占位。
  bool slot = false;

  /// 讨论槽锚定的全局 UTF-16 偏移。
  int slotOffset = 0;

  /// 累计已 shaping 的 UTF-16 code unit 数，供诊断与验收。
  int unitsLaidOut = 0;

  /// 最近一次 update 消耗的 shaping 量，供诊断。
  int lastUpdateUnits = 0;

  /// 最近一次 update 重建的段落数，供诊断。
  int lastRebuiltParagraphs = 0;

  /// 形状缓存中的段落数。
  int get metricCacheEntries => _metrics.length;

  /// 尚未完整测量的段落数。
  int get pendingParagraphs => _paragraphs.where((p) => !p.complete).length;

  /// 尚未测量的 UTF-16 code unit 总数。
  int get pendingUtf16Units =>
      _paragraphs.fold(0, (n, p) => n + p.text.length - p.frontier);

  /// 是否所有段落都已完成精确测量。
  bool get fullyMeasured => pendingParagraphs == 0;

  /// 布局版本号，每次结构或测量变化后递增。
  int revision = 0;

  /// 当前可见区域是否已解析为精确测量，供绘制前置判断。
  bool visibleReady = false;

  /// Reconfigures hosts without rewriting author text or changing undo history.
  ///
  /// 重新配置讨论宿主：只修改宿主几何与布局版本，不重写作者正文，也不改动撤销历史。
  /// 宿主 id 为空或重复、偏移越界、高度非有限值时抛 [ArgumentError]。
  void setThreadSlots(List<EditorThreadSlot> next) {
    final ids = <String>{};
    for (final host in next) {
      if (host.id.isEmpty ||
          !ids.add(host.id) ||
          host.offset < 0 ||
          host.offset > raw.length ||
          !host.height.isFinite ||
          host.height < 0) {
        throw ArgumentError('Invalid discussion host');
      }
    }
    threadSlots = List.unmodifiable(next);
    _position();
    revision++;
    visibleReady = false;
  }

  Iterable<EditorThreadSlot> _hostsAt(int paragraph) => threadSlots.where(
    (host) => _paragraphAt(host.offset.clamp(0, raw.length)) == paragraph,
  );

  double _hostHeight(int paragraph) =>
      _hostsAt(paragraph).fold(0.0, (height, host) => height + host.height);

  /// 用新正文更新排版；仅重建变更段落并刷新页与槽位置。
  ///
  /// [showSlot] 省略时保持当前槽显示状态，[slotAnchor] 省略时保持原锚点。
  /// 本方法不修改正文内容、不写撤销历史，也不写库。
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
    var oldEnd = raw.length;
    var newEnd = next.length;
    while (oldEnd > prefix &&
        newEnd > prefix &&
        raw.codeUnitAt(oldEnd - 1) == next.codeUnitAt(newEnd - 1)) {
      oldEnd--;
      newEnd--;
    }
    final first = _paragraphAt(prefix);
    final last = _paragraphAt(oldEnd);
    final delta = next.length - raw.length;
    final stop = _paragraphs[last].end + delta;
    final previous = _paragraphs[first];
    final replacement = _parse(
      next,
      previous.start,
      stop,
      last == _paragraphs.length - 1,
    );
    // 变更段落方向未变时，保留严格位于变更起点之前的已测页；边界页丢弃重测，
    // 避免旧形状与新文本错位。
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
    var low = 0;
    var high = _paragraphs.length - 1;
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
      // 硬换行符不计入排版文本，但保留在段落 [start, end) 范围内，保证全局偏移连续。
      if (contentEnd > offset && text.codeUnitAt(contentEnd - 1) == 10) {
        contentEnd--;
        if (contentEnd > offset && text.codeUnitAt(contentEnd - 1) == 13) {
          contentEnd--;
        }
      }
      result.add(
        _Paragraph(
          offset,
          end,
          text.substring(offset, contentEnd),
          textDirection(text.substring(offset, contentEnd)),
        ),
      );
      offset = end;
    }
    if (eof && (stop == 0 || text.codeUnitAt(stop - 1) == 10)) {
      result.add(_Paragraph(stop, stop, '', TextDirection.ltr));
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
    final nextPages = <EditorPage>[];
    final nextSlots = <Rect>[];
    final nextGeometry = <EditorSlotGeometry>[];
    var y = 0.0;
    final active = _paragraphAt(slotOffset);
    for (var index = 0; index < _paragraphs.length; index++) {
      final paragraph = _paragraphs[index];
      for (final part in paragraph.parts) {
        nextPages.add(
          EditorPage(
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
      for (final host in _hostsAt(index)) {
        if (paragraph.complete) {
          final rect = Rect.fromLTWH(0, y, width, host.height);
          nextSlots.add(rect);
          nextGeometry.add(EditorSlotGeometry(host.id, rect));
        }
        y += host.height;
      }
      if (slot && index == active) {
        if (paragraph.complete) {
          nextSlots.add(Rect.fromLTWH(0, y, width, 76));
        }
        y += 76;
      }
    }
    pages = List.unmodifiable(nextPages);
    slots = List.unmodifiable(nextSlots);
    threadGeometry = List.unmodifiable(nextGeometry);
    height = y;
  }

  /// 用当前样式与宽度为 [text] 创建一个尚未排版的 [TextPainter]。
  TextPainter painter(String text, TextDirection direction) => TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: direction,
  )..layout(maxWidth: width);

  /// 返回包含全局偏移 [offset] 的页下标（按页起始偏移二分查找）。
  int pageAtOffset(int offset) {
    var low = 0;
    var high = pages.length - 1;
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
///
/// 按首个强方向字符决定硬段落基础方向：阿拉伯/希伯来文为 RTL，拉丁字母或 CJK 为
/// LTR，没有强方向字符时回退 LTR。这只是原型启发式，不是完整的 Unicode bidi 段落
/// 方向服务。
TextDirection textDirection(String text) {
  for (final rune in text.runes) {
    if (rune >= 0x590 && rune <= 0x8ff) return TextDirection.rtl;
    if ((rune >= 65 && rune <= 90) ||
        (rune >= 97 && rune <= 122) ||
        rune >= 0x2e80) {
      return TextDirection.ltr;
    }
  }
  return TextDirection.ltr;
}
