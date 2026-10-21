// 目录外壳控件：品牌、筛选、页签与状态，只消费本地化标签和显式回调。
// 不读写仓库；文字随缩放增长，所有操作继承工作台控件状态。
import 'package:flutter/material.dart';

import '../../theme/workbench_controls.dart';
import '../../theme/workbench_theme.dart';

/// 目录品牌与可选的收起入口。
class SidebarBrand extends StatelessWidget {
  const SidebarBrand({required this.closeLabel, this.onCollapse, super.key});

  /// 收起操作的可访问名称。
  final String closeLabel;

  /// 抽屉中为空，普通目录中收起侧栏。
  final VoidCallback? onCollapse;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 56,
    child: Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 20),
      child: Row(
        children: [
          const Icon(
            Icons.menu_book_outlined,
            size: 21,
            color: WorkbenchTokens.accent,
          ),
          const SizedBox(width: 11),
          Text(
            '幻月',
            style: WorkbenchTokens.ui(
              size: 18,
              weight: FontWeight.w500,
              letterSpacing: 0.7,
            ),
          ),
          const Spacer(),
          if (onCollapse != null)
            IconButton(
              tooltip: closeLabel,
              onPressed: onCollapse,
              icon: const Icon(Icons.view_sidebar_outlined, size: 16),
            ),
        ],
      ),
    ),
  );
}

/// 只筛选当前页签的搜索框，外壳和输入焦点分别绘制。
class SidebarSearch extends StatelessWidget {
  const SidebarSearch({
    required this.query,
    required this.hint,
    required this.clearLabel,
    required this.onChanged,
    required this.onClear,
    super.key,
  });

  /// 由目录状态持有并释放的查询控制器。
  final TextEditingController query;

  /// 当前筛选对象的本地化提示。
  final String hint;

  /// 清空操作名称。
  final String clearLabel;

  /// 更新筛选，不改变数据。
  final ValueChanged<String> onChanged;

  /// 清空当前查询。
  final VoidCallback onClear;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(16, 17, 16, 18),
    child: Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: WorkbenchTokens.placeholder,
        borderRadius: BorderRadius.circular(WorkbenchTokens.radius),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 15, color: WorkbenchTokens.muted),
          const SizedBox(width: 9),
          Expanded(
            child: TextField(
              key: const ValueKey('sidebar-search-field'),
              controller: query,
              style: WorkbenchTokens.ui(size: 13),
              cursorColor: WorkbenchTokens.accent,
              decoration: InputDecoration(
                hintText: hint,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(
                    color: WorkbenchTokens.accent,
                    width: 2,
                  ),
                ),
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: onChanged,
            ),
          ),
          if (query.text.trim().isNotEmpty)
            IconButton(
              key: const ValueKey('sidebar-search-clear'),
              tooltip: clearLabel,
              onPressed: onClear,
              icon: const Icon(Icons.close, size: 16),
            ),
        ],
      ),
    ),
  );
}

/// 当前目录索引的页签，选中同时通过底线和语义表达。
class SidebarTabButton extends StatelessWidget {
  const SidebarTabButton({
    required this.label,
    required this.count,
    required this.active,
    required this.onPressed,
    super.key,
  });

  /// 已翻译的索引名称。
  final String label;

  /// 未截断的数据条数，超过 99 时只简化显示。
  final int count;

  /// 是否为当前索引。
  final bool active;

  /// 切换索引并由宿主清空查询。
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: active,
    child: TextButton(
      style: WorkbenchControls.button(selected: active),
      onPressed: onPressed,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(2, 7, 2, 10),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active
                    ? WorkbenchTokens.accent
                    : WorkbenchTokens.transparent,
                width: 2,
              ),
            ),
          ),
          padding: const EdgeInsetsDirectional.only(bottom: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: WorkbenchTokens.ui(
                    size: 13,
                    color: active ? WorkbenchTokens.ink : WorkbenchTokens.muted,
                    weight: active ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                count > 99 ? '99+' : '$count',
                style: WorkbenchTokens.ui(
                  size: 12,
                  color: WorkbenchTokens.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 两个目录索引共享分隔线，计数来自当前作品快照。
class SidebarTabs extends StatelessWidget {
  const SidebarTabs({
    required this.chaptersLabel,
    required this.resourcesLabel,
    required this.chapterCount,
    required this.resourceCount,
    required this.resourcesSelected,
    required this.onChanged,
    super.key,
  });
  final String chaptersLabel;
  final String resourcesLabel;
  final int chapterCount;
  final int resourceCount;
  final bool resourcesSelected;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsetsDirectional.symmetric(horizontal: 20),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: WorkbenchTokens.stroke)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: SidebarTabButton(
              label: chaptersLabel,
              count: chapterCount,
              active: !resourcesSelected,
              onPressed: () => onChanged(false),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: SidebarTabButton(
              label: resourcesLabel,
              count: resourceCount,
              active: resourcesSelected,
              onPressed: () => onChanged(true),
            ),
          ),
        ),
      ],
    ),
  );
}

/// 目录分组标题，新增操作使用独立可访问名称。
class SidebarHeading extends StatelessWidget {
  const SidebarHeading(this.label, {this.onAdd, this.addTooltip, super.key});

  /// 分组名称。
  final String label;

  /// 当前允许新增时的操作。
  final VoidCallback? onAdd;

  /// 新增操作的本地化名称。
  final String? addTooltip;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 8, 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: WorkbenchTokens.ui(size: 12, color: WorkbenchTokens.muted),
          ),
        ),
        if (onAdd != null)
          IconButton(
            tooltip: addTooltip,
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 16),
          ),
      ],
    ),
  );
}

/// 目录内的次级文字动作，继承共享命中与禁用状态。
class SidebarTextAction extends StatelessWidget {
  const SidebarTextAction(
    this.label,
    this.onPressed, {
    this.color = WorkbenchTokens.muted,
    super.key,
  });

  /// 操作名称。
  final String label;

  /// 为空时保持禁用语义。
  final VoidCallback? onPressed;

  /// 已定义的语义文字色。
  final Color color;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: WorkbenchControls.button(
      foreground: color,
    ).copyWith(textStyle: WidgetStatePropertyAll(WorkbenchTokens.ui(size: 12))),
    child: Text(label),
  );
}

/// 侧栏底部的数据模式说明及切换作品入口。
class SidebarFooter extends StatelessWidget {
  const SidebarFooter({
    required this.modeLabel,
    required this.switchLabel,
    required this.onSwitch,
    super.key,
  });

  /// 明示真实桥接或合成数据模式。
  final String modeLabel;

  /// 切换作品的本地化名称。
  final String switchLabel;

  /// 忙碌时为空。
  final VoidCallback? onSwitch;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 10),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: WorkbenchTokens.stroke)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            modeLabel,
            style: WorkbenchTokens.ui(size: 12, color: WorkbenchTokens.muted),
          ),
        ),
        SidebarTextAction(switchLabel, onSwitch),
      ],
    ),
  );
}
