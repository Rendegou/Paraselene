// 覆盖 M4 应用生命周期：原生与框架关闭信号共用脏屏障、导出取消与失败处理。
// widget 测试只验证 Dart 决策，不代表真实 Windows WM_CLOSE 或进程退出通过。

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/editor/editor_viewport.dart';
import 'package:paraselene_flutter/workspace/data/recovery_export.dart';
import 'package:paraselene_flutter/workspace/data/synthetic_workspace_repository.dart';
import 'package:paraselene_flutter/workspace/data/workspace_repository.dart';
import 'package:paraselene_flutter/workspace/workbench_app.dart';

class ExitRepository extends SyntheticWorkspaceRepository {
  bool failSave = true;
  int closes = 0;
  int saves = 0;
  String savedBody = '';

  @override
  Future<ChapterDocument> saveDocument(
    String w,
    String c,
    int? r,
    String body,
  ) {
    saves++;
    if (failSave) throw const WorkspaceFailure('storage_io');
    savedBody = body;
    return super.saveDocument(w, c, r, body);
  }

  @override
  Future<void> close() async {
    closes++;
    await super.close();
  }
}

// Throw before any repository is opened; never calls the ownedstore path.
class BootstrapFailureApp extends WorkbenchApp {
  const BootstrapFailureApp({super.key})
    : super(initialLocale: const Locale('en'));

  @override
  WorkspaceRepository? get repository =>
      throw const WorkspaceFailure('bootstrap_fixture_failure');
}

class ExitGateway implements SavePathGateway {
  String? path;
  bool fail = false;
  String? suggested;
  @override
  Future<String?> pickSavePath({required String suggestedName}) async {
    suggested = suggestedName;
    if (fail) throw const WorkspaceFailure('export_failed');
    return path;
  }
}

// The framework platform-channel path invokes registered lifecycle observers.
// This is not a native WM_CLOSE or Alt+F4 acceptance test.
Future<String> exitSignal(WidgetTester tester) async {
  final result = Completer<String>();
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/platform',
    SystemChannels.platform.codec.encodeMethodCall(
      const MethodCall('System.requestAppExit'),
    ),
    (data) {
      final value = SystemChannels.platform.codec.decodeEnvelope(data!);
      result.complete((value as Map)['response'] as String);
    },
  );
  return result.future;
}

Future<bool> nativeExitSignal(WidgetTester tester) async {
  const codec = StandardMethodCodec();
  final result = Completer<bool>();
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'paraselene/native_close',
    codec.encodeMethodCall(const MethodCall('requestClose')),
    (data) => result.complete(codec.decodeEnvelope(data!) as bool),
  );
  return result.future;
}

