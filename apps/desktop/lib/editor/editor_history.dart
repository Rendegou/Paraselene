// 编辑器撤销/重做历史：在内存中按快照保存，条数与总 UTF-16 量双重有界。
//
// 上限为 128 个快照且快照文本合计不超过 800 万 UTF-16 code unit；超限时从最旧
// 开始淘汰，但至少保留最新一条，因此整章删除仍可撤销。仅存于会话内存，不写库、无 IO。
import 'package:flutter/services.dart';

/// Session history bounded by 128 snapshots and 8 million UTF-16 code units.
/// Keeps the newest snapshot so whole-chapter deletion stays undoable.
///
/// 会话内撤销/重做快照栈；条数上限 128，快照文本总量上限 800 万 UTF-16 code unit。
/// 淘汰时优先丢弃最旧快照，且始终保留最新一条，保证整章删除仍可撤销。
final class EditorHistory {
  final List<TextEditingValue> _entries = [];
  int _units = 0;

  /// 历史是否为空。
  bool get isEmpty => _entries.isEmpty;

  /// 历史是否非空。
  bool get isNotEmpty => _entries.isNotEmpty;

  /// 清空全部快照并重置计量的文本总量。
  void clear() {
    _entries.clear();
    _units = 0;
  }

  /// 追加一个快照；超出条数或文本总量上限时从最旧开始淘汰，但至少保留一条。
  void add(TextEditingValue value) {
    _entries.add(value);
    _units += value.text.length;
    while (_entries.length > 1 && (_entries.length > 128 || _units > 8000000)) {
      _units -= _entries.removeAt(0).text.length;
    }
  }

  /// 弹出并返回最新快照；调用方需先用 isEmpty 判断，空栈调用会抛异常。
  TextEditingValue removeLast() {
    final value = _entries.removeLast();
    _units -= value.text.length;
    return value;
  }
}
