import 'dart:async';

import 'package:flutter/material.dart';

import '../data/workspace_repository.dart';
import '../workspace_controller.dart';
import 'workbench_chrome.dart';

/// Shared title prompt for creating works/chapters and renaming.
Future<String?> showTitlePrompt({
  required BuildContext context,
  required WorkbenchLabels labels,
  required String title,
  required String fieldLabel,
  String initial = '',
}) => showDialog<String>(
  context: context,
  builder: (context) => _TitlePromptDialog(
    labels: labels,
    title: title,
    fieldLabel: fieldLabel,
    initial: initial,
  ),
);

class _TitlePromptDialog extends StatefulWidget {
  const _TitlePromptDialog({
    required this.labels,
    required this.title,
    required this.fieldLabel,
    required this.initial,
  });
  final WorkbenchLabels labels;
  final String title;
  final String fieldLabel;
  final String initial;
  @override
  State<_TitlePromptDialog> createState() => _TitlePromptDialogState();
}

class _TitlePromptDialogState extends State<_TitlePromptDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initial,
  );
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _text.text.trim();
    if (value.isEmpty) {
      setState(() => _error = widget.labels.strings.titleRequired);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.labels.strings;
    return AlertDialog(
      title: Text(widget.labels(widget.title)),
      content: SizedBox(
        width: 420,
        child: TextField(
          key: const ValueKey('title-prompt-field'),
          controller: _text,
          autofocus: true,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: widget.labels(widget.fieldLabel),
            errorText: _error == null ? null : widget.labels(_error!),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.labels(s.cancelAction)),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.labels(s.createAction)),
        ),
      ],
    );
  }
}

/// Exact-body review before confirmation. The dialog closes itself with a
/// notice when the author keeps typing, because the token is then stale.
class ConfirmChapterDialog extends StatefulWidget {
  const ConfirmChapterDialog({
    required this.controller,
    required this.labels,
    required this.prepared,
    super.key,
  });
  final WorkspaceController controller;
  final WorkbenchLabels labels;
  final PreparedConfirmation prepared;

  @override
  State<ConfirmChapterDialog> createState() => _ConfirmChapterDialogState();
}

class _ConfirmChapterDialogState extends State<ConfirmChapterDialog> {
  bool _busy = false;
  String? _errorCode;

  @override
  void initState() {
    super.initState();
    _sequence = widget.controller.editing.saveState?.editSequence ?? 0;
    widget.controller.addListener(_watchEdits);
  }

  late final int _sequence;

  @override
  void dispose() {
    widget.controller.removeListener(_watchEdits);
    super.dispose();
  }

  void _watchEdits() {
    final sequence = widget.controller.editing.saveState?.editSequence;
    if (sequence != null && sequence != _sequence && mounted) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await widget.controller.confirmChapter(widget.prepared.token);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _busy = false;
        _errorCode = widget.controller.errorCode;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.labels.strings;
    return AlertDialog(
      title: Text(widget.labels(s.confirmTitle)),
      content: SizedBox(
        width: 520,
        height: 380,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.labels(s.confirmNotice),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: SelectableText(
                  widget.prepared.body,
                  key: const ValueKey('confirm-preview-body'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
            if (_errorCode != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 8),
                child: Text(
                  widget.labels(s.errorCode('\u2068$_errorCode\u2069')),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(widget.labels(s.cancelAction)),
        ),
        FilledButton(
          onPressed: _busy ? null : _confirm,
          child: Text(widget.labels(s.confirmAction)),
        ),
      ],
    );
  }
}

/// Confirmed version list with exact-body preview and explicit rollback.
class VersionsDialog extends StatefulWidget {
  const VersionsDialog({
    required this.controller,
    required this.labels,
    super.key,
  });
  final WorkspaceController controller;
  final WorkbenchLabels labels;

  @override
  State<VersionsDialog> createState() => _VersionsDialogState();
}

class _VersionsDialogState extends State<VersionsDialog> {
  late final Future<List<VersionEntry>> _versions = widget.controller
      .listVersions();

  Future<void> _rollback(VersionEntry version) async {
    final s = widget.labels.strings;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.labels(s.rollbackTitle)),
        content: Text(widget.labels(s.rollbackNotice)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(widget.labels(s.cancelAction)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(widget.labels(s.rollbackAction)),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) {
      await widget.controller.rollbackChapter(version.id);
      if (mounted) Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.labels.strings;
    return AlertDialog(
      title: Text(widget.labels(s.versionsTitle)),
      content: SizedBox(
        width: 560,
        height: 420,
        child: FutureBuilder<List<VersionEntry>>(
          future: _versions,
          builder: (context, snapshot) {
            final versions = snapshot.data;
            if (versions == null) return const LinearProgressIndicator();
            if (versions.isEmpty) return Text(widget.labels(s.emptyVersions));
            return ListView.builder(
              itemCount: versions.length,
              itemBuilder: (context, index) {
                final version = versions[index];
                return ExpansionTile(
                  key: ValueKey('version-${version.id}'),
                  title: Text(version.createdAt),
                  subtitle: version.isHead
                      ? Text(widget.labels(s.versionCurrent))
                      : null,
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.all(16),
                        child: SelectableText(
                          version.body,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ),
                    if (!version.isHead)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(bottom: 12),
                        child: TextButton(
                          onPressed: widget.controller.isBusy
                              ? null
                              : () => _rollback(version),
                          child: Text(widget.labels(s.rollbackAction)),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.labels(s.closeDialog)),
        ),
      ],
    );
  }
}
