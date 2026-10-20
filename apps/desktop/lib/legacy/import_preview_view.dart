// 导入预览只读视图：展示检测格式、警告与会话消息；预览内容由原生层有意截断。
// 不执行导入写入，也不修改作者数据。

import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';

/// Deliberately truncated native preview; the disclosure stays beside its text.
///
/// 原生预览有意截断，相关警示与预览正文一起展示；本视图不执行导入写入。
class ImportPreviewView extends StatelessWidget {
  const ImportPreviewView({required this.preview, super.key});
  final Map<String, dynamic> preview;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final sessions = preview['sessions'] as List;
    final warnings = preview['warnings'] as List;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(preview['detectedFormat'] as String),
        // 任一会话被标记为部分导入时也必须明示，不能只看 warnings 列表。
        if (warnings.isNotEmpty ||
            sessions.any((row) => (row as Map)['partial'] == true))
          Text(s.importPartial),
        for (final warning in warnings) Text(warning as String),
        for (final row in sessions.cast<Map>())
          ExpansionTile(
            title: Text((row['title'] ?? row['externalId']) as String),
            subtitle: Text('${row['messageCount']}'),
            children: [
              for (final message in (row['messages'] as List).cast<Map>())
                ListTile(
                  title: Text(message['role'] as String),
                  subtitle: SelectableText(message['text'] as String),
                ),
            ],
          ),
      ],
    );
  }
}
