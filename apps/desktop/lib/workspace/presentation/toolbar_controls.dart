// 顶栏控件：共享命中和焦点状态，不持有业务状态。
import 'package:flutter/material.dart';
import '../../theme/workbench_controls.dart';
import '../../theme/workbench_theme.dart';

/// 顶栏使用共享32px可视底板与48px透明命中区；选中与焦点保持同一边界。
class ToolbarButton extends StatelessWidget {
  const ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.label,
    this.compact = false,
    this.selected = false,
    this.accent = false,
    super.key,
  });

  /// 统一图标体系内的 Material 图标标识。
  final IconData icon;

  /// 完整操作名称，图标模式下仍可访问。
  final String tooltip;

  /// 已翻译的可见文案，同时用于操作的可访问名称。
  final String? label;

  /// 为空表示禁用；具体业务由宿主处理。
  final VoidCallback? onPressed;

  /// 是否只展示图标；可访问名称仍保留。
  final bool compact;

  /// 当前行的选中状态，同时暴露选中语义。
  final bool selected;

  /// 是否使用主题强调色，不改变命中几何。
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final showLabel = label != null && !compact;
    final color = !enabled
        ? WorkbenchTokens.muted.withValues(alpha: 0.5)
        : accent
        ? WorkbenchTokens.accent
        : WorkbenchTokens.ink;
    return Semantics(
      label: tooltip,
      onTap: onPressed,
      selected: selected,
      excludeSemantics: true,
      button: true,
      enabled: enabled,
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: TextButton(
          onPressed: onPressed,
          style: WorkbenchControls.button(
            selected: selected,
            foreground: color,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17),
              if (showLabel) ...[
                const SizedBox(width: WorkbenchControls.gap),
                Text(label!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 带下拉箭头的顶部栏菜单触发区。
class ToolbarMenuTrigger extends StatelessWidget {
  const ToolbarMenuTrigger({
    required this.icon,
    required this.label,
    required this.compact,
    this.enabled = true,
    super.key,
  });

  /// 统一图标体系内的 Material 图标标识。
  final IconData icon;

  /// 已翻译的可见文案，同时用于操作的可访问名称。
  final String label;

  /// 是否只展示图标；可访问名称仍保留。
  final bool compact;

  /// 当前菜单是否可操作，禁用不删除原标签。
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? WorkbenchTokens.ink
        : WorkbenchTokens.muted.withValues(alpha: 0.5);
    return Container(
      height: 40,
      padding: EdgeInsetsDirectional.symmetric(horizontal: compact ? 8 : 10),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: color),
          if (!compact) ...[
            const SizedBox(width: 7),
            Text(label, style: WorkbenchTokens.ui(size: 13, color: color)),
          ],
          const SizedBox(width: 3),
          Icon(Icons.arrow_drop_down, size: 16, color: color),
        ],
      ),
    );
  }
}

/// 讨论索引条目：目标文本（或全章讨论）+ 有效性 + 未发草稿。

/// 带图标与文案的通用操作按钮；保持至少 48px 的可点击尺寸。
class ChromeAction extends StatelessWidget {
  const ChromeAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  /// 已翻译的可见文案，同时用于操作的可访问名称。
  final String label;

  /// 统一图标体系内的 Material 图标标识。
  final IconData icon;

  /// 为空表示禁用；具体业务由宿主处理。
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
    ),
  );
}
