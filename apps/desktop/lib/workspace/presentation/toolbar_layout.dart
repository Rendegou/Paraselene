// 工具栏密度依据当前译文、文字缩放与编辑能力测量，预留标题和保存状态空间。
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/workbench_theme.dart';
import 'save_status_snapshot.dart';
import 'workbench_toolbar.dart';

/// 按真实标签宽度折叠；窄窗的完整动作仍在更多菜单中。
///
/// [availableWidth] 为父约束扣除内距后的逻辑像素，不钳制文字缩放。
({bool compact, bool narrow}) toolbarDensity(
  BuildContext context,
  WorkbenchToolbar toolbar,
  double availableWidth,
) {
  final scaler = MediaQuery.textScalerOf(context);
  final s = toolbar.strings;
  final registry = toolbar.actions;
  final buttons = [
    if (registry != null) s.findInChapter,
    if (registry != null && registry.canDiscuss && !toolbar.controller.isBusy)
      s.discussSelection,
    if (registry != null && registry.threads.isNotEmpty)
      s.discussionIndex(registry.threads.length),
    toolbar.focus ? s.focusOff : s.focusOn,
    s.chapterDiscussion,
  ];
  final menus = [
    s.chapterAndVersions,
    s.layoutMenu,
    s.exportMenu,
    s.languageLabel,
    s.moreTools,
  ];
  var requiredWidth = 50.0 + (toolbar.onShowSidebar == null ? 0 : 48);
  for (final label in buttons) {
    requiredWidth += math.max(48, 41 + _labelWidth(context, label));
  }
  for (final label in menus) {
    requiredWidth += 63 + _labelWidth(context, label);
  }
  // 保留标题、状态与二者间距，不能等动作占满后再挤压文字。
  final reserve = math.max(
    math.max(200, scaler.scale(15) * 12),
    scaler.scale(80) + 12 + _statusWidth(context, toolbar),
  );
  requiredWidth += reserve;
  final compactActions =
      50 +
      (toolbar.onShowSidebar == null ? 0 : 48) +
      buttons.length * 48 +
      menus.length * 52;
  final narrow =
      availableWidth <
      math.max(760 * scaler.scale(1), compactActions + reserve);
  return (compact: narrow || availableWidth < requiredWidth, narrow: narrow);
}

double _statusWidth(BuildContext context, WorkbenchToolbar toolbar) {
  final status = SaveStatusSnapshot.of(toolbar.controller);
  if (status.isEmpty) return 0;
  return _labelWidth(context, status.statusText(toolbar.labels), size: 12) +
      (status.hasError ? 37 : 16);
}

double _labelWidth(BuildContext context, String label, {double size = 13}) {
  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: WorkbenchTokens.ui(size: size),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}
