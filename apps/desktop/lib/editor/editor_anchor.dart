// 编辑器锚点：把一段冻结的原始 UTF-16 引文映射到不断变化的正文坐标。
//
// 本文件是纯 Dart 逻辑，无 Flutter 绑定、无 IO、不写库、不修改正文。
// 坐标一律以 UTF-16 code unit 计，且必须落在码点边界上（不得切开代理对）。
// 关键不变量：冻结的 text 与 baseBody 永不改写；映射不了时只把 valid 置为 false。

/// A frozen raw UTF-16 quote and its current mapped coordinates.
/// Mapping never changes the frozen text or searches for another occurrence.
///
/// 一段冻结的正文引文及它当前在正文中的映射坐标，供讨论与溯源定位使用。
/// 映射只做一次连续替换的坐标变换，绝不在别处搜索相似文本；无法唯一确认时
/// [valid] 为 false，调用方必须据此隐藏或降级显示，不能把它当成新位置。
final class EditorAnchor {
  const EditorAnchor({
    required this.from,
    required this.to,
    required this.text,
    required this.baseBody,
    required this.baseFrom,
    required this.baseTo,
    required this.valid,
  });

  /// 在 [body] 上捕获 [from, to) 半开区间并冻结其原文。
  ///
  /// 区间越界、终点早于起点，或端点切开代理对时抛 [ArgumentError]。
  factory EditorAnchor.capture(String body, int from, int to) {
    if (from < 0 ||
        to < from ||
        to > body.length ||
        !_boundary(body, from) ||
        !_boundary(body, to)) {
      throw ArgumentError('Invalid UTF-16 quote range');
    }
    return EditorAnchor(
      from: from,
      to: to,
      text: body.substring(from, to),
      baseBody: body,
      baseFrom: from,
      baseTo: to,
      valid: true,
    );
  }

  /// 当前正文中的引文起点（含），单位为 UTF-16 code unit。
  final int from;

  /// 当前正文中的引文终点（不含），单位为 UTF-16 code unit。
  final int to;

  /// 捕获时冻结的引文原文；后续映射不会改写它。
  final String text;

  /// 捕获时的整篇正文快照，用于判断是否已精确撤销回冻结状态。
  final String baseBody;

  /// 冻结快照中的引文起点（含），撤销回冻结正文时据此精确还原。
  final int baseFrom;

  /// 冻结快照中的引文终点（不含）。
  final int baseTo;

  /// 当前坐标是否仍可信；重复文本导致映射歧义或文本不匹配时为 false。
  final bool valid;

  /// Maps one contiguous replacement. Insertions at the start associate right;
  /// insertions at the end associate left. Undo to the frozen body is exact.
  ///
  /// 把一次连续替换（[before] 变成 [after]）映射为新坐标：替换区间之外的偏移原样
  /// 平移，区间之内的偏移夹到替换后的边界。撤销回 [baseBody] 时精确还原冻结坐标。
  /// 替换发生在重复文本附近、无法唯一确定引文去向时，结果标为无效而不会改指别处。
  EditorAnchor map(String before, String after) {
    if (before == after) return this;
    if (after == baseBody) return _at(baseFrom, baseTo, true);
    var start = 0;
    while (start < before.length &&
        start < after.length &&
        before.codeUnitAt(start) == after.codeUnitAt(start)) {
      start++;
    }
    var oldEnd = before.length;
    var newEnd = after.length;
    while (oldEnd > start &&
        newEnd > start &&
        before.codeUnitAt(oldEnd - 1) == after.codeUnitAt(newEnd - 1)) {
      oldEnd--;
      newEnd--;
    }
    final delta = newEnd - oldEnd;
    // Full native values do not identify an edit inside repeated text. If
    // another equally small replacement could have moved this quote, refuse
    // to call it valid rather than silently retarget a different occurrence.
    var suffix = 0;
    while (suffix < before.length &&
        suffix < after.length &&
        before.codeUnitAt(before.length - suffix - 1) ==
            after.codeUnitAt(after.length - suffix - 1)) {
      suffix++;
    }
    final earliest = (before.length - suffix - (oldEnd - start)).clamp(
      0,
      start,
    );
    final ambiguous = earliest < start && from <= oldEnd && to >= earliest;
    int position(int value, bool right) {
      if (value < start || (value == start && !right)) return value;
      if (value > oldEnd || (value == oldEnd && right)) return value + delta;
      return right ? newEnd : start;
    }

    final nextFrom = position(from, true).clamp(0, after.length);
    final nextTo = position(to, false).clamp(nextFrom, after.length);
    final matches =
        _boundary(after, nextFrom) &&
        _boundary(after, nextTo) &&
        after.substring(nextFrom, nextTo) == text;
    return _at(nextFrom, nextTo, valid && matches && !ambiguous);
  }

  EditorAnchor _at(int start, int end, bool matches) => EditorAnchor(
    from: start,
    to: end,
    text: text,
    baseBody: baseBody,
    baseFrom: baseFrom,
    baseTo: baseTo,
    valid: matches,
  );

  static bool _boundary(String text, int offset) =>
      offset == 0 ||
      offset == text.length ||
      text.codeUnitAt(offset) < 0xdc00 ||
      text.codeUnitAt(offset) > 0xdfff;
}
