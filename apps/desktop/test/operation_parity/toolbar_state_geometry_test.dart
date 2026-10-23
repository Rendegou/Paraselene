// 顶栏状态几何：英文长保存错误、讨论选区和索引同时存在仍保留恢复与键盘入口。
// 仅使用合成仓库和本地字体；不访问作者库、凭据、FFI 或模型。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/domain/editing/save_state.dart';
import 'package:paraselene_flutter/editor/editor_anchor.dart';
import 'package:paraselene_flutter/editor/editor_viewport.dart';
import 'package:paraselene_flutter/l10n/generated/app_localizations.dart';
import 'package:paraselene_flutter/theme/workbench_theme.dart';
import 'package:paraselene_flutter/workspace/data/workspace_repository.dart';
import 'package:paraselene_flutter/workspace/presentation/editor_status.dart';
import 'package:paraselene_flutter/workspace/presentation/toolbar_more_menu.dart';
import 'package:paraselene_flutter/workspace/presentation/workbench_screen.dart';
import 'package:paraselene_flutter/workspace/presentation/workbench_toolbar.dart';
import 'package:paraselene_flutter/workspace/workspace_controller.dart';

import '../support/m2_harness.dart';
import 'review_fixes_test.dart' show ReviewRepository;

void main() {
  setUpAll(loadM2Fonts);
  late bool previousFatalHitWarning;
  setUp(() {
    previousFatalHitWarning = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
  });
  tearDown(() {
    WidgetController.hitTestWarningShouldBeFatal = previousFatalHitWarning;
  });

  for (final width in [1040.0, 1060.0]) {
    for (final failure in ['revision_conflict', 'disk_full']) {
      testWidgets('英文长保存状态 $failure，窗口 $width 保留讨论与恢复', (tester) async {
        final fixture = await _pump(tester, width: width);
        final controller = fixture.controller;
        fixture.repository.failNext = WorkspaceFailure(failure);
        controller.editing.edit('${controller.body}\nSynthetic pending draft.');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        await tester.pump();
        _selectBody(tester);
        await tester.pump();

        expect(
          controller.editing.saveState?.status,
          failure == 'revision_conflict'
              ? SaveStatus.conflict
              : SaveStatus.error,
        );
        final toolbar = tester.widget<WorkbenchToolbar>(
          find.byType(WorkbenchToolbar),
        );
        final s = toolbar.strings;
        expect(toolbar.actions!.canDiscuss, isTrue);
        expect(toolbar.actions!.threads, hasLength(1));
        expect(find.byTooltip(s.discussionIndex(1)), findsOneWidget);
        expect(find.byTooltip(s.findInChapter), findsOneWidget);
        expect(find.byTooltip(s.moreTools), findsOneWidget);
        expect(tester.takeException(), isNull);

        final draft = controller.body;
        final recovery = find.descendant(
          of: find.byType(SaveStatusIndicator),
          matching: find.byWidgetPredicate(
            (widget) => widget is TextButton || widget is IconButton,
          ),
        );
        expect(recovery, findsOneWidget);
        final hit = tester.getRect(recovery);
        expect(hit.height, greaterThanOrEqualTo(48));
        expect(hit.top, greaterThanOrEqualTo(0));
        expect(hit.bottom, lessThanOrEqualTo(900));
        await tester.tapAt(Offset(hit.center.dx, hit.bottom - 2));
        await tester.pumpAndSettle();
        final panel = find.byKey(const ValueKey('save-recovery-panel'));
        expect(panel, findsOneWidget);
        expect(
          find.descendant(of: panel, matching: find.text(s.retrySave)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: panel, matching: find.text(s.exportDraft)),
          findsOneWidget,
        );
        expect(controller.body, draft);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(panel, findsNothing);
        expect(controller.body, draft);
        expect(controller.discussions!.threads, hasLength(1));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('更多菜单有局部焦点且 Enter/Escape 不改变正文或命中边界', (tester) async {
    final fixture = await _pump(tester, width: 1040);
    final controller = fixture.controller;
    final before = controller.body;
    final more = find.byType(ToolbarMoreMenu);
    final bounds = tester.getRect(more);
    expect(bounds.height, greaterThanOrEqualTo(48));
    final icon = find.descendant(of: more, matching: find.byType(Icon)).first;
    final focus = Focus.of(tester.element(icon));
    // 先以真实键盘事件进入 traditional highlight，不能把触摸焦点当键盘焦点。
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasPrimaryFocus, isTrue);
    final material = tester.widget<Material>(
      find.descendant(of: more, matching: find.byType(Material)).first,
    );
    expect((material.shape! as OutlinedBorder).side.width, 2);
    expect(
      (material.shape! as OutlinedBorder).side.color,
      WorkbenchTokens.accent,
    );
    expect(tester.getRect(more), bounds);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final s = AppLocalizations.of(tester.element(find.byType(WorkbenchScreen)));
    expect(find.text(s.refreshSources), findsOneWidget);
    expect(controller.body, before);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text(s.refreshSources), findsNothing);
    expect(tester.getRect(more), bounds);
    expect(focus.hasPrimaryFocus, isTrue);
    expect(controller.body, before);
    expect(tester.takeException(), isNull);
  });
}

final class _GeometryRepository extends ReviewRepository {
  WorkspaceFailure? failNext;

  @override
  Future<ChapterDocument> saveDocument(
    String workId,
    String chapterId,
    int? expectedRevision,
    String body,
  ) async {
    final failure = failNext;
    failNext = null;
    if (failure != null) throw failure;
    return super.saveDocument(workId, chapterId, expectedRevision, body);
  }
}

Future<({WorkspaceController controller, _GeometryRepository repository})>
_pump(WidgetTester tester, {required double width}) async {
  tester.useSurface(Size(width, 900));
  final repository = _GeometryRepository();
  final controller = WorkspaceController(repository);
  await controller.restoreSession();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    repository.failNext = null;
    repository.fake.finish();
    if (controller.editing.saveState?.dirty ?? false) {
      await controller.editing.retrySave();
    }
    await controller.editing.flushAll();
    await controller.discussions?.flush();
    controller.dispose();
    await tester.pump();
  });
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: workbenchTheme(),
      home: WorkbenchScreen(
        controller: controller,
        locale: const Locale('en'),
        onLocaleChanged: (_) {},
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  final thread = controller.discussions!.create(
    EditorAnchor.capture(controller.body, 0, 4),
  );
  await tester.pump();
  await tester.tap(find.byKey(ValueKey('thread-marker-open-${thread.id}')));
  await tester.pumpAndSettle();
  _selectBody(tester);
  await tester.pump();
  return (controller: controller, repository: repository);
}

void _selectBody(WidgetTester tester) {
  tester
      .state<EditorViewportState>(find.byType(EditorViewport))
      .controller
      .select(const TextSelection(baseOffset: 0, extentOffset: 4));
}
