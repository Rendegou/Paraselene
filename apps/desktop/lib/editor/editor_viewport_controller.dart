// 视口读写接缝：只暴露正文坐标和输入几何，不包含Widget或持久化。
import 'package:flutter/material.dart';
import 'editor_document.dart';
import 'editor_layout.dart';

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
