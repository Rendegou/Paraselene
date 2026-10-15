import 'package:flutter/material.dart';

/// Native editing baseline with an intentionally unapproved inline-slot probe.
///
/// [showDiscussion] replaces the first existing LF's rendered span with a real
/// WidgetSpan of equal UTF-16 length. Raw source remains unchanged. EOF slots
/// without LF are unsupported; native IME and hit testing remain separate gates.
class EditableCandidateA extends StatefulWidget {
  const EditableCandidateA({
    required this.initialText,
    required this.onValue,
    required this.showDiscussion,
    super.key,
  });

  final String initialText;
  final ValueChanged<TextEditingValue> onValue;
  final bool showDiscussion;

  @override
  State<EditableCandidateA> createState() => EditableCandidateAState();
}

/// Owns stable native editing identities until the candidate is disposed.
class EditableCandidateAState extends State<EditableCandidateA> {
  late final TextEditingController controller;
  final FocusNode focusNode = FocusNode();
  final ScrollController scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    controller = _SlotProbeController(text: widget.initialText);
    controller.addListener(_reportValue);
  }

  void _reportValue() => widget.onValue(controller.value);

  @override
  void dispose() {
    controller.removeListener(_reportValue);
    controller.dispose();
    focusNode.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final probe = controller as _SlotProbeController;
      probe.showDiscussion = widget.showDiscussion;
      probe.slotWidth = constraints.maxWidth;
      return EditableText(
        controller: controller,
        focusNode: focusNode,
        scrollController: scrollController,
        style: const TextStyle(
          fontFamily: 'Notebook Serif',
          fontFamilyFallback: ['Notebook Sans', 'Noto Arabic'],
          fontSize: 20,
          height: 1.85,
          color: Color(0xff222222),
        ),
        cursorColor: const Color(0xff49659c),
        backgroundCursorColor: const Color(0xff999999),
        selectionColor: const Color(0x5549659c),
        // EditableText defaults to forced strut height, which lets a tall
        // placeholder paint across following text instead of reserving space.
        strutStyle: const StrutStyle(forceStrutHeight: false),
        maxLines: null,
        expands: true,
        keyboardType: TextInputType.multiline,
      );
    },
  );
}

class _SlotProbeController extends TextEditingController {
  _SlotProbeController({required super.text});

  bool showDiscussion = false;
  double slotWidth = 600;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final newline = text.indexOf('\n');
    if (!showDiscussion || newline < 0) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final boundary = newline + 1;
    return TextSpan(
      style: style,
      children: [
        ..._sourceSpans(0, newline, withComposing),
        WidgetSpan(
          child: SizedBox(
            key: const ValueKey('candidate-a-inline-slot'),
            width: slotWidth,
            height: 96,
            child: const ColoredBox(
              color: Color(0xfff3f4f6),
              child: Text(
                'A: LF replacement slot · experimental',
                style: TextStyle(fontSize: 14, color: Color(0xff49659c)),
              ),
            ),
          ),
        ),
        ..._sourceSpans(boundary, text.length, withComposing),
      ],
    );
  }

  List<InlineSpan> _sourceSpans(int start, int end, bool withComposing) {
    final range = value.composing;
    if (!withComposing ||
        !value.isComposingRangeValid ||
        range.isCollapsed ||
        range.end <= start ||
        range.start >= end) {
      return [TextSpan(text: text.substring(start, end))];
    }
    final from = range.start.clamp(start, end);
    final to = range.end.clamp(start, end);
    return [
      TextSpan(text: text.substring(start, from)),
      TextSpan(
        text: text.substring(from, to),
        style: const TextStyle(decoration: TextDecoration.underline),
      ),
      TextSpan(text: text.substring(to, end)),
    ];
  }
}
