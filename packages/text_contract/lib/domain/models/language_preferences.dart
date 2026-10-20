// 语言偏好合同：解析语言标签，并表达 UI、作品、章节与输出语言的独立选择。
//
// 本文件是纯 Dart 值对象，不做 IO、不依赖 Flutter，也不翻译或归一化作者正文。
// 关键不变量：UI locale 只支持 en 与 zh-Hans 并显式回退；作品语言与正文内容互不影响。

/// Language metadata never transforms author bodies or generation materials.
///
/// 中文契约：语言元数据只描述选择，不转换作者正文或生成材料。
library;

import '../editing/text_coordinates.dart';

/// Canonical language/script/region tags; variants/extensions are unsupported.
///
/// 解析并规范化 language-script-region 三元组。
///
/// 只接受 2-8 字母语言、4 字母脚本与 2 字母或 3 数字区域；解析失败抛出
/// [ContractFailureCode.invalidLocale]。canonical 输出小写语言、首字母大写脚本与大写区域。
final class LocaleTag {
  LocaleTag._(this.language, this.script, this.region);

  /// 解析标签；非法组成部分或多余段直接抛出 [ContractFailure]。
  factory LocaleTag.parse(String value) {
    final parts = value.split('-');
    if (parts.isEmpty || !RegExp(r'^[A-Za-z]{2,8}$').hasMatch(parts.first)) {
      throw const ContractFailure(ContractFailureCode.invalidLocale);
    }
    var index = 1;
    String? script;
    String? region;
    if (index < parts.length &&
        RegExp(r'^[A-Za-z]{4}$').hasMatch(parts[index])) {
      final raw = parts[index++].toLowerCase();
      script = raw[0].toUpperCase() + raw.substring(1);
    }
    if (index < parts.length &&
        RegExp(r'^([A-Za-z]{2}|[0-9]{3})$').hasMatch(parts[index])) {
      region = parts[index++].toUpperCase();
    }
    if (index != parts.length) {
      throw const ContractFailure(ContractFailureCode.invalidLocale);
    }
    return LocaleTag._(parts.first.toLowerCase(), script, region);
  }

  /// 小写语言子标签。
  final String language;

  /// 可选脚本子标签，规范化为首字母大写。
  final String? script;

  /// 可选区域子标签，规范化为大写。
  final String? region;

  /// 规范化标签，形如 language[-Script][-REGION]。
  String get canonical => [language, ?script, ?region].join('-');
  @override
  /// 按 canonical 形式比较，等价标签视为相等。
  bool operator ==(Object other) =>
      other is LocaleTag && canonical == other.canonical;
  @override
  int get hashCode => canonical.hashCode;
}

/// Explicit evidence that a request used an author-selected fallback.
/// 一次 UI locale 解析的结果：请求值、实际解析值与是否使用了显式回退。
final class UiLocaleResolution {
  /// 记录请求、解析结果与回退标记；resolved 始终是已发布的 en 或 zh-Hans。
  const UiLocaleResolution(this.requested, this.resolved, this.usedFallback);

  /// 调用方请求的原始 locale。
  final LocaleTag requested;

  /// 实际使用的已发布 locale。
  final LocaleTag resolved;

  /// 为 true 表示请求值不是已发布 locale，已回退到调用方指定的 fallback。
  final bool usedFallback;
}

/// Resolves planned English and Simplified Chinese with a mandatory fallback.
///
/// 把请求 locale 解析到已发布的 en 或 zh-Hans。
///
/// 规则：en 且无脚本直接接受；zh 且脚本为 Hans 或（无脚本且区域为 CN/SG）解析为 zh-Hans；
/// 其余一律回退到 [fallback] 并标记 usedFallback。fallback 不是已发布 locale 时抛出
/// [ContractFailureCode.unsupportedFallback]。
UiLocaleResolution resolveUiLocale(
  LocaleTag requested, {
  required LocaleTag fallback,
}) {
  if (fallback.canonical != 'en' && fallback.canonical != 'zh-Hans') {
    throw const ContractFailure(ContractFailureCode.unsupportedFallback);
  }
  if (requested.language == 'en' && requested.script == null) {
    return UiLocaleResolution(requested, LocaleTag.parse('en'), false);
  }
  final simplified =
      requested.language == 'zh' &&
      (requested.script == 'Hans' ||
          (requested.script == null &&
              (requested.region == 'CN' || requested.region == 'SG')));
  if (simplified) {
    return UiLocaleResolution(requested, LocaleTag.parse('zh-Hans'), false);
  }
  return UiLocaleResolution(requested, fallback, true);
}

/// Work/document language can be unknown or mixed independently of UI locale.
///
/// 作品或文档语言的取值：已标注、混合或未确定，与 UI locale 相互独立。
sealed class WritingLanguage {
  const WritingLanguage();
}

/// 已明确标注的语言标签。
final class TaggedLanguage extends WritingLanguage {
  /// 绑定作品语言标签。
  const TaggedLanguage(this.tag);

  /// 作品语言的规范标签。
  final LocaleTag tag;
}

/// 作品包含多种语言，无法用单一标签表示。
final class MixedLanguage extends WritingLanguage {
  const MixedLanguage();
}

/// 尚未确定作品语言；不伪称任何具体语言。
final class UndeterminedLanguage extends WritingLanguage {
  const UndeterminedLanguage();
}

/// Null UI follows system; null document follows work; null output is undecided.
///
/// UI、作品、章节与输出四种语言选择的快照。
///
/// 空值语义：uiOverride 为空跟系统；documentOverride 为空跟作品；outputOverride 为空
/// 表示尚未决定。该类型只描述偏好，不改变正文或语言检测结果。
final class LanguagePreferences {
  /// 创建不可变偏好；work 必填，其余覆盖项为空时按类文档中的语义回落。
  const LanguagePreferences({
    this.uiOverride,
    required this.work,
    this.documentOverride,
    this.outputOverride,
  });

  /// UI locale 覆盖；为空时跟随系统。
  final LocaleTag? uiOverride;

  /// 作品整体语言。
  final WritingLanguage work;

  /// 单篇文档语言覆盖；为空时跟随作品。
  final WritingLanguage? documentOverride;

  /// 输出语言覆盖；为空表示尚未决定。
  final LocaleTag? outputOverride;

  /// 当前文档实际生效的语言：文档覆盖优先，否则跟随作品。
  WritingLanguage get document => documentOverride ?? work;
}