Future<void> start(
  WidgetTester tester,
  ExitRepository repo,
  ExitGateway gateway,
) async {
  tester.view.physicalSize = const Size(1280, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final work = await repo.createWork('Recovery work');
  await repo.createChapter(work.id, 'Chapter one');
  await tester.pumpWidget(
    WorkbenchApp(
      repository: repo,
      savePathGateway: gateway,
      initialLocale: const Locale('en'),
    ),
  );
  await tester.pumpAndSettle();
  final viewport = tester.widget<EditorViewport>(
    find.byKey(const ValueKey('manuscript-body')),
  );
  final controller = viewport.controller;
  controller.document.replaceBody('exact draft 👩‍💻');
  controller.select(
    TextSelection.collapsed(offset: 'exact draft 👩‍💻'.length),
  );
  (controller as ChangeNotifier).notifyListeners();
  await tester.pump();
}

Future<void> tapDialog(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(AlertDialog), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('native and framework requests share the dirty close barrier', (
    tester,
  ) async {
    final repo = ExitRepository();
    await start(tester, repo, ExitGateway());
    final native = nativeExitSignal(tester);
    final framework = exitSignal(tester);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(repo.saves, 1);
    await tapDialog(tester, 'Keep editing');
    expect(await native, isFalse);
    expect(await framework, 'cancel');
    expect(repo.closes, 0);
    repo.failSave = false;
    final retry = nativeExitSignal(tester);
    await tester.pumpAndSettle();
    await tapDialog(tester, 'Retry');
    expect(await retry, isTrue);
    expect(repo.savedBody, 'exact draft 👩‍💻');
    expect(repo.closes, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'bootstrap failure with no editable session allows framework exit',
    (tester) async {
      await tester.pumpWidget(const BootstrapFailureApp());
      await tester.pumpAndSettle();
      expect(
        tester.widget<StartupSurface>(find.byType(StartupSurface)).failed,
        isTrue,
      );
      expect(find.byKey(const ValueKey('manuscript-body')), findsNothing);
      final request = exitSignal(tester);
      await tester.pumpAndSettle();
      expect(await request, 'exit');
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('registered listener flushes on framework exit signal', (
    tester,
  ) async {
    final repo = ExitRepository()..failSave = false;
    await start(tester, repo, ExitGateway());
    final request = exitSignal(tester);
    await tester.pumpAndSettle();
    expect(await request, 'exit');
    expect(repo.savedBody, 'exact draft 👩‍💻');
    expect(repo.closes, 1);
    final exception = tester.takeException();
    expect(
      exception,
      isNull,
      reason: exception is FlutterError ? exception.toStringDeep() : null,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'repeated requests share one dialog; repeated retry failure stays visible',
    (tester) async {
      final repo = ExitRepository();
      await start(tester, repo, ExitGateway());
      final first = exitSignal(tester);
      final second = exitSignal(tester);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Changes could not be saved'), findsOneWidget);
      await tapDialog(tester, 'Retry');
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(repo.saves, 2);
      expect(repo.closes, 0);
      await tapDialog(tester, 'Keep editing');
      expect(await first, 'cancel');
      expect(await second, 'cancel');
      expect(
        tester
            .widget<EditorViewport>(
              find.byKey(const ValueKey('manuscript-body')),
            )
            .controller
            .document
            .raw,
        'exact draft 👩‍💻',
      );
      repo.failSave = false;
      final third = exitSignal(tester);
      await tester.pumpAndSettle();
      await tapDialog(tester, 'Retry');
      expect(await third, 'exit');
      expect(repo.closes, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('cancelled export never shows success or exit action', (
    tester,
  ) async {
    final repo = ExitRepository();
    final gateway = ExitGateway();
    await start(tester, repo, gateway);
    final request = exitSignal(tester);
    await tester.pumpAndSettle();
    await tapDialog(tester, 'Export draft');
    expect(await request, 'cancel');
    expect(find.text('Draft exported'), findsNothing);
    expect(find.text('Exit anyway'), findsNothing);
    expect(gateway.suggested, 'Recovery work_readable_chapter_recovery.txt');
    expect(repo.closes, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed export reports error and never enables exit', (
    tester,
  ) async {
    final repo = ExitRepository();
    await start(tester, repo, ExitGateway()..fail = true);
    final request = exitSignal(tester);
    await tester.pumpAndSettle();
    await tapDialog(tester, 'Export draft');
    expect(find.text('Draft exported'), findsNothing);
    expect(find.text('Exit anyway'), findsNothing);
    await tapDialog(tester, 'Close');
    expect(await request, 'cancel');
    expect(repo.closes, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final accept in [false, true]) {
    testWidgets(
      'verified export keeps editor frozen through exit decision ($accept)',
      (tester) async {
        final temp = Directory.systemTemp.createTempSync('m4-close-export-');
        addTearDown(() => temp.deleteSync(recursive: true));
        final repo = ExitRepository();
        final gateway = ExitGateway()..path = '${temp.path}/draft.txt';
        await start(tester, repo, gateway);
        final request = exitSignal(tester);
        await tester.pumpAndSettle();
        await tapDialog(tester, 'Export draft');
        for (
          var i = 0;
          i < 100 && find.text('Draft exported').evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(find.text('Draft exported'), findsOneWidget);
        final editor = find.byKey(const ValueKey('manuscript-body'));
        expect(
          tester.widget<EditorViewport>(editor).controller.readOnly,
          isTrue,
        );
        expect(
          File(gateway.path!).readAsStringSync(),
          contains('exact draft 👩‍💻'),
        );
        await tapDialog(tester, 'Close');
        expect(find.text('Exit anyway'), findsOneWidget);
        expect(
          tester.widget<EditorViewport>(editor).controller.readOnly,
          isTrue,
        );
        await tapDialog(tester, accept ? 'Exit anyway' : 'Keep editing');
        expect(await request, accept ? 'exit' : 'cancel');
        expect(
          tester.widget<EditorViewport>(editor).controller.readOnly,
          accept,
        );
        expect(repo.closes, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
