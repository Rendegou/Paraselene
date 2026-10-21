// 资料出处片段视图：按记录版本的正文与偏移高亮出处区间。
// 只读：不修改正文；仅当 anchor.isCurrent 为 true 时允许跳转到来源章节。

import 'package:flutter/material.dart';
import '../theme/workbench_theme.dart';
import '../l10n/generated/app_localizations.dart';

/// Highlight offsets refer to the exact recorded version, in Unicode scalars.
///
/// 高亮偏移属于被记录的那个版本，以 Unicode 标量计；只读展示，不改正文。
class LoreSourceView extends StatelessWidget {
  const LoreSourceView({required this.source, required this.onOpen, super.key});
  final Map<String, dynamic> source;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final anchor = source['anchor'] as Map;
    // 存储偏移是 Unicode 标量数，因此用 runes 而不是 UTF-16 下标切分正文。
    final points = (source['body'] as String).runes.toList();
    final start = anchor['startChar'] as int;
    final end = anchor['endChar'] as int;
    return ExpansionTile(
      title: Text(s.historicalSource),
      children: [
        if (anchor['isCurrent'] != true) Text(s.historicalSource),
        SelectableText.rich(
          TextSpan(
            style: DefaultTextStyle.of(context).style,
            children: [
              TextSpan(text: String.fromCharCodes(points.take(start))),
              TextSpan(
                text: String.fromCharCodes(
                  points.skip(start).take(end - start),
                ),
                style: WorkbenchTokens.sourceHighlight(
                  Theme.of(context).colorScheme,
                ),
              ),
              TextSpan(text: String.fromCharCodes(points.skip(end))),
            ],
          ),
        ),
        TextButton(
          // 仅仍指向当前正文的出处允许跳转，历史出处保留展示但禁用跳转。
          onPressed: anchor['isCurrent'] == true ? onOpen : null,
          child: Text(s.openSourceChapter),
        ),
      ],
    );
  }
}
