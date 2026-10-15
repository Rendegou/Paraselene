import 'dart:async';
import 'package:flutter/material.dart';
import '../../l10n/generated/app_localizations.dart';
import '../workspace_controller.dart';

/// Transforms translated chrome only for the optional expansion harness.
class WorkbenchLabels {
  const WorkbenchLabels(this.strings, this.pseudo);
  final AppLocalizations strings;
  final bool pseudo;
  String call(String value) => pseudo ? '[$value · $value]' : value;
}

class _LanguageMenu extends StatelessWidget {
  const _LanguageMenu({
    required this.labels,
    required this.locale,
    required this.onChanged,
  });
  final WorkbenchLabels labels;
  final Locale locale;
  final ValueChanged<Locale> onChanged;
  @override
  Widget build(BuildContext context) => PopupMenuButton<Locale>(
    tooltip: labels(labels.strings.languageLabel),
    initialValue: locale,
    onSelected: onChanged,
    itemBuilder: (_) => [
      PopupMenuItem(
        value: const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
        child: Text(labels(labels.strings.chineseLabel)),
      ),
      PopupMenuItem(
        value: const Locale('en'),
        child: Text(labels(labels.strings.englishLabel)),
      ),
    ],
    child: Padding(
      padding: const EdgeInsetsDirectional.all(12),
      child: Text(labels(labels.strings.languageLabel)),
    ),
  );
}

/// Wrapping controls remain reachable at large text scales.
class WorkbenchToolbar extends StatelessWidget {
  const WorkbenchToolbar({
    required this.controller,
    required this.labels,
    required this.locale,
    required this.onLocaleChanged,
    required this.focus,
    required this.wide,
    required this.showContents,
    required this.onFocus,
    required this.onWide,
    super.key,
  });
  final WorkspaceController controller;
  final WorkbenchLabels labels;
  final Locale locale;
  final ValueChanged<Locale> onLocaleChanged;
  final bool focus;
  final bool wide;
  final bool showContents;
  final VoidCallback onFocus;
  final VoidCallback onWide;

  @override
  Widget build(BuildContext context) {
    final s = labels.strings;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(8),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              labels(s.workspaceTitle),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (showContents)
              Builder(
                builder: (context) => ChromeAction(
                  label: labels(s.chapters),
                  icon: Icons.menu_book_outlined,
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
            ChromeAction(
              label: labels(s.chooseWork),
              icon: Icons.folder_open_outlined,
              onPressed: controller.isBusy
                  ? null
                  : () => unawaited(
                      showDialog<void>(
                        context: context,
                        builder: (_) =>
                            WorkPicker(controller: controller, labels: labels),
                      ),
                    ),
            ),
            ChromeAction(
              label: labels(focus ? s.focusOff : s.focusOn),
              icon: focus ? Icons.fullscreen_exit : Icons.fullscreen,
              onPressed: onFocus,
            ),
            ChromeAction(
              label: labels(wide ? s.wideOff : s.wideOn),
              icon: wide ? Icons.width_normal : Icons.width_wide,
              onPressed: onWide,
            ),
            _LanguageMenu(
              labels: labels,
              locale: locale,
              onChanged: onLocaleChanged,
            ),
          ],
        ),
      ),
    );
  }
}

/// A labelled keyboard and pointer action with a native tooltip.
class ChromeAction extends StatelessWidget {
  const ChromeAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    super.key,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: TextButton(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(child: Icon(icon, size: 18)),
          const SizedBox(width: 8),
          Flexible(child: Text(label)),
        ],
      ),
    ),
  );
}

/// Chapter navigation uses stable author identifiers and untouched titles.
class WorkbenchContents extends StatelessWidget {
  const WorkbenchContents({
    required this.controller,
    required this.labels,
    this.closeOnSelect = false,
    super.key,
  });
  final WorkspaceController controller;
  final WorkbenchLabels labels;
  final bool closeOnSelect;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsetsDirectional.all(20),
        child: Text(
          labels(labels.strings.chapters),
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
      Expanded(
        child: controller.chapters.isEmpty
            ? Padding(
                padding: const EdgeInsetsDirectional.all(20),
                child: Text(labels(labels.strings.emptyChapters)),
              )
            : ListView.builder(
                itemCount: controller.chapters.length,
                itemBuilder: (context, index) {
                  final chapter = controller.chapters[index];
                  final selected = controller.currentChapter?.id == chapter.id;
                  return ListTile(
                    key: ValueKey('chapter-${chapter.id}'),
                    selected: selected,
                    title: Text(
                      chapter.title,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    leading: ExcludeSemantics(
                      child: Icon(
                        selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 16,
                      ),
                    ),
                    onTap: controller.isBusy
                        ? null
                        : () {
                            if (closeOnSelect) Navigator.of(context).pop();
                            unawaited(controller.selectChapter(chapter));
                          },
                  );
                },
              ),
      ),
    ],
  );
}

/// Explicit work selection never translates manuscript metadata.
class WorkPicker extends StatelessWidget {
  const WorkPicker({required this.controller, required this.labels, super.key});
  final WorkspaceController controller;
  final WorkbenchLabels labels;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(labels(labels.strings.chooseWork)),
    content: SizedBox(
      width: 460,
      height: 320,
      child: controller.works.isEmpty
          ? Text(labels(labels.strings.noWorksBody))
          : ListView.builder(
              itemCount: controller.works.length,
              itemBuilder: (context, index) {
                final work = controller.works[index];
                return ListTile(
                  key: ValueKey('work-${work.id}'),
                  title: Text(work.title),
                  selected: controller.currentWork?.id == work.id,
                  onTap: controller.isBusy
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          unawaited(controller.selectWork(work));
                        },
                );
              },
            ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(labels(labels.strings.closeDialog)),
      ),
    ],
  );
}
