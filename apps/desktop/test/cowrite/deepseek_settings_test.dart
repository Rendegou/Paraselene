// DeepSeek 设置弹窗的异步关闭回归：仅使用合成输入与受控 Future。
// 不读取凭据、不调用 FFI/网络，也不代表真实 Windows 凭据存储通过。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/cowrite/deepseek_settings.dart';
import 'package:paraselene_flutter/cowrite/generation_repository.dart';
import 'package:paraselene_flutter/l10n/generated/app_localizations.dart';
import 'package:paraselene_flutter/theme/workbench_theme.dart';

import '../support/m2_harness.dart';

enum _PendingStep { saveKey, saveCloud, deleteCloud, deleteKey }

class _SettingsRepository implements GenerationRepository {
  final pending = Completer<void>();
  final calls = <String>[];
  final keys = <String>[];
  late _PendingStep step;

  @override
  Future<void> setKey(String key) async {
    keys.add(key);
    calls.add('key');
    if (step == _PendingStep.saveKey) await pending.future;
  }

  @override
  Future<void> setCloudEnabled(bool enabled) async {
    calls.add('cloud:$enabled');
    if (step == _PendingStep.saveCloud || step == _PendingStep.deleteCloud) {
      await pending.future;
    }
  }

  @override
  Future<void> deleteKey() async {
    calls.add('delete');
    if (step == _PendingStep.deleteKey) await pending.future;
  }

  @override
  Future<void> activateScope(String? work, String? chapter) async {}

  @override
  Future<void> cancel(String work, String operation) async {
    throw StateError('Settings must not cancel a model request');
  }

  @override
  Future<Map<String, dynamic>> prepare(Map<String, dynamic> request) async {
    throw StateError('Settings must not prepare a model request');
  }

  @override
  Future<void> send(
    String work,
    String preview, {
    required bool confirmed,
  }) async {
    throw StateError('Settings must not send a model request');
  }
}

class _SettingsHost extends StatelessWidget {
  const _SettingsHost(this.repository);
  final GenerationRepository repository;

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: workbenchTheme(),
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            await showDialog<void>(
              context: context,
              builder: (_) => DeepSeekSettings(repository: repository),
            );
          },
          child: const Text('Open synthetic settings'),
        ),
      ),
    ),
  );
}

Future<void> _startPending(
  WidgetTester tester,
  _SettingsRepository repository,
  _PendingStep step,
) async {
  repository.step = step;
  tester.useSurface(const Size(1280, 900));
  await tester.pumpWidget(_SettingsHost(repository));
  await tester.tap(find.text('Open synthetic settings'));
  await tester.pumpAndSettle();
  if (step != _PendingStep.saveCloud) {
    await tester.enterText(find.byType(TextField), 'synthetic-test-input');
  }
  final deleting =
      step == _PendingStep.deleteCloud || step == _PendingStep.deleteKey;
  await tester.tap(find.byType(CheckboxListTile));
  final strings = AppLocalizations.of(
    tester.element(find.byType(DeepSeekSettings)),
  );
  await tester.tap(
    find.text(
      deleting ? strings.deepseekDeleteKey : strings.deepseekSaveSettings,
    ),
  );
  await tester.pump();
  expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
  expect(
    tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).onChanged,
    isNull,
  );
}

void main() {
  setUpAll(loadM2Fonts);
  for (final step in _PendingStep.values) {
    for (final fail in [false, true]) {
      for (final escape in [false, true]) {
        testWidgets(
          '${step.name} completes ${fail ? 'with failure' : 'successfully'} '
          'after ${escape ? 'Escape' : 'outside click'} disposes the dialog',
          (tester) async {
            final repository = _SettingsRepository();
            await _startPending(tester, repository, step);
            if (escape) {
              await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            } else {
              await tester.tapAt(const Offset(8, 8));
            }
            await tester.pumpAndSettle();
            expect(find.byType(DeepSeekSettings), findsNothing);
            if (fail) {
              repository.pending.completeError(StateError('synthetic failure'));
            } else {
              repository.pending.complete();
            }
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(find.text('Open synthetic settings'), findsOneWidget);
            final expected = switch (step) {
              _PendingStep.saveKey => fail ? ['key'] : ['key', 'cloud:true'],
              _PendingStep.saveCloud => ['cloud:true'],
              _PendingStep.deleteCloud =>
                fail ? ['cloud:false'] : ['cloud:false', 'delete'],
              _PendingStep.deleteKey => ['cloud:false', 'delete'],
            };
            expect(repository.calls, expected);
            expect(
              repository.keys,
              step == _PendingStep.saveKey ? ['synthetic-test-input'] : isEmpty,
            );
          },
        );
      }
    }
  }

  testWidgets('failed save clears input and leaves a recoverable dialog', (
    tester,
  ) async {
    final repository = _SettingsRepository();
    await _startPending(tester, repository, _PendingStep.saveKey);
    repository.pending.completeError(StateError('synthetic failure'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
    expect(field.enabled, isTrue);
    final strings = AppLocalizations.of(
      tester.element(find.byType(DeepSeekSettings)),
    );
    expect(find.text(strings.generationFailed), findsOneWidget);
    expect(repository.calls, ['key']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delete clears synthetic input and disables cloud on success', (
    tester,
  ) async {
    final repository = _SettingsRepository();
    await _startPending(tester, repository, _PendingStep.deleteKey);
    repository.pending.complete();
    await tester.pumpAndSettle();
    expect(find.byType(DeepSeekSettings), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
    expect(field.enabled, isTrue);
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
    expect(repository.calls, ['cloud:false', 'delete']);
    expect(tester.takeException(), isNull);
  });
}
