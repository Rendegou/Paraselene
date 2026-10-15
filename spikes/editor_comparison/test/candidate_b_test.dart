import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:paraselene_editor_spike/candidate_b.dart';
import 'package:paraselene_editor_spike/plain_projection.dart';

void main() {
  for (final text in [
    '',
    'no final newline',
    'a\n',
    'a\r\nb\n',
    '🙂👩‍💻e\u0301 العربية\r\n尾',
  ]) {
    test('raw roundtrip ${text.codeUnits}', () {
      final projection = PlainProjection(text);
      expect(projection.read(projection.document(discussion: false)), text);
      expect(projection.read(projection.document(discussion: true)), text);
    });
  }

  test('UTF16 scalar mapping rejects surrogate splits', () {
    expect(PlainProjection.scalarOffset('a🙂b', 3), 2);
    expect(() => PlainProjection.scalarOffset('a🙂b', 2), throwsArgumentError);
  });

  test('intact embed maps selection to exact raw UTF16 coordinates', () {
    final projection = PlainProjection('a\r\n🙂b');
    final document = projection.document(discussion: true);
    expect(
      projection.selection(
        document,
        const TextSelection(baseOffset: 5, extentOffset: 7),
      ),
      const TextSelection(baseOffset: 3, extentOffset: 5),
    );
  });

  test('FAIL evidence: deleting transient embed leaves an author newline', () {
    final projection = PlainProjection('first\nsecond');
    final controller = QuillController(
      document: projection.document(discussion: true),
      selection: const TextSelection.collapsed(offset: 0),
    );
    addTearDown(controller.dispose);
    controller.replaceText(6, 1, '', const TextSelection.collapsed(offset: 6));
    expect(projection.read(controller.document), 'first\n\nsecond');
    controller.undo();
    expect(projection.read(controller.document), 'first\nsecond');
    expect(
      controller.document.toDelta().toJson().toString(),
      contains(PlainProjection.discussionType),
    );
  });

  test(
    'FAIL evidence: native plain copy contains synthetic block boundary',
    () {
      final projection = PlainProjection('first\nsecond');
      final document = projection.document(discussion: true);
      expect(document.toPlainText(), 'first\n\uFFFC\nsecond\n');
      // Even a blank embed plain-text override retains its block newline.
      expect(
        projection.document(discussion: true).toPlainText([
          const DiscussionEmbedBuilder(),
        ]),
        'first\n\nsecond\n',
      );
    },
  );

  testWidgets('discussion reserves real block height', (tester) async {
    final key = GlobalKey<EditableCandidateBState>();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates:
            FlutterQuillLocalizations.localizationsDelegates,
        home: Scaffold(
          body: EditableCandidateB(
            key: key,
            initialText: 'first\nsecond',
            onValue: (_) {},
            showDiscussion: true,
          ),
        ),
      ),
    );
    await tester.pump();
    final block = find.text('合成段下讨论 · Quill block embed');
    expect(block, findsOneWidget);
    expect(
      tester
          .getSize(
            find.ancestor(of: block, matching: find.byType(SizedBox)).first,
          )
          .height,
      160,
    );
    final controller = key.currentState!.controller;
    controller.updateSelection(
      const TextSelection(baseOffset: 0, extentOffset: 14),
      ChangeSource.local,
    );
    expect(controller.clipboardSelection(true), isTrue);
    expect(
      controller.pasteDelta.toJson().toString(),
      contains(PlainProjection.discussionType),
    );
    expect(controller.pastePlainText, isNot('first\nsecond'));
    expect(
      key.currentState!.projection.read(key.currentState!.controller.document),
      'first\nsecond',
    );
  });
}
