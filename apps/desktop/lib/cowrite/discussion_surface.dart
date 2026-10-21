import 'package:flutter/material.dart';
import '../theme/workbench_theme.dart';

/// Embedded discussion owns one paper border; dialog owns its own shell.
class DiscussionSurface extends StatelessWidget {
  const DiscussionSurface({
    required this.inDialog,
    required this.child,
    super.key,
  });
  final bool inDialog;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: inDialog
        ? EdgeInsets.zero
        : const EdgeInsets.symmetric(vertical: 8),
    child: Material(
      key: const ValueKey('discussion-surface'),
      color: inDialog ? WorkbenchTokens.transparent : WorkbenchTokens.paper,
      surfaceTintColor: WorkbenchTokens.transparent,
      elevation: 0,
      shape: inDialog
          ? null
          : const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(
                Radius.circular(WorkbenchTokens.overlayRadius),
              ),
              side: BorderSide(color: WorkbenchTokens.stroke),
            ),
      child: child,
    ),
  );
}
