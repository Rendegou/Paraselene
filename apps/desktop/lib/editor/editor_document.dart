// 编辑器文档模型：正文的权威内存表示（原始 UTF-16 文本、选区与 IME 组合态）。
//
// 本文件无 IO、无数据库访问，不归一化、不翻译、不自动补换行，正文逐字保留。
// 所有编辑入口都返回 EditResult：拒绝时文档、历史与窗口缓存均保持不变。
// 撤销/重做历史在内存中按快照有界保存（见 EditorHistory）；一次 IME 组合归并为一次事务。
// 可选的 IME 上下文窗口受 maxWindowCodeUnits 限制，无法满足时 window 为 null，
// 并通过 windowUnsupportedReason 给出原因；这不影响全量正文的编辑能力。
import 'package:characters/characters.dart';
import 'package:flutter/services.dart';
import 'editor_history.dart';
import 'editor_values.dart';
export 'editor_values.dart';

/// Authoritative raw UTF-16 document with undo/redo and optional bounded
/// IME context. Text is never normalized or translated.
///
/// The full-document API supports arbitrarily wide selections. [window] is a
/// bounded IME-context experiment and can be unavailable. History is in-memory
/// and bounded by [EditorHistory]; one composition groups into one transaction.
/// This model has no IO and provides no evidence of native IME correctness.
///
/// 单篇正文的权威内存模型：原始 UTF-16 文本、全局选区、IME 组合态与撤销/重做历史。
/// 全量 API 支持任意宽的选区；[window] 只是有界的 IME 上下文实验，可能不可用。
/// 历史仅存内存且按 [EditorHistory] 有界；一次组合归并为一次事务。
/// 无 IO，也不代表原生 IME 行为已经验证。
final class EditorDocument {
  EditorDocument(String raw, {this.maxWindowCodeUnits = 1024})
    : _value = TextEditingValue(
        text: raw,
        selection: const TextSelection.collapsed(offset: 0),
      ) {
    if (maxWindowCodeUnits < 4 || !_wellFormed(raw)) {
      throw ArgumentError('Require well-formed UTF-16 and window budget >= 4.');
    }
  }

  /// Maximum optional context size, measured in UTF-16 code units.
  ///
  /// 可选 IME 上下文的 UTF-16 code unit 上限，构造时要求至少为 4。
  final int maxWindowCodeUnits;
  TextEditingValue _value;
  final EditorHistory _undo = EditorHistory();
  final EditorHistory _redo = EditorHistory();
  TextEditingValue? _compositionBase;
  EditorWindow? _cachedWindow;
  (int, int)? _pinnedBounds;
  bool _windowDirty = true;
  String? _windowReason;

  /// 完整正文的原始 UTF-16 文本；未经任何归一化或翻译。
  String get raw => _value.text;

  /// 全局编辑状态：完整正文、全局选区与组合区间。
  TextEditingValue get globalValue => _value;

  /// 是否存在可撤销事务；进行中的组合只要偏离了组合基线也算可撤销。
  bool get canUndo =>
      _undo.isNotEmpty ||
      _compositionBase?.text != raw && _compositionBase != null;

  /// 是否存在可重做事务。
  bool get canRedo => _redo.isNotEmpty;

  /// Optional grapheme-bounded context; null means an explicit unsupported case.
  /// Inactive collapsed composing ranges project to empty; global state is exact.
  ///
  /// 落在字素边界内的可选 IME 上下文；null 表示当前状态明确不受支持。
  /// 未激活且折叠的组合区间投影为空，全局状态始终精确。
  EditorWindow? get window {
    if (_windowDirty) _refreshWindow();
    return _cachedWindow;
  }

  /// 上下文不可用时的稳定原因说明；可用时为 null。
  String? get windowUnsupportedReason {
    if (_windowDirty) _refreshWindow();
    return _windowReason;
  }

  /// Accepts full raw UTF-16 editing state, independently of context feasibility.
  ///
  /// 直接接受完整原始 UTF-16 编辑状态，与 IME 上下文是否可用无关；
  /// 校验失败返回拒绝结果，文档、历史与缓存均保持原样。
  EditResult applyGlobalValue(TextEditingValue next) => _applyGlobalValue(next);

