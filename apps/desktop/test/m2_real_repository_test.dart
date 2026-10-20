// 覆盖 M2 真实仓库：通过真实 DLL 读取合成工作目录的目录与精确正文。
// 需要真实桥接 DLL 与合成数据，不代表生产数据库、作者库或并发访问通过。

import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/workspace/data/demo_content.dart';
import 'package:paraselene_flutter/workspace/data/real_workspace_repository.dart';
import 'package:paraselene_flutter/workspace/data/workspace_repository.dart';

void main() {
  test(
    'actual DLL reads directory and exact body from fresh synthetic root',
    () async {
      final repository = await RealWorkspaceRepository.open(
        diagnosticOverride: true,
      );
      try {
        expect(repository.mode, WorkspaceMode.realBridge);
        expect(await repository.listWorks(), isEmpty);
        await repository.seedDemo();
        final works = await repository.listWorks();
        expect(works.single.title, '雨后的书店');
        final chapters = await repository.listChapters(works.single.id);
        expect(chapters.single.title, '第一章 · 归途');
        expect(
          await repository.loadBody(works.single.id, chapters.single.id),
          demoBody,
        );
        await expectLater(
          repository.loadBody(works.single.id, 'missing'),
          throwsA(isA<WorkspaceFailure>()),
        );
      } finally {
        await repository.close();
        await repository.close();
      }
      await expectLater(
        repository.listWorks(),
        throwsA(isA<WorkspaceFailure>()),
      );
      final fresh = await RealWorkspaceRepository.open(
        diagnosticOverride: true,
      );
      try {
        expect(await fresh.listWorks(), isEmpty);
      } finally {
        await fresh.close();
      }
    },
  );
}
