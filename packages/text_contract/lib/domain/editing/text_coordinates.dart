/// Coordinate conversions preserve every code unit of valid author text.
library;

/// Stable ASCII failures; callers localize codes rather than matching messages.
enum ContractFailureCode {
  malformedUtf16,
  splitSurrogate,
  invalidRange,
  emptySelection,
  staleQuote,
  staleBody,
  invalidFingerprint,
  invalidLocale,
  unsupportedFallback,
}

/// A rejected contract value, carrying an unlocalized stable [code].
final class ContractFailure implements Exception {
  const ContractFailure(this.code);
  final ContractFailureCode code;
  @override
  String toString() => 'ContractFailure(${code.name})';
}

/// Half-open offsets in UTF-16 code units, never grapheme or byte offsets.
final class Utf16Range {
  const Utf16Range(this.start, this.end);
  final int start;
  final int end;
  @override
  bool operator ==(Object other) =>
      other is Utf16Range && start == other.start && end == other.end;
  @override
  int get hashCode => Object.hash(start, end);
}

/// Half-open offsets in Unicode scalars, matching Rust `char` indexing.
final class ScalarRange {
  const ScalarRange(this.start, this.end);
  final int start;
  final int end;
  @override
  bool operator ==(Object other) =>
      other is ScalarRange && start == other.start && end == other.end;
  @override
  int get hashCode => Object.hash(start, end);
}

/// Validates UTF-16 once; conversions reject split surrogates and bad bounds.
final class TextCoordinates {
  TextCoordinates(this.body) : _boundaries = _scan(body);
  final String body;
  final List<int> _boundaries;
  int get scalarLength => _boundaries.length - 1;

  ScalarRange toScalars(Utf16Range range) {
    _check(range.start, range.end, body.length);
    return ScalarRange(_scalarAt(range.start), _scalarAt(range.end));
  }

  Utf16Range toUtf16(ScalarRange range) {
    _check(range.start, range.end, scalarLength);
    return Utf16Range(_boundaries[range.start], _boundaries[range.end]);
  }

  /// Requires a nonempty selection and its exact, unnormalized quote.
  ScalarRange validateSelection(Utf16Range range, String quote) {
    final converted = toScalars(range);
    if (range.start == range.end) {
      throw const ContractFailure(ContractFailureCode.emptySelection);
    }
    if (body.substring(range.start, range.end) != quote) {
      throw const ContractFailure(ContractFailureCode.staleQuote);
    }
    return converted;
  }

  int _scalarAt(int offset) {
    var low = 0;
    var high = _boundaries.length - 1;
    while (low <= high) {
      final middle = (low + high) ~/ 2;
      final value = _boundaries[middle];
      if (value == offset) return middle;
      if (value < offset) {
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    throw const ContractFailure(ContractFailureCode.splitSurrogate);
  }

  static void _check(int start, int end, int length) {
    if (start < 0 || end < start || end > length) {
      throw const ContractFailure(ContractFailureCode.invalidRange);
    }
  }

  static List<int> _scan(String text) {
    final boundaries = <int>[0];
    var index = 0;
    while (index < text.length) {
      final unit = text.codeUnitAt(index++);
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (index == text.length || !_isLow(text.codeUnitAt(index))) {
          throw const ContractFailure(ContractFailureCode.malformedUtf16);
        }
        index++;
      } else if (_isLow(unit)) {
        throw const ContractFailure(ContractFailureCode.malformedUtf16);
      }
      boundaries.add(index);
    }
    return List<int>.unmodifiable(boundaries);
  }

  static bool _isLow(int unit) => unit >= 0xdc00 && unit <= 0xdfff;
}

/// Opaque Rust-owned BLAKE3 wire value; Dart never computes or verifies hashes.
final class BodyFingerprint {
  BodyFingerprint.fromRust(this.value) {
    if (value.length != 64 || !RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
      throw const ContractFailure(ContractFailureCode.invalidFingerprint);
    }
  }
  final String value;
  @override
  bool operator ==(Object other) =>
      other is BodyFingerprint && value == other.value;
  @override
  int get hashCode => value.hashCode;
}

/// A frozen base body allows restoration only after exact full-body equality.
final class TargetSnapshot {
  TargetSnapshot({
    required this.baseBody,
    required this.range,
    required this.quote,
    required this.fingerprint,
  }) {
    TextCoordinates(baseBody).validateSelection(range, quote);
  }
  final String baseBody;
  final Utf16Range range;
  final String quote;
  final BodyFingerprint fingerprint;

  /// Revalidates the quote at a transaction-mapped range; never searches text.
  ScalarRange revalidate(String currentBody, Utf16Range mappedRange) =>
      TextCoordinates(currentBody).validateSelection(mappedRange, quote);

  /// Restores known offsets only when undo restores the entire frozen body.
  Utf16Range restore(String currentBody) {
    if (currentBody != baseBody) {
      throw const ContractFailure(ContractFailureCode.staleBody);
    }
    TextCoordinates(currentBody).validateSelection(range, quote);
    return range;
  }
}