  EditResult _applyGlobalValue(
    TextEditingValue next, {
    (int, int, int)? localDifference,
  }) {
    final invalid = _validate(next, checkText: next.text != raw);
    if (invalid != null) return EditResult.rejected(invalid);
    if (next == _value) return EditResult.ok;
    final before = _value;
    _recordHistory(before, next);
    _updatePin(before, next, localDifference: localDifference);
    _value = next;
    _windowDirty = true;
    return EditResult.ok;
  }

  /// Applies a native local value by changing only its minimal raw difference.
  ///
  /// Callers must send the current [window] only. [expectedWindow], when given,
  /// rejects stale callbacks after a window switch or a prior local edit.
  ///
  /// 只把原生局部值的最小差异写回全局正文，不做整篇替换。调用方必须发送当前的
  /// [window]；传入 [expectedWindow] 时，窗口切换或本地编辑之后的过期回调会被拒绝。
  EditResult updateFromPlatform(
    TextEditingValue local, {
    EditorWindow? expectedWindow,
  }) {
    final current = window;
    if (current == null) {
      return EditResult.rejected(_windowReason ?? 'context unavailable');
    }
    if (expectedWindow != null && !identical(expectedWindow, current)) {
      return const EditResult.rejected('stale context');
    }
    final invalid = _validate(local);
    if (invalid != null) return EditResult.rejected(invalid);
    if (_active(local) && local.text.length > maxWindowCodeUnits) {
      return const EditResult.rejected('local context exceeds UTF-16 budget');
    }
    final (prefix, oldEnd, newEnd) = _difference(
      current.value.text,
      local.text,
    );
    final nextRaw = raw.replaceRange(
      current.start + prefix,
      current.start + oldEnd,
      local.text.substring(prefix, newEnd),
    );
    if (_active(local) &&
        !_graphemeBounds(
          nextRaw,
          current.start,
          current.start + local.text.length,
        )) {
      return const EditResult.rejected('composition splits boundary grapheme');
    }
    return _applyGlobalValue(
      TextEditingValue(
        text: nextRaw,
        selection: _shiftSelection(local.selection, current.start),
        composing: _shiftRange(local.composing, current.start),
      ),
      localDifference: (
        current.start + prefix,
        current.start + oldEnd,
        current.start + newEnd,
      ),
    );
  }

  /// Moves a global selection. Surrogate halves and active composition reject.
  ///
  /// 移动全局选区；端点落在代理对内部或仍有进行中的组合时拒绝，要求先提交组合。
  EditResult select(TextSelection selection) {
    if (_active(_value)) {
      return const EditResult.rejected('commit composition before selection');
    }
    return applyGlobalValue(_value.copyWith(selection: selection));
  }

  /// Replaces the global selection exactly; no newline or Unicode normalization.
  ///
  /// 精确替换全局选区：不自动补换行、不做 Unicode 归一化；组合进行中拒绝。
  EditResult replaceSelection(String text) {
    if (_active(_value)) {
      return const EditResult.rejected('commit composition before replacement');
    }
    final selection = _value.selection;
    return applyGlobalValue(
      TextEditingValue(
        text: raw.replaceRange(selection.start, selection.end, text),
        selection: TextSelection.collapsed(
          offset: selection.start + text.length,
        ),
      ),
    );
  }

  /// Restores one text transaction and its global selection; clears composition.
  ///
  /// 撤销一次文本事务并恢复其全局选区，同时清空组合态。组合进行中的撤销先回到
  /// 组合前基线，并把当前状态压入重做栈；没有可撤销内容时返回拒绝结果。
  EditResult undo() {
    if (_compositionBase != null) {
      final baseline = _compositionBase!;
      _compositionBase = null;
      if (baseline.text != raw) {
        _redo.add(_withoutComposition(_value));
      }
      _restore(baseline);
      return EditResult.ok;
    }
    if (_undo.isEmpty) return const EditResult.rejected('nothing to undo');
    _redo.add(_withoutComposition(_value));
    _restore(_undo.removeLast());
    return EditResult.ok;
  }

