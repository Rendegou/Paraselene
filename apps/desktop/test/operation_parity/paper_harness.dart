// R05 纸面流程测试共用脚手架：用合成仓库直接挂载工作台，暴露 controller，
// 以便检查真实 ScrollPosition、恢复状态与正文布局坐标。不连接真实 FFI。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/l10n/generated/app_localizations.dart';
import 'package:paraselene_flutter/theme/workbench_theme.dart';
import 'package:paraselene_flutter/workspace/data/synthetic_workspace_repository.dart';
import 'package:paraselene_flutter/workspace/presentation/workbench_screen.dart';
import 'package:paraselene_flutter/workspace/workspace_controller.dart';

import '../support/m2_harness.dart';

/// 挂载工作台并返回可直接驱动的 controller。
Future<WorkspaceController> pumpPaperWorkbench(
  WidgetTester tester, {
  SyntheticWorkspaceRepository? repository,
  Size size = const Size(1440, 900),
  double textScale = 1,
}) async {
  tester.useSurface(size);
  final controller = WorkspaceController(
    repository ?? SyntheticWorkspaceRepository(withDemo: true),
  );
  await controller.restoreSession();
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('paper-capture-root'),
      child: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: true,
            textScaler: TextScaler.linear(textScale),
          ),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: chinese,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: workbenchTheme(),
            home: WorkbenchScreen(
              controller: controller,
              locale: chinese,
              onLocaleChanged: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return controller;
}

/// 清理 controller：先把编辑草稿写回合成仓库，避免 dispose 的脏文本断言。
Future<void> disposePaperController(WorkspaceController controller) async {
  await controller.editing.flushAll();
  controller.dispose();
}

/// 生成足够撑满多屏的中文段落，供长章滚动/恢复场景使用。
String longBody({int paragraphs = 60}) => List.generate(
  paragraphs,
  (index) =>
      '第${index + 1}段：雨落在旧书店的玻璃上，灯影顺着屋檐慢慢滑下去。'
      '她把伞收在门边，听见纸页翻动的声音，像很远的地方有人在轻声说话。',
).join('\n');
