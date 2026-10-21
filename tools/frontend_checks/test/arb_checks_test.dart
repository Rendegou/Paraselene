// ARB 门禁以合成临时文件验证，失败消息不得带产品正文。
import 'dart:convert';
import 'dart:io';
import 'package:frontend_checks/arb_checks.dart';
import 'package:frontend_checks/icu_fields.dart';
import 'package:test/test.dart';

void main() {
  test('nested ICU branches preserve only actual placeholders', () {
    expect(
      messageFields(
        '{count, plural, =0{Nobody} one{{name}} '
        'other{{gender, select, male{He has {count}} other{They have {count}}}}}',
      ),
      {'count', 'name', 'gender'},
    );
  });

  test('ICU escaping ignores literal braces and doubled apostrophes', () {
    expect(messageFields("You''ve shown '{literal}' and {name}"), {'name'});
    expect(messageFields("'literal {notAParameter}' {name}"), {'name'});
  });

  test('malformed ICU and missing other branches fail', () {
    for (final message in ['{name', 'unmatched }', '{n, plural, one{item}}']) {
      expect(() => messageFields(message), throwsFormatException);
    }
  });

  group('directory parity', () {
    late Directory temporary;
    setUp(
      () => temporary = Directory.systemTemp.createTempSync('arb-contract-'),
    );
    tearDown(() {
      final parent = Directory.systemTemp.absolute.path;
      expect(
        temporary.absolute.path,
        startsWith('$parent${Platform.pathSeparator}'),
      );
      expect(
        temporary.uri.pathSegments.lastWhere((part) => part.isNotEmpty),
        startsWith('arb-contract-'),
      );
      temporary.deleteSync(recursive: true);
    });

    void write(String file, Map<String, Object?> data) =>
        File('${temporary.path}/$file').writeAsStringSync(jsonEncode(data));

    Map<String, Object?> template() => {
      '@@locale': 'en',
      'greeting': 'Hello {name}',
      '@greeting': {
        'description': 'Greeting shown to a named user.',
        'placeholders': {
          'name': {'type': 'String'},
        },
      },
    };

    test('valid descriptions, keys and typed placeholders pass', () {
      write('app_en.arb', template());
      write('app_zh.arb', {'greeting': '你好 {name}'});
      expect(checkArbDirectory(temporary.path)['status'], 'PASS');
    });

    test(
      'multiple independent metadata and locale failures are all reported',
      () {
        write('app_en.arb', {'greeting': 'Hello {name}'});
        write('app_zh.arb', {'different': 'Not a translation'});
        final report = checkArbDirectory(temporary.path);
        expect(report['status'], 'FAIL');
        final errors = report['errors']! as List<String>;
        expect(errors.length, greaterThanOrEqualTo(4));
        expect(errors.join(' '), isNot(contains('Hello')));
      },
    );

    test('locale metadata cannot change a placeholder type', () {
      write('app_en.arb', template());
      write('app_zh.arb', {
        'greeting': '你好 {name}',
        '@greeting': {
          'placeholders': {
            'name': {'type': 'int'},
          },
        },
      });
      expect(
        (checkArbDirectory(temporary.path)['errors']! as List<String>).any(
          (error) => error.contains('placeholder type differs'),
        ),
        isTrue,
      );
    });

    test('missing template is never treated as empty successful data', () {
      write('app_zh.arb', {'greeting': '合成消息'});
      expect(checkArbDirectory(temporary.path)['status'], 'FAIL');
    });

    test('an empty template or non-object JSON cannot pass', () {
      write('app_en.arb', {});
      expect(checkArbDirectory(temporary.path)['status'], 'FAIL');
      File('${temporary.path}/app_en.arb').writeAsStringSync('[]');
      expect(checkArbDirectory(temporary.path)['status'], 'FAIL');
    });
  });
}
