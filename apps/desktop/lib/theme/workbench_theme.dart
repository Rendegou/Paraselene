// 工作台主题：沿用原 TS 版 DESIGN 的颜色、字号、圆角与间距令牌，
// 并把 Material 组件的默认外观压平为原版的轻量描边风格。
//
// 纯 Flutter 主题构建，无 IO、不写库；尺寸单位为逻辑像素。界面字体使用
// Notebook Sans，正文使用 Notebook Serif，阿拉伯文回退 Noto Arabic。
import 'package:flutter/material.dart';

/// Measured colors and dimensions carried forward from the original DESIGN.
///
/// 从原 TS 版 CSS 精确量取的颜色、字号与尺寸；尺寸单位为逻辑像素。
abstract final class WorkbenchTokens {
  /// 正文纸面底色。
  static const paper = Color(0xfffaf9f5);

  /// 外框、目录与工具栏底色。
  static const frame = Color(0xfff3f4f6);

  /// 顶部工具栏底色。
  static const toolbar = Color(0xfff8f8f9);

  /// 主要文字颜色。
  static const ink = Color(0xff292d34);

  /// 次要文字颜色。
  static const muted = Color(0xff616976);

  /// 分隔线与描边颜色。
  static const stroke = Color(0xffdfe2e7);

  /// 可交互元素的强调色。
  static const accent = Color(0xff49659c);

  /// 选中项底色。
  static const selected = Color(0xffe8edf5);

  /// 按钮悬停底色。
  static const hover = Color(0xffe9ecf1);

  /// 正文选区底色。
  static const selection = Color(0xffdce5f4);

  /// 警告与错误提示颜色。
  static const warning = Color(0xff955127);

  /// 保存状态绿点。
  static const saved = Color(0xff647f70);

  /// 目录栏宽度，单位为逻辑像素。
  static const directoryWidth = 240.0;

  /// 舒适阅读的正文栏宽（含两侧留白），单位为逻辑像素。
  static const comfortableWidth = 856.0;

  /// 宽屏布局的正文栏宽（含两侧留白），单位为逻辑像素。
  static const wideWidth = 1016.0;

  /// 顶部工具栏高度。
  static const toolbarHeight = 56.0;

  /// 控件圆角。
  static const radius = 6.0;

  /// 浮层圆角。
  static const overlayRadius = 8.0;

  /// 界面字体：工具、导航与标题。
  static const uiFont = 'Notebook Sans';

  /// 正文衬线字体。
  static const serifFont = 'Notebook Serif';

  /// 阿拉伯文与混排回退字体。
  static const fallbackFont = 'Noto Arabic';

  /// 界面文字样式：默认 14px/1.6 无衬线。
  static TextStyle ui({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    double height = 1.6,
    Color color = ink,
    double? letterSpacing,
    List<FontFeature>? fontFeatures,
  }) => TextStyle(
    fontFamily: uiFont,
    fontFamilyFallback: const [fallbackFont],
    fontSize: size,
    fontWeight: weight,
    height: height,
    color: color,
    letterSpacing: letterSpacing,
    fontFeatures: fontFeatures,
  );

  /// 正文样式：20px/1.85 衬线。
  static const body = TextStyle(
    fontFamily: serifFont,
    fontFamilyFallback: [uiFont, fallbackFont],
    fontSize: 20,
    height: 1.85,
    color: ink,
  );
}

