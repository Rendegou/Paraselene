// 资料作用域下拉：whole、retrospective 与 `from:<chapterId>` 三类取值。
// 只读展示：不写库；未知历史取值原样保留并标记为“历史来源”，避免静默改写数据。

import 'package:flutter/material.dart';
import '../theme/workbench_select.dart';
import '../l10n/generated/app_localizations.dart';

/// Friendly chapter choices retain the exact stored scope identities.
///
/// 下拉显示友好名称，但写回的仍是原始 scope 标识（例如 `from:<chapterId>`）。
class LoreScopePicker extends StatelessWidget {
  const LoreScopePicker({
    required this.value,
    required this.chapters,
    required this.onChanged,
    super.key,
  });
  final String value;
  final List<(String, String)> chapters;
  final ValueChanged<String?>? onChanged;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final values = {
      'whole': s.loreScopeWhole,
      'retrospective': s.loreScopeRetrospective,
      for (final chapter in chapters)
        'from:${chapter.$1}': '${s.loreScopeFromChapter} ${chapter.$2}',
    };
    // 旧数据可能含当前界面不认识的 scope，保留原值以免切换时丢失信息。
    if (!values.containsKey(value)) values[value] = s.historicalSource;
    return WorkbenchSelect<String>(
      isExpanded: true,
      label: s.loreScope,
      value: value,
      onChanged: onChanged,
      items: [
        for (final entry in values.entries)
          DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ],
    );
  }
}
