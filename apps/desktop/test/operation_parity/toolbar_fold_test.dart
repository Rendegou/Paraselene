// R13：工具栏按实际可用宽度与文字缩放折叠，核心写作入口不丢失。
// 覆盖窄窗折叠菜单、宽窗常驻入口、语义名与可点击目标尺寸；不连真实 FFI。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/l10n/generated/app_localizations.dart';
import 'package:paraselene_flutter/theme/workbench_theme.dart';
import 'package:paraselene_flutter/workspace/data/synthetic_workspace_repository.dart';
import 'package:paraselene_flutter/workspace/presentation/workbench_screen.dart';
import 'package:paraselene_flutter/workspace/workspace_controller.dart';

import '../support/m2_harness.dart';

void main() {
  setUpAll(loadM2Fonts);

  Future<WorkspaceController> pump(
    WidgetTester tester, {
    required Size size,
    required Locale locale,
    double scale = 1,
  }) async {
    tester.useSurface(size);
    final controller = WorkspaceController(
      SyntheticWorkspaceRepository(withDemo: true),
    );
    await controller.restoreSession();
    addTearDown(() async {
      await controller.editing.flushAll();
      controller.dispose();
    });
    await tester.pumpWidget(
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: workbenchTheme(),
            home: WorkbenchScreen(
              controller: controller,
              locale: locale,
              onLocaleChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return controller;
  }

  testWidgets('布局矩阵不溢出且核心入口始终存在', (tester) async {
    const sizes = [
      Size(360, 720),
      Size(600, 800),
      Size(900, 700),
      Size(1440, 900),
      Size(1920, 1080),
    ];
    for (final locale in const [chinese, Locale('en')]) {
      for (final size in sizes) {
        for (final scale in const [1.0, 2.0]) {
          await pump(tester, size: size, locale: locale, scale: scale);
          expect(
            tester.takeException(),
            isNull,
            reason: 'overflow at $locale $size scale=$scale',
          );
          // 查找正文与更多在全部宽度都可见；写作者不会因折叠丢失入口。
          final s = AppLocalizations.of(
            tester.element(find.byType(WorkbenchScreen)),
          );
          expect(
            find.byTooltip(s.findInChapter),
            findsOneWidget,
            reason: 'find missing at $locale $size scale=$scale',
          );
          expect(
            find.byTooltip(s.moreTools),
            findsOneWidget,
            reason: 'more missing at $locale $size scale=$scale',
          );
          // 保存状态点/文字至少有一种可读形态。
          expect(
            find.byKey(const ValueKey('save-status')).evaluate().isNotEmpty ||
                find
                    .byKey(const ValueKey('save-status-dot'))
                    .evaluate()
                    .isNotEmpty,
            isTrue,
            reason: 'save status missing at $locale $size scale=$scale',
          );
        }
      }
    }
  });

  testWidgets('窄窗通过更多菜单保留低频功能', (tester) async {
    final controller = await pump(
      tester,
      size: const Size(360, 720),
      locale: chinese,
      scale: 2,
    );
    final s = AppLocalizations.of(tester.element(find.byType(WorkbenchScreen)));

    // 窄窗不常驻章节/版本、版式、导出、语言与专注按钮，避免挤掉写作入口。
    expect(find.byTooltip(s.chapterAndVersions), findsNothing);
    expect(find.byTooltip(s.exportWork), findsNothing);
    expect(find.byTooltip(s.languageLabel), findsNothing);

    await tester.tap(find.byTooltip(s.moreTools));
    await tester.pumpAndSettle();

    // 更多菜单是窄窗的完整后备：版本、版式、专注、导出、语言都在其中。
    expect(find.text(s.confirmChapter), findsOneWidget);
    expect(find.text(s.versionsTitle), findsOneWidget);
    expect(find.text(s.layoutComfort), findsOneWidget);
    expect(find.text(s.layoutWide), findsOneWidget);
    expect(find.text(s.focusOn), findsOneWidget);
    expect(find.text(s.exportWork), findsOneWidget);
    expect(find.text(s.chineseLabel), findsOneWidget);
    expect(find.text(s.englishLabel), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 从菜单退出：不改变正文/章节，只关闭菜单。
    await tester.tap(find.text(s.chineseLabel));
    await tester.pumpAndSettle();
    expect(controller.currentChapter, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('顶栏按钮有语义名、禁用态与足够目标尺寸', (tester) async {
    final controller = await pump(
      tester,
      size: const Size(360, 720),
      locale: chinese,
      scale: 2,
    );
    final s = AppLocalizations.of(tester.element(find.byType(WorkbenchScreen)));
    expect(controller.phase, isNotNull);

    // 图标按钮的语义名来自 Semantics（Tooltip 已排除语义，避免重复朗读）。
    Finder semanticsNamed(String label) => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    );
    expect(semanticsNamed(s.findInChapter), findsOneWidget);
    expect(
      tester
          .widget<Semantics>(semanticsNamed(s.findInChapter))
          .properties
          .onTap,
      isNotNull,
    );
    // “更多”是 PopupMenuButton，其可访问名由按钮自身 tooltip 提供。
    expect(find.byTooltip(s.moreTools), findsOneWidget);

    // 透明命中高度48，可视底板32，且不撑破56px顶栏。
    final findSize = tester.getSize(find.byTooltip(s.findInChapter));
    expect(findSize.height, greaterThanOrEqualTo(48));
    expect(findSize.height, lessThanOrEqualTo(56));
    expect(
      tester.getSize(find.byTooltip(s.moreTools)).height,
      greaterThanOrEqualTo(40),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('不可用的模型设置在宽窗保留入口且语义标记禁用', (tester) async {
    await pump(tester, size: const Size(1440, 900), locale: chinese);
    final s = AppLocalizations.of(tester.element(find.byType(WorkbenchScreen)));

    // 合成仓库不是真实资料库，模型设置按钮保持可见但禁用，而不是静默消失。
    expect(find.byTooltip(s.modelSettings), findsOneWidget);
    final disabled = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.label == s.modelSettings &&
          widget.properties.enabled == false,
    );
    expect(disabled, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
