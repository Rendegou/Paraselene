import 'package:flutter/material.dart';
import 'workbench_controls.dart';

/// A tool selector uses the shared button plate and native menu route.
/// Values remain unchanged; long labels wrap and Escape restores trigger focus.
class WorkbenchSelect<T> extends StatefulWidget {
  const WorkbenchSelect({
    required this.value,
    required this.items,
    required this.onChanged,
    this.isExpanded = false,
    this.label,
    super.key,
  });
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final bool isExpanded;
  final String? label;

  @override
  State<WorkbenchSelect<T>> createState() => _WorkbenchSelectState<T>();
}

class _WorkbenchSelectState<T> extends State<WorkbenchSelect<T>> {
  final _focus = FocusNode();
  bool _open = false;

  Future<void> _show() async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    setState(() => _open = true);
    final value = await showMenu<T>(
      context: context,
      requestFocus: true,
      initialValue: widget.value,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(
          origin.dx,
          origin.dy + box.size.height,
          box.size.width,
          0,
        ),
        Offset.zero & overlay.size,
      ),
      items: [
        for (final item in widget.items)
          WorkbenchCheckedMenuItem<T>(
            value: item.value,
            enabled: item.enabled,
            checked: item.value == widget.value,
            child: item.child,
          ),
      ],
    );
    if (!mounted) return;
    setState(() => _open = false);
    _focus.requestFocus();
    if (value != null) widget.onChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.items.where((item) => item.value == widget.value);
    final trigger = Semantics(
      expanded: _open,
      child: TextButton(
        style: const ButtonStyle(alignment: AlignmentDirectional.centerStart),
        focusNode: _focus,
        onPressed: widget.onChanged == null ? null : _show,
        child: Row(
          mainAxisSize: widget.isExpanded ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Flexible(child: selected.first.child),
            const SizedBox(width: 8),
            const Icon(Icons.expand_more, size: 16),
          ],
        ),
      ),
    );
    if (widget.label == null) return trigger;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label!, style: Theme.of(context).textTheme.bodySmall),
        trigger,
      ],
    );
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }
}
