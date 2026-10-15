import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/workbench_theme.dart';
import '../workspace_controller.dart';
import 'workbench_chrome.dart';
import 'workbench_content.dart';

/// Read-only workspace with independent interface language and local view modes.
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
  bool _focus = false;
  bool _wide = false;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: widget.rtlHarness
        ? TextDirection.rtl
        : Directionality.of(context),
    child: AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final expanded =
              constraints.maxWidth >= 900 &&
              MediaQuery.textScalerOf(context).scale(16) < 24;
          final labels = WorkbenchLabels(
            AppLocalizations.of(context),
            widget.pseudoLocalize,
          );
          return Scaffold(
            drawer: _focus || expanded
                ? null
                : Drawer(
                    child: SafeArea(
                      child: WorkbenchContents(
                        controller: widget.controller,
                        labels: labels,
                        closeOnSelect: true,
                      ),
                    ),
                  ),
            body: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: constraints.maxHeight * .45,
                    ),
                    child: SingleChildScrollView(
                      child: ColoredBox(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerLow,
                        child: WorkbenchToolbar(
                          controller: widget.controller,
                          labels: labels,
                          locale: widget.locale,
                          onLocaleChanged: widget.onLocaleChanged,
                          focus: _focus,
                          wide: _wide,
                          showContents: !expanded && !_focus,
                          onFocus: () => setState(() => _focus = !_focus),
                          onWide: () => setState(() => _wide = !_wide),
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: _WorkspacePlane(
                      controller: widget.controller,
                      labels: labels,
                      expanded: expanded && !_focus,
                      wide: _wide,
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

class _WorkspacePlane extends StatelessWidget {
  const _WorkspacePlane({
    required this.controller,
    required this.labels,
    required this.expanded,
    required this.wide,
  });
  final WorkspaceController controller;
  final WorkbenchLabels labels;
  final bool expanded;
  final bool wide;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (expanded) ...[
        SizedBox(
          width: WorkbenchTokens.directoryWidth,
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: WorkbenchContents(controller: controller, labels: labels),
          ),
        ),
        const VerticalDivider(width: 1),
      ],
      Expanded(
        child: WorkbenchContent(
          controller: controller,
          labels: labels,
          wide: wide,
        ),
      ),
    ],
  );
}
