import 'package:flutter/material.dart';

/// Measured colors and dimensions carried forward from the original DESIGN.
abstract final class WorkbenchTokens {
  static const paper = Color(0xfffaf9f5);
  static const frame = Color(0xfff3f4f6);
  static const toolbar = Color(0xfff8f8f9);
  static const ink = Color(0xff292d34);
  static const muted = Color(0xff616976);
  static const stroke = Color(0xffdfe2e7);
  static const accent = Color(0xff49659c);
  static const selected = Color(0xffe8edf5);
  static const warning = Color(0xff955127);
  static const directoryWidth = 240.0;
  static const comfortableWidth = 760.0;
  static const wideWidth = 920.0;
}

/// Offline CJK/Latin tools, CJK serif manuscript and Arabic shaping fallback.
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
    fontFamily: 'Notebook Sans',
    fontFamilyFallback: const ['Noto Arabic'],
  );
  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      bodyLarge: const TextStyle(
        fontFamily: 'Notebook Serif',
        fontFamilyFallback: ['Notebook Sans', 'Noto Arabic'],
        fontSize: 20,
        height: 1.85,
        color: WorkbenchTokens.ink,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        fontSize: 14,
        height: 1.5,
      ),
    ),
    dividerTheme: const DividerThemeData(color: WorkbenchTokens.stroke),
    listTileTheme: const ListTileThemeData(
      selectedTileColor: WorkbenchTokens.selected,
    ),
    drawerTheme: const DrawerThemeData(backgroundColor: WorkbenchTokens.frame),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 500),
    ),
  );
}
