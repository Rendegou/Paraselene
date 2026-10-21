// 资料目录展示：加载、错误、空态和分组内容各有独立边界。
// 只接收当前作品的筛选快照；点击只传条目身份给宿主。
import 'dart:async';
import 'package:flutter/material.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/workbench_controls.dart';
import '../../theme/workbench_theme.dart';
import 'sidebar_chrome.dart';

/// 按资料读取状态展示索引，错误不会冒充空列表。
class SidebarResourceDirectory extends StatelessWidget {
  const SidebarResourceDirectory({
    required this.strings,
    required this.rows,
    required this.loading,
    required this.error,
    required this.queryEmpty,
    required this.busy,
    required this.onRetry,
    required this.onAdd,
    required this.onOpen,
    required this.onMissing,
    super.key,
  });

  /// 当前界面语言的完整标签集合。
  final AppLocalizations strings;

  /// 当前作品中已筛选的资料快照，不包含正文副本。
  final List<Map<String, dynamic>> rows;

  /// 当前作用域的读取请求是否进行中。
  final bool loading;

  /// 当前读取是否失败，失败保留重试入口。
  final bool error;

  /// 筛选词是否为空，用于区分无数据和无匹配。
  final bool queryEmpty;

  /// 写屏障状态，为真时禁止变更入口。
  final bool busy;

  /// 仅重试当前作用域，不把失败冒充空结果。
  final VoidCallback onRetry;
  final VoidCallback? onAdd;

  /// 打开明确资料，查看不等于自动引用。
  final Future<void> Function(String) onOpen;

  /// 身份缺失时明确反馈，不猜测其它条目。
  final VoidCallback onMissing;
  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsetsDirectional.all(12),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    if (error) {
      return SidebarResourceError(
        label: strings.loreReadFailed,
        retry: strings.retry,
        onRetry: onRetry,
      );
    }
    final groups = groupSidebarResources(rows);
    final labels = {
      'character': strings.loreGroupCharacters,
      'world': strings.loreGroupWorld,
      'location': strings.loreGroupLocations,
    };
    final hasVisible = groups.values.any((items) => items.isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SidebarHeading(
          strings.resourceDirectory,
          onAdd: onAdd,
          addTooltip: strings.newEntity,
        ),
        if (!hasVisible)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 16),
            child: Text(
              queryEmpty ? strings.resourcesEmpty : strings.noMatchingResources,
              style: WorkbenchTokens.ui(
                size: 12,
                color: WorkbenchTokens.muted,
                height: 1.9,
              ),
            ),
          )
        else
          SidebarResourceGroups(
            groups: groups,
            labels: labels,
            busy: busy,
            onOpen: onOpen,
            onMissing: onMissing,
          ),
      ],
    );
  }
}

/// 各类型资料分组，组内操作保留条目的真实身份。
class SidebarResourceGroups extends StatelessWidget {
  const SidebarResourceGroups({
    required this.groups,
    required this.labels,
    required this.busy,
    required this.onOpen,
    required this.onMissing,
    super.key,
  });

  /// 按协议类型划分的资料快照。
  final Map<String, List<Map<String, dynamic>>> groups;

  /// 界面文案适配器，不转换作者内容。
  final Map<String, String> labels;

  /// 写屏障状态，为真时禁止变更入口。
  final bool busy;

  /// 打开明确资料，查看不等于自动引用。
  final Future<void> Function(String) onOpen;

  /// 身份缺失时明确反馈，不猜测其它条目。
  final VoidCallback onMissing;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final kind in groups.keys)
        if (groups[kind]!.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(8, 10, 8, 7),
            child: Text(
              labels[kind]!,
              style: WorkbenchTokens.ui(size: 12, color: WorkbenchTokens.muted),
            ),
          ),
          for (final row in groups[kind]!)
            SidebarResourceRow(
              row: row,
              kind: kind,
              busy: busy,
              onOpen: onOpen,
              onMissing: onMissing,
            ),
        ],
    ],
  );
}

/// 只将协议已知的资料类型分入导航组，不改写未知数据。
Map<String, List<Map<String, dynamic>>> groupSidebarResources(
  List<Map<String, dynamic>> rows,
) {
  final groups = <String, List<Map<String, dynamic>>>{
    'character': [],
    'world': [],
    'location': [],
  };
  for (final row in rows) {
    final entry = row['entry'];
    if (entry is Map) groups[entry['kind']]?.add(row);
  }
  return groups;
}

/// 资料加载失败后的就地重试入口。
class SidebarResourceError extends StatelessWidget {
  const SidebarResourceError({
    required this.label,
    required this.retry,
    required this.onRetry,
    super.key,
  });

  /// 已翻译的可见文案，同时用于操作的可访问名称。
  final String label;

  /// 重试动作的本地化名称。
  final String retry;

  /// 仅重试当前作用域，不把失败冒充空结果。
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: WorkbenchTokens.ui(
            size: 12,
            color: WorkbenchTokens.muted,
            height: 1.9,
          ),
        ),
        SidebarTextAction(retry, onRetry, color: WorkbenchTokens.accent),
      ],
    ),
  );
}

/// 指向明确条目身份的资料行，忙碌时保留名称并禁用交互。
class SidebarResourceRow extends StatelessWidget {
  const SidebarResourceRow({
    required this.row,
    required this.kind,
    required this.busy,
    required this.onOpen,
    required this.onMissing,
    super.key,
  });

  /// 当前行的资料映射，点击只传条目身份。
  final Map<String, dynamic> row;

  /// 服务端资料类型协议值，不自动改写未知类型。
  final String kind;

  /// 写屏障状态，为真时禁止变更入口。
  final bool busy;

  /// 打开明确资料，查看不等于自动引用。
  final Future<void> Function(String) onOpen;

  /// 身份缺失时明确反馈，不猜测其它条目。
  final VoidCallback onMissing;
  @override
  Widget build(BuildContext context) {
    final entry = row['entry'] as Map;
    final id = entry['id'] as String? ?? '';
    final tone = busy
        ? WorkbenchTokens.muted.withValues(alpha: 0.5)
        : WorkbenchTokens.muted;
    final icon = switch (kind) {
      'location' => Icons.place_outlined,
      'world' => Icons.public_outlined,
      _ => Icons.people_outline,
    };
    return TextButton(
      key: ValueKey('lore-row-$id'),
      onPressed: busy
          ? null
          : () {
              if (id.isEmpty) {
                onMissing();
              } else {
                unawaited(onOpen(id));
              }
            },
      style: WorkbenchControls.button(),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(8, 9, 8, 9),
        child: Row(
          children: [
            Icon(icon, size: 16, color: tone),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                entry['name'] as String? ?? '',
                style: WorkbenchTokens.ui(
                  size: 13,
                  color: busy ? tone : WorkbenchTokens.ink,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 14, color: tone),
          ],
        ),
      ),
    );
  }
}
