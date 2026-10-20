// 简易编辑器视口控制器：为测试与无 IME 的预览提供最小实现。
//
// 不建立 TextInput 连接（attach/detach/geometry 均为空操作），键盘事件全部放行；
// 选区与文本只写入 EditorDocument/EditorLayout，不写库、不触碰剪贴板。
// 宽度变化时重建布局并沿用原讨论槽与槽锚点，宽度单位为逻辑像素。
import 'package:flutter/material.dart';
import 'editor_document.dart';
import 'editor_layout.dart';
import 'editor_viewport.dart';

/// Simple controller for testing without full IME support.
///
/// 供测试与无 IME 预览使用的文档与布局控制器；不注册原生文本输入，
/// 只支持程序化的选区、移动和宽度变更，不处理键盘编辑，也不建立 IME 组合态。
final class BasicEditorController extends ChangeNotifier
    implements EditorViewportController {
  BasicEditorController(String text, {double width = 760, required this.style})
    : document = EditorDocument(text),
      layout = EditorLayout(width: width, style: style) {
    layout.update(text);
  }

  @override
  final EditorDocument document;
  @override
  EditorLayout layout;
  @override
  final FocusNode focusNode = FocusNode(debugLabel: 'Editor viewport');

  /// 用于测量排版与配置焦点节点的文本样式；宽度单位均为逻辑像素。
  final TextStyle style;
  @override
  String? renderingError;
  @override
  bool readOnly = false;

  @override
  TextEditingValue get value => document.globalValue;
  @override
  bool get composing => value.composing.isValid && !value.composing.isCollapsed;

  @override
  void select(TextSelection selection) {
    document.select(selection);
    layout.update(document.raw);
    notifyListeners();
  }

  @override
  void move(int offset, bool shift) {
    select(
      TextSelection(
        baseOffset: shift ? value.selection.baseOffset : offset,
        extentOffset: offset,
      ),
    );
  }

  @override
  void attach(int viewId) {}
  @override
  void detach() {}
  @override
  void geometry(Size size, Matrix4 transform, Rect caret, Rect composingRect) {}
  @override
  void width(double next) {
    if ((next - layout.width).abs() < .1) return;
    final previous = layout;
    layout = EditorLayout(width: next, style: style)
      ..update(
        document.raw,
        showSlot: previous.slot,
        slotAnchor: previous.slotOffset,
      )
      ..setThreadSlots(previous.threadSlots);
  }

  @override
  KeyEventResult handleKey(FocusNode node, KeyEvent event) {
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    focusNode.dispose();
    super.dispose();
  }
}
