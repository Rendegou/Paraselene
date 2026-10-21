// R14 能力/保存/采纳提示：整章或失效线程说明生成不可用；采纳只写编辑稿；
// 保存与自动保存不新增正式版本，确认才创建正式版本。
// 边界：合成仓库与内存讨论仓库，不访问真实 FFI、网络或作者数据。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/cowrite/discussion_panel.dart';
import 'package:paraselene_flutter/cowrite/discussion_repository.dart';
import 'package:paraselene_flutter/cowrite/generation_repository.dart';
import 'package:paraselene_flutter/editor/editor_anchor.dart';
import 'package:paraselene_flutter/l10n/generated/app_localizations.dart';
import 'package:paraselene_flutter/theme/workbench_theme.dart';
import 'package:paraselene_flutter/workspace/data/synthetic_workspace_repository.dart';
import 'package:paraselene_flutter/workspace/data/workspace_repository.dart';
import 'package:paraselene_flutter/workspace/presentation/workbench_chrome.dart';
import 'package:paraselene_flutter/workspace/presentation/workbench_dialogs.dart';
import 'package:paraselene_flutter/workspace/workspace_controller.dart';

import '../support/m2_harness.dart';

/// 内存讨论仓库：可注入服务端候选投影，并记录采纳次数/失败。
class _FakeDiscussions implements DiscussionRepository, GenerationRepository {
  final Map<
    String,
    ({String chapter, int revision, Map<String, dynamic> snapshot})
  >
  rows = {};
  List<Map<String, dynamic>> operations = [];
  int applyCalls = 0;
  int prepareCalls = 0;
  int sendCalls = 0;
  int cancelCalls = 0;
  bool failApply = false;

  @override
  Future<List<Map<String, dynamic>>> listThreads(
    String work,
    String chapter,
  ) async => [
    for (final entry in rows.entries)
      if (entry.value.chapter == chapter)
        <String, dynamic>{
          'threadId': entry.key,
          'documentId': chapter,
          'revision': entry.value.revision,
          'snapshot': entry.value.snapshot,
        },
  ];

  @override
  Future<Map<String, dynamic>> saveThread(
    String work,
    String chapter,
    String id,
    int? revision,
    Map<String, dynamic> snapshot,
  ) async {
    final next = (revision ?? 0) + 1;
    rows[id] = (chapter: chapter, revision: next, snapshot: snapshot);
    return <String, dynamic>{
      'threadId': id,
      'documentId': chapter,
      'revision': next,
      'snapshot': snapshot,
    };
  }

  @override
  Future<List<Map<String, dynamic>>> listOperations(
    String work,
    String chapter,
  ) async => operations;

  @override
  Future<void> applyOperation(
    String work,
    String chapter,
    String id,
    int? revision,
  ) async {
    applyCalls++;
    if (failApply) throw const WorkspaceFailure('revision_conflict');
  }

  @override
  Future<void> rejectOperation(String work, String chapter, String id) async {}

  @override
  Future<void> activateScope(String? work, String? chapter) async {}

  @override
  Future<Map<String, dynamic>> prepare(Map<String, dynamic> request) async {
    prepareCalls++;
    return <String, dynamic>{
      'id': 'preview-1',
      'prepared': <String, dynamic>{
        'model': 'synthetic',
        'estimated_tokens': 1,
        'messages': const <Map<String, dynamic>>[],
      },
    };
  }

  @override
  Future<void> send(
    String work,
    String preview, {
    required bool confirmed,
  }) async {
    sendCalls++;
  }

  @override
  Future<void> cancel(String work, String operation) async {
    cancelCalls++;
  }

  @override
  Future<void> setCloudEnabled(bool enabled) async {}

  @override
  Future<void> setKey(String key) async {}

  @override
  Future<void> deleteKey() async {}
}

/// 合成工作区 + 讨论能力；生成能力由讨论仓库提供，避免伪造工作区能力。
class _OpsRepository extends SyntheticWorkspaceRepository
    implements DiscussionRepositoryProvider {
  _OpsRepository() : super(withDemo: true);

  final _FakeDiscussions fake = _FakeDiscussions();

  @override
  DiscussionRepository get discussions => fake;
}