  /// 重做一次文本事务并恢复其全局选区；组合进行中或没有可重做内容时返回拒绝结果。
  EditResult redo() {
    if (_active(_value)) {
      return const EditResult.rejected('commit composition before redo');
    }
    if (_redo.isEmpty) return const EditResult.rejected('nothing to redo');
    _undo.add(_withoutComposition(_value));
    _restore(_redo.removeLast());
    return EditResult.ok;
  }

  /// Replaces the entire body and clears undo/redo history.
  /// Used when an external source (e.g. chapter switch) provides new content.
  ///
  /// 整篇替换并清空撤销/重做历史与全部缓存状态，用于章节切换等外部来源；
  /// 本方法不校验新文本的 UTF-16 合法性，由调用方保证。
  void replaceBody(String newRaw) {
    _value = TextEditingValue(
      text: newRaw,
      selection: const TextSelection.collapsed(offset: 0),
    );
    _undo.clear();
    _redo.clear();
    _compositionBase = null;
    _pinnedBounds = null;
    _windowReason = null;
    _windowDirty = true;
  }

  void _restore(TextEditingValue value) {
    _value = _withoutComposition(value);
    _compositionBase = null;
    _pinnedBounds = null;
    _windowReason = null;
    _windowDirty = true;
  }

  void _recordHistory(TextEditingValue before, TextEditingValue next) {
    if (_active(next)) _compositionBase ??= _withoutComposition(before);
    if (before.text != next.text) _redo.clear();
    if (_active(next)) return;
    final baseline = _compositionBase ?? before;
    _compositionBase = null;
    if (baseline.text != next.text) {
      _undo.add(_withoutComposition(baseline));
    }
  }

  void _updatePin(
    TextEditingValue before,
    TextEditingValue next, {
    (int, int, int)? localDifference,
  }) {
    if (!_active(next)) {
      _pinnedBounds = null;
      _windowReason = null;
      return;
    }
    if (_pinnedBounds == null &&
        !_active(before) &&
        !_windowDirty &&
        _cachedWindow != null) {
      _pinnedBounds = (_cachedWindow!.start, _cachedWindow!.end);
    }
    final bounds = _pinnedBounds;
    if (bounds == null || before.text == next.text) return;
    final (start, oldEnd, newEnd) =
        localDifference ?? _difference(before.text, next.text);
    if (start < bounds.$1 || oldEnd > bounds.$2) {
      _windowReason = 'global edit escaped pinned context';
    } else {
      _pinnedBounds = (bounds.$1, bounds.$2 + newEnd - oldEnd);
    }
  }

  void _refreshWindow() {
    _windowDirty = false;
    _cachedWindow = null;
    if (_pinnedBounds != null && _windowReason != null) return;
    _windowReason = null;
    final selection = _value.selection;
    final composing = _value.composing;
    var start = selection.start;
    var end = selection.end;
    if (_active(_value)) {
      if (composing.start < start) start = composing.start;
      if (composing.end > end) end = composing.end;
    }
    final bounds = _pinnedBounds ?? _chooseBounds(start, end);
    if (bounds == null) {
      _windowReason = 'selection or grapheme exceeds bounded context';
      return;
    }
    if (_active(_value)) _pinnedBounds ??= bounds;
    if (start < bounds.$1 ||
        end > bounds.$2 ||
        bounds.$2 - bounds.$1 > maxWindowCodeUnits ||
        !_graphemeBounds(raw, bounds.$1, bounds.$2)) {
      _windowReason = 'composition or selection escaped pinned context';
      return;
    }
    _cachedWindow = EditorWindow(
      start: bounds.$1,
      end: bounds.$2,
      value: TextEditingValue(
        text: raw.substring(bounds.$1, bounds.$2),
        selection: _shiftSelection(selection, -bounds.$1),
        composing: _shiftRange(composing, -bounds.$1),
      ),
    );
  }

