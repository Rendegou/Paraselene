import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/domain/editing/save_coordinator.dart';
import 'package:paraselene_flutter/workspace/data/recovery_export.dart';
import 'package:paraselene_flutter/workspace/data/synthetic_workspace_repository.dart';
import 'package:paraselene_flutter/workspace/data/workspace_repository.dart';
import 'package:paraselene_flutter/workspace/workspace_controller.dart';

final class _FixedGateway implements SavePathGateway {
  _FixedGateway(this.path);
  final String path;
  var calls = 0;
  @override
  Future<String?> pickSavePath({required String suggestedName}) async {
    calls++;
    return path;
  }
}

final class _CancelGateway implements SavePathGateway {
  @override
  Future<String?> pickSavePath({required String suggestedName}) async => null;
}

/// A repository whose reads for one chapter fail while others succeed.
final class _BrokenReadRepository extends SyntheticWorkspaceRepository {
  String brokenId = '';
  @override
  Future<ChapterDocument> loadDocument(String workId, String chapterId) {
    if (chapterId == brokenId) throw const WorkspaceFailure('storage_io');
    return super.loadDocument(workId, chapterId);
  }
}

SaveState _state(String work, String doc, String body) => SaveState(
  document: ChapterDocument(workId: work, documentId: doc, body: body),
  generation: 1,
);

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('m4-export-'));
  tearDown(() => temp.deleteSync(recursive: true));

  Future<(WorkspaceWork, List<WorkspaceChapter>)> seed(
    SyntheticWorkspaceRepository repo,
  ) async {
    final work = await repo.createWork('导出作品');
    final a = await repo.createChapter(work.id, '第一章');
    final b = await repo.createChapter(work.id, '第二章');
    await repo.saveDocument(work.id, a.id, null, '后端第一章');
    await repo.saveDocument(work.id, b.id, null, '后端第二章');
    return (work, await repo.listChapters(work.id));
  }

  test('in-memory draft wins; UTF-8 read-back matches exactly', () async {
    final repo = SyntheticWorkspaceRepository();
    final (work, chapters) = await seed(repo);
    final target = '${temp.path}\\恢复稿.txt';
    final exporter = RecoveryExporter(repo, _FixedGateway(target));

    final outcome = await exporter.export(
      work: work,
      chapters: chapters,
      loadedStates: [
        _state(work.id, chapters[0].id, '内存未保存草稿\r\n第二行 👩\u200d💻'),
      ],
    );
    expect(outcome, isNotNull);
    final content = await File(target).readAsString(encoding: utf8);
    expect(content, contains('内存未保存草稿\r\n第二行 👩\u200d💻'));
    expect(content, contains('后端第二章'));
    expect(content, contains('# 导出作品'));
    expect(outcome!.chapters, 2);
    expect(outcome.omitted, isEmpty);
  });

  test(
    'unreadable chapters are omitted, never blocking the current draft',
    () async {
      final repo = _BrokenReadRepository();
      final (work, chapters) = await seed(repo);
      repo.brokenId = chapters[1].id;
      final target = '${temp.path}\\恢复稿.txt';
      final exporter = RecoveryExporter(repo, _FixedGateway(target));

      final outcome = await exporter.export(
        work: work,
        chapters: chapters,
        loadedStates: [_state(work.id, chapters[0].id, '当前草稿')],
      );
      expect(outcome, isNotNull);
      expect(outcome!.chapters, 1);
      expect(outcome.omitted, ['第二章']);
      final content = await File(target).readAsString(encoding: utf8);
      expect(content, contains('当前草稿'));
      expect(content, isNot(contains('后端第二章')));
    },
  );

  test(
    'same chapter id in another work cannot replace this work body',
    () async {
      final repo = SyntheticWorkspaceRepository();
      final (work, chapters) = await seed(repo);
      final target = '${temp.path}\\isolated.txt';
      final exporter = RecoveryExporter(repo, _FixedGateway(target));
      await exporter.export(
        work: work,
        chapters: chapters,
        loadedStates: [
          _state('other-work', chapters.first.id, 'foreign draft'),
        ],
      );
      final content = await File(target).readAsString();
      expect(content, contains('后端第一章'));
      expect(content, isNot(contains('foreign draft')));
    },
  );

  test('write failure never returns a verified outcome', () async {
    final repo = SyntheticWorkspaceRepository();
    final (work, chapters) = await seed(repo);
    final exporter = RecoveryExporter(repo, _FixedGateway(temp.path));
    await expectLater(
      exporter.export(work: work, chapters: chapters, loadedStates: const []),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('a cancelled dialog writes nothing and reports nothing', () async {
    final repo = SyntheticWorkspaceRepository();
    final (work, chapters) = await seed(repo);
    final target = '${temp.path}\\不应存在.txt';
    final exporter = RecoveryExporter(repo, _CancelGateway());

    final outcome = await exporter.export(
      work: work,
      chapters: chapters,
      loadedStates: const [],
    );
    expect(outcome, isNull);
    expect(File(target).existsSync(), isFalse);
  });

  test(
    'closeBarrier flushes then closes; failure keeps the repository open',
    () async {
      final repo = SyntheticWorkspaceRepository();
      final controller = WorkspaceController(repo);
      await controller.refresh();
      await controller.createWork('作品');
      await controller.createChapter('第一章');
      controller.editing.edit('正文');
      await Future<void>.delayed(const Duration(milliseconds: 450));

      expect(await controller.closeBarrier(), isTrue);
      await expectLater(repo.listWorks(), throwsA(isA<WorkspaceFailure>()));
    },
  );

  test('closeBarrier failure keeps the draft and allows retry', () async {
    final repo = _GatedSaveRepository();
    final controller = WorkspaceController(repo);
    await controller.refresh();
    await controller.createWork('作品');
    await controller.createChapter('第一章');
    controller.editing.edit('未保存');
    repo.fail = true;

    expect(await controller.closeBarrier(), isFalse);
    expect(controller.errorCode, 'storage_io');
    expect(controller.body, '未保存');
    // The repository stays usable for recovery export and retry.
    expect(await repo.listWorks(), isNotEmpty);

    repo.fail = false;
    // A stored save failure blocks the barrier itself: retry explicitly first.
    expect(await controller.retrySave(), isTrue);
    expect(await controller.closeBarrier(), isTrue);
    controller.dispose();
  });
}

/// Saves fail while [fail] is set.
final class _GatedSaveRepository extends SyntheticWorkspaceRepository {
  bool fail = false;
  @override
  Future<ChapterDocument> saveDocument(
    String workId,
    String chapterId,
    int? expectedRevision,
    String body,
  ) {
    if (fail) throw const WorkspaceFailure('storage_io');
    return super.saveDocument(workId, chapterId, expectedRevision, body);
  }
}
