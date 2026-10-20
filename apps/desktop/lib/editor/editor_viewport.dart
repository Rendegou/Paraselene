// 可见页视口：滚动、手势、键盘导航、语义树与 IME 几何上报。
//
// 组件只读取控制器状态；绘制内容是每帧构造的不可变 EditorScene。
// 命中测试与滚动使用画布像素，正文偏移统一为原始 UTF-16 code unit。
// 只读或组合输入时拒绝点击/拖拽编辑；测量失败时退化为可语义读取的纯文本占位。
// 本文件不写库、不修改正文。
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'editor_document.dart';
export 'editor_basic_controller.dart';
import 'editor_layout.dart';
import 'editor_scene.dart';
import 'editor_source_mark.dart';
import 'editor_discussion_overlay.dart';

/// Controller interface for the viewport. The future EditorInputClient will
/// implement this to provide full IME integration.
///
/// 视口控制器接口：视口只通过这里读取文档、布局与焦点状态，并回报尺寸、IME 几何
/// 与键盘事件。所有正文偏移均为原始 UTF-16 code unit，尺寸与矩形为逻辑像素；
/// 实现方负责 IME 连接的生命周期，调用方不得持有其内部可变对象。
abstract class EditorViewportController implements Listenable {
  /// 当前正文的权威内存模型，所有权归控制器。
  EditorDocument get document;

  /// 当前排版结果；测量失败时视口整体降级为纯文本占位。
  EditorLayout get layout;

  /// 焦点节点；视口挂在 Focus 上并转发键盘事件。
  FocusNode get focusNode;

  /// 全局编辑状态（完整正文、选区与组合区间）。
  TextEditingValue get value;

  /// 是否有进行中的 IME 组合；为 true 时视口拒绝点击与拖拽改写选区。
  bool get composing;

  /// 是否只读或正被同步栏栅阻止输入。
  bool get readOnly;

  /// 非空表示排版降级，视口改为可语义读取的纯文本占位。
  String? get renderingError;

  /// 设置全局选区；组合进行中或端点非法时由实现方拒绝。
  void select(TextSelection selection);

  /// 把光标移到 [offset]；[shift] 为 true 时保留锚点以扩展选区。
  void move(int offset, bool shift);

  /// 连接原生文本输入，[viewId] 为当前 Flutter 视图编号；重复调用应幂等。
  void attach(int viewId);

  /// 断开原生文本输入并作废挂起操作；可重复调用。
  void detach();

  /// 上报可编辑区尺寸、画布到屏幕的变换以及光标与组合矩形，供 IME 定位候选框。
  void geometry(Size size, Matrix4 transform, Rect caret, Rect composingRect);

  /// 设置新的排版宽度，单位为逻辑像素；实现方应忽略亚像素抖动。
  void width(double next);

  /// 处理键盘事件，返回 handled/ignored 决定事件是否继续冒泡。
  KeyEventResult handleKey(FocusNode node, KeyEvent event);
}

/// Visible-page canvas with scroll, gesture, and keyboard navigation.
/// Full IME integration is provided by EditorInputClient (Phase 1.4).
///
/// 可见页画布：自绘正文页，处理滚动、点击/拖拽选区和几何键盘导航，
/// 并把语义树与 IME 几何转发给控制器；完整 IME 接入由 EditorInputClient 提供。
class EditorViewport extends StatefulWidget {
  const EditorViewport({
    required this.controller,
    this.discussionBuilder,
    this.discussionMarkerBuilder,
    this.onThreadHostMeasured,
    this.selectionActionBuilder,
    this.onStateReady,
    this.sourceMarks = const [],
    this.sourceBody,
    this.onOpenSources,
    this.editorLabel = 'Manuscript editor',
    this.renderingFailureLabel = 'Text is kept. Undo or export the draft.',
    this.maxTextWidth = 760.0,
    this.documentHeader,
    this.documentFooter,
    this.onScrollOffset,
    this.restoreScrollOffset,
    this.restoreScrollToken,
    this.onScrollRestored,
    super.key,
  });

  /// 视口控制器；文档、布局、焦点与 IME 连接都由它持有。
  final EditorViewportController controller;

  /// 正文排版的最大宽度（逻辑像素）；舒适 760 / 宽稿 920。
  final double maxTextWidth;

  /// 需要下划线高亮的溯源标记；只在正文与 [sourceBody] 一致时生效。
  final List<EditorSourceMark> sourceMarks;

