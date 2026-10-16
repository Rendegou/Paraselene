import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/workspace/data/demo_content.dart';
import 'package:paraselene_flutter/workspace/data/synthetic_workspace_repository.dart';
import 'package:paraselene_flutter/workspace/data/workspace_repository.dart';
import 'package:paraselene_flutter/workspace/workspace_controller.dart';

class DelayedRepository extends SyntheticWorkspaceRepository {
  DelayedRepository() : super(withDemo: true);
  final first = Completer<ChapterDocument>();
  var loads = 0;
  @override
  Future<ChapterDocument> loadDocument(String workId, String chapterId) {
    loads++;
    return loads == 1 ? first.future : super.loadDocument(workId, chapterId);
  }
}

class FailedRepository extends SyntheticWorkspaceRepository {
  @override
  Future<List<WorkspaceWork>> listWorks() async =>
      throw const WorkspaceFailure('directory_failed');
}

class InterruptedSeedRepository extends SyntheticWorkspaceRepository {
  var createdWorks = 0;
  var seedAttempts = 0;
  bool bodySaved = false;

  @override
  Future<void> seedDemo() async {
    seedAttempts++;
    if (createdWorks == 0) {
      createdWorks++;
      await super.seedDemo();
      throw const WorkspaceFailure('seed_interrupted');
    }
    bodySaved = true;
  }

  @override
  Future<String> loadBody(String workId, String chapterId) async {
    if (!bodySaved) return '';
    return super.loadBody(workId, chapterId);
  }
}

void main() {
  test(
    'refresh resumes interrupted seed before listing partial metadata',
    () async {
      final repository = InterruptedSeedRepository();
      final controller = WorkspaceController(repository);
      await controller.seedDemo();
      expect(controller.phase, WorkspacePhase.error);
      expect(controller.errorCode, 'seed_interrupted');
      expect(controller.works, isEmpty);
      await controller.refresh();
      expect(controller.phase, WorkspacePhase.content);
      expect(controller.works, hasLength(1));
      expect(controller.chapters, hasLength(1));
      expect(controller.body.codeUnits, demoBody.codeUnits);
      expect(repository.createdWorks, 1);
      expect(repository.seedAttempts, 2);
      await controller.refresh();
      expect(repository.seedAttempts, 2);
      await controller.close();
    },
  );

  test(
    'empty fixture, explicit seed, immutable metadata and exact text',
    () async {
      final repository = SyntheticWorkspaceRepository();
      final controller = WorkspaceController(repository);
      await controller.refresh();
      expect(controller.phase, WorkspacePhase.empty);
      expect(repository.mode, WorkspaceMode.synthetic);
      await controller.seedDemo();
      expect(controller.phase, WorkspacePhase.content);
      expect(controller.currentWork!.title, '雨后的书店');
      expect(controller.currentChapter!.title, '第一章 · 归途');
      expect(controller.body.codeUnits, demoBody.codeUnits);
      expect(() => controller.works.clear(), throwsUnsupportedError);
      expect(() => controller.chapters.clear(), throwsUnsupportedError);
      await controller.close();
      await controller.close();
      await expectLater(
        repository.listWorks(),
        throwsA(isA<WorkspaceFailure>()),
      );
    },
  );

  test(
    'chapter tap during a pending load is rejected; in-flight body lands exactly',
    () async {
      final repository = DelayedRepository();
      final controller = WorkspaceController(repository);
      final pending = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      // The M4 barrier replaces the old newer-wins race: during a load the
      // selection is rejected, and the legitimate in-flight body lands intact.
      expect(controller.isBusy, isTrue);
      expect(
        await controller.selectChapter(controller.chapters.first),
        isFalse,
      );
      repository.first.complete(
        const ChapterDocument(
          workId: 'demo-work',
          documentId: 'demo-chapter',
          body: demoBody,
        ),
      );
      await pending;
      expect(controller.body.codeUnits, demoBody.codeUnits);
      await controller.close();
    },
  );

  test(
    'work switch during a pending load is rejected; after it the switch applies',
    () async {
      final repository = DelayedRepository();
      final controller = WorkspaceController(repository);
      final pending = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      const selected = WorkspaceWork(
        id: 'demo-work',
        title: 'Explicit selection',
      );
      expect(await controller.selectWork(selected), isFalse);
      repository.first.complete(
        const ChapterDocument(
          workId: 'demo-work',
          documentId: 'demo-chapter',
          body: demoBody,
        ),
      );
      await pending;
      expect(controller.body.codeUnits, demoBody.codeUnits);
      expect(await controller.selectWork(selected), isTrue);
      expect(controller.currentWork, same(selected));
      expect(controller.body.codeUnits, demoBody.codeUnits);
      await controller.close();
    },
  );

  test(
    'stable failures reach UI and closing prevents late notifications',
    () async {
      final failed = WorkspaceController(FailedRepository());
      await failed.refresh();
      expect(failed.phase, WorkspacePhase.error);
      expect(failed.errorCode, 'directory_failed');
      await failed.close();
      final repository = DelayedRepository();
      final controller = WorkspaceController(repository);
      var notifications = 0;
      controller.addListener(() => notifications++);
      final pending = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      await controller.close();
      final before = notifications;
      repository.first.complete(
        const ChapterDocument(
          workId: 'demo-work',
          documentId: 'demo-chapter',
          body: 'late',
        ),
      );
      await pending;
      expect(notifications, before);
    },
  );
}
