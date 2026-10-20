// R05 操作一致性测试：阅读位置持久化与恢复。
// 恢复以作品/文档/编辑会话身份为作用域，等纸面头尾与正文 extent 可用后
// 才安全钳制应用；缩短正文不越界，两个作品的位置互不串用。仅用合成材料。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/editor/editor_input_client.dart';
import 'package:paraselene_flutter/editor/editor_viewport.dart';
import 'package:paraselene_flutter/workspace/data/synthetic_workspace_repository.dart';

import '../support/m2_harness.dart';
import 'paper_harness.dart';

void main() {
  setUpAll(loadM2Fonts);

  testWidgets('长章滚动位置关闭重开后恢复，并安全钳制到新范围', (tester) async {
    final repository = SyntheticWorkspaceRepository(withDemo: true);
    final controller = await pumpPaperWorkbench(tester, repository: repository);
    var first = tester.state<EditorViewportState>(find.byKey(manuscriptKey));
    (first.controller as EditorInputClient).load(longBody());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    first = tester.state<EditorViewportState>(find.byKey(manuscriptKey));
    first.scroll.jumpTo(420);
    await tester.pump();
    expect(controller.pendingScrollTop, closeTo(420, 1));
    // 等偏好防抖写盘（350ms）后再模拟冷启动。
    await tester.pump(const Duration(milliseconds: 400));
    await disposePaperController(controller);
    await tester.pumpWidget(const SizedBox());

    final restarted = await pumpPaperWorkbench(tester, repository: repository);
    await tester.pump(const Duration(milliseconds: 100));
    addTearDown(() => disposePaperController(restarted));
    final restored = tester.state<EditorViewportState>(
      find.byKey(manuscriptKey),
    );
    expect(restored.scroll.offset, closeTo(420, 2));

    // 正文缩短后同一恢复偏移必须被钳制到 0，不能停在过去的位置。
    (restored.controller as EditorInputClient).load('只剩一行。');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(restored.scroll.offset, 0);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('作品 A/B 与章节位置互不串用', (tester) async {
    final repository = SyntheticWorkspaceRepository(withDemo: true);
    final controller = await pumpPaperWorkbench(tester, repository: repository);
    addTearDown(() => disposePaperController(controller));

    final workA = controller.currentWork!;
    (tester.state<EditorViewportState>(find.byKey(manuscriptKey)).controller
            as EditorInputClient)
        .load(longBody());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    tester
        .state<EditorViewportState>(find.byKey(manuscriptKey))
        .scroll
        .jumpTo(420);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(await controller.createWork('第二部'), isTrue);
    expect(await controller.createChapter('B 章'), isTrue);
    await tester.pump();
    (tester.state<EditorViewportState>(find.byKey(manuscriptKey)).controller
            as EditorInputClient)
        .load(longBody(paragraphs: 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    final workB = controller.currentWork!;
    expect(workB.id, isNot(workA.id));

    expect(await controller.selectWork(workA), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(controller.currentWork?.id, workA.id);
    expect(
      tester
          .state<EditorViewportState>(find.byKey(manuscriptKey))
          .scroll
          .offset,
      closeTo(420, 2),
    );

    expect(await controller.selectWork(workB), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(controller.currentWork?.id, workB.id);
    expect(
      tester
          .state<EditorViewportState>(find.byKey(manuscriptKey))
          .scroll
          .offset,
      0,
    );
    // 让最后一次滚动位置的偏好防抖写盘完成，避免测试结束时残留计时器。
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });
}
