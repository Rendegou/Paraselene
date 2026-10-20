// 覆盖素材标记的真实 FFI 集成：工作区控制器、编辑器与来源定位在真实 DLL 下的协同。
// 需要真实桥接 DLL 与合成数据，不代表 Windows 原生输入或真实用户素材通过。

import 'package:flutter/material.dart';
import 'package:paraselene_flutter/workspace/workspace_controller.dart';
import 'package:paraselene_flutter/workspace/presentation/editor_action_registry.dart';
import 'package:paraselene_flutter/workspace/presentation/manuscript_editor.dart';
import 'package:paraselene_flutter/workspace/presentation/workbench_chrome.dart';
import 'package:paraselene_flutter/l10n/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/workspace/data/real_workspace_repository.dart';

void main() {
  test(
    'real DLL source marks use exact head and UTF16 and never relocate dirty text',
    () async {
      final r = await RealWorkspaceRepository.open(diagnosticOverride: true);
      try {
        final work = await r.createWork('source fixture');
        final c = await r.createChapter(work.id, 'source');
        const body = '\uFEFFA👩‍💻 é é\r\nمرحبا';
        final saved = await r.saveDocument(work.id, c.id, null, body);
        final review = await r.prepareConfirmation(
          work.id,
          c.id,
          null,
          saved.revision!,
        );
        final confirmed = await r.confirmChapter(work.id, c.id, review.token);
        await r.lore.save(work.id, {
          'id': null,
          'expectedVersion': null,
          'kind': 'character',
          'name': 'Person',
          'body': 'material',
          'aliases': [],
          'scope': 'whole',
          'confirmed': true,
        });
        final entry = (await r.lore.list(work.id)).single['entry'] as Map;
        await r.lore.bind(work.id, {
          'entryId': entry['id'],
          'documentId': c.id,
          'versionId': confirmed.headVersionId,
          'from': 2,
          'to': 7,
          'quote': '👩‍💻',
        });
        final marks = await r.lore.sourceMarks(work.id, c.id, body);
        expect((marks['marks'] as List).single['from'], 2);
        expect((marks['marks'] as List).single['to'], 7);
        expect(
          (await r.lore.sourceMarks(work.id, c.id, 'dirty $body'))['marks'],
          isEmpty,
        );
        expect((await r.loadDocument(work.id, c.id)).body, body);
      } finally {
        await r.close();
      }
    },
  );
  testWidgets(
    'real workspace loads source marks and opens linked lore detail',
    (tester) async {
      final fixture = (await tester.runAsync(() async {
        final repository = await RealWorkspaceRepository.open(
          diagnosticOverride: true,
        );
        final work = await repository.createWork('UI fixture');
        final chapter = await repository.createChapter(
          work.id,
          'Source chapter',
        );
        const body = 'A👩‍💻B';
        final saved = await repository.saveDocument(
          work.id,
          chapter.id,
          null,
          body,
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
        await repository.lore.save(work.id, {
          'id': null,
          'expectedVersion': null,
          'kind': 'character',
          'name': 'Linked person',
          'body': 'Linked material fixture',
          'aliases': [],
          'scope': 'whole',
          'confirmed': true,
        });
        final entry =
            (await repository.lore.list(work.id)).single['entry'] as Map;
        await repository.lore.bind(work.id, {
          'entryId': entry['id'],
          'documentId': chapter.id,
          'versionId': confirmed.headVersionId,
          'from': 1,
          'to': 6,
          'quote': '👩‍💻',
        });
        final workspace = WorkspaceController(repository);
        await workspace.refresh();
        return workspace;
      }))!;
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      try {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => ManuscriptEditor(
                  controller: fixture,
                  labels: WorkbenchLabels(AppLocalizations.of(context), false),
                  wide: false,
                  actions: EditorActionRegistry(),
                ),
              ),
            ),
          ),
        );
        for (
          var i = 0;
          i < 30 && find.text('Manuscript sources').evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump();
        }
        expect(find.text('Manuscript sources'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Manuscript sources'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Linked person'));
        await tester.pump();
        for (
          var i = 0;
          i < 30 && find.text('Linked material fixture').evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(find.text('Linked material fixture'), findsOneWidget);
        expect(fixture.body, 'A👩‍💻B');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(fixture.close);
      }
    },
  );
}
