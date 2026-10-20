// 编辑结果与 IME 上下文值对象：纯数据、无 IO、不写库。
//
// EditResult 表示一次原子编辑是否被接受；EditorWindow 表示有界原生 IME 上下文。
// 偏移与区间一律为原始 UTF-16 code unit，本文件不修改任何正文。
import 'package:flutter/services.dart';

/// Outcome of an atomic edit; rejection leaves document and history untouched.
///
/// 一次原子编辑的结果；被拒绝时文档、历史与缓存均保持不变，reason 为稳定原因文本。
final class EditResult {
  const EditResult._(this.accepted, this.reason);

  /// 编辑被接受的事件结果；reason 恒为 null。
  static const ok = EditResult._(true, null);

  /// 构造拒绝结果；[reason] 是给诊断与界面使用的稳定原因文本。
  const EditResult.rejected(String reason) : this._(false, reason);

  /// 编辑是否被接受。
  final bool accepted;

  /// 拒绝原因；accepted 为 true 时为 null。
  final String? reason;
}

/// Optional bounded native IME context with raw UTF-16 [start]/[end] offsets.
///
/// 可选的有界原生 IME 上下文：value 是正文在 [start, end) 区间的切片，
/// 其中的偏移已相对窗口起点平移；不持有正文所有权。
final class EditorWindow {
  const EditorWindow({
    required this.start,
    required this.end,
    required this.value,
  });

  /// 窗口在完整正文中的起点（含），单位为 UTF-16 code unit。
  final int start;

  /// 窗口在完整正文中的终点（不含），单位为 UTF-16 code unit。
  final int end;

  /// 窗口局部编辑状态，偏移相对窗口起点。
  final TextEditingValue value;
}
