// 写作工作台主界面：目录侧栏 + 56px 顶部工具栏 + 纸面内容区。
//
// 布局对齐原 TS 版：桌面宽度常驻 240px 目录，窄布局改为抽屉；专注模式隐藏
// 目录但保留工具栏；宽稿/舒适只影响纸面正文宽度。所有状态来自 controller。
import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/workbench_theme.dart';
import '../workspace_controller.dart';
import 'editor_action_registry.dart';
import 'editor_status.dart';
import 'workbench_chrome.dart';
import 'workbench_content.dart';
import 'workbench_sidebar.dart';

/// 阅读与写作主界面；只做布局与工具装配，不直接读写仓库。
class WorkbenchScreen extends StatefulWidget {
  const WorkbenchScreen({
    required this.controller,
    required this.locale,
    required this.onLocaleChanged,
    this.pseudoLocalize = false,
    this.rtlHarness = false,
    super.key,
  });
  final WorkspaceController controller;
  final Locale locale;
  final ValueChanged<Locale> onLocaleChanged;
  final bool pseudoLocalize;
  final bool rtlHarness;

  @override
  State<WorkbenchScreen> createState() => _WorkbenchScreenState();
}

class _WorkbenchScreenState extends State<WorkbenchScreen> {
  final EditorActionRegistry _actions = EditorActionRegistry();
  bool _focus = false;
  bool _sidebar = true;

  @override
  void dispose() {
    _actions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: widget.rtlHarness
        ? TextDirection.rtl
        : Directionality.of(context),
    child: AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => _WorkbenchLayout(
        controller: widget.controller,
        locale: widget.locale,
        onLocaleChanged: widget.onLocaleChanged,
        labels: WorkbenchLabels(
          AppLocalizations.of(context),
          widget.pseudoLocalize,
        ),
        focus: _focus,
        sidebar: _sidebar,
        actions: _actions,
        onCollapse: () => setState(() => _sidebar = false),
        onExpand: () => setState(() => _sidebar = true),
        onFocus: () => setState(() => _focus = !_focus),
        onExitFocus: () => setState(() => _focus = false),
      ),
    ),
  );
}

class _WorkbenchLayout extends StatelessWidget {
  const _WorkbenchLayout({
    required this.controller,
    required this.locale,
    required this.onLocaleChanged,
    required this.labels,
    required this.focus,
    required this.sidebar,
    required this.actions,
    required this.onCollapse,
    required this.onExpand,
    required this.onFocus,
    required this.onExitFocus,
  });
  final WorkspaceController controller;
  final Locale locale;
  final ValueChanged<Locale> onLocaleChanged;
  final WorkbenchLabels labels;
  final bool focus;
  final bool sidebar;
  final EditorActionRegistry actions;
  final VoidCallback onCollapse;
  final VoidCallback onExpand;
  final VoidCallback onFocus;
  final VoidCallback onExitFocus;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final expanded =
          constraints.maxWidth >= 900 &&
          MediaQuery.textScalerOf(context).scale(16) < 24;
      return Scaffold(
        drawer: expanded
            ? null
            : Drawer(
                child: SafeArea(
                  child: WorkbenchSidebar(
                    controller: controller,
                    labels: labels,
                    closeOnSelect: true,
                    onCollapse: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
        body: SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (expanded && sidebar && !focus)
                SizedBox(
                  width: WorkbenchTokens.directoryWidth,
                  child: WorkbenchSidebar(
                    controller: controller,
                    labels: labels,
                    onCollapse: onCollapse,
                  ),
                ),
              Expanded(
                child: Builder(
                  builder: (context) => _WorkbenchMain(
                    controller: controller,
                    labels: labels,
                    locale: locale,
                    onLocaleChanged: onLocaleChanged,
                    focus: focus,
                    actions: actions,
                    onFocus: onFocus,
                    onExitFocus: focus ? onExitFocus : null,
                    onShowSidebar: !expanded
                        ? () => Scaffold.of(context).openDrawer()
                        : !sidebar && !focus
                        ? onExpand
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _WorkbenchMain extends StatelessWidget {
  const _WorkbenchMain({
    required this.controller,
    required this.labels,
    required this.locale,
    required this.onLocaleChanged,
    required this.focus,
    required this.actions,
    required this.onFocus,
    required this.onExitFocus,
    required this.onShowSidebar,
  });
  final WorkspaceController controller;
  final WorkbenchLabels labels;
  final Locale locale;
  final ValueChanged<Locale> onLocaleChanged;
  final bool focus;
  final EditorActionRegistry actions;
  final VoidCallback onFocus;
  final VoidCallback? onExitFocus;
  final VoidCallback? onShowSidebar;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      WorkbenchToolbar(
        controller: controller,
        labels: labels,
        locale: locale,
        onLocaleChanged: onLocaleChanged,
        focus: focus,
        wide: controller.wide,
        onFocus: onFocus,
        onWide: () => controller.setWide(!controller.wide),
        actions: actions,
        onShowSidebar: onShowSidebar,
      ),
      // 保存错误保持在纸面之外，滚动正文时仍然可达。
      SaveErrorBanner(controller: controller, labels: labels),
      Expanded(
        child: WorkbenchContent(
          controller: controller,
          labels: labels,
          wide: controller.wide,
          actions: actions,
          onExitFocus: onExitFocus,
        ),
      ),
    ],
  );
}
