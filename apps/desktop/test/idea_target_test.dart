// 覆盖灵感指针与目标对话框：对象载荷编解码、坏指针拒绝、CAS 保存与失败提示。
// widget 测试只验证 Dart 交互与本地化，不代表真实 FFI 转换或作者数据迁移通过。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/legacy/idea_target_dialog.dart';
import 'package:paraselene_flutter/legacy/legacy_repository.dart';
import 'package:paraselene_flutter/l10n/generated/app_localizations.dart';

const _chinese = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans');

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    locale: _chinese,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(body: child),
  ),
);

IdeaTargetView _view({String title = '目标一', String summary = '原有笔记'}) =>
    IdeaTargetView(
      space: 'novel',
      record: {
        'id': 'target-1',
        'workId': 'work-1',
        'title': title,
        'summary': summary,
        'updatedAt': '2026-10-20T00:00:00Z',
      },
      sources: [
        {'text': '来源句一'},
      ],
    );

void main() {
  group('converted idea pointer', () {
    test('object payload carries exact space and work identity', () {
      final pointer = convertedIdeaTargetPointer({
        'payload': {
          'convertedTo': {'space': 'novel', 'memoryId': 'm1', 'workId': 'w1'},
        },
      });
      expect(pointer, isNotNull);
      expect(pointer!.space, 'novel');
      expect(pointer.memoryId, 'm1');
      expect(pointer.workId, 'w1');
    });

    test('encoded payload is decoded', () {
      final pointer = convertedIdeaTargetPointer({
        'payload': '{"convertedTo":{"space":"personal","memoryId":"m2"}}',
      });
      expect(pointer!.space, 'personal');
      expect(pointer.workId, isNull);
    });

    test('unconverted idea has no pointer', () {
      expect(convertedIdeaTargetPointer({'payload': null}), isNull);
      expect(
        convertedIdeaTargetPointer({
          'payload': {'note': 'x'},
        }),
        isNull,
      );
    });

    test('malformed pointer is rejected instead of guessed', () {
      expect(
        () => convertedIdeaTargetPointer({
          'payload': {
            'convertedTo': {'space': 1, 'memoryId': 'm'},
          },
        }),
        throwsFormatException,
      );
    });
  });

  testWidgets('target dialog loads, saves with CAS and reports failure', (
    tester,
  ) async {
    var loads = 0;
    var saves = 0;
    String? savedTitle;
    String? savedSummary;
    var fail = false;
    await _pump(
      tester,
      IdeaTargetDialog(
        idea: const {},
        loadTarget: (_) async {
          loads++;
          return _view();
        },
        saveTarget: (target, title, summary) async {
          saves++;
          savedTitle = title;
          savedSummary = summary;
          if (fail) throw StateError('synthetic conflict');
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(loads, 1);
    expect(find.text('目标一'), findsOneWidget);
    expect(find.text('原有笔记'), findsOneWidget);
    expect(find.text('编辑小说目标会同步修改作品名。'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '新目标名');
    await tester.enterText(find.byType(TextField).last, '新笔记');
    await tester.tap(find.text('保存目标'));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(savedTitle, '新目标名');
    expect(savedSummary, '新笔记');
    expect(loads, 2);

    fail = true;
    await tester.tap(find.text('保存目标'));
    await tester.pumpAndSettle();
    expect(find.text('目标未能保存，请刷新后重试。'), findsOneWidget);
  });

  testWidgets('missing target is disclosed and cannot be saved', (
    tester,
  ) async {
    await _pump(
      tester,
      IdeaTargetDialog(
        idea: const {},
        loadTarget: (_) async => null,
        saveTarget: (_, _, _) async {},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('这条旧想法没有可打开的目标。'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '保存目标'),
    );
    expect(button.onPressed, isNull);
  });
}
