// 文本坐标合同：UTF-16 与 Unicode 标量半开区间的互转、选区校验、正文指纹与恢复快照。
//
// 纯 Dart 实现，不依赖 Flutter/IO/数据库；不归一化、不翻译作者正文。
// 关键不变量：所有偏移都是不可变值且按 UTF-16 代码单元计；涉及标量时必须落在代理对
// 边界上，非法字符或越界统一抛出带稳定错误码的 [ContractFailure]。

/// Coordinate conversions preserve every code unit of valid author text.
///
/// 中文契约：坐标只在合法 UTF-16 上定义；错误码稳定，由调用方负责本地化。
library;

/// Stable ASCII failures; callers localize codes rather than matching messages.
///
/// 合同校验失败的稳定枚举；调用方按 code 本地化，不得匹配英文消息。
enum ContractFailureCode {
  /// 正文包含孤立或错序的 UTF-16 代理项。
  malformedUtf16,

  /// 偏移落在代理对中间，无法映射到标量边界。
  splitSurrogate,

  /// 区间越界，或 end 小于 start。
  invalidRange,

  /// 需要非空选区时传入了空区间。
  emptySelection,

  /// 选区文本与冻结的 quote 不一致。
  staleQuote,

  /// 提供恢复的正文不是构造快照时的完整正文。
  staleBody,

  /// 指纹不是 64 位小写十六进制 BLAKE3 值。
  invalidFingerprint,

  /// 语言标签不符合 language[-Script][-REGION] 形式。
  invalidLocale,

  /// UI locale 回退目标不是已发布的 en 或 zh-Hans。
  unsupportedFallback,
}

/// A rejected contract value, carrying an unlocalized stable [code].
///
/// 携带稳定 [code] 的合同异常；不包含本地化文本或作者内容。
final class ContractFailure implements Exception {
  /// 用稳定错误码包装一次校验失败。
  const ContractFailure(this.code);

  /// 稳定的错误码，由调用方决定如何本地化。
  final ContractFailureCode code;
  @override
  String toString() => 'ContractFailure(${code.name})';
}

/// Half-open offsets in UTF-16 code units, never grapheme or byte offsets.
///
/// 半开区间 [start, end)，单位为 UTF-16 代码单元；构造时不校验边界。
final class Utf16Range {
  /// 记录起止偏移；有效性由使用它的换算函数校验。
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
///
/// 半开区间 [start, end)，单位为 Unicode 标量，与 Rust `char` 索引一致。
final class ScalarRange {
  /// 记录起止标量偏移；有效性由使用它的换算函数校验。
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
///
/// 一次扫描校验后的正文坐标视图。
///
/// 构造时扫描并拒绝孤立代理项；之后的换算与选区校验只做 O(log n) 二分。
/// 本类不复制正文，只保存标量边界，调用方必须保证偏移对应同一份正文。
final class TextCoordinates {
  /// 扫描 [body] 建立标量边界；正文含非法 UTF-16 时抛出 malformedUtf16。
  TextCoordinates(this.body) : _boundaries = _scan(body);

  /// 原始正文引用；本类不修改、不归一化该字符串。
  final String body;
  final List<int> _boundaries;

  /// 正文的 Unicode 标量数量。
  int get scalarLength => _boundaries.length - 1;

  /// 把 UTF-16 半开区间换成标量区间；越界或切在代理对中间时抛出。
  ScalarRange toScalars(Utf16Range range) {
    _check(range.start, range.end, body.length);
    return ScalarRange(_scalarAt(range.start), _scalarAt(range.end));
  }

  /// 把标量半开区间换成 UTF-16 半开区间；越界时抛出。
  Utf16Range toUtf16(ScalarRange range) {
    _check(range.start, range.end, scalarLength);
    return Utf16Range(_boundaries[range.start], _boundaries[range.end]);
  }

  /// Requires a nonempty selection and its exact, unnormalized quote.
  ///
  /// 要求选区非空且与 [quote] 完全逐码元一致，用于检测过期或歧义选区。
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

  // 在已排序边界上二分；找不到说明偏移落在代理对内部。
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

  // 统一校验半开区间边界。
  static void _check(int start, int end, int length) {
    if (start < 0 || end < start || end > length) {
      throw const ContractFailure(ContractFailureCode.invalidRange);
    }
  }

  // 单次扫描记录每个标量的 UTF-16 边界，并拒绝孤立代理项。
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
///
/// Rust 侧 BLAKE3 的十六进制 wire 值；Dart 只校验格式，不计算也不验证哈希。
final class BodyFingerprint {
  /// 从 Rust 返回值构造；只校验编码格式，不代表正文已被验证。
  BodyFingerprint.fromRust(this.value) {
    if (value.length != 64 || !RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
      throw const ContractFailure(ContractFailureCode.invalidFingerprint);
    }
  }

  /// 64 字符小写十六进制 BLAKE3 值。
  final String value;
  @override
  bool operator ==(Object other) =>
      other is BodyFingerprint && value == other.value;
  @override
  int get hashCode => value.hashCode;
}

/// A frozen base body allows restoration only after exact full-body equality.
///
/// 冻结的基准正文、选区、原文引用与 Rust 指纹；只能按精确正文与区间恢复。
final class TargetSnapshot {
  /// 构造时立即校验基准正文合法且 [quote] 与 [range] 一致，非法时抛出。
  TargetSnapshot({
    required this.baseBody,
    required this.range,
    required this.quote,
    required this.fingerprint,
  }) {
    TextCoordinates(baseBody).validateSelection(range, quote);
  }

  /// 冻结时的完整基准正文。
  final String baseBody;

  /// 引用在基准正文中的半开区间。
  final Utf16Range range;

  /// 引用原文，必须与区间逐码元一致。
  final String quote;

  /// Rust 计算并持有的正文指纹。
  final BodyFingerprint fingerprint;

  /// Revalidates the quote at a transaction-mapped range; never searches text.
  ///
  /// 在当前正文的映射区间上重新校验引用；不做文本搜索。
  ScalarRange revalidate(String currentBody, Utf16Range mappedRange) =>
      TextCoordinates(currentBody).validateSelection(mappedRange, quote);

  /// Restores known offsets only when undo restores the entire frozen body.
  ///
  /// 仅当 [currentBody] 与冻结正文完全一致时返回原区间，否则抛出 staleBody。
  Utf16Range restore(String currentBody) {
    if (currentBody != baseBody) {
      throw const ContractFailure(ContractFailureCode.staleBody);
    }
    TextCoordinates(currentBody).validateSelection(range, quote);
    return range;
  }
}
