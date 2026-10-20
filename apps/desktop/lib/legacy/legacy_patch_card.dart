// 旧补丁卡片：展示持久化的原文/替换块，支持单块或整补丁采纳。
// 块索引来自原生持久化数据；失效或重锚定后由调用方重新加载；只提交采纳，不改本地草稿。

import 'dart:convert';
import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';

/// Partial application uses persisted indices; stale/re-anchored blocks reload.
///
/// 部分采纳使用原生持久化的块索引；失效或重锚定后需要重新加载；只提交采纳。
class LegacyPatchCard extends StatelessWidget {
  const LegacyPatchCard({
    required this.row,
    required this.busy,
    required this.apply,
    super.key,
  });
  final Map<String, dynamic> row;
  final bool busy;
  final Future<void> Function(String, int?) apply;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    List<dynamic> blocks;
    try {
      blocks = jsonDecode(row['blocksJson'] as String) as List;
    } catch (_) {
      // 块 JSON 损坏时只显示不可用，不展示半份补丁。
      return Text(s.historyInvalid);
    }
    return ExpansionTile(
      title: Text(s.legacyPatches),
      children: [
        for (final block in blocks)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(s.candidateOriginal),
                SelectableText((block as Map)['original'] as String),
                Text(s.candidateReplacement),
                SelectableText(block['replacement'] as String),
                if (row['status'] == 'pending')
                  TextButton(
                    onPressed: busy
                        ? null
                        : () =>
                              apply(row['id'] as String, block['index'] as int),
                    child: Text(s.applyBlock),
                  ),
              ],
            ),
          ),
        if (row['status'] == 'pending')
          TextButton(
            onPressed: busy ? null : () => apply(row['id'] as String, null),
            child: Text(s.candidateApply),
          ),
      ],
    );
  }
}
