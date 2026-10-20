// 四项复核问题的永久回归：纯合成仓库，不读取凭据、作者数据或调用模型。
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/cowrite/discussion_panel.dart';
import 'package:paraselene_flutter/cowrite/discussion_repository.dart';
import 'package:paraselene_flutter/cowrite/generation_repository.dart';
import 'package:paraselene_flutter/editor/editor_anchor.dart';
import 'package:paraselene_flutter/editor/editor_input_client.dart';
import 'package:paraselene_flutter/editor/editor_viewport.dart';
import 'package:paraselene_flutter/workspace/data/synthetic_workspace_repository.dart';
import 'package:paraselene_flutter/workspace/presentation/lore_preview.dart';
import 'package:paraselene_flutter/workspace/workspace_controller.dart';
import 'paper_harness.dart';

class ReviewOperations implements DiscussionRepository, GenerationRepository {
  final rows = <String, Map<String, dynamic>>{};
  final pendingSend = Completer<void>();
  int sendCalls = 0;
  int cancelCalls = 0;

  @override
  Future<List<Map<String, dynamic>>> listThreads(
    String work,
    String chapter,
  ) async => rows.values.where((row) => row['documentId'] == chapter).toList();

  @override
  Future<Map<String, dynamic>> saveThread(
    String work,
    String chapter,
    String id,
    int? revision,
    Map<String, dynamic> snapshot,
  ) async {
    final row = <String, dynamic>{
      'threadId': id,
      'documentId': chapter,
      'revision': (revision ?? 0) + 1,
      'snapshot': Map<String, dynamic>.from(snapshot),
    };
    rows[id] = row;
    return row;
  }

