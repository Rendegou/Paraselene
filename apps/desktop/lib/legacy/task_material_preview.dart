// 付费请求材料预览：展示模型、预估 token 与全部待发消息，确认后才允许发送。
// 只读视图：不发送、不落库、不修改草稿。

import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';

/// All exact prepared messages remain selectable before explicit paid approval.
///
/// 在显式付费确认前展示全部待发材料（模型、预估 token、每条消息），均可选中复制。
class TaskMaterialPreview extends StatelessWidget {
  const TaskMaterialPreview({required this.prepared, super.key});
  final Map<String, dynamic> prepared;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(s.generationPreview),
      content: SizedBox(
        width: 700,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.deepseekFeeNotice),
              Text('${prepared['model']} · ${prepared['estimated_tokens']}'),
              for (final message in prepared['messages'] as List)
                SelectableText(
                  '${(message as Map)['role']}\n${message['content']}\n',
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(s.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(s.generationApprove),
        ),
      ],
    );
  }
}
