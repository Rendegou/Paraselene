// 只读资料预览的标题、当前内容、冻结历史与操作分组。
// 业务动作通过宿主回调执行；这里不持有可变引用集合或滚动控制器。
import 'package:flutter/material.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/workbench_theme.dart';
import 'lore_preview_data.dart';

/// 组成可滚动的当前内容与冻结历史，动作始终留在外层滚动区域之外。
class LorePreviewBody extends StatelessWidget {
  const LorePreviewBody({
    required this.data,
    required this.history,
    required this.currentKey,
    required this.onViewCurrent,
    super.key,
  });

  /// 当前资料副本。
  final LorePreviewData data;

  /// 提交时冻结的引用副本。
  final List<LoreRequestSnapshot> history;

  /// 宿主持有的当前内容定位键。
  final GlobalKey currentKey;

  /// 滚动到当前内容，支持减少动态效果。
  final Future<void> Function() onViewCurrent;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LorePreviewSummary(data: data, currentKey: currentKey),
      if (history.isNotEmpty) ...[
        const Divider(height: 24),
        LorePreviewHistory(history: history, onViewCurrent: onViewCurrent),
      ],
      const SizedBox(height: 8),
      Text(
        AppLocalizations.of(context).lorePreviewHint,
        style: WorkbenchTokens.ui(size: 12, color: WorkbenchTokens.muted),
      ),
    ],
  );
}

/// 标题允许换行，关闭入口保留统一命中区域。
class LorePreviewHeader extends StatelessWidget {
  const LorePreviewHeader({
    required this.data,
    required this.onClose,
    super.key,
  });

  /// 当前条目的展示副本。
  final LorePreviewData data;

  /// 关闭后由外层宿主恢复阅读位置与焦点。
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          data.name,
          style: WorkbenchTokens.ui(size: 16, weight: FontWeight.w600),
        ),
      ),
      IconButton(
        key: const ValueKey('lore-preview-close'),
        onPressed: onClose,
        tooltip: AppLocalizations.of(context).close,
        icon: const Icon(Icons.close, size: 18),
      ),
    ],
  );
}

/// 展示当前版本的元数据与正文，不改写已有的历史引用。
class LorePreviewSummary extends StatelessWidget {
  const LorePreviewSummary({
    required this.data,
    required this.currentKey,
    super.key,
  });

  /// 当前资料的副本。
  final LorePreviewData data;

  /// 宿主持有的滚动目标。
  final GlobalKey currentKey;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final meta = [
      loreKindLabel(s, data.kind),
      'v${data.version}',
      if (data.status.isNotEmpty) data.status,
      if (data.origin != null) data.origin!,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          meta.join(' · '),
          style: WorkbenchTokens.ui(size: 12, color: WorkbenchTokens.muted),
        ),
        const SizedBox(height: 10),
        Container(
          key: currentKey,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: WorkbenchTokens.paper,
            borderRadius: BorderRadius.circular(WorkbenchTokens.radius),
            border: Border.all(color: WorkbenchTokens.stroke),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                s.currentLoreContent,
                key: const ValueKey('lore-preview-current'),
                style: WorkbenchTokens.ui(
                  size: 12,
                  color: WorkbenchTokens.muted,
                ),
              ),
              const SizedBox(height: 6),
              SelectableText(
                data.body.isEmpty ? s.referenceEmpty : data.body,
                style: WorkbenchTokens.ui(size: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 展示提交时冻结的名称与正文；返回当前内容只发起滚动动作。
class LorePreviewHistory extends StatelessWidget {
  const LorePreviewHistory({
    required this.history,
    required this.onViewCurrent,
    super.key,
  });

  /// 不随当前资料变更的历史请求快照。
  final List<LoreRequestSnapshot> history;

  /// 滚动到当前资料，不改变历史快照。
  final Future<void> Function() onViewCurrent;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        AppLocalizations.of(context).historyReferences,
        key: const ValueKey('lore-preview-history'),
        style: WorkbenchTokens.ui(size: 12, weight: FontWeight.w600),
      ),
      for (var index = 0; index < history.length; index++)
        _LoreHistoryItem(
          index: index,
          snapshot: history[index],
          onViewCurrent: onViewCurrent,
        ),
    ],
  );
}

class _LoreHistoryItem extends StatelessWidget {
  const _LoreHistoryItem({
    required this.index,
    required this.snapshot,
    required this.onViewCurrent,
  });
  final int index;
  final LoreRequestSnapshot snapshot;
  final Future<void> Function() onViewCurrent;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey('lore-preview-history-item-$index'),
    margin: const EdgeInsetsDirectional.only(top: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: WorkbenchTokens.frame,
      borderRadius: BorderRadius.circular(WorkbenchTokens.radius),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (snapshot.requestText.isNotEmpty)
          Text(
            snapshot.requestText,
            style: WorkbenchTokens.ui(size: 12, color: WorkbenchTokens.muted),
          ),
        const SizedBox(height: 4),
        Text(
          snapshot.name,
          style: WorkbenchTokens.ui(size: 13, weight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        SelectableText(snapshot.body, style: WorkbenchTokens.ui(size: 13)),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
            key: ValueKey('lore-preview-view-current-$index'),
            onPressed: onViewCurrent,
            child: Text(AppLocalizations.of(context).viewCurrentLore),
          ),
        ),
      ],
    ),
  );
}

/// 操作组可换行，大字号时保留编辑与带入/移除的完整文字。
class LorePreviewActions extends StatelessWidget {
  const LorePreviewActions({
    required this.attached,
    required this.onEdit,
    required this.onAttach,
    required this.onRemove,
    super.key,
  });

  /// 当前线程是否已包含该条目。
  final bool attached;

  /// 进入现有编辑与确认链。
  final VoidCallback? onEdit;

  /// 将条目明确带入冻结的讨论目标。
  final VoidCallback? onAttach;

  /// 从冻结的讨论目标中移除该条目。
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      alignment: WrapAlignment.spaceBetween,
      children: [
        TextButton(
          key: const ValueKey('lore-preview-edit'),
          onPressed: onEdit,
          child: Text(s.expandLoreEdit),
        ),
        if (attached)
          TextButton(
            key: const ValueKey('lore-preview-remove'),
            onPressed: onRemove,
            child: Text(s.removeReference),
          )
        else
          FilledButton(
            key: const ValueKey('lore-preview-attach'),
            onPressed: onAttach,
            child: Text(s.attachToDiscussion),
          ),
      ],
    );
  }
}