  /// 溯源标记对应的正文快照；与当前正文不同则忽略全部标记，避免错位。
  final String? sourceBody;

  /// Ctrl+点击溯源标记时回调命中的标记；为 null 时禁用该交互。
  final ValueChanged<List<EditorSourceMark>>? onOpenSources;

  /// 编辑器的语义标签，供读屏用户识别。
  final String editorLabel;

  /// 排版降级时显示的提示文案；正文仍由语义节点完整暴露。
  final String renderingFailureLabel;

  /// 讨论宿主内容构建器；按宿主 id 构建，为 null 时不显示浮层。
  final Widget Function(BuildContext, String)? discussionBuilder;

  /// 收起讨论线程的段末标记构建器；为 null 时收起线程只在索引中可达。
  final Widget Function(BuildContext, String)? discussionMarkerBuilder;

  /// 展开讨论卡片测量完成后的高度回调，单位逻辑像素。
  final void Function(String id, double height)? onThreadHostMeasured;

  /// 正文存在非折叠选区时的就近轻量操作构建器。
  ///
  /// 回调参数是选区末端的画布矩形（视口本地坐标）；返回 null 时不显示。
  final Widget Function(BuildContext, Rect)? selectionActionBuilder;

  /// 视口状态就绪回调；工作区用它触发“滚动露出讨论卡片”等视口内动作。
  final ValueChanged<EditorViewportState>? onStateReady;

  /// 纸面标题/元信息，位于正文上方，与正文共用同一纵向滚动坐标。
  ///
  /// 由调用方给定自然高度；视口在首帧后测量并把高度计入文档滚动范围。
  final Widget? documentHeader;

  /// 纸面章末操作，位于正文最后一行之后，不再固定到窗口底部。
  final Widget? documentFooter;

  /// 文档滚动偏移变化（含程序滚动恢复）；单位为逻辑像素。
  ///
  /// 只在真实 ScrollPosition 变化时上报，不因 build 或布局测量触发。
  final ValueChanged<double>? onScrollOffset;

  /// 待恢复的文档滚动偏移；由 [restoreScrollToken] 界定作用域。
  ///
  /// 为 null 表示本次不恢复；0 表示新章节回到纸面顶部。恢复发生在纸面头尾
  /// 高度与正文 extent 都可用之后，并被安全钳制到当前可滚动范围。
  final double? restoreScrollOffset;

  /// 恢复作用域标识；切换章节/文档时变化，仅当它变化才重新应用恢复。
  final Object? restoreScrollToken;

