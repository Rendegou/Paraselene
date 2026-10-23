// 纸面标题与章末：共享正文滚动位置，工具不混入正文或导出。
import 'package:flutter/material.dart';
import '../../theme/workbench_controls.dart';
import '../../theme/workbench_theme.dart';

/// 随纸面滚动的标题、元信息和出处状态。
class ManuscriptPaperHeader extends StatelessWidget {
  const ManuscriptPaperHeader({
    required this.title,
    required this.meta,
    required this.renameLabel,
    required this.onRename,
    this.sourceStatus,
    this.sourceOpenFailure,
    super.key,
  });

  /// 作者标题原文，不参加界面伪本地化。
  final String title;

  /// 只读作品和字数说明，不加入作者正文。
  final String meta;

  /// 重命名动作的本地化名称。
  final String renameLabel;

  /// 打开本地化重命名流程并恢复正文焦点。
  final VoidCallback? onRename;

  /// 出处读取状态组件，不进入正文数据。
  final Widget? sourceStatus;

  /// 资料打开失败后的就地恢复入口。
  final Widget? sourceOpenFailure;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(48, 60, 48, 42),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
            ),
            if (onRename != null) ...[
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 10),
                child: ManuscriptTextAction(
                  label: renameLabel,
                  accent: true,
                  onPressed: onRename,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Flexible(
              child: Text(
                meta,
                style: WorkbenchTokens.ui(
                  size: 12,
                  color: WorkbenchTokens.muted,
                  height: 1.6,
                ),
              ),
            ),
            if (sourceStatus != null) ...[
              const SizedBox(width: 12),
              Flexible(child: sourceStatus!),
            ],
          ],
        ),
        if (sourceOpenFailure != null) sourceOpenFailure!,
      ],
    ),
  );
}

/// 随正文末尾滚动的撤销、重做与整章讨论入口。
class ManuscriptPaperFooter extends StatelessWidget {
  const ManuscriptPaperFooter({
    required this.chapterEnd,
    required this.undoLabel,
    required this.redoLabel,
    required this.discussionLabel,
    required this.onUndo,
    required this.onRedo,
    required this.onDiscussion,
    super.key,
  });

  /// 位于正文末尾之后的章末说明。
  final String chapterEnd;

  /// 撤销动作的本地化名称。
  final String undoLabel;

  /// 重做动作的本地化名称。
  final String redoLabel;

  /// 讨论动作的本地化名称。
  final String discussionLabel;

  /// 当前文档可撤销时的命令，不绕过编辑历史。
  final VoidCallback? onUndo;

  /// 当前文档可重做时的命令，不绕过编辑历史。
  final VoidCallback? onRedo;

  /// 允许整章讨论时的命令。
  final VoidCallback? onDiscussion;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(48, 14, 48, 24),
    child: Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: WorkbenchTokens.stroke)),
      ),
      padding: const EdgeInsetsDirectional.only(top: 14),
      child: Wrap(
        spacing: 14,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            chapterEnd,
            style: WorkbenchTokens.ui(size: 12, color: WorkbenchTokens.muted),
          ),
          ManuscriptTextAction(label: undoLabel, onPressed: onUndo),
          ManuscriptTextAction(label: redoLabel, onPressed: onRedo),
          if (onDiscussion != null)
            ManuscriptTextAction(
              label: discussionLabel,
              onPressed: onDiscussion,
            ),
        ],
      ),
    ),
  );
}

/// 纸面内的共享文字动作，保留禁用、键盘和命中合同。
class ManuscriptTextAction extends StatelessWidget {
  const ManuscriptTextAction({
    required this.label,
    required this.onPressed,
    this.accent = false,
    super.key,
  });

  /// 已翻译的可见文案，同时用于操作的可访问名称。
  final String label;

  /// 为空表示禁用；具体业务由宿主处理。
  final VoidCallback? onPressed;

  /// 是否使用主题强调色，不改变命中几何。
  final bool accent;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: WorkbenchControls.button(
      foreground: accent ? WorkbenchTokens.accent : WorkbenchTokens.muted,
    ),
    child: Text(label),
  );
}

/// 选区附近的小型工具，保持锚点命中而不覆盖相邻正文。
class ManuscriptSelectionAction extends StatelessWidget {
  const ManuscriptSelectionAction({
    required this.label,
    required this.onPressed,
    super.key,
  });

  /// 已翻译的可见文案，同时用于操作的可访问名称。
  final String label;

  /// 为空表示禁用；具体业务由宿主处理。
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Semantics(
    // InkWell 的 tap 语义不携带 button 角色；浮动操作需要明确的按钮身份。
    button: true,
    label: label,
    child: Material(
      color: WorkbenchTokens.floating,
      elevation: 2,
      shadowColor: WorkbenchTokens.shadow,
      borderRadius: BorderRadius.circular(WorkbenchTokens.overlayRadius),
      child: InkWell(
        key: const ValueKey('discuss-selection-inline'),
        onTap: onPressed,
        borderRadius: BorderRadius.circular(WorkbenchTokens.overlayRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.forum_outlined,
                size: 14,
                color: WorkbenchTokens.accent,
              ),
              const SizedBox(width: 5),
              Text(label, style: WorkbenchTokens.ui(size: 12)),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 收起线程的独立页边标记，不占正文排版高度。
class ManuscriptThreadMarker extends StatelessWidget {
  const ManuscriptThreadMarker({
    required this.id,
    required this.label,
    required this.onPressed,
    super.key,
  });

  /// 线程稳定身份，不用相似文字猜测目标。
  final String id;

  /// 已翻译的可见文案，同时用于操作的可访问名称。
  final String label;

  /// 为空表示禁用；具体业务由宿主处理。
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Material(
      // 选中浅蓝底 + 强调色图标：页边标记在纸面上需要可发现，不被当成装饰点。
      color: WorkbenchTokens.selected,
      shape: const CircleBorder(),
      child: InkWell(
        key: ValueKey('thread-marker-open-$id'),
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: const SizedBox(
          width: 24,
          height: 24,
          child: Icon(
            Icons.forum_outlined,
            size: 14,
            color: WorkbenchTokens.accent,
          ),
        ),
      ),
    ),
  );
}
