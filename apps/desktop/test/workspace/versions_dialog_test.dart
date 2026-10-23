// 版本弹窗四态与迟到回滚的合成测试；不接触作者库、FFI、凭据或模型。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/l10n/generated/app_localizations.dart';
import 'package:paraselene_flutter/theme/workbench_theme.dart';
import 'package:paraselene_flutter/workspace/data/synthetic_workspace_repository.dart';
import 'package:paraselene_flutter/workspace/data/workspace_repository.dart';
import 'package:paraselene_flutter/workspace/presentation/workbench_dialogs.dart';
import 'package:paraselene_flutter/workspace/presentation/workbench_labels.dart';
import 'package:paraselene_flutter/workspace/workspace_controller.dart';

import '../support/m2_harness.dart';

class _VersionsRepository extends SyntheticWorkspaceRepository {
  _VersionsRepository() : super(withDemo: true);

  final responses = <Future<List<VersionEntry>>>[];
  final reads = <(String, String)>[];
  final rollbacks = <(String, String, String)>[];
  Completer<void>? rollbackGate;
  bool failRollback = false;
  bool failSynchronously = false;

  @override
  Future<List<VersionEntry>> listVersions(String workId, String chapterId) {
    reads.add((workId, chapterId));
    if (failSynchronously) {
      failSynchronously = false;
      throw StateError('Synthetic private failure details');
    }
    if (responses.isNotEmpty) return responses.removeAt(0);
    return super.listVersions(workId, chapterId);
  }

  Future<List<VersionEntry>> storedVersions(String workId, String chapterId) =>
      super.listVersions(workId, chapterId);

  @override
  Future<WorkspaceChapter> rollbackChapter(
    String workId,
    String chapterId,
    String versionId,
    String? expectedHead,
    int? expectedRevision,
  ) async {
    rollbacks.add((workId, chapterId, versionId));
    final gate = rollbackGate;
    if (gate != null) await gate.future;
    if (failRollback) throw const WorkspaceFailure('synthetic_rollback_failed');
    return super.rollbackChapter(
      workId,
      chapterId,
      versionId,
      expectedHead,
      expectedRevision,
    );
  }
}

class _VersionsHost extends StatelessWidget {
  const _VersionsHost(this.controller);
  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: workbenchTheme(),
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            await showDialog<void>(
              context: context,
              builder: (_) => VersionsDialog(
                controller: controller,
                labels: WorkbenchLabels(AppLocalizations.of(context), false),
              ),
            );
          },
          child: const Text('Open synthetic versions'),
        ),
      ),
    ),
  );
}

Future<WorkspaceController> _controller(
  WidgetTester tester,
  _VersionsRepository repository, {
  bool seedHistory = false,
}) async {
  final controller = WorkspaceController(repository);
  addTearDown(() async {
    final gate = repository.rollbackGate;
    if (gate != null && !gate.isCompleted) gate.complete();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(await controller.closeBarrier(), isTrue);
    controller.dispose();
  });
  await controller.restoreSession();
  if (seedHistory) {
    final first = await controller.prepareConfirmation();
    expect(await controller.confirmChapter(first!.token), isTrue);
    controller.editing.edit('Second synthetic version');
    final second = await controller.prepareConfirmation();
    expect(await controller.confirmChapter(second!.token), isTrue);
  }
  return controller;
}

