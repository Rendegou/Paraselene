import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/workspace/data/demo_content.dart';
import 'package:paraselene_flutter/workspace/data/synthetic_workspace_repository.dart';

import 'support/m2_harness.dart';

void main() {
  setUpAll(loadM2Fonts);
  testWidgets('work picker cannot become stranded during a pending load', (
    tester,
  ) async {
    tester.useSurface(const Size(1280, 900));
    final repository = DelayedBodyRepository();
    await tester.pumpWorkbench(repository: repository);
    final button = find.ancestor(
      of: find.text('选择作品'),
      matching: find.byType(TextButton),
    );
    expect(tester.widget<TextButton>(button).onPressed, isNull);
    repository.pending.complete(demoBody);
    await tester.flushWorkbench();
    expect(tester.widget<TextButton>(button).onPressed, isNotNull);
    await tester.activate('选择作品');
    expect(find.byKey(const ValueKey('work-demo-work')), findsOneWidget);
  });
  testWidgets(
    'empty library seeds and chapter selection preserves exact text',
    (tester) async {
      tester.useSurface(const Size(1280, 900));
      await tester.pumpWorkbench(repository: SyntheticWorkspaceRepository());
      expect(find.text('为下一段故事，留一页安静的纸'), findsOneWidget);
      await tester.activate('创建示例材料');
      expect(rawBody(tester), demoBody);
      await tester.tap(find.byKey(const ValueKey('chapter-demo-chapter')));
      await tester.flushWorkbench();
      expect(rawBody(tester), demoBody);
      await tester.activate('选择作品');
      expect(find.byKey(const ValueKey('work-demo-work')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('work-demo-work')));
      await tester.flushWorkbench();
      expect(rawBody(tester), demoBody);
    },
  );

  testWidgets('interface locale changes without changing manuscript metadata', (
    tester,
  ) async {
    tester.useSurface(const Size(1280, 900));
    await tester.pumpWorkbench();
    await tester.activate('界面语言');
    await tester.activate('English');
    expect(find.text('Writing workspace'), findsOneWidget);
    expect(find.text('雨后的书店'), findsOneWidget);
    expect(rawBody(tester), demoBody);
    await tester.activate('Interface language');
    await tester.activate('简体中文');
    expect(find.text('写作工作台'), findsOneWidget);
    expect(rawBody(tester), demoBody);
  });

  testWidgets('focus exits and wide mode changes readable manuscript width', (
    tester,
  ) async {
    tester.useSurface(const Size(1440, 900));
    await tester.pumpWorkbench();
    final normal = tester.getSize(find.byKey(manuscriptKey)).width;
    await tester.activate('宽稿模式');
    expect(
      tester.getSize(find.byKey(manuscriptKey)).width,
      greaterThan(normal),
    );
    await tester.activate('舒适宽度');
    expect(tester.getSize(find.byKey(manuscriptKey)).width, normal);
    await tester.activate('专注模式');
    expect(find.byKey(const ValueKey('chapter-demo-chapter')), findsNothing);
    await tester.activate('退出专注');
    expect(find.byKey(const ValueKey('chapter-demo-chapter')), findsOneWidget);
    expect(rawBody(tester), demoBody);
  });

  testWidgets('recoverable repository failure exposes retry and recovers', (
    tester,
  ) async {
    tester.useSurface(const Size(900, 700));
    await tester.pumpWorkbench(repository: RetryRepository());
    expect(find.text('暂时无法读取工作台'), findsOneWidget);
    expect(find.textContaining('fixture_unavailable'), findsOneWidget);
    await tester.activate('重新读取');
    expect(rawBody(tester), demoBody);
    expect(find.text('暂时无法读取工作台'), findsNothing);
  });
  layoutMatrix();
}

class DelayedBodyRepository extends SyntheticWorkspaceRepository {
  DelayedBodyRepository() : super(withDemo: true);
  final pending = Completer<String>();
  @override
  Future<String> loadBody(String workId, String chapterId) => pending.future;
}

String? rawBody(WidgetTester tester) =>
    tester.widget<SelectableText>(find.byKey(manuscriptKey)).data;

void layoutMatrix() {
  for (final locale in const [chinese, Locale('en')]) {
    for (final size in const [
      Size(360, 800),
      Size(900, 700),
      Size(1440, 900),
    ]) {
      for (final dpr in const [1.0, 1.5, 2.0]) {
        for (final scale in const [1.0, 2.0]) {
          for (final mode in const ['plain', 'pseudo', 'rtl', 'rtl-pseudo']) {
            for (final bold in const [false, true]) {
              testWidgets(
                'fit $locale $size dpr=$dpr scale=$scale $mode bold=$bold',
                (tester) async {
                  tester.useSurface(size, dpr: dpr);
                  await tester.pumpWorkbench(
                    locale: locale,
                    scale: scale,
                    bold: bold,
                    pseudo: mode.contains('pseudo'),
                    rtl: mode.contains('rtl'),
                  );
                  expect(rawBody(tester), demoBody);
                  assertControlFit(tester, size);
                  assertDirectory(tester, size, scale, mode.contains('rtl'));
                },
              );
            }
          }
        }
      }
    }
  }
}

void assertControlFit(WidgetTester tester, Size size) {
  final buttons = find.byType(TextButton);
  for (final element in buttons.evaluate()) {
    final target = find.byWidget(element.widget);
    final rect = tester.getRect(target);
    expect(rect.width, greaterThanOrEqualTo(48));
    expect(rect.height, greaterThanOrEqualTo(48));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(size.width));
    for (final text
        in find
            .descendant(of: target, matching: find.byType(Text))
            .evaluate()) {
      final paragraph = text.renderObject! as RenderParagraph;
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(paragraph.size.width, lessThanOrEqualTo(rect.width));
      expect(paragraph.size.height, lessThanOrEqualTo(rect.height));
    }
  }
}

void assertDirectory(WidgetTester tester, Size size, double scale, bool rtl) {
  final chapter = find.byKey(const ValueKey('chapter-demo-chapter'));
  if (size.width >= 900 && scale < 1.5) {
    expect(chapter, findsOneWidget);
    final directory = tester.getRect(chapter);
    final body = tester.getRect(find.byKey(manuscriptKey));
    expect(directory.width, greaterThanOrEqualTo(200));
    expect(
      rtl ? directory.left >= body.right : directory.right <= body.left,
      isTrue,
      reason: 'Directory must occupy the directional leading edge',
    );
  } else {
    expect(chapter, findsNothing);
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
  }
}
