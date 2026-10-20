// R09 操作一致性测试：资料查阅、带入讨论与完整编辑分离。
// 纯函数验证条目定位与“提交时快照”冻结；注册表层验证只带入指定条目、
// 可移除且各线程引用独立；组件层验证预览只读、动作回调与窗口适配。
// 不使用真实仓库或 FFI，不代表 SQLite/原生资料库行为通过。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/cowrite/discussion_registry.dart';
import 'package:paraselene_flutter/cowrite/discussion_repository.dart';
import 'package:paraselene_flutter/cowrite/discussion_thread.dart';
import 'package:paraselene_flutter/editor/editor_anchor.dart';
import 'package:paraselene_flutter/editor/editor_input_client.dart';
import 'package:paraselene_flutter/editor/editor_viewport.dart';
import 'package:paraselene_flutter/l10n/generated/app_localizations.dart';
import 'package:paraselene_flutter/theme/workbench_theme.dart';
import 'package:paraselene_flutter/workspace/data/synthetic_workspace_repository.dart';
import 'package:paraselene_flutter/workspace/data/workspace_repository.dart';
import 'package:paraselene_flutter/workspace/presentation/lore_preview.dart';

import '../support/m2_harness.dart';
import 'paper_harness.dart';

/// 内存讨论仓库：只满足注册表读取/保存接缝，不验证真实持久化。
class _FakeDiscussionRepository implements DiscussionRepository {
  final saved = <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> listThreads(
    String work,
    String chapter,
  ) async => const [];

  @override
  Future<List<Map<String, dynamic>>> listOperations(
    String work,
    String chapter,
  ) async => const [];

  @override
  Future<Map<String, dynamic>> saveThread(
    String work,
    String chapter,
    String id,
    int? revision,
    Map<String, dynamic> snapshot,
  ) async {
    saved.add(snapshot);
    return {'revision': (revision ?? 0) + 1};
  }

  @override
  Future<void> applyOperation(
    String work,
    String chapter,
    String id,
    int? revision,
  ) async {}

  @override
  Future<void> rejectOperation(String work, String chapter, String id) async {}
}

Map<String, dynamic> _row({
  String id = 'character-a',
  String name = '人物甲',
  String kind = 'character',
  String status = 'confirmed',
  int version = 1,
  String body = '正文',
  String? origin = 'seed',
  bool confirmed = true,
}) => {
  'entry': {
    'id': id,
    'work_id': 'work-a',
    'kind': kind,
    'name': name,
    'aliases': const <String>[],
    'status': status,
    'scope': 'whole',
    'head_version': version,
  },
  'head': {
    'id': 'version-$id-$version',
    'entry_id': id,
    'version': version,
    'body': body,
    'confirmed': confirmed,
    'origin': origin,
  },
};

LorePreviewData _data({String body = '当前正文'}) => LorePreviewData(
  entryId: 'character-a',
  name: '人物甲',
  kind: 'character',
  status: 'confirmed',
  version: 2,
  origin: 'seed',
  confirmed: true,
  body: body,
);

LoreRequestSnapshot _snapshot() => const LoreRequestSnapshot(
  threadId: 'thread-1',
  requestIndex: 0,
  requestText: '请补写雨中的场景',
  name: '人物甲（旧）',
  body: '提交时的旧正文',
);

