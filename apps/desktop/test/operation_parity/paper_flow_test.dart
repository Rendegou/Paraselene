// R05 操作一致性测试：纸面标题、正文与章末共享同一套纵向文档坐标。
// 短章章末紧接正文，不固定到窗口底部；长章只有一个 ScrollPosition，
// 标题随纸面滚走，滚到底后章末出现在最后一行之后。仅使用合成材料。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/editor/editor_input_client.dart';
import 'package:paraselene_flutter/editor/editor_viewport.dart';

import '../support/m2_harness.dart';
import 'paper_harness.dart';

void main() {
  setUpAll(loadM2Fonts);

  testWidgets('短章：章末紧接正文，不贴窗口底部且只有一个滚动区', (tester) async {
    final controller = await pumpPaperWorkbench(tester);
    addTearDown(() => disposePaperController(controller));

    final viewport = tester.state<EditorViewportState>(
      find.byKey(manuscriptKey),
    );
    final box = tester.getRect(find.byKey(manuscriptKey));
    expect(viewport.scroll.position.maxScrollExtent, 0);
    expect(
      find.descendant(
        of: find.byKey(manuscriptKey),
        matching: find.byType(Scrollable),
      ),
      findsOneWidget,
    );

    final end = tester.getRect(find.text('本章结束'));
    expect(end.top, greaterThan(box.top));
    // 固定章末会贴在窗口底部；这里必须离底部还有明显余量。
    expect(end.bottom, lessThan(box.bottom - 150));
    expect(tester.takeException(), isNull);
  });

  testWidgets('长章：标题随纸面滚走，滚到底后章末在最后一行之后', (tester) async {
    final controller = await pumpPaperWorkbench(tester);
    addTearDown(() => disposePaperController(controller));

    final client =
        tester.state<EditorViewportState>(find.byKey(manuscriptKey)).controller
            as EditorInputClient;
    client.load(longBody());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final viewport = tester.state<EditorViewportState>(
      find.byKey(manuscriptKey),
    );
    final box = tester.getRect(find.byKey(manuscriptKey));
    expect(viewport.scroll.position.maxScrollExtent, greaterThan(500));

    final title = tester.getRect(
      find.descendant(
        of: find.byKey(manuscriptKey),
        matching: find.text('第一章 · 归途'),
      ),
    );
    expect(title.top, greaterThanOrEqualTo(box.top));
    final endBefore = tester.getRect(find.text('本章结束'));
    expect(endBefore.top, greaterThan(box.bottom));

    // 滚动过程中正文后缀会继续精确测量，可滚动范围随之增长；像真实阅读一样
    // 反复滚到当前底部，直到 extent 稳定。
    for (var i = 0; i < 40; i++) {
      final position = viewport.scroll.position;
      viewport.scroll.jumpTo(position.maxScrollExtent);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      if ((viewport.scroll.position.maxScrollExtent - viewport.scroll.offset)
              .abs() <=
          1) {
        break;
      }
    }

    expect(
      tester
          .getRect(
            find.descendant(
              of: find.byKey(manuscriptKey),
              matching: find.text('第一章 · 归途'),
            ),
          )
          .bottom,
      lessThan(box.top),
    );
    final endAfter = tester.getRect(find.text('本章结束'));
    expect(endAfter.top, greaterThan(box.top));
    expect(endAfter.bottom, lessThanOrEqualTo(box.bottom + 1));
    // 等滚动位置偏好防抖写盘完成，避免测试结束时残留计时器。
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });
}
