// 覆盖素材标记：过期来源头或正文不应用坐标、单字形两侧点击与标记生命周期。
// widget 测试只验证 Dart 交互，不代表真实 FFI 坐标采纳或 Windows 输入通过。

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/editor/editor_input_client.dart';
import 'package:paraselene_flutter/editor/editor_source_mark.dart';
import 'package:paraselene_flutter/editor/editor_viewport.dart';
import 'package:paraselene_flutter/lore/source_mark_controller.dart';
import 'package:paraselene_flutter/workspace/data/synthetic_workspace_repository.dart';
import 'package:paraselene_flutter/workspace/data/workspace_repository.dart';
import 'package:paraselene_flutter/workspace/presentation/editor_source_menu.dart';
import 'package:paraselene_flutter/workspace/presentation/source_navigation.dart';
import 'package:paraselene_flutter/workspace/workspace_controller.dart';
import 'package:paraselene_flutter/l10n/generated/app_localizations.dart';

final class Marks implements SourceMarkRepository {
  final requests = <Completer<Map<String, dynamic>>>[];
  @override
  Future<Map<String, dynamic>> sourceMarks(
    String work,
    String chapter,
    String body,
  ) {
    final next = Completer<Map<String, dynamic>>();
    requests.add(next);
    return next.future;
  }
}

Map<String, dynamic> snapshot(String head) => {
  'headVersion': head,
  'marks': [
    {'entryId': 'person', 'name': 'Person', 'from': 1, 'to': 6},
  ],
};

const _navigationBody = 'A👩‍💻B';

Future<
  ({
    WorkspaceController workspace,
    EditorInputClient editor,
    WorkspaceChapter chapter,
    String head,
  })
>
_navigationFixture() async {
  final repository = SyntheticWorkspaceRepository();
  final work = await repository.createWork('作品');
  final chapter = await repository.createChapter(work.id, '目标');
  final other = await repository.createChapter(work.id, '其他');
  final saved = await repository.saveDocument(
    work.id,
    chapter.id,
    null,
    _navigationBody,
  );
  final review = await repository.prepareConfirmation(
    work.id,
    chapter.id,
    null,
    saved.revision!,
  );
  final confirmed = await repository.confirmChapter(
    work.id,
    chapter.id,
    review.token,
  );
  final workspace = WorkspaceController(repository);
  await workspace.refresh();
  final editor = EditorInputClient(
    workspace.body,
    style: const TextStyle(fontSize: 20, height: 1.8),
  );
  workspace.editing.addListener(() {
    if (editor.document.raw != workspace.body) editor.load(workspace.body);
  });
  final listedOther = workspace.chapters.singleWhere((c) => c.id == other.id);
  expect(await workspace.selectChapter(listedOther), isTrue);
  expect(workspace.body, '');
  return (
    workspace: workspace,
    editor: editor,
    chapter: chapter,
    head: confirmed.headVersionId!,
  );
}

Map<String, dynamic> _navigationSource(
  WorkspaceChapter chapter,
  String head, {
  String body = _navigationBody,
  String? sourceVersionId,
}) => {
  'body': body,
  'anchor': {
    'documentId': chapter.id,
    'sourceVersionId': sourceVersionId ?? head,
    'startChar': 1,
    'endChar': 4,
  },
};

