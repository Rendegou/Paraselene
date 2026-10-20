// 共写候选差异展示：把请求时冻结的选段与服务端候选输出做字素级对比并高亮。
// 只读视图：不写库、不修改作者正文；作者快照版本与已应用的持久化操作记录分开展示。

import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';
import 'character_diff.dart';
import 'discussion_thread.dart';

/// Candidate markings preserve text; insertions underline and deletions strike.
///
/// 候选差异只做展示标记，不修改正文：插入以下划线标出，删除以删除线标出。
/// [before] 为请求时冻结的选段，[after] 为服务端候选输出，两者都不在此组件内改写。
class CandidateDiff extends StatelessWidget {
  const CandidateDiff({required this.before, required this.after, super.key});
  final String before;
  final String after;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SelectableText.rich(
      TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: [
          for (final part in characterDiff(before, after))
            TextSpan(
              text: part.text,
              style: part.change == 0
                  ? null
                  : TextStyle(
                      backgroundColor: part.change < 0
                          ? colors.errorContainer
                          : colors.tertiaryContainer,
                      decoration: part.change < 0
                          ? TextDecoration.lineThrough
                          : TextDecoration.underline,
                    ),
            ),
        ],
      ),
    );
  }
}

/// Durable operation records are the authority for accepted version history.
///
/// 展示线程快照中的原始选段与作者版本，以及已应用（patchStatus 为 applied）
/// 的持久化操作记录；作者版本与服务端记录分开呈现，不互相回写。
class ThreadVersionHistory extends StatelessWidget {
  const ThreadVersionHistory({
    required this.thread,
    required this.operations,
    super.key,
  });
  final DiscussionThread thread;
  final List<Map<String, dynamic>> operations;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (thread.snapshot['target'] case final Map target)
          ExpansionTile(
            title: Text(s.candidateOriginal),
            children: [SelectableText(target['text'] as String)],
          ),
        for (final version in thread.snapshot['versions'] as List)
          ExpansionTile(
            title: Text((version as Map)['label'] as String),
            children: [SelectableText(version['text'] as String)],
          ),
        for (final operation in operations.where(
          (o) => o['patchStatus'] == 'applied',
        ))
          ExpansionTile(
            title: Text(
              '${s.candidateApply} · ${operation['updatedAt'] ?? operation['createdAt'] ?? ''}',
            ),
            children: [
              CandidateDiff(
                before:
                    (((operation['binding'] as Map)['request']
                            as Map)['selectedText']
                        as String),
                after: operation['output'] as String? ?? '',
              ),
            ],
          ),
      ],
    );
  }
}
