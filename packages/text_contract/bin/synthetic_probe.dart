import 'dart:convert';
import 'dart:io';
import 'package:text_contract/text_contract.dart';

void main() {
  const bodies = [
    'a😀b',
    '中👩‍🚀e\u0301\r\n\u2067العربية\u2069',
    'é e\u0301\r\nא',
    '😀',
  ];
  final vectors = <Map<String, Object>>[];
  for (var index = 0; index < bodies.length; index++) {
    final body = bodies[index];
    final coordinates = TextCoordinates(body);
    final scalars = ScalarRange(0, coordinates.scalarLength);
    final range = coordinates.toUtf16(scalars);
    vectors.add({
      'id': 'mixed-$index',
      'body': body,
      'fromUtf16': range.start,
      'toUtf16': range.end,
      'startScalar': scalars.start,
      'endScalar': scalars.end,
      'quote': body,
    });
  }
  vectors.add({
    'id': 'emoji-inner',
    'body': 'a😀b',
    'fromUtf16': 1,
    'toUtf16': 3,
    'startScalar': 1,
    'endScalar': 2,
    'quote': '😀',
  });
  final output = const JsonEncoder.withIndent(
    '  ',
  ).convert({'schemaVersion': 1, 'vectors': vectors});
  if (Platform.environment['WRITE_VECTORS'] == '1') {
    File('test/fixtures/test_vectors.json').writeAsStringSync('$output\n');
  }
  stdout.writeln(output);
}
