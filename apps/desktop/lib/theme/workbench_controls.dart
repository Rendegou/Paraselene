// 原生控件的共享状态与几何：只构建样式，不持有业务状态；尺寸均为 logical px。
import 'package:flutter/material.dart';
import 'workbench_tokens.dart';

/// Native controls share a quiet visual plate and a separate 48px hit target.
abstract final class WorkbenchControls {
  /// Minimum visible height; text scaling may increase it without clipping.
  static const controlHeight = 32.0;

  /// Visible icon plate; Material adds transparent padding to 48px.
  static const iconPlate = 32.0;

  /// Space between controls or an icon and its label.
  static const gap = 8.0;

  /// Inset owned by the discussion surface.
  static const panelInset = 12.0;

  /// Modal scrim belongs only to blocking dialogs.
  static const barrier = Color(0x52292d34);

  /// Flat, outlined, primary and selected controls keep identical state bounds.
  static ButtonStyle button({
    bool primary = false,
    bool selected = false,
    bool outlined = false,
    Color foreground = WorkbenchTokens.ink,
  }) => ButtonStyle(
    textStyle: WidgetStatePropertyAll(WorkbenchTokens.ui(size: 13)),
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? WorkbenchTokens.muted.withValues(alpha: 0.5)
          : primary
          ? Colors.white
          : foreground,
    ),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return primary ? WorkbenchTokens.stroke : Colors.transparent;
      }
      if (primary) return WorkbenchTokens.accent;
      if (selected) return WorkbenchTokens.selected;
      return Colors.transparent;
    }),
    overlayColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return Colors.transparent;
      if (states.contains(WidgetState.pressed)) {
        return primary ? const Color(0x24ffffff) : const Color(0x2449659c);
      }
      if (states.contains(WidgetState.hovered)) {
        return primary ? const Color(0x14ffffff) : const Color(0x1249659c);
      }
      return Colors.transparent;
    }),
    side: WidgetStateProperty.resolveWith((states) {
      if (!states.contains(WidgetState.disabled) &&
          states.contains(WidgetState.focused)) {
        return BorderSide(
          color: primary ? Colors.white : WorkbenchTokens.accent,
          width: 2,
        );
      }
      return BorderSide(
        color: outlined ? WorkbenchTokens.stroke : Colors.transparent,
        width: 2,
      );
    }),
    minimumSize: const WidgetStatePropertyAll(
      Size(controlHeight, controlHeight),
    ),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(WorkbenchTokens.radius)),
      ),
    ),
    elevation: const WidgetStatePropertyAll(0),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    visualDensity: VisualDensity.standard,
    tapTargetSize: MaterialTapTargetSize.padded,
    splashFactory: NoSplash.splashFactory,
    animationDuration: Duration.zero,
  );

  /// Draft input owns its focus line; its parent owns the paper surface.
  static InputDecoration draft(String label) => InputDecoration(
    labelText: label,
    filled: false,
    contentPadding: const EdgeInsets.all(panelInset),
    border: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(WorkbenchTokens.radius)),
      borderSide: BorderSide(color: WorkbenchTokens.stroke),
    ),
    enabledBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(WorkbenchTokens.radius)),
      borderSide: BorderSide(color: WorkbenchTokens.stroke),
    ),
    focusedBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(WorkbenchTokens.radius)),
      borderSide: BorderSide(color: WorkbenchTokens.accent, width: 2),
    ),
  );
}

/// A disclosed toggle keeps its label, selected semantics and chevron in sync.
class WorkbenchDisclosure extends StatelessWidget {
  const WorkbenchDisclosure({
    required this.label,
    required this.expanded,
    required this.onPressed,
    super.key,
  });
  final String label;
  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    expanded: expanded,
    selected: expanded,
    child: TextButton(
      onPressed: onPressed,
      style: WorkbenchControls.button(selected: expanded),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 16),
          const SizedBox(width: WorkbenchControls.gap),
          Flexible(child: Text(label)),
        ],
      ),
    ),
  );
}
