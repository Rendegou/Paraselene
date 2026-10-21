// 可见编辑表面：语义、手势、讨论浮层与纸面头尾通过独立Widget组合。
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'editor_discussion_overlay.dart';
import 'editor_scene.dart';
import 'editor_viewport.dart';
import 'editor_viewport_projection.dart';

/// 视口状态提供的只读绑定，不让视图直接修改 State 的内部字段。
class EditorViewportBindings {
  const EditorViewportBindings({
    required this.configuration,
    required this.scroll,
    required this.headerKey,
    required this.footerKey,
    required this.failed,
    required this.onLayout,
    required this.project,
    required this.onFocus,
    required this.onKey,
    required this.onTap,
    required this.onDragStart,
    required this.onDrag,
  });

  /// 当前不可变视口配置，不含内部可变 State。
  final EditorViewport configuration;
  final ScrollController scroll;

  /// 标题自然高度测量的稳定键。
  final GlobalKey headerKey;

  /// 章末自然高度测量的稳定键。
  final GlobalKey footerKey;

  /// 是否进入渲染降级，语义仍保留完整正文。
  final bool failed;

  /// 报告可用尺寸，单位为逻辑像素。
  final ValueChanged<Size> onLayout;

  /// 按滚动位置计算帧，失败返回空并显示恢复提示。
  final EditorViewportFrame? Function(ViewportOffset) project;

  /// 恢复正文焦点，不创建新的输入客户端。
  final VoidCallback onFocus;

  /// 返回按键是否消费，输入法具有优先权。
  final KeyEventResult Function(FocusNode, KeyEvent) onKey;

  /// 按当前画布坐标执行命中。
  final GestureTapDownCallback onTap;

  /// 记录拖选锚点，只读或组字时不改选区。
  final GestureDragStartCallback onDragStart;

  /// 更新选区和边缘滚动，坐标为视口逻辑像素。
  final GestureDragUpdateCallback onDrag;
}

/// 视口焦点与约束外壳，布局逻辑仍由状态协调器执行。
class EditorViewportSurface extends StatelessWidget {
  const EditorViewportSurface({required this.bindings, super.key});

  /// 状态协调器提供的显式绘制与输入接缝。
  final EditorViewportBindings bindings;
  @override
  Widget build(BuildContext context) => Focus(
    focusNode: bindings.configuration.controller.focusNode,
    onKeyEvent: bindings.onKey,
    child: LayoutBuilder(
      builder: (context, constraints) {
        if (bindings.failed) {
          return EditorRenderingFailure(configuration: bindings.configuration);
        }
        bindings.onLayout(constraints.biggest);
        return EditorViewportScrollable(bindings: bindings);
      },
    ),
  );
}

/// 单个原生滚动位置，同时承载标题、正文与章末。
class EditorViewportScrollable extends StatelessWidget {
  const EditorViewportScrollable({required this.bindings, super.key});

  /// 状态协调器提供的显式绘制与输入接缝。
  final EditorViewportBindings bindings;
  @override
  Widget build(BuildContext context) => Scrollbar(
    controller: bindings.scroll,
    thumbVisibility: true,
    child: Scrollable(
      controller: bindings.scroll,
      viewportBuilder: (context, offset) {
        final frame = bindings.project(offset);
        if (frame == null) {
          return EditorRenderingFailure(configuration: bindings.configuration);
        }
        return EditorViewportDocument(bindings: bindings, frame: frame);
      },
    ),
  );
}

/// 渲染失败仍通过语义树保留完整作者正文。
class EditorRenderingFailure extends StatelessWidget {
  const EditorRenderingFailure({required this.configuration, super.key});

  /// 当前不可变视口配置，不含内部可变 State。
  final EditorViewport configuration;
  @override
  Widget build(BuildContext context) => Semantics(
    textField: true,
    liveRegion: true,
    value: configuration.controller.document.raw,
    child: Center(child: Text(configuration.renderingFailureLabel)),
  );
}

