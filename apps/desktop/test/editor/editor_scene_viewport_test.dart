// 覆盖编辑器场景与视口：坐标往返、命中测试、选区几何、画布缓存与懒滚动绘制。
// 在测试渲染管线中验证 Dart/Flutter 层行为，不代表 Windows 原生合成或性能达标。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/editor/editor_layout.dart';
import 'package:paraselene_flutter/editor/editor_scene.dart';
import 'package:paraselene_flutter/editor/editor_viewport.dart';

Future<void> _loadFonts() async {
  for (final face in const {
    'Notebook Sans': 'NotoSansSC-Regular.ttf',
    'Notebook Serif': 'NotoSerifSC-Regular.ttf',
    'Noto Arabic': 'NotoNaskhArabic.ttf',
  }.entries) {
    final loader = FontLoader(face.key);
    loader.addFont(rootBundle.load('assets/fonts/${face.value}'));
    await loader.load();
  }
}

const _testStyle = TextStyle(
  fontFamily: 'Notebook Serif',
  fontFamilyFallback: ['Notebook Sans', 'Noto Arabic'],
  fontSize: 20,
  height: 1.85,
  color: Color(0xff28231f),
);

String _heterogeneousFixture({bool singleLine = false}) {
  final buffer = StringBuffer();
  var i = 0;
  while (buffer.length < 200000) {
    final number = i++;
    buffer.write('第$number段 ${number * 7919} 月光落在窗边，人物${number % 97}转身望向河岸。');
    for (var j = 0; j < 7 + number % 43; j++) {
      buffer.writeCharCode(0x4e00 + (number * 31 + j * 19) % 20000);
    }
    if (!singleLine) buffer.write(number.isEven ? '\r\n' : '\n');
  }
  return buffer.toString().substring(0, 200000);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);

  group('EditorScene', () {
    test('transform round trips document and viewport', () {
      const transform = EditorTransform(Offset(120, -3456));
      const point = Offset(75.5, 3812.25);
      expect(transform.toDocument(transform.toCanvas(point)), point);
    });

    test('hit test returns document offset from viewport point', () {
      final layout = EditorLayout(style: _testStyle)
        ..update('abc\ndef\n')
        ..materializeAll();
      final cache = VisiblePainters();
      addTearDown(cache.dispose);
      final scene = buildScene(
        layout: layout,
        cache: cache,
        value: const TextEditingValue(
          selection: TextSelection.collapsed(offset: 0),
        ),
        viewport: const Size(800, 600),
        scroll: 0,
        revision: 1,
      );
      final hit = scene.hit(Offset(0, 0));
      expect(hit, greaterThanOrEqualTo(0));
      expect(hit, lessThanOrEqualTo(8));
    });

    test('scene captures selection and caret geometry', () {
      final layout = EditorLayout(style: _testStyle)
        ..update('hello world\n')
        ..materializeAll();
      final cache = VisiblePainters();
      addTearDown(cache.dispose);
      final scene = buildScene(
        layout: layout,
        cache: cache,
        value: const TextEditingValue(
          selection: TextSelection(baseOffset: 0, extentOffset: 5),
        ),
        viewport: const Size(800, 600),
        scroll: 0,
        revision: 1,
      );
      expect(scene.selection, isNotEmpty);
      expect(scene.caret.width, 2);
      expect(scene.pages, isNotEmpty);
    });

    test('painter cache LRU evicts warm entries beyond limit', () {
      final layout = EditorLayout(style: _testStyle);
      final paragraphs = List.generate(
        50,
        (i) => 'unique paragraph $i 月光\r\n',
      ).join();
      layout.update(paragraphs);
      layout.materializeAll();
      final cache = VisiblePainters();
      addTearDown(cache.dispose);
      buildScene(
        layout: layout,
        cache: cache,
        value: const TextEditingValue(
          selection: TextSelection.collapsed(offset: 0),
        ),
        viewport: const Size(1000, 1900),
        scroll: 0,
        revision: 1,
      );
      expect(cache.activeEntries, greaterThan(32));
      expect(cache.warmEntries, lessThanOrEqualTo(32));
      expect(cache.length, lessThanOrEqualTo(cache.activeEntries + 32));
    });
  });

  group('EditorViewport', () {
    testWidgets('lazy scrolling paints every visible pixel from raw', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final controller = BasicEditorController(
        _heterogeneousFixture(),
        style: _testStyle,
      );
      addTearDown(controller.dispose);
      final key = GlobalKey<EditorViewportState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorViewport(key: key, controller: controller),
          ),
        ),
      );
      final state = key.currentState!;
      for (var i = 0; i < 120; i++) {
        state.scroll.jumpTo(state.scroll.position.maxScrollExtent * i / 119);
        await tester.pump();
        expect(tester.takeException(), isNull);
        final pages = state.scene!.pages;
        expect(pages, isNotEmpty);
        var bottom = 0.0;
        for (final page in pages) {
          expect(
            page.page.text,
            controller.document.raw.substring(page.page.start, page.page.end),
          );
          expect(page.origin.dy, lessThanOrEqualTo(bottom + .1));
          bottom = page.origin.dy + page.page.height;
        }
        final required = (controller.layout.height - state.scroll.offset).clamp(
          0.0,
          700.0,
        );
        expect(bottom + .1, greaterThanOrEqualTo(required));
      }
    });

    testWidgets('tall viewport leases more than 32 painters safely', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 1900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final controller = BasicEditorController(
        List.generate(140, (i) => 'unique paragraph $i 月光\r\n').join(),
        style: _testStyle,
      );
      addTearDown(controller.dispose);
      final key = GlobalKey<EditorViewportState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorViewport(key: key, controller: controller),
          ),
        ),
      );
      final state = key.currentState!;
      expect(state.scene!.pages.length, greaterThan(40));
      expect(state.painters.activeEntries, greaterThan(40));
      expect(tester.takeException(), isNull);
      controller.select(
        TextSelection.collapsed(offset: controller.document.raw.length),
      );
      state.ensureCaret();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(state.painters.warmEntries, lessThanOrEqualTo(32));
      expect(
        state.painters.length,
        lessThanOrEqualTo(state.painters.activeEntries + 32),
      );
      state.scroll.jumpTo(0);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('header and footer join the single document scroll extent', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final controller = BasicEditorController(
        List.generate(60, (i) => '第$i段 月光落在窗边。\r\n').join(),
        style: _testStyle,
      );
      addTearDown(controller.dispose);
      final key = GlobalKey<EditorViewportState>();
      final headerKey = GlobalKey();
      final footerKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorViewport(
              key: key,
              controller: controller,
              documentHeader: SizedBox(key: headerKey, height: 120),
              documentFooter: SizedBox(key: footerKey, height: 90),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      final state = key.currentState!;
      expect(state.scroll.position.maxScrollExtent, greaterThan(0));
      expect(
        state.scroll.position.maxScrollExtent,
        closeTo(120 + controller.layout.height + 90 - 600, 2),
      );
      expect(tester.getTopLeft(find.byKey(headerKey)).dy, closeTo(0, 1));
      expect(
        tester.getTopLeft(find.byKey(footerKey)).dy,
        closeTo(120 + controller.layout.height, 2),
      );

      // 标题随纸面滚走，正文画布同时上移；只有一个 ScrollPosition。
      state.scroll.jumpTo(200);
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(headerKey)).dy, closeTo(-200, 1));
      expect(
        find.descendant(
          of: find.byType(EditorViewport),
          matching: find.byType(Scrollable),
        ),
        findsOneWidget,
      );

      // 滚到底后章末正好贴在视口底部。
      state.scroll.jumpTo(state.scroll.position.maxScrollExtent);
      await tester.pump();
      final viewportRect = tester.getRect(find.byType(EditorViewport));
      final footerRect = tester.getRect(find.byKey(footerKey));
      expect(footerRect.bottom, closeTo(viewportRect.bottom, 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('tap below the paper header maps to the first body line', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final controller = BasicEditorController(
        '第一行正文\r\n第二行正文\r\n第三行正文',
        style: _testStyle,
      );
      addTearDown(controller.dispose);
      final key = GlobalKey<EditorViewportState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorViewport(
              key: key,
              controller: controller,
              documentHeader: const SizedBox(height: 120),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      final origin = tester.getTopLeft(find.byType(EditorViewport));
      // 标题高度以下的第一行正文；坐标换算必须扣除纸面标题高度。
      await tester.tapAt(origin + const Offset(20, 130));
      await tester.pump();
      final selection = controller.value.selection;
      expect(selection.isCollapsed, isTrue);
      expect(selection.extentOffset, lessThan(30));
      expect(tester.takeException(), isNull);
    });

    testWidgets('tap sets collapsed selection at hit offset', (tester) async {
      tester.view.physicalSize = const Size(1000, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final controller = BasicEditorController(
        'hello world\r\nsecond line\r\n',
        style: _testStyle,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: EditorViewport(controller: controller)),
        ),
      );
      await tester.tapAt(const Offset(100, 10));
      await tester.pump();
      expect(controller.value.selection.isCollapsed, isTrue);
      expect(controller.value.selection.extentOffset, greaterThanOrEqualTo(0));
    });

    testWidgets('arrow keys move caret vertically', (tester) async {
      tester.view.physicalSize = const Size(1000, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final controller = BasicEditorController(
        'first line\r\nsecond line\r\nthird line\r\n',
        style: _testStyle,
      );
      addTearDown(controller.dispose);
      final key = GlobalKey<EditorViewportState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorViewport(key: key, controller: controller),
          ),
        ),
      );
      key.currentState!.requestFocus();
      await tester.pump();
      controller.select(const TextSelection.collapsed(offset: 0));
      await tester.pump();
      final before = controller.value.selection.extentOffset;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(controller.value.selection.extentOffset, greaterThan(before));
    });
  });
}