  (int, int)? _chooseBounds(int selectionStart, int selectionEnd) {
    if (selectionEnd - selectionStart > maxWindowCodeUnits) return null;
    final budget = (selectionEnd - selectionStart + 2).clamp(
      maxWindowCodeUnits ~/ 2,
      maxWindowCodeUnits,
    );
    final spare = budget - (selectionEnd - selectionStart);
    final targetStart = (selectionStart - spare ~/ 2).clamp(0, raw.length);
    var offset = 0;
    var start = 0;
    var end = 0;
    for (final grapheme in raw.characters) {
      final next = offset + grapheme.length;
      if (next <= targetStart) {
        start = next;
        end = next;
        offset = next;
        continue;
      }
      if (next > start + budget) break;
      end = next;
      offset = next;
    }
    if (selectionStart < start || selectionEnd > end) return null;
    if (selectionStart > 0 && selectionStart == start) return null;
    return (start, end);
  }

  static bool _active(TextEditingValue value) =>
      value.composing.isValid && !value.composing.isCollapsed;

  static TextEditingValue _withoutComposition(TextEditingValue value) =>
      value.copyWith(composing: TextRange.empty);

  static TextSelection _shiftSelection(TextSelection value, int delta) =>
      value.copyWith(
        baseOffset: value.baseOffset + delta,
        extentOffset: value.extentOffset + delta,
      );

  static TextRange _shiftRange(TextRange value, int delta) =>
      value.isValid && !value.isCollapsed
      ? TextRange(start: value.start + delta, end: value.end + delta)
      : TextRange.empty;

  static bool _graphemeBounds(String text, int start, int end) {
    var offset = 0;
    var foundStart = start == 0;
    if (start == 0 && end == 0) return true;
    for (final grapheme in text.characters) {
      offset += grapheme.length;
      if (offset == start) foundStart = true;
      if (offset >= end) return foundStart && offset == end;
    }
    return false;
  }

  static String? _validate(TextEditingValue value, {bool checkText = true}) {
    final text = value.text;
    if (checkText && !_wellFormed(text)) return 'malformed UTF-16';
    final selection = value.selection;
    if (!_boundary(text, selection.baseOffset) ||
        !_boundary(text, selection.extentOffset)) {
      return 'selection outside raw text or inside surrogate pair';
    }
    final composing = value.composing;
    if (composing == TextRange.empty) return null;
    if (!composing.isNormalized ||
        !_boundary(text, composing.start) ||
        !_boundary(text, composing.end)) {
      return 'composing outside raw text or inside surrogate pair';
    }
    return null;
  }

  static bool _boundary(String text, int offset) =>
      offset >= 0 &&
      offset <= text.length &&
      !(offset > 0 &&
          offset < text.length &&
          _high(text.codeUnitAt(offset - 1)) &&
          _low(text.codeUnitAt(offset)));

  static bool _high(int unit) => unit >= 0xd800 && unit <= 0xdbff;
  static bool _low(int unit) => unit >= 0xdc00 && unit <= 0xdfff;

  static bool _wellFormed(String text) {
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (_high(unit)) {
        if (++i >= text.length || !_low(text.codeUnitAt(i))) return false;
      } else if (_low(unit)) {
        return false;
      }
    }
    return true;
  }

  static (int, int, int) _difference(String before, String after) {
    var prefix = 0;
    while (prefix < before.length &&
        prefix < after.length &&
        before.codeUnitAt(prefix) == after.codeUnitAt(prefix)) {
      prefix++;
    }
    while (!_boundary(before, prefix) || !_boundary(after, prefix)) {
      prefix--;
    }
    var oldEnd = before.length;
    var newEnd = after.length;
    while (oldEnd > prefix &&
        newEnd > prefix &&
        before.codeUnitAt(oldEnd - 1) == after.codeUnitAt(newEnd - 1)) {
      oldEnd--;
      newEnd--;
    }
    while (!_boundary(before, oldEnd) || !_boundary(after, newEnd)) {
      oldEnd++;
      newEnd++;
    }
    return (prefix, oldEnd, newEnd);
  }
}
