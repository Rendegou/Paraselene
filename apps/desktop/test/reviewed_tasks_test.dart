// 覆盖审核任务 UI 与数据合同：有界 diff 展示、预览撤销、取消运行与迟到结果处理。
// widget 测试使用假仓库与假传输，不代表真实模型请求、网络或 FFI 通过。

import 'dart:async';
import 'package:paraselene_flutter/cowrite/candidate_diff.dart';
import 'package:paraselene_flutter/cowrite/discussion_thread.dart';
import 'package:paraselene_flutter/lore/lore_source_view.dart';
import 'package:paraselene_flutter/lore/lore_map_preview.dart';
import 'package:paraselene_flutter/theme/workbench_theme.dart';
import 'support/m2_harness.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/legacy/reviewed_task_repository.dart';
import 'package:paraselene_flutter/legacy/reviewed_task_dialog.dart';
import 'package:paraselene_flutter/l10n/generated/app_localizations.dart';
import 'package:paraselene_flutter/cowrite/character_diff.dart';

final class Tasks implements ReviewedTaskRepository {
  final requests = <Map<String, dynamic>>[];
  final cancelled = <String>[];
  int sends = 0;
  bool cancelCompletes = true;
  Completer<Map<String, dynamic>>? waiting;
  @override
  Future<Map<String, dynamic>> prepareTask(Map<String, dynamic> request) async {
    requests.add(request);
    return {
      'id': 'ticket-${requests.length}',
      'prepared': {
        'model': 'fixture',
        'estimated_tokens': 7,
        'messages': [
          {'role': 'system', 'content': 'EXACT material 👩‍💻\r\n'},
        ],
      },
    };
  }

  @override
  Future<Map<String, dynamic>> sendTask(String work, String id) async {
    sends++;
    if (waiting != null) return waiting!.future;
    if (requests.last['kind'] == 'scene') {
      return {
        'kind': 'scene',
        'id': 'scene-token',
        'scene': {
          'scene': 'Temporary scene',
          'options': ['Knock', 'Wait'],
        },
      };
    }
    return requests.last['kind'] == 'summary'
        ? {
            'kind': 'summary',
            'summary': {'body': 'Derived summary'},
          }
        : {
            'kind': 'draft',
            'draft': {'body': 'Pending prose'},
          };
  }

  @override
  Future<void> cancelTask(String work, String id) async {
    cancelled.add(id);
    if (waiting case final pending?
        when !pending.isCompleted && cancelCompletes) {
      pending.completeError(StateError('cancelled'));
    }
  }
}

