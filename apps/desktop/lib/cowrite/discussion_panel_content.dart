// 讨论面板的无状态布局：承载草稿输入、状态和操作分组。
// 控制器与焦点由 DiscussionPanel 持有；本视图不释放它们或创建业务任务。
import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/workbench_controls.dart';
import '../theme/workbench_theme.dart';
import 'discussion_candidates.dart';
import 'discussion_panel_toolbar.dart';
import 'discussion_presentation.dart';
import 'discussion_surface.dart';

/// 把讨论投影组合成单一纸面表面，长历史仅在有界卡片内滚动。
class DiscussionPanelContent extends StatelessWidget {
  const DiscussionPanelContent({
    required this.view,
    required this.actions,
    required this.draft,
    required this.draftFocus,
    super.key,
  });

  /// 本帧只读讨论状态。
  final DiscussionPresentation view;

  /// 稳定宿主提供的业务操作。
  final DiscussionPanelActions actions;

  /// 由宿主持有的草稿控制器。
  final TextEditingController draft;

  /// 由宿主持有、资料往返后恢复的焦点。
  final FocusNode draftFocus;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final availableHeight =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).vertical -
        64;
    return DiscussionSurface(
      inDialog: view.inDialog,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: view.inDialog ? availableHeight.clamp(120.0, 720.0) : 420,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(WorkbenchControls.panelInset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _DiscussionHeading(view: view, onCollapse: actions.onCollapse),
              const SizedBox(height: 6),
              if (view.canGenerate &&
                  (view.thread.isChapter || !view.thread.valid))
                Padding(
                  padding: const EdgeInsetsDirectional.only(bottom: 6),
                  child: Text(
                    s.discussionGenerationUnavailable,
                    key: const ValueKey('discussion-generation-unavailable'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (view.saveFailed)
                _DiscussionSaveFailure(onRetry: actions.onRetry),
              TextField(
                key: const ValueKey('discussion-draft'),
                style: WorkbenchTokens.input,
                controller: draft,
                focusNode: draftFocus,
                enabled: !view.busy,
                minLines: 1,
                maxLines: 3,
                decoration: WorkbenchControls.draft(s.discussionDraft),
                onChanged: actions.onDraft,
              ),
              const SizedBox(height: WorkbenchControls.gap),
              DiscussionPanelToolbar(view: view, actions: actions),
              if (view.running) const LinearProgressIndicator(),
              if (view.failed)
                Semantics(liveRegion: true, child: Text(s.generationFailed)),
              DiscussionCandidates(view: view, actions: actions),
              if (view.history) DiscussionHistory(view: view),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiscussionHeading extends StatelessWidget {
  const _DiscussionHeading({required this.view, required this.onCollapse});
  final DiscussionPresentation view;
  final VoidCallback? onCollapse;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final status = view.thread.draftPending
        ? (view.status.isEmpty
              ? s.discussionDraft
              : '${view.status} · ${s.discussionDraft}')
        : view.status;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(view.title, style: Theme.of(context).textTheme.titleMedium),
              if (status.isNotEmpty)
                Text(status, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        if (onCollapse != null)
          IconButton(
            tooltip: view.inDialog ? s.closeDialog : s.discussionCollapse,
            onPressed: onCollapse,
            icon: Icon(
              view.inDialog ? Icons.close : Icons.unfold_less,
              size: 18,
            ),
          ),
      ],
    );
  }
}

class _DiscussionSaveFailure extends StatelessWidget {
  const _DiscussionSaveFailure({required this.onRetry});
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 6),
      child: Row(
        key: const ValueKey('discussion-save-failed'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              s.discussionSaveFailed,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          TextButton(
            key: const ValueKey('discussion-save-retry'),
            onPressed: onRetry,
            child: Text(s.retrySave),
          ),
        ],
      ),
    );
  }
}
