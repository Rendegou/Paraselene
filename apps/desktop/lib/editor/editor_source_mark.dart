// 溯源标记：Rust 校验过的精确正文半开区间（原始 UTF-16）。
//
// 只读值对象，不写库、不修改正文；from/to 必须落在同一份已确认章节正文上，
// 正文切换后旧标记不得复用（视口会用 sourceBody 快照比对来禁用命中）。
import 'package:flutter/foundation.dart';

/// A Rust-validated half-open UTF-16 range in one exact confirmed chapter body.
///
/// 一个由 Rust 校验、绑定到某份精确已确认章节正文的半开 UTF-16 区间。
@immutable
final class EditorSourceMark {
  const EditorSourceMark({
    required this.entryId,
    required this.name,
    required this.from,
    required this.to,
  });

  /// 溯源条目 ID，由 Rust 侧生成，在作品内稳定。
  final String entryId;

  /// 供界面展示的条目标题。
  final String name;

  /// 区间起点（含），单位为 UTF-16 code unit。
  final int from;

  /// 区间终点（不含），单位为 UTF-16 code unit。
  final int to;
}
