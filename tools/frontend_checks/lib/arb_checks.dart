// ARB 元数据与占位符合同；只返回文件名、键及规则，不输出产品正文。
import 'dart:convert';
import 'dart:io';
import 'icu_fields.dart';

/// 收集全部 ARB 合同错误；不因首个元数据缺口跳过其他 locale。
Map<String, Object> checkArbDirectory(String directory) {
  final errors = <String>[];
  final files =
      Directory(directory)
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.arb'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final template = _read(File('$directory/app_en.arb'), errors);
  final keys = _keys(template);
  if (keys.isEmpty) errors.add('app_en.arb: template has no messages');
  final templateFields = <String, Set<String>>{};
  for (final key in keys) {
    final metadata = _metadata(template, key);
    if (metadata['description'] is! String ||
        (metadata['description']! as String).trim().isEmpty) {
      errors.add('app_en.arb/$key: missing description');
    }
    final fields = _fields(template[key], key, 'app_en.arb', errors);
    templateFields[key] = fields;
    _checkMetadata(metadata, fields, key, 'app_en.arb', errors, required: true);
  }
  for (final file in files) {
    final name = file.uri.pathSegments.last;
    final locale = _read(file, errors);
    if (!_same(keys, _keys(locale))) errors.add('$name: message keys differ');
    for (final key in keys) {
      final fields = _fields(locale[key], key, name, errors);
      if (!_same(fields, templateFields[key]!)) {
        errors.add('$name/$key: message placeholders differ');
      }
      final metadata = _metadata(locale, key);
      _checkMetadata(
        metadata,
        fields,
        key,
        name,
        errors,
        required: name == 'app_en.arb',
      );
      _checkTypes(_metadata(template, key), metadata, key, name, errors);
    }
  }
  return {
    'status': errors.isEmpty ? 'PASS' : 'FAIL',
    'keys': keys.length,
    'arbFiles': files.length,
    'errors': errors,
  };
}

Map<String, Object?> _read(File file, List<String> errors) {
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is Map<String, Object?>) return decoded;
    errors.add('${file.uri.pathSegments.last}: ARB root must be an object');
  } on FormatException {
    errors.add('${file.uri.pathSegments.last}: invalid JSON');
  } on FileSystemException {
    errors.add('${file.uri.pathSegments.last}: unavailable file');
  }
  return {};
}

Set<String> _keys(Map<String, Object?> arb) =>
    arb.keys.where((key) => !key.startsWith('@')).toSet();

Map<String, Object?> _metadata(Map<String, Object?> arb, String key) =>
    arb['@$key'] is Map ? (arb['@$key']! as Map).cast<String, Object?>() : {};

Set<String> _fields(
  Object? text,
  String key,
  String file,
  List<String> errors,
) {
  if (text is! String) {
    errors.add('$file/$key: message must be a string');
    return {};
  }
  try {
    return messageFields(text);
  } on FormatException catch (error) {
    errors.add('$file/$key: ${error.message}');
    return {};
  }
}

Map<String, Object?> _placeholders(Map<String, Object?> metadata) =>
    metadata['placeholders'] is Map
    ? (metadata['placeholders']! as Map).cast<String, Object?>()
    : {};

void _checkMetadata(
  Map<String, Object?> metadata,
  Set<String> fields,
  String key,
  String file,
  List<String> errors, {
  required bool required,
}) {
  final placeholders = _placeholders(metadata);
  if (!required && !metadata.containsKey('placeholders')) return;
  if (!_same(fields, placeholders.keys.toSet())) {
    errors.add('$file/$key: placeholder declarations differ');
  }
  for (final field in fields) {
    final declaration = placeholders[field];
    if (declaration is! Map ||
        declaration['type'] is! String ||
        (declaration['type'] as String).trim().isEmpty) {
      errors.add('$file/$key/$field: missing placeholder type');
    }
  }
}

void _checkTypes(
  Map<String, Object?> template,
  Map<String, Object?> locale,
  String key,
  String file,
  List<String> errors,
) {
  final expected = _placeholders(template);
  for (final entry in _placeholders(locale).entries) {
    final metadata = entry.value;
    final templateMetadata = expected[entry.key];
    if (metadata is Map &&
        templateMetadata is Map &&
        metadata['type'] != templateMetadata['type']) {
      errors.add('$file/$key/${entry.key}: placeholder type differs');
    }
  }
}

bool _same(Set<String> first, Set<String> second) =>
    first.length == second.length && first.containsAll(second);
