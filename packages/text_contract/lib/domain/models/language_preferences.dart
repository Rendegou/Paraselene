/// Language metadata never transforms author bodies or generation materials.
library;

import '../editing/text_coordinates.dart';

/// Canonical language/script/region tags; variants/extensions are unsupported.
final class LocaleTag {
  LocaleTag._(this.language, this.script, this.region);
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
  final String language;
  final String? script;
  final String? region;
  String get canonical => [language, ?script, ?region].join('-');
  @override
  bool operator ==(Object other) =>
      other is LocaleTag && canonical == other.canonical;
  @override
  int get hashCode => canonical.hashCode;
}

/// Explicit evidence that a request used an author-selected fallback.
final class UiLocaleResolution {
  const UiLocaleResolution(this.requested, this.resolved, this.usedFallback);
  final LocaleTag requested;
  final LocaleTag resolved;
  final bool usedFallback;
}

/// Resolves planned English and Simplified Chinese with a mandatory fallback.
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
sealed class WritingLanguage {
  const WritingLanguage();
}

final class TaggedLanguage extends WritingLanguage {
  const TaggedLanguage(this.tag);
  final LocaleTag tag;
}

final class MixedLanguage extends WritingLanguage {
  const MixedLanguage();
}

final class UndeterminedLanguage extends WritingLanguage {
  const UndeterminedLanguage();
}

/// Null UI follows system; null document follows work; null output is undecided.
final class LanguagePreferences {
  const LanguagePreferences({
    this.uiOverride,
    required this.work,
    this.documentOverride,
    this.outputOverride,
  });
  final LocaleTag? uiOverride;
  final WritingLanguage work;
  final WritingLanguage? documentOverride;
  final LocaleTag? outputOverride;
  WritingLanguage get document => documentOverride ?? work;
}
