// 覆盖审核任务的真实 FFI 边界：预览隔离、可撤销、门控与精确正文。
// 需要真实桥接 DLL，不代表任何模型或网络调用、也不代表真实用户审阅流程通过。

import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/workspace/data/real_workspace_repository.dart';

void main() {
  test(
    'real DLL reviewed preview is isolated, revocable, gated and exact',
    () async {
      final r = await RealWorkspaceRepository.open(diagnosticOverride: true);
      try {
        final work = await r.createWork('reviewed fixture');
        final c = await r.createChapter(work.id, 'chapter');
        final saved = await r.saveDocument(
          work.id,
          c.id,
          null,
          'confirmed 👩‍💻\r\n',
        );
        final prepared = await r.prepareConfirmation(
          work.id,
          c.id,
          null,
          saved.revision!,
        );
        await r.confirmChapter(work.id, c.id, prepared.token);
        final current = await r.loadDocument(work.id, c.id);
        await r.saveDocument(
          work.id,
          c.id,
          current.revision,
          'UNCONFIRMED SECRET',
        );
        await r.discussions.activateScope(work.id, c.id);
        final request = {
          'work': work.id,
          'chapter': c.id,
          'kind': 'summary',
          'text': '',
          'sceneId': null,
          'outputLanguage': 'en',
        };
        await expectLater(r.legacy.prepareTask(request), throwsA(anything));
        await r.discussions.setCloudEnabled(true);
        final p = await r.legacy.prepareTask(request);
        expect(p.toString(), contains('confirmed 👩‍💻'));
        expect(p.toString(), isNot(contains('UNCONFIRMED SECRET')));
        await r.legacy.cancelTask(work.id, p['id'] as String);
        await expectLater(
          r.legacy.sendTask(work.id, p['id'] as String),
          throwsA(anything),
        );
        expect((await r.legacy.history(work.id, c.id))['summary'], isNull);
        await r.lore.save(work.id, {
          'id': null,
          'expectedVersion': null,
          'kind': 'location',
          'name': 'Gate',
          'body': 'candidate',
          'aliases': ['门'],
          'scope': 'whole',
          'confirmed': false,
        });
        final entry = (await r.lore.list(work.id)).single['entry'] as Map;
        await expectLater(
          r.lore.reject(work.id, entry['id'] as String, 99),
          throwsA(anything),
        );
        await r.lore.reject(
          work.id,
          entry['id'] as String,
          entry['headVersion'] as int,
        );
        expect(
          ((await r.lore.list(work.id)).single['entry'] as Map)['status'],
          'rejected',
        );
      } finally {
        await r.close();
      }
    },
  );
}
