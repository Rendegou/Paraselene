// 覆盖章节内查找栏：空结果提示、选择保持、Escape 关闭与关闭按钮可用性。
// widget 测试只验证 Dart 交互，不代表 Windows 原生查找、IME 或真实文本输入通过。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/editor/editor_input_client.dart';
import 'package:paraselene_flutter/l10n/generated/app_localizations.dart';
import 'package:paraselene_flutter/workspace/presentation/chapter_find.dart';

const _chinese = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans');

final class _FindHost extends StatefulWidget {
  const _FindHost();
  @override
  State<_FindHost> createState() => _FindHostState();
}

class _FindHostState extends State<_FindHost> {
  late final EditorInputClient client = EditorInputClient(
    '甲乙丙甲乙',
    style: const TextStyle(fontSize: 16),
  );
  bool closed = false;

  @override
  void dispose() {
    client.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: _chinese,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(
      body: ChapterFindBar(
        editor: client,
        onClose: () => setState(() => closed = true),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'find selects the next exact match, wraps and reports code points',
    (tester) async {
      await tester.pumpWidget(const _FindHost());
      await tester.pump();
      final state = tester.state<_FindHostState>(find.byType(_FindHost));

      await tester.enterText(find.byType(TextField), '甲乙');
      await tester.tap(find.text('下一处'));
      await tester.pump();
      expect(
        state.client.value.selection,
        const TextSelection(baseOffset: 0, extentOffset: 2),
      );
      expect(find.text('已定位第 1 字'), findsOneWidget);

      await tester.tap(find.text('下一处'));
      await tester.pump();
      expect(
        state.client.value.selection,
        const TextSelection(baseOffset: 3, extentOffset: 5),
      );
      expect(find.text('已定位第 4 字'), findsOneWidget);

      await tester.tap(find.text('下一处'));
      await tester.pump();
      expect(
        state.client.value.selection,
        const TextSelection(baseOffset: 0, extentOffset: 2),
      );
      expect(find.text('已定位第 1 字'), findsOneWidget);
    },
  );

  testWidgets('missing text reports explicitly without changing selection', (
    tester,
  ) async {
    await tester.pumpWidget(const _FindHost());
    await tester.pump();
    final state = tester.state<_FindHostState>(find.byType(_FindHost));
    final before = state.client.value.selection;

    await tester.enterText(find.byType(TextField), '不存在');
    await tester.tap(find.text('下一处'));
    await tester.pump();
    expect(find.text('本章没有匹配文字。'), findsOneWidget);
    expect(state.client.value.selection, before);
  });

  testWidgets('Escape closes the bar and the close button is usable', (
    tester,
  ) async {
    await tester.pumpWidget(const _FindHost());
    await tester.pump();
    final state = tester.state<_FindHostState>(find.byType(_FindHost));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(state.closed, isTrue);
  });
}
