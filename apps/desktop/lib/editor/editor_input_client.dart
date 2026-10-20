// 完整原生文本输入客户端：直接持有 EditorDocument 与 EditorLayout，
// 通过 TextInputClient 与 Windows IME 对接，不使用隐藏的 EditableText。
//
// 作者输入先经同步栏栅（readOnly/inputBlocked）判断，再落到文档模型；
// 编辑结果统一经 _complete 更新布局、记录错误并通知视口，必要时把状态回写 IME。
// 剪贴板等异步操作以输入代次和持久化栏栅代次作废过期回调（见 editor_clipboard.dart）。
// 本文件不写库：持久化由 workspace 层的 EditingSession/SaveCoordinator 负责。
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'editor_document.dart';
import 'editor_layout.dart';
import 'editor_thread_slot.dart';
import 'editor_viewport.dart';
part 'editor_clipboard.dart';

/// Full raw native text client. No hidden EditableText and no native window.
/// Implements EditorViewportController to provide IME integration to the viewport.
///
/// 完整原始文本输入客户端：把 IME、键盘和剪贴板输入写入 [EditorDocument]，
/// 维护布局并通过 [EditorViewportController] 向视口暴露状态。不创建原生窗口，
/// 坐标一律为原始 UTF-16 code unit，宽度单位为逻辑像素。
final class EditorInputClient extends ChangeNotifier
    with TextInputClient
    implements EditorViewportController {
  /// Creates an exact UTF-16 editor; [width] is measured in logical pixels.
  /// [inputBlocked] checks session barriers synchronously before author edits,
  /// including native callbacks arriving before the next widget frame.
  ///
  /// 创建精确 UTF-16 编辑器；[width] 单位为逻辑像素。[inputBlocked] 在作者编辑前
  /// 同步检查会话栏栅，覆盖下一帧之前到达的原生回调；[barrierEpoch] 每次变化都会
  /// 作废挂起的异步剪贴板操作，避免过期内容回写。
  EditorInputClient(
    String text, {
    double width = 760,
    required this.style,
    bool Function()? inputBlocked,
    int Function()? barrierEpoch,
  }) : _inputBlocked = inputBlocked,
       _barrierEpoch = barrierEpoch,
       document = EditorDocument(text),
       _layout = EditorLayout(width: width, style: style) {
    _layout.update(text);
  }

  @override
  final EditorDocument document;
  EditorLayout _layout;
  @override
  EditorLayout get layout => _layout;
  @override
  final FocusNode focusNode = FocusNode(debugLabel: 'Editor input client');

  /// 排版与测量使用的文本样式；布局宽度单位为逻辑像素。
  final TextStyle style;

  TextInputConnection? _connection;

  /// 当前是否已连接到原生 IME；连接关闭后为 false。
  bool get attached => _connection?.attached ?? false;

  /// 最近一次编辑或剪贴板操作的失败原因；成功时清空。
  String? error;
  @override
  String? renderingError;
  final bool Function()? _inputBlocked;
  final int Function()? _barrierEpoch;
  bool _readOnly = false;
  int _inputGeneration = 0;

  /// Rejects edits while the UI or synchronous session barrier blocks input.
  ///
  /// 只读状态为显式只读或 UI/会话同步栏栅阻止输入；切换时会递增输入代次，
  /// 以作废挂起的异步剪贴板操作。
  @override
  bool get readOnly => _readOnly || (_inputBlocked?.call() ?? false);

  /// Invalidates pending clipboard mutations when the UI freeze state changes.
  ///
  /// 设置显式只读标志；只有值真正变化时才递增输入代次。
  set readOnly(bool next) {
    if (_readOnly == next) return;
    _readOnly = next;
    _inputGeneration++;
  }

  /// 编辑与布局状态版本号，每次变更后递增，供视口判断是否需要重绘。
  int revision = 0;

  /// 已接收的原生命中回调计数，仅用于诊断，不参与语义判断。
  int nativeCallbacks = 0;

  /// 正文长度，单位为 UTF-16 code unit。
  int get length => document.raw.length;
  @override
  TextEditingValue get value => document.globalValue;
  @override
  bool get composing => value.composing.isValid && !value.composing.isCollapsed;

  @override
  TextEditingValue get currentTextEditingValue => value;
  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void attach(int viewId) {
    if (attached) return;
    _connection = TextInput.attach(
      this,
      TextInputConfiguration(
        viewId: viewId,
        inputType: TextInputType.multiline,
        inputAction: TextInputAction.newline,
        autocorrect: false,
        enableSuggestions: false,
      ),
    );
    _connection!.setEditingState(value);
    _connection!.show();
    revision++;
    notifyListeners();
  }

  @override
  void detach() {
    _inputGeneration++;
    _connection?.close();
    _connection = null;
    revision++;
    notifyListeners();
  }

  @override
  void geometry(Size size, Matrix4 transform, Rect caret, Rect composingRect) {
    if (!attached) return;
    _connection!.setEditableSizeAndTransform(size, transform);
    _connection!.setCaretRect(caret);
    _connection!.setComposingRect(composingRect);
  }

  @override
  void updateEditingValue(TextEditingValue next) {
    nativeCallbacks++;
    _edit(() => document.applyGlobalValue(next), sendNative: false);
  }

  /// 应用一次来自原生层的编辑状态；与内置回调不同，成功后会回写原生输入连接。
  void apply(TextEditingValue next) =>
      _edit(() => document.applyGlobalValue(next));

  @override
  void select(TextSelection selection) =>
      _edit(() => document.select(selection));

  /// 用 [text] 精确替换当前选区；不补换行、不做 Unicode 归一化。
  void replace(String text) => _edit(() => document.replaceSelection(text));

  /// 撤销一次文本事务；组合进行中的语义由文档模型裁决。
  void undo() => _edit(document.undo);

  /// 重做一次文本事务。
  void redo() => _edit(document.redo);

  /// 切换选区末尾的讨论槽占位显示；只重排布局，不修改正文与撤销历史。
  void toggleSlot() {
    layout.update(
      document.raw,
      showSlot: !layout.slot,
      slotAnchor: value.selection.extentOffset,
    );
    revision++;
    notifyListeners();
  }

  /// Installs stable discussion geometry without modifying document history.
  ///
  /// 安装稳定的讨论宿主几何；只重排布局并递增版本号，不修改正文与撤销历史。
  void setThreadSlots(List<EditorThreadSlot> slots) {
    layout.setThreadSlots(slots);
    revision++;
    notifyListeners();
  }

  /// 装载外部正文并清空撤销/重做历史；递增输入代次以作废挂起的异步操作，
  /// 同时清空错误状态并重写原生编辑状态。
  void load(String text) {
    _inputGeneration++;
    document.replaceBody(text);
    layout.update(text, showSlot: layout.slot);
    error = null;
    renderingError = null;
    revision++;
    _connection?.setEditingState(value);
    notifyListeners();
  }

  /// Installs a Rust-committed candidate as one undoable transaction. This is
  /// an external trusted update and deliberately bypasses the input barrier.
  ///
  /// 把 Rust 已提交的候选正文作为一次可撤销事务采纳，光标按字素边界夹到原位置附近。
  /// 这是受信任的外部更新，有意绕过输入栏栅，但仍保存正文与撤销历史。
  void adoptPersisted(String text) {
    _inputGeneration++;
    final caret = CharacterRange.at(
      text,
      value.selection.extentOffset.clamp(0, text.length),
    ).stringBeforeLength;
    _complete(
      document.applyGlobalValue(
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: caret),
        ),
      ),
    );
  }

  @override
  void width(double next) {
    if ((next - layout.width).abs() < .1) return;
    final previous = layout;
    _layout = EditorLayout(width: next, style: style)
      ..update(
        document.raw,
        showSlot: previous.slot,
        slotAnchor: previous.slotOffset,
      )
      ..setThreadSlots(previous.threadSlots);
    revision++;
  }

  void _edit(EditResult Function() action, {bool sendNative = true}) {
    if (_disposed) return;
    if (readOnly) {
      if (_connection?.attached ?? false) _connection!.setEditingState(value);
      return;
    }
    _complete(action(), sendNative: sendNative);
  }

  void _complete(EditResult result, {bool sendNative = true}) {
    if (!result.accepted) {
      error = result.reason;
      if (_connection?.attached ?? false) _connection!.setEditingState(value);
    } else {
      error = null;
      try {
        layout.update(document.raw);
        renderingError = null;
      } on StateError catch (failure) {
        renderingError = 'Bounded renderer unsupported: $failure';
        error = renderingError;
      }
      // 焦点在讨论草稿/菜单等其它控件时编辑器连接可能已断开，
      // 只更新本地选区与布局，等下次 attach 时再同步原生输入状态。
      if (sendNative && (_connection?.attached ?? false)) {
        _connection!.setEditingState(value);
      }
    }
    revision++;
    notifyListeners();
  }

  /// 执行 copy/cut/paste 异步操作；失败写入 [error] 而不向调用方抛出异常。
  Future<void> clipboard(String operation) => _clipboard(operation);

  void _failure(String message) {
    error = message;
    revision++;
    notifyListeners();
  }

  @override
  KeyEventResult handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (composing) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed) {
      return _control(key, keyboard.isShiftPressed);
    }
    if (key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.delete) {
      _delete(key == LogicalKeyboardKey.backspace);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      replace('\n');
    } else if ([
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.home,
      LogicalKeyboardKey.end,
    ].contains(key)) {
      _horizontal(key, keyboard.isShiftPressed);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _control(LogicalKeyboardKey key, bool shift) {
    if (key == LogicalKeyboardKey.keyA) {
      select(TextSelection(baseOffset: 0, extentOffset: length));
    } else if (key == LogicalKeyboardKey.keyC ||
        key == LogicalKeyboardKey.keyX ||
        key == LogicalKeyboardKey.keyV) {
      unawaited(
        clipboard(
          key == LogicalKeyboardKey.keyC
              ? 'copy'
              : key == LogicalKeyboardKey.keyX
              ? 'cut'
              : 'paste',
        ),
      );
    } else if (key == LogicalKeyboardKey.keyZ) {
      if (shift) {
        redo();
      } else {
        undo();
      }
    } else if (key == LogicalKeyboardKey.keyY) {
      redo();
    } else if (key == LogicalKeyboardKey.home ||
        key == LogicalKeyboardKey.end) {
      _move(key == LogicalKeyboardKey.home ? 0 : length, shift);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// 把偏移按字素边界前移或后移一位并返回新偏移，避免切开代理对与组合字素。
  int boundary(int offset, bool forward) {
    final range = CharacterRange.at(document.raw, offset);
    if (range.current.isNotEmpty) {
      return forward
          ? range.stringBeforeLength + range.current.length
          : range.stringBeforeLength;
    }
    if (forward) {
      return range.moveNext()
          ? range.stringBeforeLength + range.current.length
          : length;
    }
    return range.moveBack() ? range.stringBeforeLength : 0;
  }

  void _delete(bool backward) {
    final selection = value.selection;
    final start = CharacterRange.at(document.raw, selection.start);
    final end = CharacterRange.at(document.raw, selection.end);
    if (start.current.isNotEmpty || end.current.isNotEmpty) {
      select(
        TextSelection(
          baseOffset: start.stringBeforeLength,
          extentOffset: end.stringBeforeLength + end.current.length,
        ),
      );
      replace('');
      return;
    }
    if (selection.isCollapsed) {
      final other = boundary(selection.extentOffset, !backward);
      select(
        TextSelection(baseOffset: selection.extentOffset, extentOffset: other),
      );
    }
    replace('');
  }

  void _horizontal(LogicalKeyboardKey key, bool shift) {
    final selection = value.selection;
    var offset = selection.extentOffset;
    if (key == LogicalKeyboardKey.home || key == LogicalKeyboardKey.end) {
      offset = key == LogicalKeyboardKey.home
          ? document.raw.lastIndexOf('\n', mathOffset(offset)) + 1
          : document.raw.indexOf('\n', offset);
      if (offset < 0) offset = length;
    } else if (!shift && !selection.isCollapsed) {
      offset = key == LogicalKeyboardKey.arrowLeft
          ? selection.start
          : selection.end;
    } else {
      offset = boundary(offset, key == LogicalKeyboardKey.arrowRight);
    }
    _move(offset, shift);
  }

  /// home 键查找用的前移辅助偏移，避免从 0 回绕成负数。
  int mathOffset(int offset) => offset == 0 ? 0 : offset - 1;

  @override
  void move(int offset, bool shift) => _move(offset, shift);

  void _move(int offset, bool shift) => select(
    TextSelection(
      baseOffset: shift ? value.selection.baseOffset : offset,
      extentOffset: offset,
    ),
  );

  @override
  void performAction(TextInputAction action) {
    if (action == TextInputAction.newline && !composing) replace('\n');
  }

  @override
  void connectionClosed() {
    _inputGeneration++;
    _connection = null;
    revision++;
    notifyListeners();
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}
  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}
  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    _connection?.close();
    focusNode.dispose();
    super.dispose();
  }
}
