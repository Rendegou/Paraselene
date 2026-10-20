// 覆盖 M9 真实 FFI：素材导入、灵感转换与按作用域删除后的正文保持。
// 需要真实桥接 DLL 与合成工作目录，不代表 Windows UI 或用户真实作品迁移通过。

import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/cowrite/discussion_registry.dart';
import 'package:paraselene_flutter/workspace/data/real_workspace_repository.dart';

void main() {
  test(
    'real DLL preserves imported source through idea conversion and scoped deletion',
    () async {
      final repository = await RealWorkspaceRepository.open(
        diagnosticOverride: true,
      );
      try {
        final legacy = repository.legacy;
        final work = await repository.createWork('BOM fixture');
        final chapter = await repository.createChapter(work.id, 'BOM chapter');
        // A whole-chapter discussion has no quotation target; the native
        // writer must accept and return it unchanged.
        final registry = DiscussionRegistry(repository.discussions);
        addTearDown(registry.dispose);
        await registry.open(work.id, chapter.id);
        final chapterThread = registry.chapterThread();
        registry.editDraft(chapterThread.id, '全章讨论草稿');
        await registry.flush();
        final rows = await repository.discussions.listThreads(
          work.id,
          chapter.id,
        );
        final snapshot = rows.single['snapshot'] as Map;
        expect(snapshot['target'], isNull);
        expect(snapshot['anchor'], isNull);
        expect(snapshot['draft'], '全章讨论草稿');

        const body = '\uFEFF\uFEFFé é\r\n👩‍💻';
        final saved = await repository.saveDocument(
          work.id,
          chapter.id,
          null,
          body,
        );
        expect(saved.body, body);
        expect((await repository.loadDocument(work.id, chapter.id)).body, body);
        const original =
            '\uFEFF# fixture\r\n#### You:\r\n我想做一个 Unicode 👩‍💻 工具\r\n';
        final preview = await legacy.previewImport('manual', original);
        await legacy.confirmImport(preview['token'] as String);
        final candidate = (await legacy.ideaCandidate(0))!;
        final session = candidate['sessionId'] as String;
        expect(await legacy.importedOriginal(session), original);
        await legacy.confirmIdea(candidate, 'fixture idea');
        final idea = (await legacy.memories('idea', null)).single;
        await legacy.ideaStatus(idea, 'started');
        await expectLater(legacy.ideaStatus(idea, 'done'), throwsA(anything));
        await legacy.convertIdea(idea['id'] as String, 'personal');
        await expectLater(
          legacy.convertIdea(idea['id'] as String, 'personal'),
          throwsA(anything),
        );
        final target = (await legacy.memories('personal', null)).single;
        final convertedIdea = (await legacy.memories('idea', null)).single;
        await expectLater(
          legacy.deleteMemory('idea', convertedIdea),
          throwsA(anything),
        );
        final detail = await legacy.memoryDetail(
          'personal',
          null,
          target['id'] as String,
        );
        expect(
          (detail['sources'] as List).single['text'],
          contains('Unicode 👩‍💻'),
        );
        await expectLater(
          legacy.deleteMemory('novel', target),
          throwsA(anything),
        );
        await legacy.correctMemory(
          'personal',
          target,
          'corrected fixture',
          'é é\r\n',
        );
        // Reading and renaming the converted target uses only the stored
        // payload pointer plus the existing memory detail/CAS boundary.
        final ideaRow = (await legacy.memories('idea', null)).single;
        final view = await legacy.ideaTarget(ideaRow);
        expect(view, isNotNull);
        expect(view!.space, 'personal');
        expect(view.title, 'corrected fixture');
        expect((view.sources.single as Map)['text'], contains('Unicode 👩‍💻'));
        await legacy.updateIdeaTarget(view, 'renamed target', 'note');
        final reloaded = await legacy.ideaTarget(
          (await legacy.memories('idea', null)).single,
        );
        expect(reloaded!.title, 'renamed target');
        await expectLater(
          legacy.deleteMemory('personal', target),
          throwsA(anything),
        );
        final current = (await legacy.memories('personal', null)).single;
        await legacy.deleteMemory('personal', current);
        expect(await legacy.memories('personal', null), isEmpty);
        expect(await legacy.importedOriginal(session), original);
        expect(await legacy.memories('idea', null), hasLength(1));
      } finally {
        await repository.close();
      }
    },
  );
}