void main() {
  test(
    'async source results require exact scope/head/body and clear invalidates flight',
    () async {
      final fake = Marks();
      final controller = SourceMarkController(fake);
      addTearDown(controller.dispose);
      final old = controller.load('w', 'a', 'a1', 'A👩‍💻');
      final next = controller.load('w', 'b', 'b1', 'B👩‍💻');
      fake.requests[1].complete(snapshot('b1'));
      await next;
      fake.requests[0].complete(snapshot('a1'));
      await old;
      expect(controller.visible('w', 'b', 'b1', 'B👩‍💻'), hasLength(1));
      expect(controller.visible('w', 'a', 'a1', 'A👩‍💻'), isEmpty);
      expect(controller.visible('w', 'b', 'b1', 'dirty B👩‍💻'), isEmpty);
      expect(controller.visible('w', 'b', 'b1', 'B👩‍💻'), hasLength(1));
      final pending = controller.load('w', 'b', 'b1', 'B👩‍💻');
      controller.clear();
      fake.requests[2].complete(snapshot('b1'));
      await pending;
      expect(controller.visible('w', 'b', 'b1', 'B👩‍💻'), isEmpty);
    },
  );
  test(
    'head drift, invalid ranges and a late disposed read cannot publish',
    () async {
      final fake = Marks();
      final controller = SourceMarkController(fake);
      var pending = controller.load('w', 'a', 'a1', 'A👩‍💻');
      fake.requests.last.complete(snapshot('changed'));
      await pending;
      expect(controller.failed, isTrue);
      expect(controller.visible('w', 'a', 'a1', 'A👩‍💻'), isEmpty);
      pending = controller.load('w', 'a', 'a1', 'short');
      fake.requests.last.complete(snapshot('a1'));
      await pending;
      expect(controller.failed, isTrue);
      pending = controller.load('w', 'a', 'a1', 'A👩‍💻');
      controller.dispose();
      fake.requests.last.complete(snapshot('a1'));
      await pending;
    },
  );
  test(
    'source state exposes loading, error, empty and content separately',
    () async {
      final fake = Marks();
      final controller = SourceMarkController(fake);
      addTearDown(controller.dispose);

      // 未完成的读取属于加载中，而不是空态或失败态。
      final pending = controller.load('w', 'a', 'a1', 'A👩‍💻');
      expect(controller.loading, isTrue);
      expect(controller.failed, isFalse);
      expect(
        controller.stateFor('w', 'a', 'a1', 'A👩‍💻'),
        SourceMarkState.loading,
      );

      // 返回空标记且版本一致 → 空态，仍不是失败。
      fake.requests.last.complete({'headVersion': 'a1', 'marks': []});
      await pending;
      expect(controller.loading, isFalse);
      expect(controller.failed, isFalse);
      expect(
        controller.stateFor('w', 'a', 'a1', 'A👩‍💻'),
        SourceMarkState.empty,
      );
      expect(controller.visible('w', 'a', 'a1', 'A👩‍💻'), isEmpty);

      // 有标记 → 内容态。
      final content = controller.load('w', 'a', 'a1', 'A👩‍💻');
      fake.requests.last.complete(snapshot('a1'));
      await content;
      expect(
        controller.stateFor('w', 'a', 'a1', 'A👩‍💻'),
        SourceMarkState.content,
      );

      // 版本漂移 → 失败态；重新发起读取立即回到加载中。
      final failed = controller.load('w', 'a', 'a1', 'A👩‍💻');
      fake.requests.last.complete(snapshot('changed'));
      await failed;
      expect(controller.failed, isTrue);
      expect(
        controller.stateFor('w', 'a', 'a1', 'A👩‍💻'),
        SourceMarkState.error,
      );
      final retry = controller.load('w', 'a', 'a1', 'A👩‍💻');
      expect(
        controller.stateFor('w', 'a', 'a1', 'A👩‍💻'),
        SourceMarkState.loading,
      );
      fake.requests.last.complete(snapshot('a1'));
      await retry;
      expect(controller.failed, isFalse);
      expect(
        controller.stateFor('w', 'a', 'a1', 'A👩‍💻'),
        SourceMarkState.content,
      );
    },
  );
  testWidgets(
    'painted source boxes and Ctrl-click share offset geometry without edits',
    (tester) async {
      const body = 'prefix marked end\nمرحبا';
      final controller = BasicEditorController(
        body,
        style: const TextStyle(fontSize: 20, height: 1.8),
      );
      addTearDown(controller.dispose);
      final opened = <List<EditorSourceMark>>[];
      const marks = [
        EditorSourceMark(entryId: 'a', name: 'A', from: 7, to: 13),
        EditorSourceMark(entryId: 'b', name: 'B', from: 7, to: 13),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 800,
            height: 500,
            child: EditorViewport(
              controller: controller,
              sourceMarks: marks,
              sourceBody: body,
              onOpenSources: opened.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final state = tester.state<EditorViewportState>(
        find.byType(EditorViewport),
      );
      expect(state.scene!.sourceMarks, isNotEmpty);
      expect(controller.layout.width, 752);
      final point =
          tester.getTopLeft(find.byType(EditorViewport)) +
          state.scene!.sourceMarks.first.center;
      final before = controller.value.selection;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tapAt(point);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(opened.single.map((m) => m.entryId), ['a', 'b']);
      expect(controller.document.raw, body);
      expect(controller.value.selection, before);
      await tester.tapAt(point);
      await tester.pump();
      expect(opened, hasLength(1));
      expect(controller.value.selection.extentOffset, inInclusiveRange(7, 13));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'source list exposes the same opening action without modifier keys',
    (tester) async {
      final opened = <List<EditorSourceMark>>[];
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: EditorSourceMenu(
              marks: const [
                EditorSourceMark(entryId: 'a', name: 'A', from: 1, to: 3),
              ],
              failed: false,
              enabled: true,
              onOpen: opened.add,
              onRefresh: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manuscript sources'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();
      expect(opened.single.single.entryId, 'a');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'locating a source switches chapter and selects exact UTF16 span',
    (tester) async {
      final fixture = await _navigationFixture();
      addTearDown(fixture.editor.dispose);
      addTearDown(fixture.workspace.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Focus(
            focusNode: fixture.editor.focusNode,
            child: const SizedBox(),
          ),
        ),
      );
      await locateLoreSource(
        fixture.workspace,
        fixture.editor,
        _navigationSource(fixture.chapter, fixture.head),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(fixture.workspace.currentChapter?.id, fixture.chapter.id);
      expect(fixture.editor.document.raw, _navigationBody);
      expect(
        fixture.editor.value.selection,
        const TextSelection(baseOffset: 1, extentOffset: 6),
      );
      expect(fixture.editor.focusNode.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('stale source head or body never applies coordinates', (
    tester,
  ) async {
    final fixture = await _navigationFixture();
    addTearDown(fixture.editor.dispose);
    addTearDown(fixture.workspace.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Focus(
          focusNode: fixture.editor.focusNode,
          child: const SizedBox(),
        ),
      ),
    );
    await locateLoreSource(
      fixture.workspace,
      fixture.editor,
      _navigationSource(
        fixture.chapter,
        fixture.head,
        body: 'dirty $_navigationBody',
      ),
    );
    expect(fixture.editor.value.selection.extentOffset, 0);
    await locateLoreSource(
      fixture.workspace,
      fixture.editor,
      _navigationSource(
        fixture.chapter,
        fixture.head,
        sourceVersionId: 'old-head',
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(fixture.editor.value.selection.extentOffset, 0);
    expect(fixture.editor.document.raw, _navigationBody);
    expect(tester.takeException(), isNull);
  });
  for (final body in ['X', 'م', '👩‍💻']) {
    testWidgets('Ctrl-click either side of a single source glyph: $body', (
      tester,
    ) async {
      final controller = BasicEditorController(
        body,
        style: const TextStyle(fontSize: 24, height: 1.8),
      );
      addTearDown(controller.dispose);
      var opens = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 700,
            height: 300,
            child: EditorViewport(
              controller: controller,
              sourceBody: body,
              sourceMarks: [
                EditorSourceMark(
                  entryId: 'only',
                  name: 'Only',
                  from: 0,
                  to: body.length,
                ),
              ],
              onOpenSources: (_) => opens++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final state = tester.state<EditorViewportState>(
        find.byType(EditorViewport),
      );
      final box = state.scene!.sourceMarks.first;
      final origin = tester.getTopLeft(find.byType(EditorViewport));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      for (final fraction in [.2, .8]) {
        await tester.tapAt(
          origin + Offset(box.left + box.width * fraction, box.center.dy),
        );
        await tester.pump();
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(opens, 2);
      expect(controller.document.raw, body);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('editing before the next frame rejects old source geometry', (
    tester,
  ) async {
    final controller = BasicEditorController(
      'X',
      style: const TextStyle(fontSize: 24, height: 1.8),
    );
    addTearDown(controller.dispose);
    var opens = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 700,
          height: 300,
          child: EditorViewport(
            controller: controller,
            sourceBody: 'X',
            sourceMarks: const [
              EditorSourceMark(entryId: 'only', name: 'Only', from: 0, to: 1),
            ],
            onOpenSources: (_) => opens++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final state = tester.state<EditorViewportState>(
      find.byType(EditorViewport),
    );
    final point =
        tester.getTopLeft(find.byType(EditorViewport)) +
        state.scene!.sourceMarks.first.center;
    controller.document.replaceBody('Y');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tapAt(point);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(opens, 0);
    expect(controller.document.raw, 'Y');
    expect(state.scene!.sourceMarks, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