/// Flutter theme that mirrors the original writing-workspace stylesheet.
///
/// 构建与原始写作工作台一致的浅色主题：平面按钮、细描边、6px/8px 圆角，
/// 并在所有文字与控件上保持相同的字体、字号与颜色。
ThemeData workbenchTheme() {
  const colors = ColorScheme.light(
    primary: WorkbenchTokens.accent,
    onPrimary: Colors.white,
    primaryContainer: WorkbenchTokens.selected,
    onPrimaryContainer: WorkbenchTokens.ink,
    secondary: WorkbenchTokens.accent,
    onSecondary: Colors.white,
    surface: WorkbenchTokens.paper,
    onSurface: WorkbenchTokens.ink,
    onSurfaceVariant: WorkbenchTokens.muted,
    surfaceContainer: WorkbenchTokens.frame,
    surfaceContainerLow: WorkbenchTokens.toolbar,
    outline: WorkbenchTokens.stroke,
    error: WorkbenchTokens.warning,
    onError: Colors.white,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    scaffoldBackgroundColor: colors.surface,
    fontFamily: WorkbenchTokens.uiFont,
    fontFamilyFallback: const [WorkbenchTokens.fallbackFont],
  );
  final flat = ButtonStyle(
    textStyle: WidgetStatePropertyAll(WorkbenchTokens.ui()),
    foregroundColor: const WidgetStatePropertyAll(WorkbenchTokens.ink),
    backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
    overlayColor: const WidgetStatePropertyAll(WorkbenchTokens.hover),
    minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WorkbenchTokens.radius),
      ),
    ),
    elevation: const WidgetStatePropertyAll(0),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      bodyLarge: WorkbenchTokens.body,
      bodyMedium: WorkbenchTokens.ui(),
      bodySmall: WorkbenchTokens.ui(size: 12, color: WorkbenchTokens.muted),
      titleMedium: WorkbenchTokens.ui(size: 15, weight: FontWeight.w500),
      titleSmall: WorkbenchTokens.ui(size: 12, color: WorkbenchTokens.muted),
      headlineMedium: WorkbenchTokens.ui(
        size: 32,
        weight: FontWeight.w600,
        height: 1.55,
        letterSpacing: -0.8,
      ),
      headlineSmall: WorkbenchTokens.ui(
        size: 27,
        weight: FontWeight.w600,
        height: 1.55,
        letterSpacing: -0.5,
      ),
      labelLarge: WorkbenchTokens.ui(size: 13),
    ),
    textButtonTheme: TextButtonThemeData(style: flat),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        textStyle: WidgetStatePropertyAll(WorkbenchTokens.ui()),
        backgroundColor: const WidgetStatePropertyAll(WorkbenchTokens.accent),
        foregroundColor: const WidgetStatePropertyAll(Colors.white),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WorkbenchTokens.radius),
          ),
        ),
        elevation: const WidgetStatePropertyAll(0),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(style: flat),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: const WidgetStatePropertyAll(WorkbenchTokens.muted),
        overlayColor: const WidgetStatePropertyAll(WorkbenchTokens.hover),
        minimumSize: const WidgetStatePropertyAll(Size(36, 36)),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WorkbenchTokens.radius),
          ),
        ),
      ),
    ),
    iconTheme: const IconThemeData(color: WorkbenchTokens.muted, size: 18),
    dividerTheme: const DividerThemeData(
      color: WorkbenchTokens.stroke,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      hintStyle: WorkbenchTokens.ui(size: 13, color: WorkbenchTokens.muted),
      labelStyle: WorkbenchTokens.ui(size: 13, color: WorkbenchTokens.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      errorStyle: WorkbenchTokens.ui(size: 12, color: WorkbenchTokens.warning),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Colors.white,
      elevation: 8,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WorkbenchTokens.overlayRadius),
      ),
      textStyle: WorkbenchTokens.ui(),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 16,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WorkbenchTokens.overlayRadius),
      ),
      titleTextStyle: WorkbenchTokens.ui(size: 15, weight: FontWeight.w500),
      contentTextStyle: WorkbenchTokens.ui(),
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: WorkbenchTokens.frame,
      surfaceTintColor: Colors.transparent,
      width: WorkbenchTokens.directoryWidth,
      shape: RoundedRectangleBorder(),
    ),
    listTileTheme: ListTileThemeData(
      selectedTileColor: WorkbenchTokens.selected,
      iconColor: WorkbenchTokens.muted,
      textColor: WorkbenchTokens.ink,
      dense: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WorkbenchTokens.radius),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      textStyle: WorkbenchTokens.ui(size: 12, color: Colors.white),
      decoration: BoxDecoration(
        color: const Color(0xff2f3640),
        borderRadius: BorderRadius.circular(4),
      ),
      waitDuration: const Duration(milliseconds: 500),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(8),
      radius: const Radius.circular(4),
      thumbColor: const WidgetStatePropertyAll(WorkbenchTokens.stroke),
      crossAxisMargin: 2,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xff2f3640),
      contentTextStyle: WorkbenchTokens.ui(size: 13, color: Colors.white),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
