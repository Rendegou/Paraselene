// R11：出处装饰的 loading/empty/error/content 四态、失败重试与旧响应隔离。
// 仅覆盖 Dart widget/controller 行为；真实 FFI 读取与桌面 IME 另列 NOT_RUN。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/editor/editor_source_mark.dart';
import 'package:paraselene_flutter/editor/editor_viewport.dart';
import 'package:paraselene_flutter/l10n/generated/app_localizations.dart';
import 'package:paraselene_flutter/lore/lore_source_view.dart';
import 'package:paraselene_flutter/lore/source_mark_controller.dart';
import 'package:paraselene_flutter/theme/workbench_theme.dart';
import 'package:paraselene_flutter/workspace/data/synthetic_workspace_repository.dart';
import 'package:paraselene_flutter/workspace/presentation/editor_source_menu.dart';

import 'paper_harness.dart';
import '../support/m2_harness.dart';

/// 可控出处读取器：每个请求都由测试决定何时成功或失败。
final class _FakeSourceMarks implements SourceMarkRepository {
  final requests = <Completer<Map<String, dynamic>>>[];
  final bodies = <String>[];

  @override
  Future<Map<String, dynamic>> sourceMarks(
    String work,
    String chapter,
    String body,
  ) {
    bodies.add(body);
    final next = Completer<Map<String, dynamic>>();
    requests.add(next);
    return next.future;
  }
}

/// 合成仓库实现 [SourceMarkHost]，让工作台注入受控的出处读取器。
final class _SourceRepository extends SyntheticWorkspaceRepository
    implements SourceMarkHost {
  _SourceRepository({required this.source, super.withDemo});
  final _FakeSourceMarks source;

  @override
  SourceMarkRepository get sourceMarks => source;
}

Map<String, dynamic> _snapshot(
  String? head,
  List<Map<String, dynamic>> marks,
) => {'headVersion': head, 'marks': marks};

EditorViewportState _viewport(WidgetTester tester) =>
    tester.state<EditorViewportState>(find.byKey(manuscriptKey));

