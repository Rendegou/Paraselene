// 门禁负向样本：验证真正的 AST 边界，避免注释、字符串、回调或命名绕过。
import 'package:frontend_checks/metrics.dart';
import 'package:test/test.dart';

void main() {
  test('comments and blank lines do not inflate a short function', () {
    final comments = List.filled(
      500,
      '// Color(1); Widget hidden() => x;',
    ).join('\n');
    expect(
      inspectSource('lib/short.dart', '$comments\nvoid work() {\n}\n'),
      isEmpty,
    );
  });

  test('long ordinary, method and constructor bodies are rejected', () {
    final statements = List.generate(61, (i) => 'print($i);').join('\n');
    for (final source in [
      'void work() {\n$statements\n}',
      'class A { void work() {\n$statements\n} }',
      'class A { A() {\n$statements\n} }',
    ]) {
      expect(
        inspectSource(
          'lib/long.dart',
          source,
        ).where((finding) => finding.rule == 'function-lines'),
        isNotEmpty,
      );
    }
  });

  test('anonymous callbacks count independently and inside the owner', () {
    final statements = List.generate(61, (i) => 'print($i);').join('\n');
    final report = inspectSource(
      'lib/callback.dart',
      'void work() {\nlisten(() {\n$statements\n});\n}',
    );
    expect(
      report.where((finding) => finding.rule == 'function-lines').length,
      2,
    );
  });

  test('multiline literal content cannot hide production file length', () {
    final data = List.filled(401, 'literal data').join('\n');
    final report = inspectSource(
      'lib/data.dart',
      "const payload = '''\n$data\n''';",
    );
    expect(report.single.rule, 'file-lines');
  });

  test(
    'module size includes constructor initializers and declaration tables',
    () {
      final fields = List.generate(
        401,
        (i) => 'const value$i = $i;',
      ).join('\n');
      expect(inspectSource('lib/data.dart', fields).single.rule, 'file-lines');
    },
  );

  test('all named Widget helpers are rejected, build override is allowed', () {
    final report = inspectSource('lib/view.dart', '''
Widget createHeader() => Header();
class View {
  Widget? header() => null;
  @override
  Widget build(BuildContext context) => Header();
}
''');
    expect(
      report
          .where((finding) => finding.rule == 'widget-builder')
          .map((finding) => finding.symbol),
      ['createHeader', 'header'],
    );
  });

  test('raw theme constructors include implicit and named creation', () {
    for (final expression in [
      'const Color(1)',
      'Color(1)',
      'Color.fromARGB(255, 0, 0, 0)',
      'const m.TextStyle()',
      'm.TextStyle()',
      'TextStyle()',
      'MaterialColor(1, {})',
    ]) {
      final report = inspectSource(
        'lib/view.dart',
        'final value = $expression;',
      );
      expect(
        report.any((finding) => finding.rule == 'theme-constructor'),
        isTrue,
        reason: expression,
      );
    }
  });

  test('raw Colors and font families are rejected outside the theme', () {
    final report = inspectSource('lib/view.dart', '''
final color = Colors.white;
final aliasColor = material.Colors.black;
final text = ExistingStyle(fontFamily: 'Raw family');
''');
    expect(
      report.map((finding) => finding.rule),
      containsAll(['theme-color', 'theme-font']),
    );
    expect(report.where((finding) => finding.rule == 'theme-color').length, 2);
  });

  test('theme declarations and business role references are allowed', () {
    expect(
      inspectSource(
        'lib/theme/palette.dart',
        "final value = const TextStyle(color: Colors.white, fontFamily: 'Local');",
        theme: true,
      ),
      isEmpty,
    );
    expect(
      inspectSource(
        'lib/view.dart',
        'final style = WorkbenchTokens.ui().copyWith(color: WorkbenchTokens.ink);',
      ),
      isEmpty,
    );
  });

  test(
    'empty error handlers and ignore calls cannot conceal a failed Future',
    () {
      final report = inspectSource('lib/error.dart', '''
void work() {
  future.catchError((error) {});
  future.then(done, onError: (error, stack) { /* intentionally blank */ });
  future.catchError((error) => null);
  future.ignore();
}
''');
      expect(
        report.where((finding) => finding.rule == 'empty-error-handler').length,
        3,
      );
      expect(
        report.where((finding) => finding.rule == 'ignored-future').length,
        1,
      );
    },
  );

  test('an observed error result is allowed', () {
    expect(
      inspectSource('lib/error.dart', '''
void work() {
  future.then(done, onError: (error, stack) { result.record(error, stack); });
}
'''),
      isEmpty,
    );
  });

  test('popup menus must use the native state-styled button branch', () {
    for (final expression in [
      'PopupMenuButton<int>(child: label)',
      'm.PopupMenuButton<String>(child: label, style: shared)',
      'new PopupMenuButton<int>(child: label)',
      'new m.PopupMenuButton<String>(child: label)',
      'new PopupMenuButton<m.Locale>(child: label)',
      'new m.PopupMenuButton<ui.Locale>(child: label)',
    ]) {
      expect(
        inspectSource(
          'lib/menu.dart',
          'final menu = $expression;',
        ).where((finding) => finding.rule == 'menu-state-style').length,
        1,
        reason: expression,
      );
    }
    expect(
      inspectSource('lib/menu.dart', '''
final menu = PopupMenuButton<int>(icon: label, style: shared);
final defaultMenu = PopupMenuButton<String>();
final noChild = PopupMenuButton<int>(child: null);
'''),
      isEmpty,
    );
  });

  test('minimum text size covers direct styles, copyWith and ui roles', () {
    final report = inspectSource('lib/theme/text.dart', '''
final first = TextStyle(fontSize: 11.5);
final second = base.copyWith(fontSize: (10));
final third = WorkbenchTokens.ui(size: -1);
final icon = Icon(Icons.add, size: 8);
final allowed = WorkbenchTokens.ui(size: 12);
''', theme: true);
    expect(
      report
          .where((finding) => finding.rule == 'minimum-font-size')
          .map((finding) => finding.actual),
      [11.5, 10, -1],
    );
  });

  test(
    'invalid Dart is a gate failure rather than an empty successful scan',
    () {
      expect(
        inspectSource(
          'lib/broken.dart',
          'void work( {',
        ).any((finding) => finding.rule == 'syntax'),
        isTrue,
      );
    },
  );
}
