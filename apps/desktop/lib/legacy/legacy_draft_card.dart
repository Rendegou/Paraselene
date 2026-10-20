// 历史遗留草稿卡片：展示旧草稿及其来源、状态，并提供载入或丢弃操作。
// 已决草稿仍保持可读；查看/复制不等于确认，写入只发生在显式操作时。

import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';

/// Historical text remains readable after resolution; copying isn't confirmation.
///
/// 已决历史文本仍保持可读；载入/丢弃只是显式操作，查看或复制不构成确认。
class LegacyDraftCard extends StatelessWidget {
  const LegacyDraftCard({
    required this.row,
    required this.busy,
    required this.review,
    super.key,
  });
  final Map<String, dynamic> row;
  final bool busy;
  final Future<void> Function(Map<String, dynamic>, bool) review;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final status = switch (row['status']) {
      'pending' => s.historicalPending,
      'accepted' => s.historicalAccepted,
      'discarded' => s.historicalDiscarded,
      _ => s.historicalUnknown,
    };
    final origin = row['origin'] == 'ai' ? s.historicalAi : s.historicalAuthor;
    return ExpansionTile(
      title: Text(s.legacyDrafts),
      subtitle: Text('${row['createdAt']} · $origin · $status'),
      children: [
        SelectableText(row['body'] as String),
        if (row['status'] == 'pending')
          Wrap(
            children: [
              TextButton(
                onPressed: busy ? null : () => review(row, true),
                child: Text(s.loadHistoricalDraft),
              ),
              TextButton(
                onPressed: busy ? null : () => review(row, false),
                child: Text(s.discardHistoricalDraft),
              ),
            ],
          ),
      ],
    );
  }
}
