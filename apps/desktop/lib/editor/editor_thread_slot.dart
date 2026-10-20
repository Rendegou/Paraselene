// 讨论宿主槽位：在正文中挂载讨论组件的稳定位置与已测量矩形。
//
// 偏移一律为原始 UTF-16 code unit，高度为逻辑像素；未测量段落没有矩形。
// 只读布局数据，不写库、不修改正文。
import 'package:flutter/painting.dart';

/// Stable discussion host, anchored by raw UTF-16 offset. Height is logical px.
///
/// 稳定的讨论宿主锚点：offset 处应插入一个高度为 height 的宿主槽，
/// 重新打开或滚动后位置不变。
final class EditorThreadSlot {
  const EditorThreadSlot({
    required this.id,
    required this.offset,
    this.height = 76,
  });

  /// 宿主稳定标识，同一布局内唯一且非空。
  final String id;

  /// 锚定的全局 UTF-16 偏移，必须落在正文范围内。
  final int offset;

  /// 宿主槽高度，单位为逻辑像素，必须为有限非负值。
  final double height;
}

/// Exact measured host rectangle. Unmeasured paragraphs have no rectangle.
///
/// 宿主槽的精确测量矩形（文档坐标）；对应段落尚未测量时不产生该几何。
final class EditorSlotGeometry {
  const EditorSlotGeometry(this.id, this.rect);

  /// 对应的宿主稳定标识。
  final String id;

  /// 宿主在文档坐标中的矩形，单位为逻辑像素。
  final Rect rect;
}
