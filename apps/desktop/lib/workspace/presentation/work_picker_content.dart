// 作品选择的搜索与列表：展示受控目录，不拥有作品或异步任务。
// 查询输入可随文字增高，内容高度由当前视口限制，核心操作不靠缩小字体适配。
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/workbench_theme.dart';
import '../data/workspace_repository.dart';
import '../workspace_controller.dart';
import 'workbench_chrome.dart';

/// 作品筛选展示；列表选择仅转发给会话所有者。
class WorkPickerContent extends StatelessWidget {
  const WorkPickerContent({
    required this.controller,
    required this.labels,
    required this.query,
    required this.works,
    required this.onQuery,
    required this.onClear,
    required this.onSelect,
    super.key,
  });

  /// 目录和当前选择的只读来源。
  final WorkspaceController controller;

  /// 当前界面的文本包装器。
  final WorkbenchLabels labels;

  /// 查询输入的外部所有者负责释放。
  final TextEditingController query;

  /// 已按标题筛选的只读目录。
  final List<WorkspaceWork> works;

  /// 查询变化回传本地State。
  final ValueChanged<String> onQuery;

  /// 清空查询动作。
  final VoidCallback onClear;

  /// 选择作品；处理程序负责等待并展示失败。
  final Future<void> Function(WorkspaceWork) onSelect;

  @override
  Widget build(BuildContext context) {
    final viewport =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).vertical;
    return SizedBox(
      width: 460,
      height: math.min(320, viewport * 0.55),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WorkSearch(
            query: query,
            labels: labels,
            onChanged: onQuery,
            onClear: onClear,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: controller.works.isEmpty
                ? Text(labels(labels.strings.noWorksBody))
                : works.isEmpty
                ? Text(labels(labels.strings.noMatchingWorks))
                : ListView.builder(
                    itemCount: works.length,
                    itemBuilder: (_, index) {
                      final work = works[index];
                      return ListTile(
                        key: ValueKey('work-${work.id}'),
                        title: Text(work.title),
                        selected: controller.currentWork?.id == work.id,
                        onTap: controller.isBusy
                            ? null
                            : () async {
                                await onSelect(work);
                              },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _WorkSearch extends StatelessWidget {
  const _WorkSearch({
    required this.query,
    required this.labels,
    required this.onChanged,
    required this.onClear,
  });
  final TextEditingController query;
  final WorkbenchLabels labels;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 48),
    padding: const EdgeInsetsDirectional.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: WorkbenchTokens.placeholder,
      borderRadius: BorderRadius.circular(WorkbenchTokens.radius),
    ),
    child: Row(
      children: [
        const Icon(Icons.search, size: 16, color: WorkbenchTokens.muted),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            key: const ValueKey('work-picker-search'),
            controller: query,
            style: WorkbenchTokens.ui(size: 13),
            cursorColor: WorkbenchTokens.accent,
            decoration: InputDecoration(
              hintText: labels.strings.searchWorks,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: WorkbenchTokens.accent, width: 2),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
            onChanged: onChanged,
          ),
        ),
        if (query.text.trim().isNotEmpty)
          IconButton(
            key: const ValueKey('work-picker-search-clear'),
            onPressed: onClear,
            tooltip: labels.strings.clearSearch,
            icon: const Icon(Icons.close, size: 16),
          ),
      ],
    ),
  );
}
