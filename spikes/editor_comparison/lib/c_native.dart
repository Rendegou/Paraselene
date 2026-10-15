import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'c_layout.dart';
import 'c_window_document.dart';

/// Full raw native text client. No hidden EditableText and no native window.
final class CNativeEditor extends ChangeNotifier with TextInputClient {
  CNativeEditor(String text) : document = CWindowDocument(text) {
    layout.update(text);
  }
  CWindowDocument document;
  CLayout layout = CLayout();
  final focusNode = FocusNode(debugLabel: 'C global native editor');
  TextInputConnection? _connection;
  bool get attached => _connection?.attached ?? false;
  String? error;
  String? renderingError;
  final trace = <Map<String, Object?>>[];
  bool captureTrace = true;
  int revision = 0;
  int nativeCallbacks = 0;
  int get length => document.raw.length;
  TextEditingValue get value => document.globalValue;
  bool get composing => value.composing.isValid && !value.composing.isCollapsed;
  @override
  TextEditingValue get currentTextEditingValue => value;
  @override
  AutofillScope? get currentAutofillScope => null;

  void attach(int viewId) {
    // Echoing an active composing value resets Windows IME ownership. Refocus
    // and toolbar callbacks must not resend the already attached editing state.
    if (attached) return;
    if (!attached) {
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
    }
    _connection!.setEditingState(value);
    _connection!.show();
    revision++;
    notifyListeners();
  }

  void detach() {
    _connection?.close();
    _connection = null;
    revision++;
    notifyListeners();
  }

  void geometry(Size size, Matrix4 transform, Rect caret, Rect composingRect) {
    if (!attached) return;
    _connection!.setEditableSizeAndTransform(size, transform);
    _connection!.setCaretRect(caret);
    _connection!.setComposingRect(composingRect);
  }

  @override
  void updateEditingValue(TextEditingValue next) {
    nativeCallbacks++;
    if (captureTrace) {
      trace.add({
        'callback': nativeCallbacks,
        'length': next.text.length,
        'selection': [next.selection.baseOffset, next.selection.extentOffset],
        'composing': [next.composing.start, next.composing.end],
        'composingText': next.isComposingRangeValid
            ? next.composing.textInside(next.text)
            : '',
        'containsNiHao': next.text.contains('你好'),
      });
    }
    _complete(document.applyGlobalValue(next), sendNative: false);
  }

  /// Controller proxy used for profiling; includes outbound native state cost.
  void apply(TextEditingValue next) =>
      _complete(document.applyGlobalValue(next));
  void select(TextSelection selection) => _complete(document.select(selection));
  void replace(String text) => _complete(document.replaceSelection(text));
  void undo() => _complete(document.undo());
  void redo() => _complete(document.redo());
  void toggleSlot() {
    layout.update(
      document.raw,
      showSlot: !layout.slot,
      slotAnchor: value.selection.extentOffset,
    );
    revision++;
    notifyListeners();
  }

  void load(String text) {
    document = CWindowDocument(text);
    layout = CLayout(width: layout.width)..update(text, showSlot: layout.slot);
    error = null;
    renderingError = null;
    trace.clear();
    revision++;
    _connection?.setEditingState(value);
    notifyListeners();
  }

  void width(double next) {
    if ((next - layout.width).abs() < .1) return;
    layout = CLayout(width: next)..update(document.raw, showSlot: layout.slot);
    revision++;
  }

  void _complete(CEditResult result, {bool sendNative = true}) {
    if (!result.accepted) {
      error = result.reason;
      _connection?.setEditingState(value);
    } else {
      error = null;
      try {
        layout.update(document.raw);
        renderingError = null;
      } on StateError catch (failure) {
        renderingError = 'Bounded renderer unsupported: $failure';
        error = renderingError;
      }
      if (sendNative) _connection?.setEditingState(value);
    }
    revision++;
    notifyListeners();
  }

  /// Clipboard failures are displayed; pending paste rejects concurrent edits.
  Future<void> clipboard(String operation) async {
    if (composing) return;
    final before = value;
    try {
      if (operation == 'paste') {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        if (_disposed) return;
        if (value != before) {
          _failure('Paste cancelled: document changed while reading clipboard');
          return;
        }
        if (data != null) replace(data.text ?? '');
      } else {
        await Clipboard.setData(
          ClipboardData(text: before.selection.textInside(before.text)),
        );
        if (_disposed) return;
        if (operation == 'cut') {
          if (value != before) {
            _failure('Cut cancelled: document changed while writing clipboard');
            return;
          }
          replace('');
        }
      }
    } catch (exception) {
      if (!_disposed) _failure('Clipboard $operation failed: $exception');
    }
  }

  void _failure(String message) {
    error = message;
    revision++;
    notifyListeners();
  }

  KeyEventResult key(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // The IME owns arrows/deletion/enter and shortcuts until composition commits.
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
      return KeyEventResult
          .ignored; // Physical text goes through Windows native input.
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
      // A platform scalar caret may be inside a grapheme. The user deletion
      // expands to the whole cluster, while the native value itself stays raw.
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
      // Home/End default to raw hard-line boundaries; viewport handles visual
      // line Home/End and vertical movement with exactly the painted geometry.
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

  int mathOffset(int offset) => offset == 0 ? 0 : offset - 1;
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