  @override
  Future<List<Map<String, dynamic>>> listOperations(
    String work,
    String chapter,
  ) async => [];
  @override
  Future<void> applyOperation(
    String work,
    String chapter,
    String id,
    int? revision,
  ) async {}
  @override
  Future<void> rejectOperation(String work, String chapter, String id) async {}
  @override
  Future<void> activateScope(String? work, String? chapter) async {}
  @override
  Future<Map<String, dynamic>> prepare(Map<String, dynamic> request) async => {
    'id': 'synthetic-preview',
    'prepared': {
      'model': 'local-synthetic',
      'estimated_tokens': 1,
      'messages': [],
    },
  };
  @override
  Future<void> send(String work, String preview, {required bool confirmed}) {
    sendCalls++;
    return pendingSend.future;
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
  void finish() {
    if (!pendingSend.isCompleted) pendingSend.complete();
  }
}

class ReviewRepository extends SyntheticWorkspaceRepository
    implements DiscussionRepositoryProvider {
  ReviewRepository() : super(withDemo: true);
  final fake = ReviewOperations();
  @override
  DiscussionRepository get discussions => fake;
}

Future<WorkspaceController> setup(
  WidgetTester tester,
  ReviewRepository repo,
) async {
  final controller = await pumpPaperWorkbench(tester, repository: repo);
  addTearDown(() async {
    repo.fake.finish();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.editing.flushAll();
    await controller.discussions?.flush();
    controller.dispose();
    await tester.pump();
  });
  return controller;
}

EditorViewportState viewport(WidgetTester tester) =>
    tester.state<EditorViewportState>(find.byType(EditorViewport));

Future<void> compose(WidgetTester tester) async {
  final state = viewport(tester);
  state.requestFocus();
  await tester.pump();
  final client = state.controller as EditorInputClient;
  client.updateEditingValue(
    client.value.copyWith(
      selection: const TextSelection.collapsed(offset: 1),
      composing: const TextRange(start: 0, end: 1),
    ),
  );
  await tester.pump();
  expect(client.composing, isTrue);
}

void main() {
  testWidgets('review: body IME composition must not open Ctrl+F', (
    tester,
  ) async {
    await setup(tester, ReviewRepository());
    await compose(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(
      find.text('下一处'),
      findsNothing,
      reason: 'The custom editor composing state must gate global shortcuts',
    );
  });

  testWidgets('review: body IME Escape must not exit focus mode', (
    tester,
  ) async {
    await setup(tester, ReviewRepository());
    await tester.tap(find.byTooltip('专注模式'));
    await tester.pump();
    expect(find.text('幻月'), findsNothing);
    await compose(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(
      find.text('幻月'),
      findsNothing,
      reason: 'IME owns Escape until composition ends',
    );
  });

  testWidgets('review: sidebar attach must use the displayed selection thread', (
    tester,
  ) async {
    final controller = await setup(tester, ReviewRepository());
    final registry = controller.discussions!;
    final thread = registry.create(EditorAnchor.capture(controller.body, 0, 4));
    await tester.pump();
    await tester.tap(find.byKey(ValueKey('thread-marker-open-${thread.id}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(find.byType(DiscussionPanel), findsOneWidget);
    attachLoreReference(registry, 'synthetic-reference');
    expect(
      thread.snapshot['attached'],
      contains('synthetic-reference'),
      reason:
          'The sidebar action should attach to the active paragraph discussion',
    );
    await registry.flush();
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets(
    'review: generation cancellation must survive collapse and reopen',
    (tester) async {
      final repo = ReviewRepository();
      final controller = await setup(tester, repo);
      final registry = controller.discussions!;
      final thread = registry.create(
        EditorAnchor.capture(controller.body, 0, 4),
      );
      registry.editDraft(thread.id, 'synthetic instruction');
      await tester.pump();
      final marker = find.byKey(ValueKey('thread-marker-open-${thread.id}'));
      await tester.tap(marker);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      final preview = find.widgetWithText(TextButton, '预览完整外发消息');
      await tester.ensureVisible(preview);
      await tester.tap(preview);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '确认这些材料并仅发送一次'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(repo.fake.sendCalls, 1);
      expect(find.widgetWithText(TextButton, '取消生成'), findsOneWidget);
      final close = find.descendant(
        of: find.byType(DiscussionPanel),
        matching: find.byType(IconButton),
      );
      await tester.ensureVisible(close.first);
      await tester.tap(close.first);
      await tester.pump();
      expect(find.byType(DiscussionPanel), findsNothing);
      expect(
        repo.fake.cancelCalls,
        0,
        reason: 'Collapsing is not cancellation',
      );
      await tester.tap(marker);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        find.widgetWithText(TextButton, '取消生成'),
        findsOneWidget,
        reason: 'A still-running operation must remain visible and cancellable',
      );
      final cancel = find.widgetWithText(TextButton, '取消生成');
      await tester.ensureVisible(cancel);
      await tester.tap(cancel);
      await tester.pump();
      expect(repo.fake.cancelCalls, 1);
    },
  );
  testWidgets(
    'frozen reference target survives another discussion becoming active',
    (tester) async {
      final controller = await setup(tester, ReviewRepository());
      final registry = controller.discussions!;
      final first = registry.create(
        EditorAnchor.capture(controller.body, 0, 2),
      );
      final second = registry.create(
        EditorAnchor.capture(controller.body, 4, 6),
      );
      registry.setActiveThread(first.id);
      final target = LoreDiscussionTarget.capture(registry)!;
      registry.setActiveThread(second.id);
      attachLoreReference(registry, 'synthetic-reference', target: target);
      expect(first.snapshot['attached'], ['synthetic-reference']);
      expect(second.snapshot['attached'], isEmpty);
      expect(registry.threads, hasLength(2));
      expect(
        loreEntryAttached(
          registry.threads,
          'synthetic-reference',
          threadId: first.id,
        ),
        isTrue,
      );
      removeLoreReference(registry, 'synthetic-reference', target: target);
      expect(first.snapshot['attached'], isEmpty);
      await registry.flush();
      await tester.pump(const Duration(milliseconds: 400));
    },
  );

  testWidgets(
    'old reference preview cannot write into a newly opened chapter',
    (tester) async {
      final controller = await setup(tester, ReviewRepository());
      final registry = controller.discussions!;
      final thread = registry.create(
        EditorAnchor.capture(controller.body, 0, 2),
      );
      registry.setActiveThread(thread.id);
      final target = LoreDiscussionTarget.capture(registry)!;
      await controller.createChapter('合成新章节');
      await tester.pump();
      expect(registry.chapter, isNot(target.chapter));
      expect(
        () => attachLoreReference(
          registry,
          'synthetic-reference',
          target: target,
        ),
        throwsA(anything),
      );
      expect(registry.threads, isEmpty);
      await controller.editing.flushAll();
      await registry.flush();
      await tester.pump(const Duration(milliseconds: 400));
    },
  );
}
