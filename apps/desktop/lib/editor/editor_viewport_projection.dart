// 视口投影：保持文档滚动与正文画布滚动的区别，修正排版测量位移。
import 'dart:math' as math;
import 'package:flutter/rendering.dart';
import 'editor_scene.dart';
import 'editor_layout.dart';
import 'editor_viewport.dart';

/// 一帧纸面的不可变投影结果，尺寸均为逻辑像素。
class EditorViewportFrame {
  const EditorViewportFrame({
    required this.scene,
    required this.pixels,
    required this.bodyTop,
    required this.headerExtent,
    required this.size,
  });

  /// 当前帧场景，画者仍由视口状态负责释放。
  final EditorScene scene;

  /// 文档滚动偏移，单位为逻辑像素。
  final double pixels;

  /// 正文画布相对视口顶部的位置，单位为逻辑像素。
  final double bodyTop;

  /// 纸面标题实测高度，单位为逻辑像素。
  final double headerExtent;

  /// 视口可用尺寸，单位为逻辑像素。
  final Size size;

  /// 正文画布的当前可用尺寸。
  Size get bodySize => Size(size.width, math.max(0.0, size.height - bodyTop));
}

/// 修正滚动坐标并生成可见场景；排版失败由宿主转成明确错误态。
EditorViewportFrame projectEditorViewport({
  required EditorViewport configuration,
  required Size size,
  required double header,
  required double footer,
  required ViewportOffset offset,
  required VisiblePainters painters,
  required int revision,
}) {
  final controller = configuration.controller;
  final position = _preparePosition(
    configuration,
    size,
    header,
    footer,
    offset,
  );
  final scene = buildScene(
    layout: controller.layout,
    cache: painters,
    value: controller.value,
    viewport: Size(size.width, position.viewport),
    scroll: position.scroll,
    revision: revision,
    sourceRanges: [
      for (final mark
          in configuration.sourceBody == controller.document.raw
              ? configuration.sourceMarks
              : [])
        TextRange(start: mark.from, end: mark.to),
    ],
  );
  return EditorViewportFrame(
    scene: scene,
    pixels: offset.pixels,
    bodyTop: position.top,
    headerExtent: header,
    size: size,
  );
}

({double top, double scroll, double viewport}) _bodyPosition(
  Size size,
  double header,
  double pixels,
) {
  final top = math.max(0.0, header - pixels);
  return (
    top: top,
    scroll: math.max(0.0, pixels - header),
    viewport: math.max(0.0, size.height - top),
  );
}

({double top, double scroll, double viewport}) _preparePosition(
  EditorViewport configuration,
  Size size,
  double header,
  double footer,
  ViewportOffset offset,
) {
  final controller = configuration.controller;
  offset.applyViewportDimension(size.height);
  var position = _bodyPosition(size, header, offset.pixels);
  final maximum = math.max(0.0, controller.layout.height - position.viewport);
  final prepareScroll = math.min(position.scroll, maximum);
  final corrected = controller.layout.prepareViewport(
    prepareScroll,
    position.viewport,
    caret: controller.value.selection.extentOffset,
  );
  final shift = corrected - prepareScroll;
  if (shift.abs() > .01) {
    offset.correctBy(shift);
    position = _bodyPosition(size, header, offset.pixels);
  }
  offset.applyContentDimensions(
    0,
    math.max(0, header + controller.layout.height + footer - size.height),
  );
  return position;
}
