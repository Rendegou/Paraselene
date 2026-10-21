// 工作台主题装配：保持原有纸面与控件视觉，主题角色来自同目录的令牌与组件主题。
// 只构建 Flutter 值，不执行 IO；所有尺寸为 logical px，作者稿件显式消费 body。
import 'package:flutter/material.dart';
import 'workbench_controls.dart';
import 'workbench_component_themes.dart';
import 'workbench_tokens.dart';

export 'workbench_tokens.dart';

/// 构建唯一浅色工作台主题；默认文字服务工具界面，稿件使用独立正文角色。
ThemeData workbenchTheme() {
  const colors = ColorScheme.light(
    primary: WorkbenchTokens.accent,
    onPrimary: WorkbenchTokens.floating,
    primaryContainer: WorkbenchTokens.selected,
    onPrimaryContainer: WorkbenchTokens.ink,
    secondary: WorkbenchTokens.accent,
    onSecondary: WorkbenchTokens.floating,
    surface: WorkbenchTokens.paper,
    onSurface: WorkbenchTokens.ink,
    onSurfaceVariant: WorkbenchTokens.muted,
    surfaceContainer: WorkbenchTokens.frame,
    surfaceContainerLow: WorkbenchTokens.toolbar,
    outline: WorkbenchTokens.stroke,
    error: WorkbenchTokens.warning,
    onError: WorkbenchTokens.floating,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    scaffoldBackgroundColor: colors.surface,
    fontFamily: WorkbenchTokens.uiFont,
    fontFamilyFallback: const [WorkbenchTokens.fallbackFont],
  );
  return base.copyWith(
    splashFactory: NoSplash.splashFactory,
    hoverColor: WorkbenchTokens.hoverOverlay,
    highlightColor: WorkbenchTokens.pressedOverlay,
    focusColor: WorkbenchTokens.selected,
    textTheme: WorkbenchComponentThemes.text(base.textTheme),
    textButtonTheme: TextButtonThemeData(style: WorkbenchControls.button()),
    filledButtonTheme: FilledButtonThemeData(
      style: WorkbenchControls.button(primary: true),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: WorkbenchControls.button(outlined: true),
    ),
    iconButtonTheme: WorkbenchComponentThemes.iconButton(),
    cardTheme: WorkbenchComponentThemes.card,
    iconTheme: const IconThemeData(color: WorkbenchTokens.muted, size: 18),
    checkboxTheme: WorkbenchComponentThemes.checkbox(),
    switchTheme: WorkbenchComponentThemes.toggle(),
    dividerTheme: WorkbenchComponentThemes.divider,
    inputDecorationTheme: WorkbenchComponentThemes.input(),
    popupMenuTheme: WorkbenchComponentThemes.menu(),
    dialogTheme: WorkbenchComponentThemes.dialog(),
    drawerTheme: WorkbenchComponentThemes.drawer,
    listTileTheme: WorkbenchComponentThemes.listTile(),
    tooltipTheme: WorkbenchComponentThemes.tooltip(),
    scrollbarTheme: WorkbenchComponentThemes.scrollbar,
    snackBarTheme: WorkbenchComponentThemes.snackBar(),
  );
}
