// Material 控件主题：按输入、导航、反馈等职责组织可复用组件配置。
// 不持有状态或执行 IO；业务通过 workbenchTheme 使用这些显式角色。
import 'package:flutter/material.dart';
import 'workbench_controls.dart';
import 'workbench_tokens.dart';

/// 保持原生控件交互语义，同时消除默认字体与表面颜色泄漏。
abstract final class WorkbenchComponentThemes {
  /// 工具文本默认 14px/1.6；作者正文必须显式选 body 角色。
  static TextTheme text(TextTheme base) => base.copyWith(
    bodyLarge: WorkbenchTokens.ui(),
    bodyMedium: WorkbenchTokens.ui(),
    bodySmall: WorkbenchTokens.ui(size: 12, color: WorkbenchTokens.muted),
    titleMedium: WorkbenchTokens.ui(size: 15, weight: FontWeight.w500),
    titleLarge: WorkbenchTokens.ui(size: 18, weight: FontWeight.w600),
    titleSmall: WorkbenchTokens.ui(size: 12, color: WorkbenchTokens.muted),
    headlineMedium: WorkbenchTokens.title,
    headlineSmall: WorkbenchTokens.titleCompact,
    labelLarge: WorkbenchTokens.ui(size: 13),
  );

  /// 图标底板继承按钮状态与独立命中区域。
  static IconButtonThemeData iconButton() => IconButtonThemeData(
    style: WorkbenchControls.button(foreground: WorkbenchTokens.muted).copyWith(
      iconSize: const WidgetStatePropertyAll(18),
      padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) &&
                !states.contains(WidgetState.disabled)
            ? WorkbenchTokens.selected
            : WorkbenchTokens.transparent,
      ),
    ),
  );

  /// 卡片只绘制一次纸面与装饰细线，不叠默认色调或阴影。
  static const card = CardThemeData(
    color: WorkbenchTokens.paper,
    surfaceTintColor: WorkbenchTokens.transparent,
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(
        Radius.circular(WorkbenchTokens.overlayRadius),
      ),
      side: BorderSide(color: WorkbenchTokens.stroke),
    ),
  );

  /// 复选框保留原生选择形状、48px 命中和局部焦点线。
  static CheckboxThemeData checkbox() => CheckboxThemeData(
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
    side: WidgetStateBorderSide.resolveWith(
      (states) => BorderSide(
        color: states.contains(WidgetState.disabled)
            ? WorkbenchTokens.stroke
            : states.contains(WidgetState.focused)
            ? WorkbenchTokens.accent
            : WorkbenchTokens.muted,
        width: states.contains(WidgetState.focused) ? 2 : 1,
      ),
    ),
    overlayColor: WidgetStateProperty.resolveWith(_selectionOverlay),
  );

  /// 开关以轨道和切换状态表达选择，不套普通按钮底板。
  static SwitchThemeData toggle() => SwitchThemeData(
    materialTapTargetSize: MaterialTapTargetSize.padded,
    overlayColor: WidgetStateProperty.resolveWith(_selectionOverlay),
    trackOutlineColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.focused)
          ? WorkbenchTokens.accent
          : WorkbenchTokens.muted,
    ),
    trackOutlineWidth: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.focused) ? 2 : 1,
    ),
  );

  /// 方向中性的装饰分隔线，不承担控件唯一识别信息。
  static const divider = DividerThemeData(
    color: WorkbenchTokens.stroke,
    thickness: 1,
    space: 1,
  );

  /// 表单输入的边框、标签及错误使用工具角色，焦点仅影响局部边线。
  static InputDecorationTheme input() => InputDecorationTheme(
    isDense: true,
    filled: false,
    border: _inputBorder(WorkbenchTokens.stroke),
    enabledBorder: _inputBorder(WorkbenchTokens.stroke),
    disabledBorder: _inputBorder(WorkbenchTokens.stroke),
    errorBorder: _inputBorder(WorkbenchTokens.warning),
    focusedErrorBorder: _inputBorder(WorkbenchTokens.warning, width: 2),
    focusedBorder: _inputBorder(WorkbenchTokens.accent, width: 2),
    hintStyle: WorkbenchTokens.ui(size: 13, color: WorkbenchTokens.muted),
    labelStyle: WorkbenchTokens.ui(size: 13, color: WorkbenchTokens.muted),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    errorStyle: WorkbenchTokens.ui(size: 12, color: WorkbenchTokens.warning),
  );

  /// 菜单由原生路由管理焦点与关闭，外观使用统一轻浮层。
  static PopupMenuThemeData menu() => PopupMenuThemeData(
    color: WorkbenchTokens.floating,
    elevation: 4,
    menuPadding: const EdgeInsets.all(4),
    position: PopupMenuPosition.under,
    surfaceTintColor: WorkbenchTokens.transparent,
    shape: _overlayShape(),
    textStyle: WorkbenchTokens.ui(),
  );

  /// 任务型对话框标题为 15px/500；浏览标题由 titleLarge 显式消费。
  static DialogThemeData dialog() => DialogThemeData(
    backgroundColor: WorkbenchTokens.floating,
    surfaceTintColor: WorkbenchTokens.transparent,
    elevation: 8,
    barrierColor: WorkbenchControls.barrier,
    shape: _overlayShape(),
    titleTextStyle: WorkbenchTokens.ui(size: 15, weight: FontWeight.w500),
    contentTextStyle: WorkbenchTokens.ui(),
  );

  /// 窄窗目录继承框架表面与固定角色宽度。
  static const drawer = DrawerThemeData(
    backgroundColor: WorkbenchTokens.frame,
    surfaceTintColor: WorkbenchTokens.transparent,
    width: WorkbenchTokens.directoryWidth,
    shape: RoundedRectangleBorder(),
  );

  /// 导航行保留起止方向、选中底色与原生列表语义。
  static ListTileThemeData listTile() => ListTileThemeData(
    contentPadding: const EdgeInsetsDirectional.symmetric(
      horizontal: 12,
      vertical: 4,
    ),
    titleTextStyle: WorkbenchTokens.ui(),
    subtitleTextStyle: WorkbenchTokens.ui(
      size: 12,
      color: WorkbenchTokens.muted,
    ),
    selectedTileColor: WorkbenchTokens.selected,
    iconColor: WorkbenchTokens.muted,
    textColor: WorkbenchTokens.ink,
    dense: true,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(WorkbenchTokens.radius),
    ),
  );

  /// 辅助提示使用反色表面，保持至少 12px 的可读文字。
  static TooltipThemeData tooltip() => TooltipThemeData(
    textStyle: WorkbenchTokens.ui(size: 12, color: WorkbenchTokens.floating),
    decoration: BoxDecoration(
      color: WorkbenchTokens.inverseSurface,
      borderRadius: BorderRadius.circular(4),
    ),
    waitDuration: const Duration(milliseconds: 500),
  );

  /// 滚动条几何保持原有设计；轨迹不作为操作的唯一入口。
  static const scrollbar = ScrollbarThemeData(
    thickness: WidgetStatePropertyAll(8),
    radius: Radius.circular(4),
    thumbColor: WidgetStatePropertyAll(WorkbenchTokens.stroke),
    crossAxisMargin: 2,
  );

  /// 可恢复反馈使用统一反色表面和工具文字。
  static SnackBarThemeData snackBar() => SnackBarThemeData(
    backgroundColor: WorkbenchTokens.inverseSurface,
    contentTextStyle: WorkbenchTokens.ui(
      size: 13,
      color: WorkbenchTokens.floating,
    ),
    behavior: SnackBarBehavior.floating,
  );
}

OutlineInputBorder _inputBorder(Color color, {double width = 1}) =>
    OutlineInputBorder(
      borderRadius: const BorderRadius.all(
        Radius.circular(WorkbenchTokens.radius),
      ),
      borderSide: BorderSide(color: color, width: width),
    );

RoundedRectangleBorder _overlayShape() => RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(WorkbenchTokens.overlayRadius),
);

Color _selectionOverlay(Set<WidgetState> states) {
  if (states.contains(WidgetState.disabled)) return WorkbenchTokens.transparent;
  if (states.contains(WidgetState.focused)) return WorkbenchTokens.focusOverlay;
  if (states.contains(WidgetState.pressed)) {
    return WorkbenchTokens.pressedOverlay;
  }
  if (states.contains(WidgetState.hovered)) return WorkbenchTokens.hoverOverlay;
  return WorkbenchTokens.transparent;
}
