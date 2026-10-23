// M2 工作台测试的共享装配：离线字体加载、合成仓库与工作台 pump 辅助。
// 仅提供测试脚手架且不含断言，不代表真实 Windows 窗口或 FFI 行为通过。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/workspace/data/synthetic_workspace_repository.dart';
import 'package:paraselene_flutter/workspace/data/workspace_repository.dart';
import 'package:paraselene_flutter/workspace/workbench_app.dart';

const chinese = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans');
const manuscriptKey = ValueKey('manuscript-body');

/// Loads the exact bundled faces rather than accepting the test Ahem font.
Future<void> loadM2Fonts() async {
  for (final family in <String, List<String>>{
    'Notebook Sans': [
      'NotoSansSC-Regular.ttf',
      'NotoSansSC-Medium.ttf',
      'NotoSansSC-Semibold.ttf',
    ],
    'Notebook Serif': ['NotoSerifSC-Regular.ttf'],
    'Noto Arabic': ['NotoNaskhArabic.ttf'],
  }.entries) {
    final loader = FontLoader(family.key);
    for (final file in family.value) {
      loader.addFont(rootBundle.load('assets/fonts/$file'));
    }
    await loader.load();
  }
  final icons = FontLoader('MaterialIcons');
  icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
}

extension M2Harness on WidgetTester {
  void useSurface(Size logical, {double dpr = 1}) {
    view.devicePixelRatio = dpr;
    view.physicalSize = logical * dpr;
    addTearDown(view.reset);
  }

  Future<void> pumpWorkbench({
    WorkspaceRepository? repository,
    Locale locale = chinese,
    double scale = 1,
    bool bold = false,
    bool pseudo = false,
    bool rtl = false,
  }) async {
    await pumpWidget(
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            boldText: bold,
            disableAnimations: true,
          ),
          child: WorkbenchApp(
            repository:
                repository ?? SyntheticWorkspaceRepository(withDemo: true),
            initialLocale: locale,
            pseudoLocalize: pseudo,
            rtlHarness: rtl,
          ),
        ),
      ),
    );
    await flushWorkbench();
  }

  Future<void> flushWorkbench() async {
    await pump();
    await pump();
    await pump(const Duration(milliseconds: 300));
  }

  Future<void> activate(String label) async {
    final text = find.text(label).first;
    // CheckedPopupMenuItem 的文字被 IgnorePointer 包裹；真实命中由整行接收。
    final menu = find.ancestor(
      of: text,
      matching: find.byWidgetPredicate(
        (widget) => widget is PopupMenuEntry<dynamic>,
      ),
    );
    final target = menu.evaluate().isEmpty ? text : menu.first;
    await ensureVisible(target);
    await tap(target);
    await flushWorkbench();
  }
}

/// A recoverable fixture failure; it cannot validate a native bridge.
class RetryRepository extends SyntheticWorkspaceRepository {
  RetryRepository() : super(withDemo: true);
  bool failNext = true;
  @override
  Future<List<WorkspaceWork>> listWorks() {
    if (failNext) {
      failNext = false;
      throw const WorkspaceFailure('fixture_unavailable');
    }
    return super.listWorks();
  }
}
