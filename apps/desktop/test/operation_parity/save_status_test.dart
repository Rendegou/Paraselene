// R01/R02 操作一致性测试：保存状态必须随 EditingSession 实时刷新，且失败恢复在
// 宽窗与 360×720/200% 窄窗都可见、可鼠标与键盘到达。
// 仅使用合成仓库与门闩保存，不连接真实 FFI、数据库或作者材料。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/domain/editing/save_state.dart';
import 'package:paraselene_flutter/editor/editor_viewport.dart';
import 'package:paraselene_flutter/l10n/generated/app_localizations.dart';
import 'package:paraselene_flutter/theme/workbench_theme.dart';
import 'package:paraselene_flutter/workspace/data/synthetic_workspace_repository.dart';
import 'package:paraselene_flutter/workspace/data/workspace_repository.dart';
import 'package:paraselene_flutter/workspace/presentation/workbench_screen.dart';
import 'package:paraselene_flutter/workspace/workspace_controller.dart';

import '../support/m2_harness.dart';

void main() {
  setUpAll(loadM2Fonts);

  testWidgets('保存状态随 EditingSession 刷新：dirty→saving→saved，不重建编辑器', (
    tester,
  ) async {
    final repository = _GatedRepository();
    final controller = await _pumpScreen(tester, repository);

    final epochBefore = controller.editing.contentEpoch;
    final editorBefore = tester
        .state<EditorViewportState>(find.byType(EditorViewport))
        .controller;

    repository.holdNextSave();
    controller.editing.edit('${controller.body}雨');
    await tester.pump();
    expect(find.text('有未保存更改'), findsOneWidget);
    expect(controller.editing.saveState?.status, SaveStatus.dirty);

    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('保存中…'), findsOneWidget);
    expect(controller.editing.saveState?.status, SaveStatus.saving);

    repository.releaseSave();
    await tester.pump();
    await tester.pump();
    expect(find.text('已保存'), findsOneWidget);
    expect(controller.editing.saveState?.status, SaveStatus.saved);

    // 保存状态更新不得重置正文、输入客户端或撤销历史。
    expect(controller.editing.contentEpoch, epochBefore);
    expect(
      tester.state<EditorViewportState>(find.byType(EditorViewport)).controller,
      same(editorBefore),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('保存失败立即可见，就地重试成功后回到已保存', (tester) async {
    final repository = _GatedRepository();
    final controller = await _pumpScreen(tester, repository);

    repository.holdNextSave();
    repository.failNext = const WorkspaceFailure('disk_full');
    controller.editing.edit('${controller.body}灯');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    repository.releaseSave();
    await tester.pump();
    await tester.pump();

    expect(controller.editing.saveState?.status, SaveStatus.error);
    expect(find.byKey(const ValueKey('save-error-banner')), findsOneWidget);
    expect(find.text('保存失败——草稿已保留'), findsWidgets);
    expect(find.text('重试保存'), findsOneWidget);

    final callsBefore = repository.saveCalls;
    repository.holdNextSave();
    await tester.tap(find.text('重试保存'));
    await tester.pump();
    expect(repository.saveCalls, callsBefore + 1);
    expect(find.text('保存中…'), findsOneWidget);
    repository.releaseSave();
    await tester.pump();
    await tester.pump();
    expect(find.text('已保存'), findsOneWidget);
    expect(find.byKey(const ValueKey('save-error-banner')), findsNothing);
    expect(controller.editing.saveState?.status, SaveStatus.saved);
    expect(tester.takeException(), isNull);
  });

  testWidgets('保存冲突也立即显示并保留草稿基线提示', (tester) async {
    final repository = _GatedRepository();
    final controller = await _pumpScreen(tester, repository);

    repository.holdNextSave();
    repository.failNext = const WorkspaceFailure('revision_conflict');
    controller.editing.edit('${controller.body}店');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    repository.releaseSave();
    await tester.pump();
    await tester.pump();

    expect(controller.editing.saveState?.status, SaveStatus.conflict);
    expect(find.byKey(const ValueKey('save-error-banner')), findsOneWidget);
    expect(find.text('保存冲突——草稿已保留'), findsWidgets);
    expect(find.text('重试保存'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('360×720/200% 窄窗：错误图标打开恢复面板，键盘重试', (tester) async {
    final repository = _GatedRepository();
    final controller = await _pumpScreen(
      tester,
      repository,
      size: const Size(360, 720),
      scale: 2,
    );

    repository.holdNextSave();
    repository.failNext = const WorkspaceFailure('disk_full');
    controller.editing.edit('${controller.body}门');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    repository.releaseSave();
    await tester.pump();
    await tester.pump();

    final errorIcon = find.byKey(const ValueKey('save-status-error-icon'));
    expect(errorIcon, findsOneWidget);
    expect(find.byKey(const ValueKey('save-error-banner')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(errorIcon);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('save-recovery-panel')), findsOneWidget);
    expect(find.text('保存失败——草稿已保留'), findsWidgets);
    final panel = find.byKey(const ValueKey('save-recovery-panel'));
    expect(
      find.descendant(of: panel, matching: find.text('重试保存')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: panel, matching: find.text('导出草稿')),
      findsOneWidget,
    );
    expect(find.textContaining('disk_full'), findsWidgets);
    expect(tester.takeException(), isNull);

    // 恢复面板的主操作自动获得焦点，Enter 即可重试（键盘可达）。
    repository.failNext = null;
    final callsBefore = repository.saveCalls;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(repository.saveCalls, callsBefore + 1);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('save-recovery-panel')), findsNothing);
    expect(find.byKey(const ValueKey('save-error-banner')), findsNothing);
    expect(find.byKey(const ValueKey('save-status-dot')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('恢复面板重试再次失败时保留上下文，成功才关闭', (tester) async {
    final repository = _GatedRepository();
    final controller = await _pumpScreen(
      tester,
      repository,
      size: const Size(360, 720),
      scale: 2,
    );
    repository.failNext = const WorkspaceFailure('disk_full');
    controller.editing.edit('${controller.body}保存失败回归');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-status-error-icon')));
    await tester.pumpAndSettle();
    final panel = find.byKey(const ValueKey('save-recovery-panel'));
    expect(panel, findsOneWidget);
    repository.failNext = const WorkspaceFailure('disk_full');
    await tester.tap(find.descendant(of: panel, matching: find.text('重试保存')));
    await tester.pumpAndSettle();
    expect(panel, findsOneWidget);
    expect(find.byKey(const ValueKey('save-recovery-code')), findsOneWidget);
    expect(controller.editing.saveState?.status, SaveStatus.error);
    await tester.tap(find.descendant(of: panel, matching: find.text('重试保存')));
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(controller.editing.saveState?.status, SaveStatus.saved);
    expect(tester.takeException(), isNull);
  });
}

/// 门闩仓库：保存先停在可控 Future 上，便于观察 dirty/saving/saved 与失败注入。
final class _GatedRepository extends SyntheticWorkspaceRepository {
  _GatedRepository() : super(withDemo: true);

  Completer<void>? _gate;
  bool _hold = false;

  /// 注入下一次保存的失败；null 表示成功。
  WorkspaceFailure? failNext;

  /// 已进入保存接缝的次数（含失败与重试）。
  int saveCalls = 0;

  void holdNextSave() => _hold = true;

  void releaseSave() {
    _hold = false;
    final gate = _gate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  Future<ChapterDocument> saveDocument(
    String workId,
    String chapterId,
    int? expectedRevision,
    String body,
  ) async {
    saveCalls++;
    if (_hold) {
      _hold = false;
      _gate = Completer<void>();
      await _gate!.future;
    }
    final failure = failNext;
    failNext = null;
    if (failure != null) throw failure;
    return super.saveDocument(workId, chapterId, expectedRevision, body);
  }
}

/// 用真实工作台外壳泵起单个 controller；返回已恢复会话的 controller。
Future<WorkspaceController> _pumpScreen(
  WidgetTester tester,
  _GatedRepository repository, {
  Size size = const Size(1440, 900),
  double scale = 1,
}) async {
  tester.useSurface(size);
  final controller = WorkspaceController(repository);
  await controller.restoreSession();
  addTearDown(() async {
    repository.failNext = null;
    repository.releaseSave();
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    final state = controller.editing.saveState;
    if (state != null && state.dirty) {
      try {
        await controller.editing.retrySave();
      } on WorkspaceFailure {
        // 测试结束时仅需释放控制器；未恢复的失败由断言负责。
      }
    }
    controller.dispose();
  });
  await tester.pumpWidget(
    Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: true,
        ),
        child: MaterialApp(
          locale: chinese,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: workbenchTheme(),
          home: WorkbenchScreen(
            controller: controller,
            locale: chinese,
            onLocaleChanged: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return controller;
}
