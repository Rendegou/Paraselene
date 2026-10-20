// 章节派生摘要卡片：展示摘要正文、状态与重建任务。
// 只读视图：摘要非 ready 时明确提示过期，不自动触发重建。

import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';

/// A stale derived summary stays readable with a clear validity warning.
///
/// 过期派生摘要仍保持可读，但会显示明确的失效提示；不自动触发重建。
class DerivedSummaryCard extends StatelessWidget {
  const DerivedSummaryCard({
    required this.summary,
    required this.jobs,
    super.key,
  });
  final Map summary;
  final List jobs;
  String _status(AppLocalizations s, String value) => switch (value) {
    'ready' => s.summaryReady,
    'dirty' => s.summaryStale,
    'queued' => s.rebuildQueued,
    'running' => s.rebuildRunning,
    'done' => s.rebuildDone,
    'failed' => s.rebuildFailed,
    // 未知状态按“过期”提示，不把不可信状态展示为可用。
    _ => s.summaryStale,
  };
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return ExpansionTile(
      title: Text(s.chapterSummary),
      subtitle: Text(_status(s, summary['status'] as String)),
      children: [
        if (summary['status'] != 'ready') Text(s.summaryStale),
        SelectableText(summary['body'] as String),
        for (final job in jobs)
          ListTile(
            title: Text(_status(s, (job as Map)['status'] as String)),
            subtitle: Text(job['updatedAt'] as String),
          ),
      ],
    );
  }
}