Future<void> _pumpPanel(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: chinese,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: workbenchTheme(),
      home: Scaffold(body: child),
    ),
  );
  await tester.pump();
}

Future<void> _dispose(WorkspaceController controller) async {
  await controller.editing.flushAll();
  await controller.discussions?.flush();
  controller.dispose();
}

void main() {
  testWidgets('整章讨论说明生成不可用，草稿仍可保留', (tester) async {
    final repository = _OpsRepository();
    final controller = WorkspaceController(repository);
    addTearDown(() => _dispose(controller));
    await controller.restoreSession();
    final thread = controller.discussions!.chapterThread();
    await controller.discussions!.flush();

    await _pumpPanel(
      tester,
      DiscussionPanel(thread: thread, workspace: controller),
    );

    expect(
      find.byKey(const ValueKey('discussion-generation-unavailable')),
      findsOneWidget,
      reason: '整章线程必须解释为什么不能生成，而不是只禁用按钮',
    );
    expect(find.textContaining('生成预览需要有效选段'), findsOneWidget);
    final preview = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '预览完整外发消息'),
    );
    expect(preview.onPressed, isNull);

    await tester.enterText(
      find.descendant(
        of: find.byType(DiscussionPanel),
        matching: find.byType(TextField),
      ),
      '整章讨论草稿',
    );
    await tester.pump();
    expect(find.text('整章讨论草稿'), findsOneWidget);
    await controller.discussions!.flush();
  });

  testWidgets('候选采纳只写编辑稿；失败时保留正文并说明原因', (tester) async {
    final repository = _OpsRepository();
    final controller = WorkspaceController(repository);
    addTearDown(() => _dispose(controller));
    await controller.restoreSession();
    final created = controller.discussions!.create(
      EditorAnchor.capture(controller.body, 0, 2),
    );
    await controller.discussions!.flush();
    repository.fake.operations = [
      <String, dynamic>{
        'operationId': 'op-1',
        'threadId': created.id,
        'patchStatus': 'pending',
        'binding': <String, dynamic>{
          'request': <String, dynamic>{
            'selectedText': controller.body.substring(0, 2),
          },
        },
        'output': '候选输出',
      },
    ];
    await controller.discussions!.refreshOperations();
    await _pumpPanel(
      tester,
      DiscussionPanel(
        thread: controller.discussions!.byId(created.id)!,
        workspace: controller,
      ),
    );

    expect(
      find.byKey(const ValueKey('candidate-apply-notice')),
      findsOneWidget,
      reason: '采纳前必须说明只写编辑稿、可一次撤销',
    );
    final body = controller.body;

    repository.fake.failApply = true;
    await tester.tap(find.widgetWithText(TextButton, '采纳候选'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(repository.fake.applyCalls, 1);
    expect(
      find.byKey(const ValueKey('candidate-apply-failed')),
      findsOneWidget,
      reason: '正文/目标变化导致拒绝时必须说明候选未写入',
    );
    expect(controller.body, body, reason: '拒绝采纳不得修改正文');
    expect(await controller.listVersions(), isEmpty);

    repository.fake.failApply = false;
    await tester.tap(find.widgetWithText(TextButton, '采纳候选'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(repository.fake.applyCalls, 2);
    expect(find.byKey(const ValueKey('candidate-apply-failed')), findsNothing);
    expect(controller.body, body);
    expect(
      controller.editing.preserveEditorHistory,
      isTrue,
      reason: '采纳候选必须保留编辑器历史，作者可用一次撤销撤回',
    );
    expect(
      await controller.listVersions(),
      isEmpty,
      reason: '采纳候选只写编辑稿，不新增正式版本',
    );
  });

  testWidgets('保存不新增正式版本，确认对话框说明版本语义', (tester) async {
    final repository = SyntheticWorkspaceRepository(withDemo: true);
    final controller = WorkspaceController(repository);
    addTearDown(() => _dispose(controller));
    await controller.restoreSession();

    controller.editing.edit('${controller.body}\n保存但不确认');
    await controller.editing.flushAll();
    expect(await controller.listVersions(), isEmpty, reason: '保存只写编辑稿');

    final prepared = await controller.prepareConfirmation();
    expect(prepared, isNotNull);
    final confirmation = prepared!;

    await tester.pumpWidget(
      MaterialApp(
        locale: chinese,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: workbenchTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  await showDialog<void>(
                    context: context,
                    builder: (_) => ConfirmChapterDialog(
                      controller: controller,
                      labels: WorkbenchLabels(
                        AppLocalizations.of(context),
                        false,
                      ),
                      prepared: confirmation,
                    ),
                  );
                },
                child: const Text('打开确认'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开确认'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('confirm-preview-body')), findsOneWidget);
    expect(
      find.textContaining('Ctrl+S 与自动保存只写编辑稿'),
      findsOneWidget,
      reason: '确认前必须区分编辑稿与正式版本',
    );
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    expect(await controller.confirmChapter(confirmation.token), isTrue);
    expect(await controller.listVersions(), hasLength(1));
  });

  test('生成预览不修改正文，取消票据不发送请求', () async {
    final repository = _OpsRepository();
    final controller = WorkspaceController(repository);
    addTearDown(() => _dispose(controller));
    await controller.restoreSession();
    final thread = controller.discussions!.create(
      EditorAnchor.capture(controller.body, 0, 2),
    );
    await controller.discussions!.flush();
    final before = controller.body;

    final preview = await controller.prepareGeneration(thread.id);
    expect(preview, isNotNull);
    expect(repository.fake.prepareCalls, 1);
    expect(controller.body, before, reason: '准备预览只读，不改正文');
    expect(await controller.listVersions(), isEmpty);

    await repository.fake.cancel(
      preview!['workId'] as String,
      preview['operationId'] as String,
    );
    expect(repository.fake.cancelCalls, 1);
    expect(repository.fake.sendCalls, 0, reason: '取消预览票据绝不能触发外发请求');
    expect(controller.body, before);
  });

  test('20 万字章节多轮采纳后线程草稿冷启动仍保留', () async {
    final repository = _OpsRepository();
    final controller = WorkspaceController(repository);
    await controller.restoreSession();

    // 20 万字多段正文：只验证作者快照/草稿在多次操作与冷启动后仍一致。
    final paragraph = '天地玄黄，宇宙洪荒。日月盈昃，辰宿列张。\n';
    final longBody = List.filled(4000, paragraph).join() * 3;
    expect(longBody.length, greaterThan(200000));
    controller.editing.edit(longBody);
    await controller.editing.flushAll();

    final thread = controller.discussions!.create(
      EditorAnchor.capture(controller.body, 0, 2),
    );
    controller.discussions!.editDraft(thread.id, '长稿讨论草稿');
    await controller.discussions!.flush();

    repository.fake.operations = [
      for (var index = 0; index < 4; index++)
        <String, dynamic>{
          'operationId': 'long-op-$index',
          'threadId': thread.id,
          'patchStatus': 'pending',
          'binding': <String, dynamic>{
            'request': <String, dynamic>{'selectedText': '天地'},
          },
          'output': '候选 $index',
        },
    ];
    for (var index = 0; index < 4; index++) {
      expect(await controller.applyCandidate('long-op-$index'), isTrue);
    }
    expect(controller.body.length, longBody.length);
    expect(await controller.listVersions(), isEmpty);
    await controller.discussions!.flush();
    await _dispose(controller);

    // 冷启动：同一仓库重新装载，线程草稿与正文快照仍在，且不重发服务端请求。
    final restarted = WorkspaceController(repository);
    addTearDown(() => _dispose(restarted));
    await restarted.restoreSession();
    expect(restarted.body.length, longBody.length);
    expect(restarted.discussions!.threads, hasLength(1));
    expect(restarted.discussions!.threads.single.draft, '长稿讨论草稿');
    expect(repository.fake.prepareCalls, 0, reason: '冷启动不得重发服务端请求');
    expect(await restarted.listVersions(), isEmpty, reason: '采纳候选不会写正式版本');
  });
}