/// 纸面头尾与正文使用同一帧滚动坐标，测量键保持稳定。
class EditorViewportDocument extends StatelessWidget {
  const EditorViewportDocument({
    required this.bindings,
    required this.frame,
    super.key,
  });

  /// 状态协调器提供的显式绘制与输入接缝。
  final EditorViewportBindings bindings;

  /// 绘制、命中与讨论叠层共用的投影帧。
  final EditorViewportFrame frame;
  @override
  Widget build(BuildContext context) {
    final configuration = bindings.configuration;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (configuration.documentHeader != null)
          Positioned(
            top: -frame.pixels,
            left: 0,
            right: 0,
            child: KeyedSubtree(
              key: bindings.headerKey,
              child: configuration.documentHeader!,
            ),
          ),
        Positioned(
          top: frame.bodyTop,
          left: 0,
          right: 0,
          bottom: 0,
          child: EditorViewportBody(bindings: bindings, frame: frame),
        ),
        if (configuration.documentFooter != null)
          Positioned(
            top:
                frame.headerExtent +
                configuration.controller.layout.height -
                frame.pixels,
            left: 0,
            right: 0,
            child: KeyedSubtree(
              key: bindings.footerKey,
              child: configuration.documentFooter!,
            ),
          ),
      ],
    );
  }
}

/// 正文场景与讨论叠层共享同一变换，文本选区浮动动作保持锚点。
class EditorViewportBody extends StatelessWidget {
  const EditorViewportBody({
    required this.bindings,
    required this.frame,
    super.key,
  });

  /// 状态协调器提供的显式绘制与输入接缝。
  final EditorViewportBindings bindings;

  /// 绘制、命中与讨论叠层共用的投影帧。
  final EditorViewportFrame frame;
  @override
  Widget build(BuildContext context) {
    final configuration = bindings.configuration;
    final controller = configuration.controller;
    final viewport = frame.bodySize;
    return Stack(
      children: [
        Positioned.fill(
          child: EditorSceneCanvas(bindings: bindings, frame: frame),
        ),
        if (configuration.discussionBuilder != null)
          Positioned.fill(
            child: ClipRect(
              child: EditorDiscussionOverlay(
                layout: controller.layout,
                origin: frame.scene.transform.origin,
                builder: configuration.discussionBuilder!,
                markerBuilder: configuration.discussionMarkerBuilder,
                onHostMeasured: configuration.onThreadHostMeasured,
              ),
            ),
          ),
        if (configuration.selectionActionBuilder != null &&
            !controller.composing &&
            !controller.value.selection.isCollapsed)
          Positioned(
            left: (frame.scene.caret.left + 6)
                .clamp(4.0, math.max(4.0, frame.size.width - 140))
                .toDouble(),
            top: (frame.scene.caret.top - 38)
                .clamp(4.0, math.max(4.0, viewport.height - 32))
                .toDouble(),
            child: configuration.selectionActionBuilder!(
              context,
              frame.scene.caret,
            ),
          ),
      ],
    );
  }
}

/// 画布的语义与命中统一包裹，绘制与命中始终使用同一帧。
class EditorSceneCanvas extends StatelessWidget {
  const EditorSceneCanvas({
    required this.bindings,
    required this.frame,
    super.key,
  });

  /// 状态协调器提供的显式绘制与输入接缝。
  final EditorViewportBindings bindings;

  /// 绘制、命中与讨论叠层共用的投影帧。
  final EditorViewportFrame frame;
  @override
  Widget build(BuildContext context) {
    final controller = bindings.configuration.controller;
    return Semantics(
      textField: true,
      multiline: true,
      focused: controller.focusNode.hasFocus,
      label: bindings.configuration.editorLabel,
      value: controller.document.raw,
      onTap: bindings.onFocus,
      onSetSelection: controller.select,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: bindings.onTap,
          onPanStart: bindings.onDragStart,
          onPanUpdate: bindings.onDrag,
          child: ClipRect(
            child: RepaintBoundary(
              child: CustomPaint(
                size: frame.bodySize,
                painter: ScenePainter(
                  frame.scene,
                  controller.focusNode.hasFocus,
                ),
                isComplex: true,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