  /// 恢复成功应用后回调；用于消费 controller 的 pendingScrollTop 状态。
  final VoidCallback? onScrollRestored;
  @override
  State<EditorViewport> createState() => EditorViewportState();
}

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

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: controller.focusNode,
    onKeyEvent: _key,
    child: LayoutBuilder(
      builder: (context, constraints) {
        if (controller.renderingError != null || _layoutFailed) {
          return Semantics(
            textField: true,
            value: controller.document.raw,
            child: Center(child: Text(widget.renderingFailureLabel)),
          );
        }
        _size = constraints.biggest;
        // 正文栏宽限制在 80–760 逻辑像素：过窄无法正常断行，过宽有损阅读。
        final targetWidth = math.min(
          widget.maxTextWidth,
          math.max(80.0, _size.width - 48),
        );
        if ((targetWidth - controller.layout.width).abs() > .1) {
          controller.width(targetWidth);
        }
        _scheduleChromeMeasure();
        return Scrollbar(
          controller: scroll,
          thumbVisibility: true,
          child: Scrollable(
            controller: scroll,
            viewportBuilder: (context, offset) {
              offset.applyViewportDimension(_size.height);
              var pixels = offset.pixels;
              // 纸面标题/章末与正文共用同一个 ScrollPosition：正文画布只在
              // 标题滚出视口后才开始滚动，正文上方的剩余高度由标题占据。
              var bodyTop = math.max(0.0, _headerExtent - pixels);
              var bodyScroll = math.max(0.0, pixels - _headerExtent);
              var bodyViewport = math.max(0.0, _size.height - bodyTop);
              // 章末占据视口底部一段高度时，正文画布可以滚到自身最大偏移之后，
              // 为章末让出空间。prepareViewport 按正文自身范围钳制并返回测量修正，
              // 这里只把它当作滚动修正量，不用它替换文档偏移。
              final maxBodyScroll = math.max(
                0.0,
                controller.layout.height - bodyViewport,
              );
              final prepareScroll = math.min(bodyScroll, maxBodyScroll);
              double corrected;
              try {
                corrected = controller.layout.prepareViewport(
                  prepareScroll,
                  bodyViewport,
                  caret: controller.value.selection.extentOffset,
                );
              } on StateError {
                _layoutFailed = true;
                offset.applyContentDimensions(0, 0);
                return Semantics(
                  liveRegion: true,
                  child: Center(child: Text(widget.renderingFailureLabel)),
                );
              }
              final shift = corrected - prepareScroll;
              if (shift.abs() > .01) {
                offset.correctBy(shift);
                pixels = offset.pixels;
                bodyTop = math.max(0.0, _headerExtent - pixels);
                bodyScroll = math.max(0.0, pixels - _headerExtent);
                bodyViewport = math.max(0.0, _size.height - bodyTop);
              }
              _bodyTop = bodyTop;
              offset.applyContentDimensions(
                0,
                math.max(
                  0,
                  _headerExtent +
                      controller.layout.height +
                      _footerExtent -
                      _size.height,
                ),
              );
              _scheduleRestore();
              scene = buildScene(
                layout: controller.layout,
                cache: painters,
                value: controller.value,
                viewport: Size(_size.width, bodyViewport),
                scroll: bodyScroll,
                revision: ++_revision,
                sourceRanges: [
                  for (final mark
                      in widget.sourceBody == controller.document.raw
                          ? widget.sourceMarks
                          : <EditorSourceMark>[])
                    TextRange(start: mark.from, end: mark.to),
                ],
              );
              WidgetsBinding.instance.addPostFrameCallback((_) => _geometry());
              final bodySize = Size(_size.width, bodyViewport);
              final manuscript = Semantics(
                textField: true,
                multiline: true,
                focused: controller.focusNode.hasFocus,
                label: widget.editorLabel,
                value: controller.document.raw,
                onTap: requestFocus,
                onSetSelection: (selection) => controller.select(selection),
                child: ExcludeSemantics(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: _tap,
                    onPanStart: _dragStart,
                    onPanUpdate: _drag,
                    child: ClipRect(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          size: bodySize,
                          painter: ScenePainter(
                            scene!,
                            controller.focusNode.hasFocus,
                          ),
                          isComplex: true,
                        ),
                      ),
                    ),
                  ),
                ),
              );
              final body = Stack(
                children: [
                  Positioned.fill(child: manuscript),
                  if (widget.discussionBuilder != null)
                    Positioned.fill(
                      child: ClipRect(
                        child: EditorDiscussionOverlay(
                          layout: controller.layout,
                          origin: scene!.transform.origin,
                          builder: widget.discussionBuilder!,
                          markerBuilder: widget.discussionMarkerBuilder,
                          onHostMeasured: widget.onThreadHostMeasured,
                        ),
                      ),
                    ),
                  // 选区旁的就近操作：随选区末端定位并限制在视口内，避免
                  // 窄窗或靠近边缘时把按钮推出可视区域。
                  if (widget.selectionActionBuilder != null &&
                      !controller.composing &&
                      scene != null &&
                      !controller.value.selection.isCollapsed)
                    Positioned(
                      left: (scene!.caret.left + 6)
                          .clamp(4.0, math.max(4.0, _size.width - 140))
                          .toDouble(),
                      top: (scene!.caret.top - 38)
                          .clamp(4.0, math.max(4.0, bodyViewport - 32))
                          .toDouble(),
                      child: widget.selectionActionBuilder!(
                        context,
                        scene!.caret,
                      ),
                    ),
                ],
              );
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (widget.documentHeader != null)
                    Positioned(
                      // 标题位于文档坐标 0；视口坐标随滚动上移。
                      top: -pixels,
                      left: 0,
                      right: 0,
                      child: KeyedSubtree(
                        key: _headerKey,
                        child: widget.documentHeader!,
                      ),
                    ),
                  Positioned(
                    top: bodyTop,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: body,
                  ),
                  if (widget.documentFooter != null)
                    Positioned(
                      top: _headerExtent + controller.layout.height - pixels,
                      left: 0,
                      right: 0,
                      child: KeyedSubtree(
                        key: _footerKey,
                        child: widget.documentFooter!,
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
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
