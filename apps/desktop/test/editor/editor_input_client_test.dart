// 覆盖 EditorInputClient 的输入客户端合同：初始化、选择/替换、撤销重做与字素边界。
// 使用测试字体与合成布局，不代表 Windows IME、原生文本服务或真实字体渲染通过。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/editor/editor_input_client.dart';
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

Future<GlobalKey<EditorViewportState>> _mount(
  WidgetTester tester,
  EditorInputClient client,
) async {
  final key = GlobalKey<EditorViewportState>();
  tester.view.physicalSize = const Size(1000, 700);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: EditorViewport(key: key, controller: client),
      ),
    ),
  );
  key.currentState!.requestFocus();
  await tester.pump();
  return key;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);

  group('EditorInputClient', () {
    test('initializes with document and layout', () {
      final client = EditorInputClient('hello world', style: _testStyle);
      addTearDown(client.dispose);
      expect(client.document.raw, 'hello world');
      expect(client.length, 11);
      expect(client.layout.raw, 'hello world');
      expect(client.attached, isFalse);
    });

    test('select updates document and notifies', () {
      final client = EditorInputClient('hello world', style: _testStyle);
      addTearDown(client.dispose);
      var notified = false;
      client.addListener(() => notified = true);
      client.select(const TextSelection.collapsed(offset: 5));
      expect(notified, isTrue);
      expect(client.value.selection.extentOffset, 5);
    });

    test('replace modifies document', () {
      final client = EditorInputClient('hello world', style: _testStyle);
      addTearDown(client.dispose);
      client.select(const TextSelection(baseOffset: 0, extentOffset: 5));
      client.replace('goodbye');
      expect(client.document.raw, 'goodbye world');
    });

    test('undo and redo work correctly', () {
      final client = EditorInputClient('hello', style: _testStyle);
      addTearDown(client.dispose);
      client.select(const TextSelection.collapsed(offset: 5));
      client.replace(' world');
      expect(client.document.raw, 'hello world');
      client.undo();
      expect(client.document.raw, 'hello');
      client.redo();
      expect(client.document.raw, 'hello world');
    });

    test('boundary respects grapheme clusters', () {
      final client = EditorInputClient('a👩‍💻e\u0301z', style: _testStyle);
      addTearDown(client.dispose);
      // 'a' (1) + '👩‍💻' (5) + 'e\u0301' (2) + 'z' (1) = 9 total
      expect(client.boundary(0, true), 1); // after 'a'
      expect(client.boundary(1, true), 6); // after '👩‍💻'
      expect(client.boundary(6, true), 8); // after 'e\u0301'
      expect(client.boundary(8, true), 9); // after 'z'
      expect(client.boundary(9, false), 8); // before 'z'
      expect(client.boundary(8, false), 6); // before 'e\u0301'
      expect(client.boundary(6, false), 1); // before '👩‍💻'
    });

    test('load replaces document and layout', () {
      final client = EditorInputClient('hello', style: _testStyle);
      addTearDown(client.dispose);
      client.load('goodbye world');
      expect(client.document.raw, 'goodbye world');
      expect(client.layout.raw, 'goodbye world');
    });

    testWidgets('attaches to IME on focus', (tester) async {
      final client = EditorInputClient('hello', style: _testStyle);
      addTearDown(client.dispose);
      await _mount(tester, client);
      expect(client.attached, isTrue);
    });

    testWidgets('detaches from IME on blur', (tester) async {
      final client = EditorInputClient('hello', style: _testStyle);
      addTearDown(client.dispose);
      await _mount(tester, client);
      expect(client.attached, isTrue);
      client.focusNode.unfocus();
      await tester.pump();
      expect(client.attached, isFalse);
    });

    testWidgets('updateEditingValue applies changes', (tester) async {
      final client = EditorInputClient('hello', style: _testStyle);
      addTearDown(client.dispose);
      await _mount(tester, client);
      client.updateEditingValue(
        const TextEditingValue(
          text: 'hello world',
          selection: TextSelection.collapsed(offset: 11),
        ),
      );
      expect(client.document.raw, 'hello world');
      expect(client.nativeCallbacks, 1);
    });

    testWidgets('composing state is tracked', (tester) async {
      final client = EditorInputClient('hello', style: _testStyle);
      addTearDown(client.dispose);
      await _mount(tester, client);
      expect(client.composing, isFalse);
      client.updateEditingValue(
        const TextEditingValue(
          text: 'hello你',
          selection: TextSelection.collapsed(offset: 6),
          composing: TextRange(start: 5, end: 6),
        ),
      );
      expect(client.composing, isTrue);
      expect(client.value.composing, const TextRange(start: 5, end: 6));
    });

    testWidgets('keyboard deletion honors grapheme boundaries', (tester) async {
      final client = EditorInputClient('a👩‍💻e\u0301\r\nz', style: _testStyle);
      addTearDown(client.dispose);
      await _mount(tester, client);
      client.select(const TextSelection.collapsed(offset: 6));
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(client.document.raw, 'ae\u0301\r\nz');
      client.undo();
      expect(client.document.raw, 'a👩‍💻e\u0301\r\nz');
      client.select(const TextSelection.collapsed(offset: 8));
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      expect(client.document.raw, 'a👩‍💻e\u0301z');
    });

    testWidgets('Ctrl+Z and Ctrl+Y work', (tester) async {
      final client = EditorInputClient('hello', style: _testStyle);
      addTearDown(client.dispose);
      await _mount(tester, client);
      client.select(const TextSelection.collapsed(offset: 5));
      client.replace(' world');
      expect(client.document.raw, 'hello world');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(client.document.raw, 'hello');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(client.document.raw, 'hello world');
    });

    testWidgets('Ctrl+A selects all', (tester) async {
      final client = EditorInputClient('hello world', style: _testStyle);
      addTearDown(client.dispose);
      await _mount(tester, client);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(client.value.selection.baseOffset, 0);
      expect(client.value.selection.extentOffset, 11);
    });

    testWidgets('clipboard copy and paste work', (tester) async {
      final client = EditorInputClient('abc\r\ndef', style: _testStyle);
      addTearDown(client.dispose);
      await _mount(tester, client);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      String? copied;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
          return null;
        }
        if (call.method == 'Clipboard.getData') return {'text': 'x\r\ny'};
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      client.select(const TextSelection(baseOffset: 0, extentOffset: 5));
      await client.clipboard('copy');
      expect(copied, 'abc\r\n');
      await client.clipboard('paste');
      expect(client.document.raw, 'x\r\nydef');
    });

    testWidgets('clipboard failure is reported', (tester) async {
      final client = EditorInputClient('abc', style: _testStyle);
      addTearDown(client.dispose);
      await _mount(tester, client);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method.startsWith('Clipboard.')) {
          throw PlatformException(code: 'synthetic-denied');
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await client.clipboard('paste');
      expect(client.error, contains('synthetic-denied'));
    });

    testWidgets('toggleSlot shows and hides slot', (tester) async {
      final client = EditorInputClient('hello\r\nworld', style: _testStyle);
      addTearDown(client.dispose);
      await _mount(tester, client);
      expect(client.layout.slot, isFalse);
      client.toggleSlot();
      expect(client.layout.slot, isTrue);
      expect(client.layout.slots.length, 1);
      client.toggleSlot();
      expect(client.layout.slot, isFalse);
    });

    testWidgets('viewport builds scene with client state', (tester) async {
      final client = EditorInputClient(
        'hello world\r\nsecond line',
        style: _testStyle,
      );
      addTearDown(client.dispose);
      final key = await _mount(tester, client);
      final state = key.currentState!;
      expect(state.scene, isNotNull);
      expect(state.scene!.pages, isNotEmpty);
      client.select(const TextSelection(baseOffset: 0, extentOffset: 5));
      await tester.pump();
      expect(state.scene!.selection, isNotEmpty);
    });
  });
}
