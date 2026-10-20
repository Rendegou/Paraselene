// 桌面自绘标题栏：窗口拖动区、标题与最小化/最大化/关闭按钮。
//
// 只调用 DesktopWindowController 的窗口能力；关闭是否真正执行仍由原生保存守卫决定。
// 按钮提供工具提示、语义节点与确定的焦点顺序，标题栏本身不持有窗口状态。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../l10n/generated/app_localizations.dart';
import 'desktop_window_controller.dart';

/// A separate window row leaves all workbench commands available below it.
///
/// 独立的窗口标题行；下方仍保留完整工作台命令区。窗口操作失败时以实时语义区域
/// 提示，关闭按钮始终走控制器的 requestClose，不直接退出。
class DesktopTitleBar extends StatelessWidget {
  const DesktopTitleBar({
    required this.controller,
    required this.title,
    super.key,
  });

  /// 提供全部窗口操作的控制器；标题栏不缓存其状态。
  final DesktopWindowController controller;

  /// 当前窗口标题，同时用于拖动区文字与语义标签。
  final String title;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: WindowDragRegion(controller: controller, title: title),
                ),
                WindowCaptionButton(
                  label: s.windowMinimize,
                  icon: Icons.remove,
                  order: 1,
                  onPressed: controller.minimize,
                ),
                WindowCaptionButton(
                  label: controller.maximized
                      ? s.windowRestore
                      : s.windowMaximize,
                  icon: controller.maximized
                      ? Icons.filter_none
                      : Icons.crop_square,
                  order: 2,
                  onPressed: controller.toggleMaximize,
                ),
                WindowCaptionButton(
                  label: s.windowClose,
                  icon: Icons.close,
                  order: 3,
                  onPressed: controller.requestClose,
                  isClose: true,
                ),
              ],
            ),
            if (controller.actionFailed)
              Semantics(liveRegion: true, child: Text(s.windowActionFailed)),
            const Divider(height: 1),
          ],
        ),
      ),
    );
  }
}

/// Keyboard focus, tooltip and one labelled semantics node per caption action.
///
/// 标题栏按钮：合并工具提示与语义标签，按 order 固定焦点遍历顺序；
/// 关闭按钮在悬停/按下时使用错误色，但触发仍需控制器完成关闭决策。
class WindowCaptionButton extends StatelessWidget {
  const WindowCaptionButton({
    required this.label,
    required this.icon,
    required this.order,
    required this.onPressed,
    this.isClose = false,
    super.key,
  });

  /// 按钮文案，同时作为工具提示与语义标签。
  final String label;

  /// 按钮图标；图标本身从语义树排除，避免重复朗读。
  final IconData icon;

  /// 焦点遍历顺序，数值越小越靠前。
  final double order;

  /// 按下后的窗口异步操作；失败由控制器记录。
  final Future<void> Function() onPressed;

  /// 是否为关闭按钮，仅影响悬停/按下配色。
  final bool isClose;

  @override
  Widget build(BuildContext context) => FocusTraversalOrder(
    order: NumericFocusOrder(order),
    child: MergeSemantics(
      child: Semantics(
        button: true,
        label: label,
        sortKey: OrdinalSortKey(order),
        child: Tooltip(
          message: label,
          excludeFromSemantics: true,
          child: IconButton(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 44),
            style: ButtonStyle(
              shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) =>
                    isClose &&
                        (states.contains(WidgetState.hovered) ||
                            states.contains(WidgetState.pressed))
                    ? Theme.of(context).colorScheme.error
                    : null,
              ),
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) =>
                    isClose &&
                        (states.contains(WidgetState.hovered) ||
                            states.contains(WidgetState.pressed))
                    ? Theme.of(context).colorScheme.onError
                    : null,
              ),
            ),
            onPressed: () {
              unawaited(onPressed());
            },
            icon: ExcludeSemantics(child: Icon(icon, size: 18)),
          ),
        ),
      ),
    ),
  );
}

/// Only the title area starts dragging; caption actions are siblings.
///
/// 只有标题文字区域发起系统拖动，窗口按钮作为兄弟节点不参与拖动；
/// 双击标题切换最大化。
class WindowDragRegion extends StatelessWidget {
  const WindowDragRegion({
    required this.controller,
    required this.title,
    super.key,
  });

  /// 接收拖动与双击操作的控制器。
  final DesktopWindowController controller;

  /// 窗口标题，显示并作为语义标签。
  final String title;

  @override
  Widget build(BuildContext context) => Semantics(
    label: title,
    sortKey: const OrdinalSortKey(0),
    child: GestureDetector(
      excludeFromSemantics: true,
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) {
        unawaited(controller.startDragging());
      },
      onDoubleTap: () {
        unawaited(controller.toggleMaximize());
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          child: Tooltip(
            message: title,
            child: ExcludeSemantics(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