Future<void> _pumpPreview(
  WidgetTester tester,
  Widget preview, {
  Locale locale = chinese,
  Size size = const Size(1440, 900),
}) async {
  tester.useSurface(size);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: workbenchTheme(),
      home: Scaffold(body: preview),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(loadM2Fonts);

  group('资料条目定位与提交时快照', () {
    test('按条目 ID 精确查行，缺失或空 ID 返回 null', () {
      final rows = [
        _row(id: 'character-a', name: '人物甲'),
        _row(id: 'location-b', name: '地点乙', kind: 'location'),
      ];
      expect(loreRowById(rows, 'location-b')?['entry']['name'], '地点乙');
      expect(loreRowById(rows, 'character-a')?['entry']['name'], '人物甲');
      expect(loreRowById(rows, 'character-z'), isNull);
      expect(loreRowById(rows, ''), isNull);
    });

    test('缺失条目结构与 ID 时预览数据为 null，不用其它条目冒充', () {
      expect(LorePreviewData.fromRow({'entry': null, 'head': null}), isNull);
      final full = LorePreviewData.fromRow(
        _row(id: 'character-a', name: '人物甲', version: 3, body: '甲正文'),
      );
      expect(full, isNotNull);
      expect(full!.entryId, 'character-a');
      expect(full.name, '人物甲');
      expect(full.kind, 'character');
      expect(full.version, 3);
      expect(full.body, '甲正文');
      expect(full.confirmed, isTrue);
      expect(LorePreviewData.fromRow({'head': null}), isNull);
      final noHead = LorePreviewData.fromRow({
        'entry': {'id': 'character-a', 'name': '人物甲', 'kind': 'character'},
        'head': null,
      });
      expect(noHead!.body, '');
      expect(noHead.version, 0);
    });

    test('历史请求快照在提交时冻结，之后改资料不覆盖历史依据', () {
      final thread = DiscussionThread.createChapter('thread-1', 'chapter-a');
      thread.update({
        'requests': [
          {
            'id': 'request-1',
            'text': '请补写雨中的场景',
            'references': [
              {'id': 'character-a', 'name': '人物甲', 'body': '提交时的旧正文'},
              {'id': 'location-b', 'name': '地点乙', 'body': '地点提交时正文'},
            ],
          },
        ],
      });
      final first = loreRequestSnapshots([thread], 'character-a');
      expect(first, hasLength(1));
      expect(first.single.requestText, '请补写雨中的场景');
      expect(first.single.name, '人物甲');
      expect(first.single.body, '提交时的旧正文');
      expect(first.single.threadId, 'thread-1');
      // 模拟资料后来被编辑：历史快照仍是提交时的内容。
      final current = _row(id: 'character-a', body: '后来修改的正文');
      expect(current['head']['body'], '后来修改的正文');
      final again = loreRequestSnapshots([thread], 'character-a');
      expect(again.single.body, '提交时的旧正文');
      expect(
        loreRequestSnapshots([thread], 'location-b').single.body,
        '地点提交时正文',
      );
      expect(loreRequestSnapshots([thread], 'character-z'), isEmpty);
    });

    test('整章线程判断不创建线程，引用只属于本章', () async {
      final repository = _FakeDiscussionRepository();
      final registry = DiscussionRegistry(repository);
      addTearDown(registry.dispose);
      await registry.open('work-a', 'chapter-a');
      expect(registry.threads, isEmpty);
      expect(chapterDiscussion(registry.threads), isNull);
      expect(registry.threads, isEmpty);
      final thread = registry.chapterThread();
      expect(chapterDiscussion(registry.threads), same(thread));
      expect(loreEntryAttached(registry.threads, 'character-a'), isFalse);
    });
  });

  group('带入讨论的引用集合', () {
    test('只带入指定条目，可移除，且重复带入不重复', () async {
      final repository = _FakeDiscussionRepository();
      final registry = DiscussionRegistry(repository);
      addTearDown(registry.dispose);
      await registry.open('work-a', 'chapter-a');
      final chapter = registry.chapterThread();
      attachLoreReference(registry, 'character-a');
      expect(loreAttachedIds(chapter), ['character-a']);
      attachLoreReference(registry, 'character-a');
      expect(loreAttachedIds(chapter), ['character-a']);
      attachLoreReference(registry, 'location-b');
      expect(loreAttachedIds(chapter), ['character-a', 'location-b']);
      expect(loreEntryAttached(registry.threads, 'character-a'), isTrue);
      removeLoreReference(registry, 'character-a');
      expect(loreAttachedIds(chapter), ['location-b']);
      removeLoreReference(registry, 'character-a');
      expect(loreAttachedIds(chapter), ['location-b']);
      expect(loreEntryAttached(registry.threads, 'character-a'), isFalse);
    });

    test('选区线程与整章线程引用互不串写', () async {
      final repository = _FakeDiscussionRepository();
      final registry = DiscussionRegistry(repository);
      addTearDown(registry.dispose);
      await registry.open('work-a', 'chapter-a');
      final chapter = registry.chapterThread();
      final selection = registry.create(EditorAnchor.capture('正文段落', 0, 2));
      selection.update({
        'attached': ['location-b'],
      });
      attachLoreReference(registry, 'character-a');
      expect(loreAttachedIds(chapter), ['character-a']);
      expect(loreAttachedIds(selection), ['location-b']);
      removeLoreReference(registry, 'character-a');
      expect(loreAttachedIds(chapter), isEmpty);
      expect(loreAttachedIds(selection), ['location-b']);
    });

    test('没有打开章节时沿用既有整章规则报错，不冒充成功', () async {
      final repository = _FakeDiscussionRepository();
      final registry = DiscussionRegistry(repository);
      addTearDown(registry.dispose);
      await registry.open('work-a', null);
      expect(
        () => attachLoreReference(registry, 'character-a'),
        throwsA(
          isA<WorkspaceFailure>().having(
            (failure) => failure.code,
            'code',
            'no_open_chapter',
          ),
        ),
      );
    });

    test('引用上限为 32 项，超出时报 valid_input 且不改已有集合', () async {
      final repository = _FakeDiscussionRepository();
      final registry = DiscussionRegistry(repository);
      addTearDown(registry.dispose);
      await registry.open('work-a', 'chapter-a');
      final chapter = registry.chapterThread();
      final full = [for (var index = 0; index < 32; index++) 'entry-$index'];
      registry.attachReferences(chapter.id, full);
      expect(loreAttachedIds(chapter), hasLength(32));
      expect(
        () => attachLoreReference(registry, 'entry-extra'),
        throwsA(
          isA<WorkspaceFailure>().having(
            (failure) => failure.code,
            'code',
            'invalid_input',
          ),
        ),
      );
      expect(loreAttachedIds(chapter), full);
    });
  });

  group('只读预览卡', () {
    testWidgets('展示当前资料与提交时快照，预览本身不附加', (tester) async {
      var attachCalls = 0;
      var removeCalls = 0;
      var editCalls = 0;
      var closeCalls = 0;
      await _pumpPreview(
        tester,
        LorePreview(
          data: _data(),
          history: [_snapshot()],
          attached: false,
          onAttach: () {
            attachCalls += 1;
            return true;
          },
          onRemove: () {
            removeCalls += 1;
            return true;
          },
          onEdit: () => editCalls += 1,
          onClose: () => closeCalls += 1,
        ),
      );
      expect(find.byKey(const ValueKey('lore-preview-card')), findsOneWidget);
      expect(find.text('人物甲'), findsOneWidget);
      expect(find.textContaining('人物 · v2 · confirmed · seed'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('lore-preview-current')),
        findsOneWidget,
      );
      expect(find.text('当前正文'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('lore-preview-history')),
        findsOneWidget,
      );
      expect(find.text('历史请求中的引用（提交时快照）'), findsOneWidget);
      expect(find.text('提交时的旧正文'), findsOneWidget);
      expect(find.text('人物甲（旧）'), findsOneWidget);
      expect(find.text('仅预览：不会带入讨论，也不会发送给模型。'), findsOneWidget);
      // 打开预览不应触发带入：动作只能由作者明确点击。
      expect(attachCalls, 0);
      expect(removeCalls, 0);

      await tester.tap(find.byKey(const ValueKey('lore-preview-attach')));
      await tester.pump();
      expect(attachCalls, 1);
      expect(find.byKey(const ValueKey('lore-preview-remove')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('lore-preview-remove')));
      await tester.pump();
      expect(removeCalls, 1);
      expect(find.byKey(const ValueKey('lore-preview-attach')), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const ValueKey('lore-preview-view-current-0')),
      );
      await tester.tap(
        find.byKey(const ValueKey('lore-preview-view-current-0')),
      );
      await tester.pumpAndSettle();
      expect(find.text('当前正文'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('lore-preview-edit')));
      expect(editCalls, 1);
      await tester.tap(find.byKey(const ValueKey('lore-preview-close')));
      expect(closeCalls, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('带入库失败时不切换本地按钮状态', (tester) async {
      await _pumpPreview(
        tester,
        LorePreview(
          data: _data(),
          onAttach: () => false,
          onRemove: () => false,
          onClose: () {},
        ),
      );
      await tester.tap(find.byKey(const ValueKey('lore-preview-attach')));
      await tester.pump();
      expect(find.byKey(const ValueKey('lore-preview-attach')), findsOneWidget);
      expect(find.byKey(const ValueKey('lore-preview-remove')), findsNothing);
    });

    testWidgets('窄窗渲染同一内容且不溢出', (tester) async {
      await _pumpPreview(
        tester,
        LorePreview(
          data: _data(),
          history: [_snapshot()],
          onAttach: () => true,
          onEdit: () {},
          onClose: () {},
        ),
        size: const Size(420, 760),
      );
      expect(find.byKey(const ValueKey('lore-preview-card')), findsOneWidget);
      expect(find.text('当前内容'), findsOneWidget);
      expect(find.text('带入讨论'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('英文界面显示对应文案', (tester) async {
      await _pumpPreview(
        tester,
        LorePreview(
          data: _data(),
          history: [_snapshot()],
          onAttach: () => true,
          onClose: () {},
        ),
        locale: const Locale('en'),
      );
      expect(find.text('Current content'), findsOneWidget);
      expect(find.text('Bring into discussion'), findsOneWidget);
      expect(
        find.text('Preview only. Nothing is attached or sent to the model.'),
        findsOneWidget,
      );
      expect(
        find.text('References in past requests (snapshot at submission)'),
        findsOneWidget,
      );
      expect(find.text('View current material'), findsOneWidget);
    });

    testWidgets('预览不附加，点带入只加入指定条目且可移除', (tester) async {
      final repository = _FakeDiscussionRepository();
      final registry = DiscussionRegistry(repository);
      addTearDown(registry.dispose);
      await registry.open('work-a', 'chapter-a');
      final chapter = registry.chapterThread();
      await _pumpPreview(
        tester,
        LorePreview(
          data: _data(),
          attached: loreEntryAttached(registry.threads, 'character-a'),
          onAttach: () {
            try {
              attachLoreReference(registry, 'character-a');
              return true;
            } on WorkspaceFailure {
              return false;
            }
          },
          onRemove: () {
            removeLoreReference(registry, 'character-a');
            return true;
          },
          onClose: () {},
        ),
      );
      // 仅看预览不会改变 attached 数量。
      expect(loreAttachedIds(chapter), isEmpty);
      await tester.tap(find.byKey(const ValueKey('lore-preview-attach')));
      await tester.pump();
      expect(loreAttachedIds(chapter), ['character-a']);
      expect(loreAttachedIds(registry.threads.single), ['character-a']);
      await tester.tap(find.byKey(const ValueKey('lore-preview-remove')));
      await tester.pump();
      expect(loreAttachedIds(chapter), isEmpty);
      // 等注册表防抖保存完成，避免测试结束时残留计时器。
      await tester.pump(const Duration(milliseconds: 400));
    });
  });

  group('长章中部查阅返回', () {
    testWidgets('位置、选区与一次 undo 都延续', (tester) async {
      final repository = SyntheticWorkspaceRepository(withDemo: true);
      final controller = await pumpPaperWorkbench(
        tester,
        repository: repository,
      );
      addTearDown(() => disposePaperController(controller));
      var state = tester.state<EditorViewportState>(find.byKey(manuscriptKey));
      (state.controller as EditorInputClient).load(longBody());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      state = tester.state<EditorViewportState>(find.byKey(manuscriptKey));
      final client = state.controller as EditorInputClient;
      state.scroll.jumpTo(420);
      await tester.pump();
      client.select(const TextSelection(baseOffset: 120, extentOffset: 160));
      await tester.pump();
      final beforeReplace = state.controller.document.raw;
      client.replace('替换后的段落');
      await tester.pump();
      final edited = state.controller.document.raw;
      expect(edited, isNot(beforeReplace));
      final scrollBefore = state.scroll.offset;
      final selectionBefore = state.controller.value.selection;

      // 模拟从正文打开资料预览，再关闭返回；不重建编辑器。
      unawaited(
        showDialog<void>(
          context: tester.element(find.byKey(manuscriptKey)),
          builder: (dialogContext) => LorePreview(
            data: _data(),
            history: [_snapshot()],
            onClose: () => Navigator.of(dialogContext).pop(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('lore-preview-card')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('lore-preview-close')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('lore-preview-card')), findsNothing);

      state = tester.state<EditorViewportState>(find.byKey(manuscriptKey));
      expect(state.scroll.offset, closeTo(scrollBefore, 2));
      expect(state.controller.value.selection, selectionBefore);
      expect(state.controller.document.raw, edited);
      // 查阅不消耗撤销历史：一次 undo 回到替换前。
      (state.controller as EditorInputClient).undo();
      await tester.pump();
      expect(state.controller.document.raw, beforeReplace);
      // 等阅读位置偏好防抖写盘完成，避免残留计时器。
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    });
  });
}
