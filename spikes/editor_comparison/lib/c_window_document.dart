import 'package:characters/characters.dart';
import 'package:flutter/services.dart';

/// An atomic edit outcome; rejection leaves document and history untouched.
final class CEditResult {
  const CEditResult._(this.accepted, this.reason);

  static const ok = CEditResult._(true, null);
  const CEditResult.rejected(String reason) : this._(false, reason);

  final bool accepted;
  final String? reason;
}

/// Immutable optional native context, with raw UTF-16 [start]/[end] offsets.
final class CWindow {
  const CWindow({required this.start, required this.end, required this.value});

  final int start;
  final int end;
  final TextEditingValue value;
}

/// Synthetic candidate C state. Raw text is authoritative and never normalized.
///
/// The full-document API supports arbitrarily wide selections. [window] is a
/// separate, bounded IME-context experiment and can be unavailable. History is
/// in-memory, unbounded, and groups one composition into one text transaction.
/// This model has no IO and provides no evidence of native IME correctness.
final class CWindowDocument {
  CWindowDocument(String raw, {this.maxWindowCodeUnits = 1024})
    : _value = TextEditingValue(
        text: raw,
        selection: const TextSelection.collapsed(offset: 0),
      ) {
    if (maxWindowCodeUnits < 4 || !_wellFormed(raw)) {
      throw ArgumentError('Require well-formed UTF-16 and window budget >= 4.');
    }
  }

  /// Maximum optional context size, measured in UTF-16 code units.
  final int maxWindowCodeUnits;
  TextEditingValue _value;
  final List<TextEditingValue> _undo = [];
  final List<TextEditingValue> _redo = [];
  TextEditingValue? _compositionBase;
  CWindow? _cachedWindow;
  (int, int)? _pinnedBounds;
  bool _windowDirty = true;
  String? _windowReason;

  String get raw => _value.text;
  TextEditingValue get globalValue => _value;
  bool get canUndo =>
      _undo.isNotEmpty ||
      _compositionBase?.text != raw && _compositionBase != null;
  bool get canRedo => _redo.isNotEmpty;

  /// Optional grapheme-bounded context; null means an explicit unsupported case.
  /// Inactive collapsed composing ranges project to empty; global state is exact.
  CWindow? get window {
    if (_windowDirty) _refreshWindow();
    return _cachedWindow;
  }

  String? get windowUnsupportedReason {
    if (_windowDirty) _refreshWindow();
    return _windowReason;
  }

  /// Accepts full raw UTF-16 editing state, independently of context feasibility.
  CEditResult applyGlobalValue(TextEditingValue next) =>
      _applyGlobalValue(next);

  CEditResult _applyGlobalValue(
    TextEditingValue next, {
    (int, int, int)? localDifference,
  }) {
    final invalid = _validate(next, checkText: next.text != raw);
    if (invalid != null) return CEditResult.rejected(invalid);
    if (next == _value) return CEditResult.ok;
    final before = _value;
    _recordHistory(before, next);
    _updatePin(before, next, localDifference: localDifference);
    _value = next;
    _windowDirty = true;
    return CEditResult.ok;
  }

  /// Applies a native local value by changing only its minimal raw difference.
  ///
  /// Callers must send the current [window] only. [expectedWindow], when given,
  /// rejects stale callbacks after a window switch or a prior local edit.
  CEditResult updateFromPlatform(
    TextEditingValue local, {
    CWindow? expectedWindow,
  }) {
    final current = window;
    if (current == null) {
      return CEditResult.rejected(_windowReason ?? 'context unavailable');
    }
    if (expectedWindow != null && !identical(expectedWindow, current)) {
      return const CEditResult.rejected('stale context');
    }
    final invalid = _validate(local);
    if (invalid != null) return CEditResult.rejected(invalid);
    if (_active(local) && local.text.length > maxWindowCodeUnits) {
      return const CEditResult.rejected('local context exceeds UTF-16 budget');
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
      return const CEditResult.rejected('composition splits boundary grapheme');
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
  CEditResult select(TextSelection selection) {
    if (_active(_value)) {
      return const CEditResult.rejected('commit composition before selection');
    }
    return applyGlobalValue(_value.copyWith(selection: selection));
  }

  /// Replaces the global selection exactly; no newline or Unicode normalization.
  CEditResult replaceSelection(String text) {
    if (_active(_value)) {
      return const CEditResult.rejected(
        'commit composition before replacement',
      );
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
  CEditResult undo() {
    if (_compositionBase != null) {
      final baseline = _compositionBase!;
      _compositionBase = null;
      if (baseline.text != raw) {
        _redo.add(_withoutComposition(_value));
      }
      _restore(baseline);
      return CEditResult.ok;
    }
    if (_undo.isEmpty) return const CEditResult.rejected('nothing to undo');
    _redo.add(_withoutComposition(_value));
    _restore(_undo.removeLast());
    return CEditResult.ok;
  }

  CEditResult redo() {
    if (_active(_value)) {
      return const CEditResult.rejected('commit composition before redo');
    }
    if (_redo.isEmpty) return const CEditResult.rejected('nothing to redo');
    _undo.add(_withoutComposition(_value));
    _restore(_redo.removeLast());
    return CEditResult.ok;
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
    if (baseline.text != next.text) _undo.add(_withoutComposition(baseline));
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
    _cachedWindow = CWindow(
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
    // Reserve half the budget for composition growth without switching context.
    final budget = (selectionEnd - selectionStart + 2).clamp(
      maxWindowCodeUnits ~/ 2,
      maxWindowCodeUnits,
    );
    final spare = budget - (selectionEnd - selectionStart);
    final targetStart = (selectionStart - spare ~/ 2).clamp(0, raw.length);
    var start = 0;
    var end = 0;
    var offset = 0;
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
    // A boundary caret must retain the preceding grapheme for Backspace.
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
