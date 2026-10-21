// 讨论操作行：集中输出语言、资料、生成、取消与展开动作。
// 只根据快照控制可用性，所有异步动作仍回到原讨论宿主。
import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/workbench_controls.dart';
import '../theme/workbench_select.dart';
import 'discussion_presentation.dart';

/// 使用统一按钮底座和状态规则展示讨论操作。
class DiscussionPanelToolbar extends StatelessWidget {
  const DiscussionPanelToolbar({
    required this.view,
    required this.actions,
    super.key,
  });

  /// 当前讨论状态。
  final DiscussionPresentation view;

  /// 由宿主处理的动作接口。
  final DiscussionPanelActions actions;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Wrap(
      spacing: WorkbenchControls.gap,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _DiscussionLanguage(view: view, onChanged: actions.onLanguage),
        if (view.canReference)
          TextButton(
            onPressed: view.busy ? null : actions.onReferences,
            child: Text(
              '${s.referenceMaterials} (${(view.thread.snapshot['attached'] as List).length})',
            ),
          ),
        if (view.canGenerate)
          FilledButton(
            onPressed:
                view.busy ||
                    view.running ||
                    !view.thread.valid ||
                    view.thread.isChapter
                ? null
                : actions.onGenerate,
            child: Text(s.generationPreview),
          ),
        if (view.running)
          TextButton(
            onPressed: view.cancelling ? null : actions.onCancel,
            child: Text(s.generationCancel),
          ),
        WorkbenchDisclosure(
          label: s.candidateCompare,
          expanded: view.compare,
          onPressed: actions.onCompare,
        ),
        WorkbenchDisclosure(
          label: s.discussionHistory,
          expanded: view.history,
          onPressed: actions.onHistory,
        ),
      ],
    );
  }
}

class _DiscussionLanguage extends StatelessWidget {
  const _DiscussionLanguage({required this.view, required this.onChanged});
  final DiscussionPresentation view;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return WorkbenchSelect<String>(
      value: view.outputLanguage,
      items: [
        DropdownMenuItem(
          value: 'preserve',
          child: Text(s.preserveTextLanguage),
        ),
        DropdownMenuItem(value: 'zh-Hans', child: Text(s.chineseLabel)),
        DropdownMenuItem(value: 'en', child: Text(s.englishLabel)),
      ],
      onChanged: view.running || view.busy
          ? null
          : (value) => onChanged(value!),
    );
  }
}
