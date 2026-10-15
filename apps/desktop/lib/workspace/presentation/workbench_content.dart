import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/workbench_theme.dart';
import '../data/workspace_repository.dart';
import '../workspace_controller.dart';
import 'workbench_chrome.dart';

/// Resolves the four workspace phases at one boundary.
class WorkbenchContent extends StatelessWidget {
  const WorkbenchContent({
    required this.controller,
    required this.labels,
    required this.wide,
    super.key,
  });
  final WorkspaceController controller;
  final WorkbenchLabels labels;
  final bool wide;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surface,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 170),
          child: SingleChildScrollView(
            child: WorkspaceStatus(controller: controller, labels: labels),
          ),
        ),
        Expanded(
          child: switch (controller.phase) {
            WorkspacePhase.loading => WorkspaceMessage(
              labels: labels,
              title: labels.strings.loading,
              loading: true,
            ),
            WorkspacePhase.empty => WorkspaceMessage(
              labels: labels,
              title: labels.strings.noWorksTitle,
              body: labels.strings.noWorksBody,
              action: labels.strings.createDemo,
              onAction: () => unawaited(controller.seedDemo()),
            ),
            WorkspacePhase.error => WorkspaceMessage(
              labels: labels,
              title: labels.strings.errorTitle,
              body: labels.strings.errorBody,
              technicalCode: controller.errorCode,
              action: labels.strings.retry,
              onAction: () => unawaited(controller.refresh()),
            ),
            WorkspacePhase.content => ManuscriptPreview(
              controller: controller,
              labels: labels,
              wide: wide,
            ),
          },
        ),
      ],
    ),
  );
}

/// Persistent provenance and language independence disclosure.
class WorkspaceStatus extends StatelessWidget {
  const WorkspaceStatus({
    required this.controller,
    required this.labels,
    super.key,
  });
  final WorkspaceController controller;
  final WorkbenchLabels labels;
  @override
  Widget build(BuildContext context) {
    final s = labels.strings;
    final real = controller.repository.mode == WorkspaceMode.realBridge;
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(24, 14, 24, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              labels(real ? s.realMode : s.syntheticMode),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            Text(
              labels(s.syntheticNotice),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              labels(s.languageIndependence),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Read-only author text, kept separate from the interface translation harness.
class ManuscriptPreview extends StatelessWidget {
  const ManuscriptPreview({
    required this.controller,
    required this.labels,
    required this.wide,
    super.key,
  });
  final WorkspaceController controller;
  final WorkbenchLabels labels;
  final bool wide;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: wide
              ? WorkbenchTokens.wideWidth
              : WorkbenchTokens.comfortableWidth,
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(28, 28, 28, 64),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (controller.currentWork != null)
                Text(
                  controller.currentWork!.title,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              const SizedBox(height: 16),
              Semantics(
                header: true,
                child: Text(
                  controller.currentChapter?.title ??
                      labels(labels.strings.chooseChapter),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              const SizedBox(height: 14),
              LanguageMetadata(labels: labels),
              const SizedBox(height: 12),
              Text(
                labels(labels.strings.readOnlyHint),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 32),
              SelectableText(
                controller.body,
                key: const ValueKey('manuscript-body'),
                textDirection: TextDirection.ltr,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      ),
    ),
  );
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

/// Actionable state messages disclose a technical code without raw exceptions.
class WorkspaceMessage extends StatelessWidget {
  const WorkspaceMessage({
    required this.labels,
    required this.title,
    this.body,
    this.technicalCode,
    this.action,
    this.onAction,
    this.loading = false,
    super.key,
  });
  final WorkbenchLabels labels;
  final String title;
  final String? body;
  final String? technicalCode;
  final String? action;
  final VoidCallback? onAction;
  final bool loading;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsetsDirectional.all(28),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (loading) const LinearProgressIndicator(),
            const SizedBox(height: 24),
            Semantics(
              header: true,
              child: Text(
                labels(title),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            if (body != null) ...[
              const SizedBox(height: 16),
              Text(labels(body!)),
            ],
            if (technicalCode != null) ...[
              const SizedBox(height: 16),
              Text(
                labels(labels.strings.errorCode('\u2068$technicalCode\u2069')),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 24),
              ChromeAction(
                label: labels(action!),
                icon: Icons.refresh,
                onPressed: onAction,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
