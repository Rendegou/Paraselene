import 'package:flutter/material.dart';

import '../../theme/workbench_theme.dart';
import '../../domain/editing/save_coordinator.dart';
import '../workspace_controller.dart';
import 'export_flow.dart';
import 'workbench_chrome.dart';

/// TEMPORARY M4 editing surface — a plain multi-line field wired to the
/// editing session. It is not the M3 production editor and makes no long-form
/// performance claims. Author text is never normalized, trimmed or rewritten
/// on save-status updates; the field is reset only when [contentEpoch] moves.
class ManuscriptEditor extends StatefulWidget {
  const ManuscriptEditor({
    required this.controller,
    required this.labels,
    required this.wide,
    super.key,
  });
  final WorkspaceController controller;
  final WorkbenchLabels labels;
  final bool wide;

  @override
  State<ManuscriptEditor> createState() => _ManuscriptEditorState();
}

class _ManuscriptEditorState extends State<ManuscriptEditor> {
  final TextEditingController _text = TextEditingController();
  final ScrollController _scroll = ScrollController();
  int _epoch = -1;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _text.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.hasClients) {
      widget.controller.noteScrollTop(_scroll.offset);
    }
  }

  /// Restores the persisted scroll offset once the new chapter has laid out;
  /// a stale callback from the previous chapter cannot write the new offset.
  void _applyPendingScroll() {
    final controller = widget.controller;
    if (!controller.applyScrollPending) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || !controller.applyScrollPending) {
        return;
      }
      final limit = _scroll.position.maxScrollExtent;
      _scroll.jumpTo(controller.pendingScrollTop.clamp(0.0, limit));
      controller.markScrollApplied();
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.controller.editing;
    if (session.contentEpoch != _epoch) {
      _epoch = session.contentEpoch;
      // External reset only (open/confirm/rollback): typing never comes back.
      _text.value = TextEditingValue(
        text: session.body,
        selection: TextSelection.collapsed(offset: session.body.length),
      );
      _applyPendingScroll();
    }
    return SingleChildScrollView(
      controller: _scroll,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: widget.wide
                ? WorkbenchTokens.wideWidth
                : WorkbenchTokens.comfortableWidth,
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(28, 28, 28, 64),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.controller.currentWork != null)
                  Text(
                    widget.controller.currentWork!.title,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                const SizedBox(height: 16),
                Semantics(
                  header: true,
                  child: Text(
                    widget.controller.currentChapter?.title ??
                        widget.labels(widget.labels.strings.chooseChapter),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                const SizedBox(height: 14),
                LanguageMetadata(labels: widget.labels),
                const SizedBox(height: 12),
                SaveStatusStrip(
                  controller: widget.controller,
                  labels: widget.labels,
                ),
                const SizedBox(height: 8),
                Text(
                  widget.labels(widget.labels.strings.editorTemporaryHint),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('manuscript-body'),
                  controller: _text,
                  readOnly: widget.controller.isBusy,
                  onChanged: widget.controller.editing.edit,
                  maxLines: null,
                  textDirection: TextDirection.ltr,
                  style: Theme.of(context).textTheme.bodyLarge,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Unknown source metadata is disclosed without guessing from the UI locale.
class LanguageMetadata extends StatelessWidget {
  const LanguageMetadata({required this.labels, super.key});
  final WorkbenchLabels labels;
  @override
  Widget build(BuildContext context) {
    final s = labels.strings;
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        Text(labels('${s.workLanguage}: ${s.undeterminedLanguage}')),
        Text(labels('${s.documentLanguage}: ${s.undeterminedLanguage}')),
        Text(labels('${s.outputLanguage}: ${s.undeterminedLanguage}')),
      ],
    );
  }
}

/// Localized persistence status with the stable technical code and retry.
class SaveStatusStrip extends StatelessWidget {
  const SaveStatusStrip({
    required this.controller,
    required this.labels,
    super.key,
  });
  final WorkspaceController controller;
  final WorkbenchLabels labels;

  @override
  Widget build(BuildContext context) {
    final s = labels.strings;
    final state = controller.editing.saveState;
    final barrierError = controller.errorCode;
    final status = state?.status;
    final text = switch (status) {
      SaveStatus.dirty => labels(s.saveDirty),
      SaveStatus.saving => labels(s.saveSaving),
      SaveStatus.saved => labels(s.saveSaved),
      SaveStatus.conflict => labels(s.saveConflict),
      SaveStatus.error => labels(s.saveError),
      null => null,
    };
    final errorCode = state?.errorCode ?? barrierError;
    final draftNotice = state != null && state.baseHead != state.head
        ? labels(s.draftRestoredBase)
        : null;
    if (text == null && errorCode == null && draftNotice == null) {
      return const SizedBox.shrink();
    }
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(bottom: 8),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (text != null)
              Text(
                text,
                key: const ValueKey('save-status'),
                style: Theme.of(context).textTheme.labelLarge,
              ),
            if (draftNotice != null)
              Text(draftNotice, style: Theme.of(context).textTheme.bodySmall),
            if (errorCode != null) ...[
              Text(
                labels(s.errorCode('\u2068$errorCode\u2069')),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (errorCode == 'durable_save_failed')
                Text(
                  labels(s.durableSaveFailed),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ChromeAction(
                label: labels(s.retrySave),
                icon: Icons.refresh,
                onPressed: controller.isBusy
                    ? null
                    : () => controller.retrySave(),
              ),
              ChromeAction(
                label: labels(s.exportDraft),
                icon: Icons.download_outlined,
                onPressed: controller.isBusy
                    ? null
                    : () => RecoveryExportFlow.run(context, controller, labels),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