void main() {
  setUpAll(loadM2Fonts);

  for (final scale in [1.0, 2.0]) {
    testWidgets('出处重试和菜单有完整命中与焦点边界，字号 $scale', (tester) async {
      final source = _FakeSourceMarks();
      final controller = await pumpPaperWorkbench(
        tester,
        repository: _SourceRepository(source: source, withDemo: true),
        textScale: scale,
      );
      addTearDown(() => disposePaperController(controller));
      source.requests[0].completeError(StateError('synthetic source failure'));
      await tester.pump();
      await tester.pump();
      final retry = find.byKey(const ValueKey('source-marks-retry'));
      expect(tester.getSize(retry).height, greaterThanOrEqualTo(48));
      final retryText = find.descendant(of: retry, matching: find.byType(Text));
      Focus.of(tester.element(retryText)).requestFocus();
      await tester.pump();
      expect(Focus.of(tester.element(retryText)).hasFocus, isTrue);
      expect(Focus.of(tester.element(retryText)).hasPrimaryFocus, isTrue);
      final material = tester.widget<Material>(
        find.descendant(of: retry, matching: find.byType(Material)).first,
      );
      expect((material.shape! as OutlinedBorder).side.width, 2);
      expect(
        (material.shape! as OutlinedBorder).side.color,
        WorkbenchTokens.accent,
      );
      final bodyBeforeActivation = controller.body;
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(
        controller.body,
        bodyBeforeActivation,
        reason: '聚焦出处控件时 Enter 不能被外层编辑器当作正文换行',
      );
      expect(source.requests, hasLength(2));
      source.requests[1].complete(
        _snapshot(null, [
          {'entryId': 'source', 'name': '出处甲', 'from': 0, 'to': 2},
        ]),
      );
      await tester.pump();
      await tester.pump();
      final menu = find.byKey(const ValueKey('source-marks-menu'));
      final bounds = tester.getRect(menu);
      expect(bounds.height, greaterThanOrEqualTo(48));
      final menuText = find.descendant(of: menu, matching: find.byType(Text));
      Focus.of(tester.element(menuText)).requestFocus();
      await tester.pump();
      expect(Focus.of(tester.element(menuText)).hasFocus, isTrue);
      final menuMaterial = tester.widget<Material>(
        find.descendant(of: menu, matching: find.byType(Material)).first,
      );
      expect((menuMaterial.shape! as OutlinedBorder).side.width, 2);
      expect(
        (menuMaterial.shape! as OutlinedBorder).side.color,
        WorkbenchTokens.accent,
      );
      // 点透明命中区的下缘，而不是只点文字中心。
      await tester.tapAt(Offset(bounds.center.dx, bounds.bottom - 2));
      await tester.pumpAndSettle();
      expect(find.text('出处甲'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('loading → empty 四态可见且正文仍可写', (tester) async {
    final source = _FakeSourceMarks();
    final repository = _SourceRepository(source: source, withDemo: true);
    final controller = await pumpPaperWorkbench(tester, repository: repository);
    addTearDown(() => disposePaperController(controller));

    // 首次加载尚未完成：显示加载中，而不是“无出处”。
    expect(find.byKey(const ValueKey('source-marks-loading')), findsOneWidget);
    expect(find.text('出处加载中…'), findsOneWidget);
    expect(source.requests, hasLength(1));

    source.requests[0].complete(_snapshot(null, []));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('source-marks-loading')), findsNothing);
    expect(find.byKey(const ValueKey('source-marks-empty')), findsOneWidget);
    expect(find.text('本章暂无出处'), findsOneWidget);
    expect(find.text('出处未能加载，请刷新后重试。'), findsNothing);

    // 出处失败/空态都不阻塞正文编辑。
    controller.editing.edit('${controller.body}改');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(controller.body, endsWith('改'));
  });

  testWidgets('加载失败显式提示并可重试恢复', (tester) async {
    final source = _FakeSourceMarks();
    final repository = _SourceRepository(source: source, withDemo: true);
    final controller = await pumpPaperWorkbench(tester, repository: repository);
    addTearDown(() => disposePaperController(controller));

    source.requests[0].completeError(StateError('source read failed'));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('source-marks-retry')), findsOneWidget);
    expect(find.text('出处未能加载，请刷新后重试。'), findsOneWidget);
    expect(find.byKey(const ValueKey('source-marks-empty')), findsNothing);
    expect(find.text('本章暂无出处'), findsNothing);

    // 重试入口显式发起下一次读取，成功后回到空态。
    await tester.tap(find.byKey(const ValueKey('source-marks-retry')));
    await tester.pump();
    expect(source.requests, hasLength(2));
    source.requests[1].complete(_snapshot(null, []));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('source-marks-retry')), findsNothing);
    expect(find.byKey(const ValueKey('source-marks-empty')), findsOneWidget);
  });

  testWidgets('旧章节的迟到响应不会装饰当前正文', (tester) async {
    final source = _FakeSourceMarks();
    final repository = _SourceRepository(source: source, withDemo: false);
    final work = await repository.createWork('作品');
    final first = await repository.createChapter(work.id, '第一章');
    await repository.saveDocument(work.id, first.id, null, '第一章正文');
    final second = await repository.createChapter(work.id, '第二章');
    await repository.saveDocument(work.id, second.id, null, '第二章正文');
    await repository.selectWork(work.id);
    final controller = await pumpPaperWorkbench(tester, repository: repository);
    addTearDown(() => disposePaperController(controller));

    expect(controller.currentChapter?.id, first.id);
    expect(source.requests, hasLength(1));
    await tester.pump();

    await controller.selectChapter(controller.chapters.last);
    await tester.pump();
    // 让切换章节触发的 UI 会话偏好防抖计时器落地，避免测试结束时仍有挂起计时器。
    await tester.pump(const Duration(milliseconds: 400));
    expect(controller.currentChapter?.id, second.id);
    expect(source.requests.length, greaterThanOrEqualTo(2));

    // 新章节先成功：一个真实标记。
    source.requests[1].complete(
      _snapshot(null, [
        {'entryId': 'new', 'name': '人物乙', 'from': 0, 'to': 2},
      ]),
    );
    await tester.pump();
    await tester.pump();
    expect(_viewport(tester).scene!.sourceMarks, hasLength(1));

    // 旧章节的迟到响应即使更晚返回也不能覆盖当前正文装饰。
    source.requests[0].complete(
      _snapshot(null, [
        {'entryId': 'old-a', 'name': '人物甲', 'from': 0, 'to': 1},
        {'entryId': 'old-b', 'name': '地点甲', 'from': 1, 'to': 3},
      ]),
    );
    await tester.pump();
    await tester.pump();
    expect(_viewport(tester).scene!.sourceMarks, hasLength(1));
    expect(controller.body, '第二章正文');
  });

  testWidgets('出处菜单与空态/失败态文案互相区分', (tester) async {
    Future<void> pumpMenu({
      required List<EditorSourceMark> marks,
      required bool failed,
      bool loading = false,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'Hans'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: EditorSourceMenu(
              marks: marks,
              failed: failed,
              loading: loading,
              enabled: true,
              onOpen: (_) {},
              onRefresh: () {},
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await pumpMenu(marks: const [], failed: false, loading: true);
    expect(find.text('出处加载中…'), findsOneWidget);
    expect(find.text('本章暂无出处'), findsNothing);

    await pumpMenu(marks: const [], failed: false);
    expect(find.text('本章暂无出处'), findsOneWidget);
    expect(find.text('出处未能加载，请刷新后重试。'), findsNothing);

    await pumpMenu(marks: const [], failed: true);
    expect(find.text('出处未能加载，请刷新后重试。'), findsOneWidget);
    expect(find.text('本章暂无出处'), findsNothing);
    expect(find.text('刷新出处'), findsOneWidget);
  });

  testWidgets('历史出处显示记录版本原文且禁用跳转', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'Hans'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: LoreSourceView(
            source: {
              'body': '旧版本正文',
              'anchor': {'startChar': 0, 'endChar': 3, 'isCurrent': false},
            },
            onOpen: () => opened = true,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('历史出处'), findsWidgets);
    // 历史出处位于默认折叠的分组里，先展开才能看到记录版本原文与跳转按钮。
    await tester.tap(find.text('历史出处').first);
    await tester.pumpAndSettle();
    expect(find.text('历史出处'), findsNWidgets(2));
    expect(find.textContaining('旧版本正文', findRichText: true), findsOneWidget);
    final locate = find.widgetWithText(TextButton, '定位到来源章节');
    expect(locate, findsOneWidget);
    expect(tester.widget<TextButton>(locate).onPressed, isNull);
    expect(opened, isFalse);
  });
}