Future<void> _openVersions(
  WidgetTester tester,
  WorkspaceController controller,
) async {
  tester.useSurface(const Size(1280, 900));
  await tester.pumpWidget(_VersionsHost(controller));
  await tester.tap(find.text('Open synthetic versions'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<VersionEntry> _openRollback(
  WidgetTester tester,
  WorkspaceController controller,
  _VersionsRepository repository,
) async {
  final versions = await repository.storedVersions(
    controller.currentWork!.id,
    controller.currentChapter!.id,
  );
  final historical = versions.firstWhere((version) => !version.isHead);
  await _openVersions(tester, controller);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('version-${historical.id}')));
  await tester.pumpAndSettle();
  final strings = AppLocalizations.of(
    tester.element(find.byType(VersionsDialog)),
  );
  final rollback = find.widgetWithText(TextButton, strings.rollbackAction);
  await tester.ensureVisible(rollback);
  await tester.pumpAndSettle();
  await tester.tap(rollback);
  await tester.pumpAndSettle();
  return historical;
}

Future<void> _acceptRollback(WidgetTester tester) async {
  final strings = AppLocalizations.of(
    tester.element(find.byType(VersionsDialog)),
  );
  await tester.tap(find.widgetWithText(FilledButton, strings.rollbackAction));
  await tester.pump();
}

void main() {
  setUpAll(loadM2Fonts);

  testWidgets('failed loading exposes a stable error and retry reaches empty', (
    tester,
  ) async {
    final first = Completer<List<VersionEntry>>();
    final retry = Completer<List<VersionEntry>>();
    final repository = _VersionsRepository()
      ..responses.addAll([first.future, retry.future]);
    final controller = await _controller(tester, repository);
    await _openVersions(tester, controller);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(repository.reads, [('demo-work', 'demo-chapter')]);
    controller.setWide(true);
    await tester.pump();
    expect(repository.reads, hasLength(1), reason: 'Rebuilds reuse the Future');

    first.completeError(StateError('Synthetic private failure details'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.textContaining('versions_load_failed'), findsOneWidget);
    expect(find.textContaining('private failure'), findsNothing);
    final strings = AppLocalizations.of(
      tester.element(find.byType(VersionsDialog)),
    );
    await tester.tap(find.text(strings.retry));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(repository.reads, hasLength(2));
    controller.setWide(false);
    // 偏好保存有350ms防抖；完成这次模拟时钟后再结束测试。
    await tester.pump(const Duration(milliseconds: 400));
    expect(repository.reads, hasLength(2));
    retry.complete([]);
    await tester.pumpAndSettle();
    expect(find.text(strings.emptyVersions), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('synchronous repository failure has the same retry state', (
    tester,
  ) async {
    final repository = _VersionsRepository()..failSynchronously = true;
    final controller = await _controller(tester, repository);
    await _openVersions(tester, controller);
    await tester.pumpAndSettle();
    expect(find.textContaining('versions_load_failed'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('content previews exact synthetic text and marks the head', (
    tester,
  ) async {
    final repository = _VersionsRepository();
    final controller = await _controller(tester, repository, seedHistory: true);
    await _openVersions(tester, controller);
    await tester.pumpAndSettle();
    final versions = await repository.storedVersions(
      'demo-work',
      'demo-chapter',
    );
    final head = versions.singleWhere((version) => version.isHead);
    await tester.tap(find.byKey(ValueKey('version-${head.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Second synthetic version'), findsOneWidget);
    final strings = AppLocalizations.of(
      tester.element(find.byType(VersionsDialog)),
    );
    expect(find.text(strings.versionCurrent), findsOneWidget);
    expect(
      find.widgetWithText(TextButton, strings.rollbackAction),
      findsNothing,
    );
    expect(repository.reads, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a changed work cannot retry the old dialog against the new work',
    (tester) async {
      final pending = Completer<List<VersionEntry>>();
      final repository = _VersionsRepository()..responses.add(pending.future);
      final controller = await _controller(tester, repository);
      await _openVersions(tester, controller);
      final other = await repository.createWork('Another synthetic work');
      expect(await controller.selectWork(other), isTrue);
      pending.completeError(StateError('Late synthetic failure'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('versions_target_changed'), findsOneWidget);
      expect(repository.reads, [('demo-work', 'demo-chapter')]);
      final strings = AppLocalizations.of(
        tester.element(find.byType(VersionsDialog)),
      );
      expect(find.text(strings.retry), findsNothing);
      expect(find.text(strings.closeDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'switching work during confirmation prevents cross-work rollback',
    (tester) async {
      final repository = _VersionsRepository();
      final controller = await _controller(
        tester,
        repository,
        seedHistory: true,
      );
      await _openRollback(tester, controller, repository);
      final other = await repository.createWork('Another synthetic work');
      expect(await controller.selectWork(other), isTrue);
      await _acceptRollback(tester);
      await tester.pumpAndSettle();
      expect(repository.rollbacks, isEmpty);
      expect(controller.currentWork!.id, other.id);
      expect(find.byType(VersionsDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final fail in [false, true]) {
    testWidgets('rollback ${fail ? 'failure stays open' : 'success closes'}', (
      tester,
    ) async {
      final gate = Completer<void>();
      final repository = _VersionsRepository()
        ..rollbackGate = gate
        ..failRollback = fail;
      final controller = await _controller(
        tester,
        repository,
        seedHistory: true,
      );
      final historical = await _openRollback(tester, controller, repository);
      final bodyBeforeRollback = controller.body;
      await _acceptRollback(tester);
      expect(repository.rollbacks, [
        ('demo-work', 'demo-chapter', historical.id),
      ]);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(VersionsDialog), fail ? findsOneWidget : findsNothing);
      if (fail) {
        expect(
          find.descendant(
            of: find.byType(VersionsDialog),
            matching: find.textContaining('synthetic_rollback_failed'),
          ),
          findsOneWidget,
        );
        expect(controller.body, bodyBeforeRollback);
        expect(find.text(historical.body), findsOneWidget);
        repository.failRollback = false;
        repository.rollbackGate = null;
        final strings = AppLocalizations.of(
          tester.element(find.byType(VersionsDialog)),
        );
        final retryRollback = find.widgetWithText(
          TextButton,
          strings.rollbackAction,
        );
        await tester.ensureVisible(retryRollback);
        await tester.pumpAndSettle();
        await tester.tap(retryRollback);
        await tester.pumpAndSettle();
        await _acceptRollback(tester);
        await tester.pumpAndSettle();
        expect(repository.rollbacks, hasLength(2));
        expect(controller.body, historical.body);
        expect(find.byType(VersionsDialog), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final fail in [false, true]) {
    testWidgets(
      'late rollback ${fail ? 'failure' : 'success'} cannot pop a newer route',
      (tester) async {
        final gate = Completer<void>();
        final repository = _VersionsRepository()
          ..rollbackGate = gate
          ..failRollback = fail;
        final controller = await _controller(
          tester,
          repository,
          seedHistory: true,
        );
        await _openRollback(tester, controller, repository);
        await _acceptRollback(tester);
        final navigator = Navigator.of(
          tester.element(find.byType(VersionsDialog)),
        );
        final covering = navigator.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('New synthetic route')),
          ),
        );
        await tester.pumpAndSettle();
        gate.complete();
        await tester.pumpAndSettle();
        expect(find.text('New synthetic route'), findsOneWidget);
        expect(
          find.byType(VersionsDialog, skipOffstage: false),
          findsOneWidget,
        );
        navigator.pop();
        await covering;
        await tester.pumpAndSettle();
        expect(find.byType(VersionsDialog), findsOneWidget);
        if (fail) {
          expect(
            find.textContaining('synthetic_rollback_failed'),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('late rollback success after disposal leaves the parent route', (
    tester,
  ) async {
    final gate = Completer<void>();
    final repository = _VersionsRepository()..rollbackGate = gate;
    final controller = await _controller(tester, repository, seedHistory: true);
    await _openRollback(tester, controller, repository);
    await _acceptRollback(tester);
    Navigator.of(tester.element(find.byType(VersionsDialog))).pop();
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(VersionsDialog), findsNothing);
    expect(find.text('Open synthetic versions'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
