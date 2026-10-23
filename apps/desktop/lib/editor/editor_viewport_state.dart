// 编辑器视口状态：持有滚动、测量、画者缓存和输入生命周期。
// 绘制表面只接收只读绑定，不能直接改写这些状态字段。
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'editor_scene.dart';
import 'editor_layout.dart';
import 'editor_viewport.dart';
import 'editor_viewport_projection.dart';
import 'editor_viewport_surface.dart';

/// 视口状态：持有滚动控制器、画者缓存与最近一帧场景，把手势与键盘导航
/// 转成控制器调用，并在每帧绘制后上报 IME 几何。
class EditorViewportState extends State<EditorViewport> {
  /// 正文滚动控制器；滚动偏移单位为逻辑像素。
  final scroll = ScrollController();

  /// 可见页画者缓存；所有权在本 State，销毁时统一释放。
  final painters = VisiblePainters();

  /// 纸面头尾的测量键；自然高度计入同一滚动范围。
  final _headerKey = GlobalKey();
  final _footerKey = GlobalKey();

  /// 最近一帧构建的场景；绘制与命中测试只读它。
  EditorScene? scene;
  Size _size = Size.zero;
  int _revision = 0;
  int _anchor = 0;
  int _lastExtent = -1;
  bool _layoutFailed = false;

  /// 纸面标题/章末当前高度；首帧为 0，测量后进入同一文档坐标。
  double _headerExtent = 0;
  double _footerExtent = 0;
  bool _measureScheduled = false;
  bool _chromeMeasured = false;

  /// 正文画布在视口中的纵向起点（滚动小于标题高度时留出标题空间）。
  double _bodyTop = 0;

  /// 待应用的滚动恢复状态；token 变化才重置。
  bool _restorePending = false;
  bool _restoreScheduled = false;

  /// 当前视口控制器；直接委托给 widget 持有的实例。
  EditorViewportController get controller => widget.controller;

  /// 纸面标题实测高度，单位为逻辑像素；用于把排版文档坐标换算到视口坐标。
  @visibleForTesting
  double get headerExtent => _headerExtent;

  @override
  void initState() {
    super.initState();
    controller.addListener(_changed);
    controller.focusNode.addListener(_focus);
    scroll.addListener(_scroll);
    _restorePending = widget.restoreScrollOffset != null;
    widget.onStateReady?.call(this);
  }

