// reviewed task 内容渲染：摘要任务与 RPG 场景/回应共用，不持有原生请求生命周期。
// 只读展示与本地文本编辑；输出语言只影响下一次请求，与作品语言相互独立。

import 'package:flutter/material.dart';
import '../theme/workbench_theme.dart';
import '../theme/workbench_select.dart';
import '../l10n/generated/app_localizations.dart';

/// Renders a task state without owning the native request lifecycle.
///
/// 渲染 reviewed task 状态，不持有原生请求生命周期；只做展示与本地文本编辑。
class ReviewedTaskContent extends StatelessWidget {
  const ReviewedTaskContent({
    required this.summaryOnly,
    required this.language,
    required this.text,
    required this.scene,
    required this.result,
    required this.busy,
    required this.failed,
    required this.onLanguage,
    super.key,
  });
  final bool summaryOnly;
  final String language;
  final TextEditingController text;
  final Map<String, dynamic>? scene;
  final String? result;
  final bool busy;
  final bool failed;
  final ValueChanged<String?>? onLanguage;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return SizedBox(
      width: 700,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(summaryOnly ? s.summaryTaskNotice : s.rpgTaskNotice),
            TaskOutputLanguage(value: language, onChanged: onLanguage),
            if (scene != null)
              TaskSceneContent(
                scene: scene!,
                onChoose: busy ? null : (value) => text.text = value,
              ),
            if (!summaryOnly)
              TextField(
                style: WorkbenchTokens.input,
                controller: text,
                enabled: !busy,
                minLines: 2,
                maxLines: 6,
                maxLength: scene == null ? 500 : 300,
                decoration: InputDecoration(
                  labelText: scene == null ? s.rpgDirection : s.rpgReply,
                ),
              ),
            if (busy) const LinearProgressIndicator(),
            if (failed)
              Semantics(liveRegion: true, child: Text(s.generationFailed)),
            if (result != null) ...[
              Text(summaryOnly ? s.summaryTaskDone : s.rpgDraftDone),
              SelectableText(result!),
            ],
          ],
        ),
      ),
    );
  }
}

/// 输出语言选择（preserve/zh-Hans/en）；语言决定下一次请求的输出，与作品语言独立。
class TaskOutputLanguage extends StatelessWidget {
  const TaskOutputLanguage({
    required this.value,
    required this.onChanged,
    super.key,
  });
  final String value;
  final ValueChanged<String?>? onChanged;
  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return WorkbenchSelect<String>(
      value: value,
      onChanged: onChanged,
      items: [
        DropdownMenuItem(
          value: 'preserve',
          child: Text(s.preserveTextLanguage),
        ),
        DropdownMenuItem(value: 'zh-Hans', child: Text(s.chineseLabel)),
        DropdownMenuItem(value: 'en', child: Text(s.englishLabel)),
      ],
    );
  }
}

/// RPG 场景文本与预置选项；选择选项只把文本回填到输入框，不发送请求。
class TaskSceneContent extends StatelessWidget {
  const TaskSceneContent({
    required this.scene,
    required this.onChoose,
    super.key,
  });
  final Map<String, dynamic> scene;
  final ValueChanged<String>? onChoose;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SelectableText(scene['scene'] as String),
      for (final option in scene['options'] as List)
        TextButton(
          onPressed: onChoose == null
              ? null
              : () => onChoose!(option as String),
          child: Text(option as String),
        ),
    ],
  );
}