Future<void> host(
  WidgetTester tester,
  Tasks tasks, {
  bool summary = false,
}) async {
  tester.view.physicalSize = const Size(1300, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ReviewedTaskDialog(
        repository: tasks,
        work: 'work',
        chapter: 'chapter',
        summaryOnly: summary,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> preview(WidgetTester tester) async {
  await tester.tap(find.text('Review outgoing messages'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> approve(WidgetTester tester) async {
  await tester.tap(find.text('Approve these messages and send once'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  test(
    'diff preserves exact Unicode, CRLF and both reconstruction directions',
    () {
      for (final pair in [
        ('A👩‍💻é\r\n é end', 'A👩‍💻é\r\n changed end'),
        ('', 'é'),
        ('x', ''),
        ('same', 'same'),
        ('${'a' * 1000}X${'c' * 1000}', '${'b' * 1000}X${'d' * 1000}'),
      ]) {
        final parts = characterDiff(pair.$1, pair.$2);
        expect(
          parts.where((p) => p.change <= 0).map((p) => p.text).join(),
          pair.$1,
        );
        expect(
          parts.where((p) => p.change >= 0).map((p) => p.text).join(),
          pair.$2,
        );
      }
      expect(
        characterDiff(
          '👩‍💻',
          '👨‍💻',
        ).every((p) => p.text.characters.length == 1),
        isTrue,
      );
    },
  );
  test('large deletion and insertion use bounded exact display spans', () {
    for (final pair in [
      ('x' * 200000, ''),
      ('', '👩‍💻' * 20000),
      ('a', 'b' * 200000),
    ]) {
      final parts = characterDiff(pair.$1, pair.$2);
      expect(parts.length, lessThanOrEqualTo(2));
      expect(
        parts.where((p) => p.change <= 0).map((p) => p.text).join(),
        pair.$1,
      );
      expect(
        parts.where((p) => p.change >= 0).map((p) => p.text).join(),
        pair.$2,
      );
    }
  });
  testWidgets('declining exact preview revokes ticket and sends nothing', (
    tester,
  ) async {
    final tasks = Tasks();
    await host(tester, tasks, summary: true);
    await preview(tester);
    expect(find.textContaining('EXACT material'), findsOneWidget);
    expect(tasks.sends, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tasks.cancelled, contains('ticket-1'));
    expect(tasks.sends, 0);
  });
  testWidgets(
    'RPG requires distinct approvals and sends opaque scene id with reply',
    (tester) async {
      final tasks = Tasks();
      await host(tester, tasks);
      await tester.enterText(find.byType(TextField), 'Rain');
      await preview(tester);
      await approve(tester);
      expect(find.text('Temporary scene'), findsOneWidget);
      expect(tasks.sends, 1);
      await tester.tap(find.text('Knock'));
      await preview(tester);
      expect(tasks.requests.last['sceneId'], 'scene-token');
      expect(tasks.requests.last['text'], 'Knock');
      expect(tasks.sends, 1);
      await approve(tester);
      await tester.pumpAndSettle();
      expect(tasks.sends, 2);
      expect(find.text('Pending prose'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('cancel running summary releases transport and permits close', (
    tester,
  ) async {
    final tasks = Tasks()..waiting = Completer();
    await host(tester, tasks, summary: true);
    await preview(tester);
    await approve(tester);
    expect(tasks.sends, 1);
    await tester.tap(find.text('Cancel generation'));
    await tester.pumpAndSettle();
    expect(tasks.cancelled, contains('ticket-1'));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'summary result is derived and never exposes manuscript adoption',
    (tester) async {
      final tasks = Tasks();
      await host(tester, tasks, summary: true);
      await preview(tester);
      await approve(tester);
      await tester.pumpAndSettle();
      expect(tasks.requests.single['kind'], 'summary');
      expect(find.text('Derived summary'), findsOneWidget);
      expect(find.text('Apply'), findsNothing);
    },
  );
  testWidgets('late cancel cannot hide a committed successful result', (
    tester,
  ) async {
    final tasks = Tasks()
      ..waiting = Completer()
      ..cancelCompletes = false;
    await host(tester, tasks, summary: true);
    await preview(tester);
    await approve(tester);
    await tester.tap(find.text('Cancel generation'));
    await tester.pump();
    tasks.waiting!.complete({
      'kind': 'summary',
      'summary': {'body': 'Already committed'},
    });
    await tester.pumpAndSettle();
    expect(find.text('Already committed'), findsOneWidget);
  });
  testWidgets('nullable legacy target can render durable revision history', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ThreadVersionHistory(
            thread: DiscussionThread(
              id: 'thread',
              chapter: 'chapter',
              snapshot: {'target': null, 'versions': []},
            ),
            operations: const [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'historical source highlights Unicode scalars against original body',
    (tester) async {
      const body = 'A👩‍💻 é\r\n';
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: LoreSourceView(
              source: {
                'body': body,
                'anchor': {'startChar': 1, 'endChar': 4, 'isCurrent': false},
              },
              onOpen: () {},
            ),
          ),
        ),
      );
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      final span = tester
          .widget<SelectableText>(find.byType(SelectableText))
          .textSpan!;
      expect(span.toPlainText(), body);
      expect((span.children![1] as TextSpan).text, '👩‍💻');
      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNull,
      );
    },
  );
  testWidgets(
    'map previews only locations, links and drags without native writes',
    (tester) async {
      final positions = <String, Offset>{};
      final links = <(String, String)>{};
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: LoreMapPreview(
              rows: [
                {
                  'entry': {'id': 'a', 'name': 'Gate', 'kind': 'location'},
                },
                {
                  'entry': {'id': 'b', 'name': 'Harbor', 'kind': 'location'},
                },
                {
                  'entry': {'id': 'c', 'name': 'Person', 'kind': 'character'},
                },
              ],
              positions: positions,
              links: links,
              onOpen: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Person'), findsNothing);
      await tester.tap(find.text('Relation').at(0));
      await tester.tap(find.text('Relation').at(1));
      await tester.pump();
      expect(links, {('a', 'b')});
      final drag = await tester.startGesture(
        tester.getCenter(find.text('Gate')),
      );
      await drag.moveBy(const Offset(25, 25));
      await tester.pump();
      await drag.moveBy(const Offset(30, 40));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();
      expect(positions['a'], isNotNull);
      final before = positions['a']!;
      tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!
          .value = Matrix4.diagonal3Values(
        2,
        2,
        1,
      );
      await tester.pump();
      final zoomed = await tester.startGesture(
        tester.getCenter(find.text('Gate')),
      );
      await zoomed.moveBy(const Offset(25, 25));
      await tester.pump();
      await zoomed.moveBy(const Offset(30, 40));
      await tester.pump();
      await zoomed.up();
      await tester.pumpAndSettle();
      expect((positions['a']! - before).dx, closeTo(15, .01));
      expect((positions['a']! - before).dy, closeTo(20, .01));
      final edge = await tester.startGesture(
        tester.getCenter(find.text('Gate')),
      );
      await edge.moveBy(const Offset(-30, 0));
      await tester.pump();
      await edge.moveBy(const Offset(-1000, 0));
      await tester.pump();
      await edge.up();
      await tester.pumpAndSettle();
      expect(positions['a']!.dx, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('map canvas contains every default location in a large catalog', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: LoreMapPreview(
            rows: List.generate(
              71,
              (i) => {
                'entry': {'id': '$i', 'name': 'place $i', 'kind': 'location'},
              },
            ),
            positions: {},
            links: {},
            onOpen: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final canvas = viewer.child as SizedBox;
    final top = tester
        .widget<Positioned>(
          find.ancestor(
            of: find.text('place 70'),
            matching: find.byType(Positioned),
          ),
        )
        .top!;
    expect(top + 88, lessThanOrEqualTo(canvas.height!));
    expect(tester.takeException(), isNull);
  });
  testWidgets('map relation keeps 48px hit target at doubled text size', (
    tester,
  ) async {
    await loadM2Fonts();
    await tester.pumpWidget(
      MaterialApp(
        theme: workbenchTheme(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: LoreMapPreview(
            rows: [
              {
                'entry': {'id': 'a', 'name': 'Gate', 'kind': 'location'},
              },
            ],
            positions: {},
            links: {},
            onOpen: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final relation = find
        .ancestor(
          of: find.text('Relation'),
          matching: find.byWidgetPredicate((widget) => widget is TextButton),
        )
        .first;
    expect(tester.getSize(relation).height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });
}