  @override
  void didUpdateWidget(EditorViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != controller) {
      oldWidget.controller.removeListener(_changed);
      oldWidget.controller.focusNode.removeListener(_focus);
      controller.addListener(_changed);
      controller.focusNode.addListener(_focus);
    }
    if (oldWidget.restoreScrollToken != widget.restoreScrollToken) {
      _restorePending = widget.restoreScrollOffset != null;
    }
  }

  void _changed() {
    if (!mounted) return;
    _layoutFailed = false;
    setState(() {});
    final extent = controller.value.selection.extentOffset;
    if (_lastExtent != extent) {
      _lastExtent = extent;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ensureCaret();
      });
    }
  }

  void _focus() {
    if (controller.focusNode.hasFocus) {
      controller.attach(View.of(context).viewId);
    } else {
      controller.detach();
    }
  }

  /// 请求焦点，并在下一帧确认焦点仍在编辑器时连接原生 IME。
  void requestFocus() {
    controller.focusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && controller.focusNode.hasFocus) {
        controller.attach(View.of(context).viewId);
      }
    });
  }

  void _scroll() {
    if (!mounted) return;
    setState(() {});
    // 只在真实 ScrollPosition 变化时上报，供 controller 防抖持久化阅读位置。
    widget.onScrollOffset?.call(scroll.offset);
  }

  /// 把指定讨论线程的段下卡片滚动到可见范围（含底部留白）。
  ///
  /// 只读取当前排版几何并直接跳转滚动位置；卡片尚未进入排版或视口未连接时
  /// 安全返回，由下一次测量回调再次触发。
  void revealThread(String id) {
    if (!mounted || !scroll.hasClients || _size.height <= 0) return;
    Rect? rect;
    for (final geometry in controller.layout.threadGeometry) {
      if (geometry.id == id) {
        rect = geometry.rect;
        break;
      }
    }
    if (rect == null) return;
    final viewTop = scroll.offset;
    final viewBottom = viewTop + _size.height;
    final top = _headerExtent + rect.top;
    final bottom = _headerExtent + rect.bottom;
    double? target;
    if (bottom > viewBottom - 24) {
      target = bottom + 24 - _size.height;
    } else if (top < viewTop) {
      target = top - 12;
    }
    if (target == null) return;
    final position = scroll.position;
    final maxExtent = position.hasContentDimensions
        ? position.maxScrollExtent
        : double.infinity;
    final next = target.clamp(0.0, maxExtent.isFinite ? maxExtent : target);
    if ((next - viewTop).abs() > 0.5) scroll.jumpTo(next);
  }

  /// 排一帧测量纸面头尾的自然高度；高度变化只触发一次局部重建。
  void _scheduleChromeMeasure() {
    if (_measureScheduled ||
        (widget.documentHeader == null && widget.documentFooter == null)) {
      return;
    }
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted) return;
      final header = _measuredHeight(_headerKey);
      final footer = _measuredHeight(_footerKey);
      _chromeMeasured = true;
      if ((header - _headerExtent).abs() > .5 ||
          (footer - _footerExtent).abs() > .5) {
        setState(() {
          _headerExtent = header;
          _footerExtent = footer;
        });
      }
    });
  }

  double _measuredHeight(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize ? box.size.height : 0;
  }

  /// 在 extent 与头尾高度都可用后应用一次滚动恢复；失败/越界只做安全钳制。
  void _scheduleRestore() {
    if (!_restorePending || _restoreScheduled) return;
    _restoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreScheduled = false;
      if (!mounted || !_restorePending || !scroll.hasClients) return;
      // 纸面头尾尚未测量时 extent 还不完整，等测量帧后再恢复，避免把远偏移
      // 钳到临时偏小的可滚动范围。
      if (widget.documentHeader != null && !_chromeMeasured) {
        _scheduleRestore();
        return;
      }
      final target = (widget.restoreScrollOffset ?? 0).clamp(
        0.0,
        scroll.position.maxScrollExtent,
      );
      if ((target - scroll.offset).abs() > .1) scroll.jumpTo(target);
      _restorePending = false;
      widget.onScrollRestored?.call();
    });
  }

  /// 确保光标可见：测量光标所在页并把滚动位置调到距离上下边缘至少 12 像素。
  /// 测量失败（StateError）时标记排版降级并重绘。
  void ensureCaret() {
    try {
      _ensureCaret();
    } on StateError {
      if (mounted) setState(() => _layoutFailed = true);
    }
  }

  void _ensureCaret() {
    if (!scroll.hasClients || _size.height == 0) return;
    controller.layout.ensureOffset(controller.value.selection.extentOffset);
    final page =
        controller.layout.pages[controller.layout.pageAtOffset(
          controller.value.selection.extentOffset,
        )];
    final caret = caretAt(
      painters.get(controller.layout, page),
      page,
      controller.value.selection.extentOffset,
      Offset(0, page.y),
    );
    var target = scroll.offset;
    // caret 是正文画布坐标；纸面标题在其上方，换算成文档滚动偏移后
    // 分别保证光标距视口上下边缘至少 12 像素（标题随纸面滚走时同样成立）。
    final topLimit = _headerExtent + caret.top - 12;
    final bottomLimit = _headerExtent + caret.bottom - _size.height + 12;
    if (target > topLimit) target = topLimit;
    if (target < bottomLimit) target = bottomLimit;
    target = target.clamp(0, scroll.position.maxScrollExtent);
    if ((target - scroll.offset).abs() > .1) scroll.jumpTo(target);
  }

  void _geometry() {
    if (!mounted || scene == null) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    // 场景矩形以正文画布为原点；正文画布随标题高度下移，需平移回视口坐标。
    final shift = Offset(0, _bodyTop);
    var composing = scene!.caret.shift(shift);
    for (final rect in scene!.composing) {
      composing = composing.expandToInclude(rect.shift(shift));
    }
    controller.geometry(
      box.size,
      box.getTransformTo(null),
      scene!.caret.shift(shift),
      composing,
    );
  }

  int _hit(Offset point) {
    final raw = controller.document.raw;
    final hit = scene!.hit(point).clamp(0, raw.length);
    final range = CharacterRange.at(raw, hit);
    return range.stringBeforeLength;
  }

  void _tap(TapDownDetails details) {
    if (controller.readOnly || controller.composing || scene == null) return;
    if (HardwareKeyboard.instance.isControlPressed &&
        widget.onOpenSources != null &&
        widget.sourceBody == controller.document.raw) {
      // 溯源标记只属于其来源正文快照；正文已变时禁用 Ctrl+点击，避免命中错位。
      final matches = [
        for (final index in scene!.sourceIndicesAt(details.localPosition))
          widget.sourceMarks[index],
      ];
      if (matches.isNotEmpty) {
        widget.onOpenSources!(matches);
        return;
      }
    }
    requestFocus();
    controller.select(
      TextSelection.collapsed(offset: _hit(details.localPosition)),
    );
  }

  void _dragStart(DragStartDetails details) {
    if (controller.readOnly || controller.composing || scene == null) return;
    requestFocus();
    _anchor = _hit(details.localPosition);
    controller.select(TextSelection.collapsed(offset: _anchor));
  }

  void _drag(DragUpdateDetails details) {
    if (controller.readOnly || controller.composing || scene == null) return;
    controller.move(_hit(details.localPosition), true);
    if (!scroll.hasClients) return;
    final dy = details.localPosition.dy;
    if (dy < 16 || dy > _size.height - 16) {
      scroll.jumpTo(
        (scroll.offset + (dy < 16 ? -24 : 24)).clamp(
          0,
          scroll.position.maxScrollExtent,
        ),
      );
    }
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    // 头尾控件与嵌入讨论共享视口子树；它们的按键继续交给自身 Actions。
    if (!node.hasPrimaryFocus) return KeyEventResult.ignored;
    if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
        !controller.composing &&
        !HardwareKeyboard.instance.isControlPressed) {
      final key = event.logicalKey;
      if ([
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.home,
        LogicalKeyboardKey.end,
      ].contains(key)) {
        _geometryMove(key, HardwareKeyboard.instance.isShiftPressed);
        return KeyEventResult.handled;
      }
    }
    return controller.handleKey(node, event);
  }

  void _geometryMove(LogicalKeyboardKey key, bool shift) {
    try {
      _moveByGeometry(key, shift);
    } on StateError {
      if (mounted) setState(() => _layoutFailed = true);
    }
  }

  void _moveByGeometry(LogicalKeyboardKey key, bool shift) {
    final layout = controller.layout;
    final offset = controller.value.selection.extentOffset;
    layout.ensureOffset(offset);
    final page = layout.pages[layout.pageAtOffset(offset)];
    final painter = painters.get(layout, page);
    final local = TextPosition(
      offset: (offset - page.start).clamp(0, page.text.length),
    );
    int next;
    if (key == LogicalKeyboardKey.home || key == LogicalKeyboardKey.end) {
      final line = painter.getLineBoundary(local);
      next =
          page.start + (key == LogicalKeyboardKey.home ? line.start : line.end);
    } else {
      final caret = caretAt(painter, page, offset, Offset(0, page.y));
      final lineHeight = painter.computeLineMetrics().first.height;
      final y =
          caret.center.dy +
          (key == LogicalKeyboardKey.arrowUp ? -lineHeight : lineHeight);
      var target = layout.pages.first;
      for (final candidate in layout.pages) {
        if (candidate.y <= y) target = candidate;
        if (candidate.y > y) break;
      }
      next =
          target.start +
          painters
              .get(layout, target)
              .getPositionForOffset(Offset(caret.left, y - target.y))
              .offset;
    }
    final range = CharacterRange.at(
      controller.document.raw,
      next.clamp(0, controller.document.raw.length),
    );
    controller.move(range.stringBeforeLength, shift);
  }

  void _constrain(Size size) {
    _size = size;
    final targetWidth = math.min(
      widget.maxTextWidth,
      math.max(80.0, _size.width - 48),
    );
    if ((targetWidth - controller.layout.width).abs() > .1) {
      controller.width(targetWidth);
    }
    _scheduleChromeMeasure();
  }

  EditorViewportFrame? _project(ViewportOffset offset) {
    try {
      final frame = projectEditorViewport(
        configuration: widget,
        size: _size,
        header: _headerExtent,
        footer: _footerExtent,
        offset: offset,
        painters: painters,
        revision: ++_revision,
      );
      _bodyTop = frame.bodyTop;
      scene = frame.scene;
      _scheduleRestore();
      WidgetsBinding.instance.addPostFrameCallback((_) => _geometry());
      return frame;
    } on StateError {
      _layoutFailed = true;
      offset.applyContentDimensions(0, 0);
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => EditorViewportSurface(
    bindings: EditorViewportBindings(
      configuration: widget,
      scroll: scroll,
      headerKey: _headerKey,
      footerKey: _footerKey,
      failed: controller.renderingError != null || _layoutFailed,
      onLayout: _constrain,
      project: _project,
      onFocus: requestFocus,
      onKey: _key,
      onTap: _tap,
      onDragStart: _dragStart,
      onDrag: _drag,
    ),
  );
  @override
  void dispose() {
    controller.removeListener(_changed);
    controller.focusNode.removeListener(_focus);
    scroll.dispose();
    painters.dispose();
    super.dispose();
  }
}
