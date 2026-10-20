// 字素级差异计算：产出未变/删除/插入片段，供候选对比高亮使用。
// 纯 Dart 计算模块：不依赖 Flutter、IO 或数据库，不修改入参，也不写库。

import 'package:characters/characters.dart';

/// Exact grapheme-preserving spans. Bounded LCS falls back to one changed middle.
///
/// 差异片段以 Unicode 字素簇为最小单位，不会从中间切开组合字符或代理对。
final class DiffPart {
  const DiffPart(this.text, this.change);

  /// 片段原文，按字素簇边界直接拼接即可还原完整文本。
  final String text;

  /// -1 deletion, 0 unchanged, 1 insertion.
  ///
  /// 变更类型：-1 删除、0 未变、1 插入，用于选择高亮样式。
  final int change;
}

/// 计算两个字符串之间的字素级差异片段。
///
/// 先剥离公共前缀与后缀以缩小中间区；中间区超过规模上限时退化为整段删除加整段插入，
/// 保证最坏情况下时间与内存可控。返回值按顺序拼接后与 [after] 等价，入参不会被修改。
List<DiffPart> characterDiff(String before, String after) {
  final a = before.characters.toList();
  final b = after.characters.toList();
  var prefix = 0;
  while (prefix < a.length && prefix < b.length && a[prefix] == b[prefix]) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < a.length - prefix &&
      suffix < b.length - prefix &&
      a[a.length - 1 - suffix] == b[b.length - 1 - suffix]) {
    suffix++;
  }
  final middle = _middle(
    a.sublist(prefix, a.length - suffix),
    b.sublist(prefix, b.length - suffix),
  );
  return [
    if (prefix > 0) DiffPart(a.take(prefix).join(), 0),
    ...middle,
    if (suffix > 0) DiffPart(a.skip(a.length - suffix).join(), 0),
  ];
}

List<DiffPart> _middle(List<String> a, List<String> b) {
  // 超过规模上限时不再分配 LCS 矩阵，避免长段落造成平方级内存与耗时。
  if (a.isEmpty ||
      b.isEmpty ||
      a.length + b.length > 2000 ||
      a.length * b.length > 250000) {
    return [
      if (a.isNotEmpty) DiffPart(a.join(), -1),
      if (b.isNotEmpty) DiffPart(b.join(), 1),
    ];
  }
  final lengths = List.generate(
    a.length + 1,
    (_) => List.filled(b.length + 1, 0),
  );
  for (var i = a.length - 1; i >= 0; i--) {
    for (var j = b.length - 1; j >= 0; j--) {
      lengths[i][j] = a[i] == b[j]
          ? 1 + lengths[i + 1][j + 1]
          : lengths[i + 1][j] > lengths[i][j + 1]
          ? lengths[i + 1][j]
          : lengths[i][j + 1];
    }
  }
  final result = <DiffPart>[];
  var i = 0;
  var j = 0;
  while (i < a.length || j < b.length) {
    if (i < a.length && j < b.length && a[i] == b[j]) {
      result.add(DiffPart(a[i++], 0));
      j++;
    } else if (j == b.length ||
        (i < a.length && lengths[i + 1][j] >= lengths[i][j + 1])) {
      result.add(DiffPart(a[i++], -1));
    } else {
      result.add(DiffPart(b[j++], 1));
    }
  }
  return _merge(result);
}

List<DiffPart> _merge(List<DiffPart> parts) {
  // 合并相邻同类型片段，减少 TextSpan 与样式对象的数量。
  if (parts.isEmpty) return [];
  final result = <DiffPart>[];
  var change = parts.first.change;
  var text = StringBuffer();
  for (final part in parts) {
    if (part.change != change) {
      result.add(DiffPart(text.toString(), change));
      text = StringBuffer();
      change = part.change;
    }
    text.write(part.text);
  }
  result.add(DiffPart(text.toString(), change));
  return result;
}
