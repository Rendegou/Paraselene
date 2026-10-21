// 编辑器视口公开组件：配置与状态分开维护，既有调用入口保持稳定。
import 'package:flutter/material.dart';
import 'editor_source_mark.dart';
import 'editor_viewport_controller.dart';
import 'editor_viewport_state.dart';
export 'editor_basic_controller.dart';
export 'editor_viewport_controller.dart';
export 'editor_viewport_state.dart';

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
