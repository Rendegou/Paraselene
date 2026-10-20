// R03 操作一致性测试：宽稿只由 controller 的每作品持久偏好决定，顶栏勾选与纸面宽度
// 必须同源；切换作品与重开工作台后各自恢复，且版面变化不重建编辑器。
// 仅使用合成仓库，不连接真实 FFI 或作者材料。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/editor/editor_viewport.dart';
import 'package:paraselene_flutter/l10n/generated/app_localizations.dart';
import 'package:paraselene_flutter/theme/workbench_theme.dart';
import 'package:paraselene_flutter/workspace/data/synthetic_workspace_repository.dart';
import 'package:paraselene_flutter/workspace/presentation/workbench_screen.dart';
import 'package:paraselene_flutter/workspace/workspace_controller.dart';

import '../support/m2_harness.dart';

void main() {
  setUpAll(loadM2Fonts);

  testWidgets('版式菜单写入 controller.wide，纸面宽度与重启恢复同源', (tester) async {
    final repository = SyntheticWorkspaceRepository(withDemo: true);
    final first = await _pump(tester, repository);

    expect(first.controller.wide, isFalse);
    expect(_readableWidth(tester), 760);

    await tester.tap(find.byTooltip('版式'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('宽稿 · 920 px'));
    await tester.pumpAndSettle();

    expect(first.controller.wide, isTrue);
    expect(_readableWidth(tester), 920);
    // 版面切换不得重置正文编辑器（contentEpoch 只在导航/确认/回滚时递增）。
    expect(first.controller.editing.contentEpoch, 1);

    // 等待 UI 会话偏好防抖写盘，再模拟冷启动。
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(const SizedBox());
    first.dispose();

    final restarted = await _pump(tester, repository);
    expect(restarted.controller.wide, isTrue);
    expect(_readableWidth(tester), 920);
  });

  testWidgets('作品 A 宽稿、作品 B 舒适：切换作品各自恢复', (tester) async {
    final repository = SyntheticWorkspaceRepository(withDemo: true);
    final harness = await _pump(tester, repository);
    final controller = harness.controller;
    final workA = controller.currentWork!;

    await tester.tap(find.byTooltip('版式'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('宽稿 · 920 px'));
    await tester.pumpAndSettle();
    expect(controller.wide, isTrue);
    await tester.pump(const Duration(milliseconds: 400));

    expect(await controller.createWork('第二部'), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.currentWork?.title, '第二部');
    expect(controller.wide, isFalse);

    expect(await controller.selectWork(workA), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.currentWork?.title, '雨后的书店');
    expect(controller.wide, isTrue);
    expect(_readableWidth(tester), 920);
    expect(tester.takeException(), isNull);
  });
}

/// 正文实际排版宽度；纸面容器可更宽，但可读行宽必须与版式偏好一致。
double _readableWidth(WidgetTester tester) => tester
    .state<EditorViewportState>(find.byKey(manuscriptKey))
    .controller
    .layout
    .width;

Future<_Harness> _pump(
  WidgetTester tester,
  SyntheticWorkspaceRepository repository,
) async {
  tester.useSurface(const Size(1440, 900));
  final controller = WorkspaceController(repository);
  final harness = _Harness(controller);
  await controller.restoreSession();
  await tester.pumpWidget(
    Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: MaterialApp(
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
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return harness;
}

class _Harness {
  _Harness(this.controller) {
    addTearDown(dispose);
  }

  final WorkspaceController controller;
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    controller.dispose();
  }
}
