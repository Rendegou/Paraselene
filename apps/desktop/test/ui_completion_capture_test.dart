// Real bundled fonts and production widgets against an exclusive temporary
// synthetic native session. No model requests, key/settings writes or author data.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/theme/workbench_theme.dart';
import 'package:paraselene_flutter/l10n/generated/app_localizations.dart';
import 'package:paraselene_flutter/lore/lore_library.dart';
import 'package:paraselene_flutter/lore/lore_edit_dialog.dart';
import 'package:paraselene_flutter/lore/lore_picker.dart';
import 'package:paraselene_flutter/legacy/character_dialog.dart';
import 'package:paraselene_flutter/legacy/companion_service.dart';
import 'package:paraselene_flutter/legacy/memory_dialog.dart';
import 'package:paraselene_flutter/legacy/imported_dialog.dart';
import 'package:paraselene_flutter/legacy/novel_history_dialog.dart';
import 'package:paraselene_flutter/cowrite/deepseek_settings.dart';
import 'package:paraselene_flutter/cowrite/discussion_panel.dart';
import 'package:paraselene_flutter/workspace/data/real_workspace_repository.dart';
import 'package:paraselene_flutter/workspace/workspace_controller.dart';
import 'package:paraselene_flutter/workspace/presentation/backup_dialog.dart';
import 'support/m2_harness.dart';

void main() {
  late RealWorkspaceRepository repository;
  late WorkspaceController workspace;
  setUpAll(() async {
    await loadM2Fonts();
    repository = await RealWorkspaceRepository.open(diagnosticOverride: true);
    workspace = WorkspaceController(repository);
    await workspace.restoreSession();
    await workspace.seedDemo();
  });
  tearDownAll(() async {
    workspace.dispose();
    await repository.close();
  });
  for (final variant in [
    (1440.0, 900.0, 1.0),
    (680.0, 900.0, 1.0),
    (680.0, 900.0, 2.0),
  ]) {
    for (final name in [
      'lore-edit',
      'lore-library',
      'lore-picker',
      'character',
      'memory-edit',
      'memory',
      'history',
      'import',
      'settings',
      'backup',
      'chapter-discussion',
    ]) {
      testWidgets('$name ${variant.$1} scale ${variant.$3}', (tester) async {
        tester.useSurface(Size(variant.$1, variant.$2));
        final shadows = debugDisableShadows;
        debugDisableShadows = false;
        addTearDown(() {
          debugDisableShadows = shadows;
        });
        final work = workspace.currentWork!.id;
        final widget = switch (name) {
          'lore-edit' => LoreEditDialog(
            repository: repository.lore,
            work: work,
          ),
          'lore-library' => LoreLibrary(
            repository: repository.lore,
            work: work,
          ),
          'lore-picker' => LorePicker(repository: repository.lore, work: work),
          'character' => CharacterDialog(
            repository: repository.legacy,
            companion: const UnavailableCompanionService(),
          ),
          'memory-edit' => MemoryEditDialog(
            repository: repository.legacy,
            space: 'personal',
          ),
          'memory' => MemoryDialog(repository: repository.legacy, work: work),
          'history' => NovelHistoryDialog(
            repository: repository.legacy,
            workspace: workspace,
          ),
          'import' => ImportedDialog(repository: repository.legacy),
          'settings' => DeepSeekSettings(repository: repository.discussions),
          'backup' => BackupDialog(
            repository: repository,
            workspace: workspace,
          ),
          _ => Dialog(
            child: SizedBox(
              width: 560,
              child: DiscussionPanel(
                thread: workspace.discussions!.chapterThread(),
                workspace: workspace,
                inDialog: true,
                onCollapse: () {},
              ),
            ),
          ),
        };
        await tester.pumpWidget(
          MaterialApp(
            theme: workbenchTheme(),
            locale: chinese,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(variant.$3)),
              child: RepaintBoundary(
                key: const ValueKey('capture'),
                child: child!,
              ),
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => widget,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pump();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 150));
        });
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        for (final field in tester.widgetList<TextField>(
          find.byType(TextField),
        )) {
          final style = WidgetStateProperty.resolveAs<TextStyle>(
            field.style!,
            {},
          );
          expect(style.fontFamily, WorkbenchTokens.uiFont);
          expect(style.fontSize, 14);
        }
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = Directory('../../build/ui-completion-20261021')
            ..createSync(recursive: true);
          await File(
            '${directory.path}/$name-${variant.$1.toInt()}-${variant.$3.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        debugDisableShadows = shadows;
        await tester.runAsync(() => workspace.discussions!.flush());
        if (name == 'chapter-discussion' && variant.$3 == 1) {
          expect(
            tester.getSize(find.byType(DiscussionPanel)).height,
            lessThan(500),
          );
          expect(find.text('全章讨论'), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
    }
  }
}
