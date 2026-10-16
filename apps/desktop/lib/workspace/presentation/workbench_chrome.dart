import 'dart:async';
import 'package:flutter/material.dart';
import '../../l10n/generated/app_localizations.dart';
import '../data/workspace_repository.dart';
import '../workspace_controller.dart';
import 'workbench_dialogs.dart';

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

  /// Flushes and prepares the exact-body review, then opens the dialog only
  /// when preparation succeeded; failures surface in the save-status strip.
  Future<void> _confirmChapter(BuildContext context) async {
    final prepared = await controller.prepareConfirmation();
    if (prepared == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => ConfirmChapterDialog(
        controller: controller,
        labels: labels,
        prepared: prepared,
      ),
    );
  }

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
              label: labels(s.confirmChapter),
              icon: Icons.task_alt_outlined,
              onPressed: controller.isBusy || !controller.editing.hasOpenChapter
                  ? null
                  : () => unawaited(_confirmChapter(context)),
            ),
            ChromeAction(
              label: labels(s.versionsTitle),
              icon: Icons.history,
              onPressed: controller.isBusy || !controller.editing.hasOpenChapter
                  ? null
                  : () => unawaited(
                      showDialog<void>(
                        context: context,
                        builder: (_) => VersionsDialog(
                          controller: controller,
                          labels: labels,
                        ),
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

/// Chapter navigation with create/rename/archive/restore and drag reorder.
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

  Future<void> _createChapter(BuildContext context) async {
    final s = labels.strings;
    final title = await showTitlePrompt(
      context: context,
      labels: labels,
      title: s.newChapter,
      fieldLabel: s.chapterTitleLabel,
    );
    if (title != null) await controller.createChapter(title);
  }

  Future<void> _renameChapter(
    BuildContext context,
    WorkspaceChapter chapter,
  ) async {
    final s = labels.strings;
    final title = await showTitlePrompt(
      context: context,
      labels: labels,
      title: s.renameChapter,
      fieldLabel: s.chapterTitleLabel,
      initial: chapter.title,
    );
    if (title != null) await controller.renameChapter(chapter, title);
  }

  void _reorder(int oldIndex, int newIndex) {
    final ids = controller.chapters.map((c) => c.id).toList();
    if (newIndex > oldIndex) newIndex--;
    ids.insert(newIndex, ids.removeAt(oldIndex));
    unawaited(controller.reorderChapters(ids));
  }

  @override
  Widget build(BuildContext context) {
    final s = labels.strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.all(20),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  labels(s.chapters),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: labels(s.newChapter),
                onPressed: controller.isBusy || controller.currentWork == null
                    ? null
                    : () => _createChapter(context),
                icon: const Icon(Icons.add, size: 20),
              ),
            ],
          ),
        ),
        Expanded(
          child: controller.chapters.isEmpty
              ? Padding(
                  padding: const EdgeInsetsDirectional.all(20),
                  child: Text(labels(s.emptyChapters)),
                )
              : ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  itemCount: controller.chapters.length,
                  onReorder: controller.isBusy ? (_, __) {} : _reorder,
                  itemBuilder: (context, index) {
                    final chapter = controller.chapters[index];
                    final selected =
                        controller.currentChapter?.id == chapter.id;
                    return _ChapterTile(
                      key: ValueKey('chapter-${chapter.id}'),
                      chapter: chapter,
                      index: index,
                      selected: selected,
                      labels: labels,
                      busy: controller.isBusy,
                      onSelect: () {
                        if (closeOnSelect) Navigator.of(context).pop();
                        unawaited(controller.selectChapter(chapter));
                      },
                      onRename: () => _renameChapter(context, chapter),
                      onArchive: () => unawaited(
                        controller.setChapterArchived(chapter, true),
                      ),
                    );
                  },
                ),
        ),
        if (controller.archivedChapters.isNotEmpty) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsetsDirectional.all(16),
            child: Text(
              labels(s.archivedChapters),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          SizedBox(
            height: 48.0 * controller.archivedChapters.length.clamp(1, 4),
            child: ListView.builder(
              itemCount: controller.archivedChapters.length,
              itemBuilder: (context, index) {
                final chapter = controller.archivedChapters[index];
                return ListTile(
                  key: ValueKey('archived-${chapter.id}'),
                  dense: true,
                  title: Text(
                    chapter.title,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  trailing: TextButton(
                    onPressed: controller.isBusy
                        ? null
                        : () => unawaited(
                            controller.setChapterArchived(chapter, false),
                          ),
                    child: Text(labels(s.restoreChapter)),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _ChapterTile extends StatelessWidget {
  const _ChapterTile({
    required this.chapter,
    required this.index,
    required this.selected,
    required this.labels,
    required this.busy,
    required this.onSelect,
    required this.onRename,
    required this.onArchive,
    super.key,
  });
  final WorkspaceChapter chapter;
  final int index;
  final bool selected;
  final WorkbenchLabels labels;
  final bool busy;
  final VoidCallback onSelect;
  final VoidCallback onRename;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final s = labels.strings;
    return ListTile(
      selected: selected,
      leading: ReorderableDragStartListener(
        index: index,
        child: Icon(
          selected ? Icons.radio_button_checked : Icons.drag_indicator,
          size: 16,
        ),
      ),
      title: Text(chapter.title, style: Theme.of(context).textTheme.bodyMedium),
      trailing: PopupMenuButton<String>(
        enabled: !busy,
        onSelected: (value) {
          if (value == 'rename') onRename();
          if (value == 'archive') onArchive();
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'rename', child: Text(labels(s.renameChapter))),
          PopupMenuItem(
            value: 'archive',
            child: Text(labels(s.archiveChapter)),
          ),
        ],
      ),
      onTap: busy ? null : onSelect,
    );
  }
}

/// Explicit work selection never translates manuscript metadata.
class WorkPicker extends StatelessWidget {
  const WorkPicker({required this.controller, required this.labels, super.key});
  final WorkspaceController controller;
  final WorkbenchLabels labels;

  Future<void> _createWork(BuildContext context) async {
    final s = labels.strings;
    final title = await showTitlePrompt(
      context: context,
      labels: labels,
      title: s.newWork,
      fieldLabel: s.workTitleLabel,
    );
    if (title != null && context.mounted) {
      await controller.createWork(title);
      if (context.mounted) Navigator.of(context).maybePop();
    }
  }

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
        onPressed: controller.isBusy ? null : () => _createWork(context),
        child: Text(labels(labels.strings.newWork)),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(labels(labels.strings.closeDialog)),
      ),
    ],
  );
}
