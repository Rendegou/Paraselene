import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';
import 'package:text_contract/text_contract.dart';

Matcher failure(ContractFailureCode code) =>
    throwsA(isA<ContractFailure>().having((error) => error.code, 'code', code));

Object? readFixture(String path) {
  final text = File(path).readAsStringSync();
  return jsonDecode(text.startsWith('\ufeff') ? text.substring(1) : text);
}

void main() {
  test('normalization, CRLF and bidi differences remain stale', () {
    for (final pair in [
      ['e\u0301', 'é'],
      ['a\r\nb', 'a\nb'],
      ['\u2067א\u2069', 'א'],
    ]) {
      final body = pair[0];
      final coordinates = TextCoordinates(body);
      expect(
        () =>
            coordinates.validateSelection(Utf16Range(0, body.length), pair[1]),
        failure(ContractFailureCode.staleQuote),
      );
      expect(coordinates.body, body);
    }
  });

  test('seeded independent scalar-prefix oracle and mixed roundtrips', () {
    final random = Random(20261015);
    const alphabet = [
      0x61,
      0x4e2d,
      0x1f469,
      0x200d,
      0x1f680,
      0x301,
      0x5d0,
      0x627,
      0xd,
      0xa,
      0x2067,
      0x2069,
    ];
    for (var trial = 0; trial < 200; trial++) {
      final scalars = List.generate(
        1 + random.nextInt(80),
        (_) => alphabet[random.nextInt(alphabet.length)],
      );
      final body = String.fromCharCodes(scalars);
      final coordinates = TextCoordinates(body);
      for (var start = 0; start <= scalars.length; start++) {
        final end = start + random.nextInt(scalars.length - start + 1);
        final expected = Utf16Range(
          String.fromCharCodes(scalars.take(start)).length,
          String.fromCharCodes(scalars.take(end)).length,
        );
        expect(coordinates.toUtf16(ScalarRange(start, end)), expected);
        expect(coordinates.toScalars(expected), ScalarRange(start, end));
        expect(
          body.substring(expected.start, expected.end),
          String.fromCharCodes(scalars.sublist(start, end)),
        );
      }
    }
  });

  test('empty/full boundaries and 200k scalar body', () {
    expect(
      TextCoordinates('').toScalars(const Utf16Range(0, 0)),
      const ScalarRange(0, 0),
    );
    final body = List.filled(100000, '中😀').join();
    final coordinates = TextCoordinates(body);
    expect(coordinates.scalarLength, 200000);
    expect(
      coordinates.toUtf16(const ScalarRange(0, 200000)),
      const Utf16Range(0, 300000),
    );
    expect(
      coordinates.toScalars(const Utf16Range(300000, 300000)),
      const ScalarRange(200000, 200000),
    );
  });

  test('malformed UTF16 and unsafe ranges are rejected', () {
    for (final units in [
      [0xd800],
      [0xdc00],
      [0xd800, 0x61],
    ]) {
      expect(
        () => TextCoordinates(String.fromCharCodes(units)),
        failure(ContractFailureCode.malformedUtf16),
      );
    }
    final coordinates = TextCoordinates('a😀b');
    expect(
      () => coordinates.toScalars(const Utf16Range(2, 3)),
      failure(ContractFailureCode.splitSurrogate),
    );
    for (final range in [
      const Utf16Range(-1, 0),
      const Utf16Range(3, 1),
      const Utf16Range(0, 5),
    ]) {
      expect(
        () => coordinates.toScalars(range),
        failure(ContractFailureCode.invalidRange),
      );
    }
    expect(
      () => coordinates.toUtf16(const ScalarRange(0, 4)),
      failure(ContractFailureCode.invalidRange),
    );
    expect(
      () => coordinates.validateSelection(const Utf16Range(1, 1), ''),
      failure(ContractFailureCode.emptySelection),
    );
    expect(
      () => coordinates.validateSelection(const Utf16Range(1, 3), 'x'),
      failure(ContractFailureCode.staleQuote),
    );
  });

  test('frozen snapshot requires exact body restoration, not quote search', () {
    final fingerprint = BodyFingerprint.fromRust(List.filled(64, 'a').join());
    final snapshot = TargetSnapshot(
      baseBody: 'x😀\r\ne\u0301\u2067א\u2069',
      range: const Utf16Range(1, 3),
      quote: '😀',
      fingerprint: fingerprint,
    );
    expect(snapshot.restore(snapshot.baseBody), snapshot.range);
    expect(
      snapshot.revalidate('xx😀', const Utf16Range(2, 4)),
      const ScalarRange(2, 3),
    );
    expect(
      () => snapshot.restore('xx😀'),
      failure(ContractFailureCode.staleBody),
    );
    expect(
      () => snapshot.revalidate('x!😀', snapshot.range),
      failure(ContractFailureCode.splitSurrogate),
    );
    expect(snapshot.fingerprint.value, List.filled(64, 'a').join());
    for (final invalid in [
      '',
      List.filled(64, 'A').join(),
      List.filled(63, 'a').join(),
      '${List.filled(64, 'a').join()}\n',
    ]) {
      expect(
        () => BodyFingerprint.fromRust(invalid),
        failure(ContractFailureCode.invalidFingerprint),
      );
    }
  });

  test('locale case/script/region and explicit traditional fallback', () {
    expect(LocaleTag.parse('ZH-hANT-tw').canonical, 'zh-Hant-TW');
    expect(LocaleTag.parse('en-us').canonical, 'en-US');
    expect(LocaleTag.parse('es-419').canonical, 'es-419');
    for (final invalid in [
      '',
      'en_US',
      '-en',
      'en-',
      'en-US-x',
      '12',
      'zh-Hans-CN-extra',
      ' en',
      'en--US',
    ]) {
      expect(
        () => LocaleTag.parse(invalid),
        failure(ContractFailureCode.invalidLocale),
      );
    }
    final fallback = LocaleTag.parse('en');
    for (final request in [
      'zh-Hant',
      'zh-TW',
      'zh-HK',
      'zh',
      'ar',
      'en-Latn',
    ]) {
      final result = resolveUiLocale(
        LocaleTag.parse(request),
        fallback: fallback,
      );
      expect(result.resolved.canonical, 'en');
      expect(result.usedFallback, isTrue);
    }
    for (final request in ['zh-Hans', 'zh-CN', 'zh-SG']) {
      final result = resolveUiLocale(
        LocaleTag.parse(request),
        fallback: fallback,
      );
      expect(result.resolved.canonical, 'zh-Hans');
      expect(result.usedFallback, isFalse);
    }
    expect(
      () => resolveUiLocale(fallback, fallback: LocaleTag.parse('ar')),
      failure(ContractFailureCode.unsupportedFallback),
    );
  });

  test('UI/work/document/output are independent metadata', () {
    final preferences = LanguagePreferences(
      uiOverride: LocaleTag.parse('en'),
      work: TaggedLanguage(LocaleTag.parse('zh-Hant')),
      documentOverride: TaggedLanguage(LocaleTag.parse('ar')),
      outputOverride: LocaleTag.parse('ja'),
    );
    expect(preferences.uiOverride!.canonical, 'en');
    expect((preferences.work as TaggedLanguage).tag.canonical, 'zh-Hant');
    expect((preferences.document as TaggedLanguage).tag.canonical, 'ar');
    expect(preferences.outputOverride!.canonical, 'ja');
    const unknown = LanguagePreferences(work: UndeterminedLanguage());
    expect(unknown.document, same(unknown.work));
    expect(unknown.outputOverride, isNull);
  });

  test('shared Rust vectors preserve exact body and quote', () {
    final envelope =
        readFixture('test/fixtures/test_vectors.json') as Map<String, Object?>;
    expect(envelope['schemaVersion'], 1);
    for (final raw in envelope['vectors']! as List<Object?>) {
      final vector = raw! as Map<String, Object?>;
      final coordinates = TextCoordinates(vector['body']! as String);
      final range = Utf16Range(
        vector['fromUtf16']! as int,
        vector['toUtf16']! as int,
      );
      final scalars = ScalarRange(
        vector['startScalar']! as int,
        vector['endScalar']! as int,
      );
      expect(
        coordinates.validateSelection(range, vector['quote']! as String),
        scalars,
      );
      expect(coordinates.toUtf16(scalars), range);
    }
  });

  test('Rust fingerprint wire values remain unchanged and lengths agree', () {
    final envelope =
        readFixture('test/fixtures/test_vectors.json') as Map<String, Object?>;
    final vectors = <String, Map<String, Object?>>{};
    for (final raw in envelope['vectors']! as List<Object?>) {
      final vector = raw! as Map<String, Object?>;
      vectors[vector['id']! as String] = vector;
    }
    final fingerprints =
        readFixture('test/fixtures/rust_fingerprints.json') as List<Object?>;
    final seen = <String>{};
    for (final raw in fingerprints) {
      final rust = raw! as Map<String, Object?>;
      final id = rust['id']! as String;
      expect(seen.add(id), isTrue);
      expect(vectors.containsKey(id), isTrue);
      final body = vectors[id]!['body']! as String;
      expect(body.length, rust['utf16Length']);
      expect(TextCoordinates(body).scalarLength, rust['scalarLength']);
      for (final field in ['bodyHash', 'quoteHash']) {
        final wire = rust[field]! as String;
        expect(BodyFingerprint.fromRust(wire).value, wire);
      }
    }
    expect(seen, vectors.keys.toSet());
  });
}
