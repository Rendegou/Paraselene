// 前端静态门禁入口；仅读取明确自有的 Dart 源文件。
import 'dart:convert';
import 'dart:io';
import 'package:frontend_checks/metrics.dart';
import 'package:path/path.dart' as p;

void main(List<String> arguments) {
  final root = p.normalize(p.absolute(_option(arguments, '--root') ?? '../..'));
  final scope = _option(arguments, '--scope');
  final paths = [
    p.join(root, 'apps', 'desktop', 'lib'),
    p.join(root, 'packages', 'text_contract', 'lib'),
  ];
  final findings = <Finding>[];
  var files = 0;
  for (final directory in paths) {
    for (final file in Directory(
      directory,
    ).listSync(recursive: true, followLinks: false).whereType<File>()) {
      final relative = p.relative(file.path, from: root).replaceAll('\\', '/');
      if (!_included(relative, scope)) continue;
      files++;
      findings.addAll(
        inspectSource(
          relative,
          file.readAsStringSync(),
          theme: relative.startsWith('apps/desktop/lib/theme/'),
        ),
      );
    }
  }
  final output = {
    'status': files == 0
        ? 'ERROR'
        : findings.isEmpty
        ? 'PASS'
        : 'FAIL',
    'files': files,
    'violations': findings.length,
    'findings': findings.map((finding) => finding.toJson()).toList(),
  };
  final json = const JsonEncoder.withIndent('  ').convert(output);
  final destination = _option(arguments, '--output');
  if (destination != null) File(destination).writeAsStringSync('$json\n');
  stdout.writeln(json);
  exitCode = files == 0
      ? 2
      : findings.isEmpty
      ? 0
      : 1;
}

String? _option(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  if (index < 0) return null;
  if (index + 1 >= arguments.length)
    throw ArgumentError('Missing value: $name');
  return arguments[index + 1];
}

bool _included(String path, String? scope) =>
    path.endsWith('.dart') &&
    !path.startsWith('apps/desktop/lib/native/generated/') &&
    !path.startsWith('apps/desktop/lib/l10n/generated/') &&
    (scope == null || path.startsWith(scope.replaceAll('\\', '/')));
