// M4 原生探针入口：在真实 Windows 窗口下驱动关闭、缩放等原生交互并输出轨迹。
// 测试专用探针，不代表生产 UI 行为或 Release 构建通过。

import 'package:flutter/material.dart';
import 'dart:io';
import 'package:paraselene_flutter/theme/font_licenses.dart';
import 'package:paraselene_flutter/workspace/data/synthetic_workspace_repository.dart';
import 'package:paraselene_flutter/workspace/data/workspace_repository.dart';
import 'package:paraselene_flutter/workspace/workbench_app.dart';
import 'package:paraselene_flutter/window/desktop_window_controller.dart';

import '../test/support/owned_store_fixture.dart';
import 'support/window_probe_trace.dart';

/// Standalone native-window probe, never selected by the production entry point.
/// Default uses an explicit in-memory failing repository to exercise recovery UI.
/// --real uses the preflight-verified isolated DLL and retains its unique run root.
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  final WorkspaceRepository repository;
  if (args.contains('--real')) {
    final fixture = OwnedStoreFixture();
    stdout.writeln('M4_NATIVE: preflight');
    await fixture.create();
    stdout.writeln('M4_NATIVE: open');
    repository = await fixture.open();
    stdout.writeln('M4_NATIVE: opened');
  } else {
    repository = _FailingSaveRepository();
  }
  final work = await repository.createWork('M4 native synthetic');
  stdout.writeln('M4_NATIVE: work');
  final chapter = await repository.createChapter(work.id, 'Recovery chapter');
  if (args.contains('--versions')) {
    for (final body in ['version-one\r\né e\u0301 👩‍💻', 'version-two']) {
      final current = await repository.loadDocument(work.id, chapter.id);
      final saved = await repository.saveDocument(
        work.id,
        chapter.id,
        current.revision,
        body,
      );
      final review = await repository.prepareConfirmation(
        work.id,
        chapter.id,
        saved.headVersionId,
        saved.revision!,
      );
      await repository.confirmChapter(work.id, chapter.id, review.token);
    }
    final current = await repository.loadDocument(work.id, chapter.id);
    await repository.saveDocument(
      work.id,
      chapter.id,
      current.revision,
      'unconfirmed-draft',
    );
  }
  stdout.writeln('M4_NATIVE: chapter');
  await repository.selectWork(work.id);
  stdout.writeln('M4_NATIVE: runApp');
  runApp(
    WorkbenchApp(
      repository: repository,
      initialLocale: const Locale('en'),
      windowController: args.contains('--window-shell')
          ? args.contains('--trace-window')
                ? traceWindow(ManagedDesktopWindow())
                : ManagedDesktopWindow()
          : null,
    ),
  );
}

final class _FailingSaveRepository extends SyntheticWorkspaceRepository {
  @override
  Future<ChapterDocument> saveDocument(
    String workId,
    String documentId,
    int? expectedRevision,
    String body,
  ) async => throw const WorkspaceFailure('durable_save_failed');
}
