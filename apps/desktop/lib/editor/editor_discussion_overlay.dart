// 讨论宿主浮层：按当前布局给出的像素位置叠放讨论宿主组件。
//
// 每个宿主用 ValueKey 常挂载，仅在对应段落尚未测量时 Offstage 隐藏，
// 以保留未完成草稿与焦点状态。只读布局数据，不修改正文、不写库。
//
// 高度为 0 的槽位表示该线程已收起：只在段末显示一个可点击标记，不占正文高度；
// 高度大于 0 的槽位显示讨论卡片，并把实际测量高度回传给编辑工作区。
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'editor_layout.dart';

/// Keyed hosts remain mounted while offscreen, preserving draft/focus state.
///
/// 逐个讨论宿主定位并叠放在正文上；组件始终挂载，未测量段落只做 Offstage 隐藏，
/// 因此滚动或重新排版不会丢失草稿与焦点。origin 是正文画布原点的画布坐标。
class EditorDiscussionOverlay extends StatelessWidget {
  const EditorDiscussionOverlay({
    required this.layout,
    required this.origin,
    required this.builder,
    this.markerBuilder,
    this.onHostMeasured,
    super.key,
  });

  /// 提供槽位几何与正文宽度的当前布局；浮层只读取其中已测量的矩形。
  final EditorLayout layout;

  /// 正文画布原点在父级坐标系中的偏移，单位逻辑像素。
  final Offset origin;

  /// 按宿主 id 构建讨论内容的构建器；宿主 id 在布局内稳定且唯一。
  final Widget Function(BuildContext, String) builder;

  /// 收起线程的段末标记构建器；为空时收起线程只在索引中可达。
  final Widget Function(BuildContext, String)? markerBuilder;

  /// 展开卡片测量完成后的高度回调，单位逻辑像素。
  final void Function(String id, double height)? onHostMeasured;

  @override
  Widget build(BuildContext context) {
    final geometry = {
      for (final host in layout.threadGeometry) host.id: host.rect,
    };
    // 同一段的多个收起标记需要各自独立命中区域，按段末 top 依次向右排开。
    final markerSlots = <double, int>{};
    final markers = <Widget>[];
    for (final host in layout.threadSlots) {
      if (host.height > 0) continue;
      final top = geometry[host.id]?.top;
      if (top == null || markerBuilder == null) continue;
      final index = markerSlots[top] ?? 0;
      markerSlots[top] = index + 1;
      markers.add(
        Positioned(
          key: ValueKey('thread-marker-${host.id}'),
          left: origin.dx + layout.width - 26 - index * 26,
          top: top + origin.dy,
          width: 24,
          height: 24,
          child: markerBuilder!(context, host.id),
        ),
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final host in layout.threadSlots)
          if (host.height > 0)
            Positioned(
              key: ValueKey(host.id),
              left: origin.dx,
              top: (geometry[host.id]?.top ?? 0) + origin.dy,
              width: layout.width,
              child: Offstage(
                offstage: !geometry.containsKey(host.id),
                child: _MeasuredHost(
                  id: host.id,
                  onMeasured: onHostMeasured,
                  child: builder(context, host.id),
                ),
              ),
            ),
        ...markers,
      ],
    );
  }
}

/// 把子树的实际高度在帧后回传，只在尺寸变化时通知，避免测量与重建互相触发。
class _MeasuredHost extends SingleChildRenderObjectWidget {
  const _MeasuredHost({
    required this.id,
    required this.onMeasured,
    required super.child,
  });

  final String id;
  final void Function(String id, double height)? onMeasured;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasuredHost(id, onMeasured);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasuredHost render) {
    render.onMeasured = onMeasured;
  }
}

class _RenderMeasuredHost extends RenderProxyBox {
  _RenderMeasuredHost(this.id, this.onMeasured);

  final String id;
  void Function(String id, double height)? onMeasured;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (_reported != null && (height - _reported!).abs() < 0.5) return;
    _reported = height;
    final callback = onMeasured;
    if (callback == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => callback(id, height));
  }
}
