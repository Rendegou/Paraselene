// 候选和历史的只读投影：展示冻结原文、差异与原子采纳入口。
// 线程失效时保持历史可读，禁止采纳；本视图不直接写入作者快照。
import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/workbench_controls.dart';
import 'candidate_diff.dart';
import 'discussion_presentation.dart';

/// 当前线程的待审候选及采纳失败提示。
class DiscussionCandidates extends StatelessWidget {
  const DiscussionCandidates({
    required this.view,
    required this.actions,
    super.key,
  });

  /// 当前只读状态。
  final DiscussionPresentation view;

  /// 原编辑宿主提供的采纳与拒绝入口。
  final DiscussionPanelActions actions;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final candidates = view.operations.where(
      (row) => row['patchStatus'] == 'pending',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (candidates.isNotEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: 4),
            child: Text(
              s.candidateApplyNotice,
              key: const ValueKey('candidate-apply-notice'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (view.applyFailed)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: 4),
            child: Semantics(
              liveRegion: true,
              child: Text(
                s.candidateApplyFailed,
                key: const ValueKey('candidate-apply-failed'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          ),
        for (final operation in candidates)
          _DiscussionCandidate(
            view: view,
            actions: actions,
            operation: operation,
          ),
      ],
    );
  }
}

class _DiscussionCandidate extends StatelessWidget {
  const _DiscussionCandidate({
    required this.view,
    required this.actions,
    required this.operation,
  });
  final DiscussionPresentation view;
  final DiscussionPanelActions actions;
  final Map<String, dynamic> operation;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final before =
        ((operation['binding'] as Map?)?['request'] as Map?)?['selectedText']
            as String? ??
        '';
    final after = operation['output'] as String? ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (view.compare) ...[
          CandidateDiff(before: before, after: after),
          Text(
            s.candidateOriginal,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          SelectableText(before),
        ],
        Text(
          s.candidateReplacement,
          style: Theme.of(context).textTheme.labelMedium,
        ),
        SelectableText(after),
        const SizedBox(height: WorkbenchControls.gap),
        Wrap(
          spacing: WorkbenchControls.gap,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton(
              onPressed: view.busy || !view.thread.valid
                  ? null
                  : () async => await actions.onApply(
                      operation['operationId'] as String,
                    ),
              child: Text(s.candidateApply),
            ),
            TextButton(
              onPressed: view.busy
                  ? null
                  : () async => await actions.onReject(
                      operation['operationId'] as String,
                    ),
              child: Text(s.candidateReject),
            ),
          ],
        ),
      ],
    );
  }
}

/// 保持请求、候选与作者版本分离的只读历史。
class DiscussionHistory extends StatelessWidget {
  const DiscussionHistory({required this.view, super.key});

  /// 当前线程及服务端操作投影。
  final DiscussionPresentation view;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      ThreadVersionHistory(thread: view.thread, operations: view.operations),
      for (final request in view.thread.snapshot['requests'] as List)
        SelectableText((request as Map)['text'] as String? ?? ''),
      for (final operation in view.operations)
        SelectableText(
          '${((operation['binding'] as Map?)?['request'] as Map?)?['instruction'] ?? ''}\n${operation['output'] ?? ''}',
        ),
    ],
  );
}
