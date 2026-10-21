// 作品选择负向回归：创建失败保留可重试上下文，成功才关闭，不连接原生存储。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/workspace/data/synthetic_workspace_repository.dart';
import 'package:paraselene_flutter/workspace/data/workspace_repository.dart';
import 'package:paraselene_flutter/workspace/presentation/work_picker.dart';
import 'support/m2_harness.dart';

class _CreateFailureRepository extends SyntheticWorkspaceRepository {
  _CreateFailureRepository() : super(withDemo: true);
  bool rejectCreate = true;
  @override
  Future<WorkspaceWork> createWork(String title) {
    if (rejectCreate) throw const WorkspaceFailure('create_failed');
    return super.createWork(title);
  }
}

void main() {
  setUpAll(loadM2Fonts);
  testWidgets('failed creation keeps the picker; successful retry closes it', (
    tester,
  ) async {
    tester.useSurface(const Size(1280, 900));
    final repository = _CreateFailureRepository();
    await tester.pumpWorkbench(repository: repository);
    await tester.activate('切换作品');
    expect(find.byType(WorkPicker), findsOneWidget);
    await tester.tap(find.text('新建作品').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('title-prompt-field')),
      '合成创建失败',
    );
    await tester.tap(find.text('创建').last);
    await tester.pumpAndSettle();
    expect(find.byType(WorkPicker), findsOneWidget);
    expect(repository.rejectCreate, isTrue);
    repository.rejectCreate = false;
    await tester.tap(find.text('新建作品').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('title-prompt-field')),
      '合成创建成功',
    );
    await tester.tap(find.text('创建').last);
    await tester.pumpAndSettle();
    expect(find.byType(WorkPicker), findsNothing);
    expect(find.text('合成创建成功'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
