// 主题契约验证：固定已采用的文字/状态对比度，防止主题改动使可读性回退。
// 只验证颜色计算和排版角色，不冒充 Windows 屏幕阅读器或真实 DPI 验收。
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/theme/workbench_theme.dart';

double _contrast(Color foreground, Color background) {
  final first = foreground.computeLuminance();
  final second = background.computeLuminance();
  return (math.max(first, second) + 0.05) / (math.min(first, second) + 0.05);
}

void main() {
  for (final entry in {
    'paper': WorkbenchTokens.paper,
    'frame': WorkbenchTokens.frame,
    'toolbar': WorkbenchTokens.toolbar,
    'floating': WorkbenchTokens.floating,
    'selected': WorkbenchTokens.selected,
    'placeholder': WorkbenchTokens.placeholder,
  }.entries) {
    test('tool text retains AA contrast on ${entry.key}', () {
      expect(
        _contrast(WorkbenchTokens.ink, entry.value),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(WorkbenchTokens.muted, entry.value),
        greaterThanOrEqualTo(4.5),
      );
    });
  }

  test('primary actions and readable warnings retain contrast', () {
    expect(
      _contrast(WorkbenchTokens.floating, WorkbenchTokens.accent),
      greaterThanOrEqualTo(4.5),
    );
    final warningSurface = Color.alphaBlend(
      WorkbenchTokens.warning.withValues(alpha: 0.08),
      WorkbenchTokens.paper,
    );
    expect(
      _contrast(WorkbenchTokens.warning, warningSurface),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(WorkbenchTokens.floating, WorkbenchTokens.inverseSurface),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('necessary focus and source indicators retain non-text contrast', () {
    for (final surface in [
      WorkbenchTokens.paper,
      WorkbenchTokens.frame,
      WorkbenchTokens.floating,
    ]) {
      expect(
        _contrast(WorkbenchTokens.accent, surface),
        greaterThanOrEqualTo(3),
      );
      expect(
        _contrast(WorkbenchTokens.source, surface),
        greaterThanOrEqualTo(3),
      );
    }
  });

  test(
    'tool defaults cannot leak manuscript typography into native fields',
    () {
      final theme = workbenchTheme();
      expect(theme.textTheme.bodyLarge!.fontFamily, WorkbenchTokens.uiFont);
      expect(theme.textTheme.bodyLarge!.fontSize, 14);
      expect(theme.textTheme.bodyLarge!.height, 1.6);
      expect(WorkbenchTokens.body.fontFamily, WorkbenchTokens.serifFont);
      expect(WorkbenchTokens.body.fontSize, 20);
      expect(WorkbenchTokens.body.height, 1.85);
    },
  );
}
