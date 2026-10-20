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

  bool _expanded(BoxConstraints constraints, BuildContext context) =>
      constraints.maxWidth >= 900 &&
      MediaQuery.textScalerOf(context).scale(16) < 24;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: widget.rtlHarness
          ? TextDirection.rtl
          : Directionality.of(context),
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final labels = WorkbenchLabels(
              AppLocalizations.of(context),
              widget.pseudoLocalize,
            );
            final expanded = _expanded(constraints, context);
            if (!expanded) {
              return Scaffold(
                drawer: Drawer(
                  child: SafeArea(
                    child: WorkbenchSidebar(
                      controller: widget.controller,
                      labels: labels,
                      closeOnSelect: true,
                      onCollapse: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
                body: SafeArea(
                  child: Builder(
                    builder: (context) => _main(
                      context,
                      labels,
                      expanded: false,
                      onShowSidebar: () => Scaffold.of(context).openDrawer(),
                    ),
                  ),
                ),
              );
            }
            return Scaffold(
              body: SafeArea(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_sidebar && !_focus)
                      SizedBox(
                        width: WorkbenchTokens.directoryWidth,
                        child: WorkbenchSidebar(
                          controller: widget.controller,
                          labels: labels,
                          onCollapse: () => setState(() => _sidebar = false),
                        ),
                      ),
                    Expanded(
                      child: _main(
                        context,
                        labels,
                        expanded: true,
                        onShowSidebar: !_sidebar && !_focus
                            ? () => setState(() => _sidebar = true)
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _main(
    BuildContext context,
    WorkbenchLabels labels, {
    required bool expanded,
    required VoidCallback? onShowSidebar,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      WorkbenchToolbar(
        controller: widget.controller,
        labels: labels,
        locale: widget.locale,
        onLocaleChanged: widget.onLocaleChanged,
        focus: _focus,
        // 宽稿是 controller 持有的每作品持久偏好，界面不再保留第二份局部状态。
        wide: widget.controller.wide,
        onFocus: () => setState(() => _focus = !_focus),
        onWide: () => widget.controller.setWide(!widget.controller.wide),
        actions: _actions,
        onShowSidebar: onShowSidebar,
      ),
      // 保存失败不占用纸面空间：错误条在工具栏与正文之间，滚动正文时仍可见。
      SaveErrorBanner(controller: widget.controller, labels: labels),
      Expanded(
        child: WorkbenchContent(
          controller: widget.controller,
          labels: labels,
          wide: widget.controller.wide,
          actions: _actions,
          // Escape 的最外层：退出专注（查找/讨论层已先被正文编辑器消费）。
          onExitFocus: _focus ? () => setState(() => _focus = false) : null,
        ),
      ),
    ],
  );
}
