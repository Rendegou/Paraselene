import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'plain_projection.dart';

/// Isolated Quill spike. Raw strings remain the callback/save boundary.
class EditableCandidateB extends StatefulWidget {
  const EditableCandidateB({
    required this.initialText,
    required this.onValue,
    required this.showDiscussion,
    super.key,
  });
  final String initialText;
  final ValueChanged<TextEditingValue> onValue;
  final bool showDiscussion;
  @override
  State<EditableCandidateB> createState() => EditableCandidateBState();
}

class EditableCandidateBState extends State<EditableCandidateB> {
  late final QuillController controller;
  final focusNode = FocusNode();
  final scrollController = ScrollController();
  late final PlainProjection projection;

  @override
  void initState() {
    super.initState();
    projection = PlainProjection(widget.initialText);
    controller = QuillController(
      document: projection.document(discussion: widget.showDiscussion),
      selection: const TextSelection.collapsed(offset: 0),
    );
    controller.addListener(_changed);
  }

  void _changed() {
    final raw = projection.read(controller.document);
    projection.rawText = raw;
    widget.onValue(
      TextEditingValue(
        text: raw,
        selection: projection.selection(
          controller.document,
          controller.selection,
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant EditableCandidateB oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showDiscussion != widget.showDiscussion) {
      // Deliberately uses real Quill transactions so history contamination is
      // observable. This is a failed candidate contract, not a production fix.
      final index = controller.document.toPlainText().indexOf('\n') + 1;
      controller.replaceText(
        index,
        widget.showDiscussion ? 0 : 2,
        widget.showDiscussion
            ? const BlockEmbed(PlainProjection.discussionType, 'transient')
            : '',
        null,
      );
    }
  }

  @override
  Widget build(BuildContext context) => QuillEditor(
    controller: controller,
    focusNode: focusNode,
    scrollController: scrollController,
    config: const QuillEditorConfig(
      padding: EdgeInsets.zero,
      embedBuilders: [DiscussionEmbedBuilder()],
      customStyles: DefaultStyles(
        paragraph: DefaultTextBlockStyle(
          TextStyle(
            fontFamily: 'Notebook Serif',
            fontFamilyFallback: ['Notebook Sans', 'Noto Arabic'],
            fontSize: 20,
            height: 1.85,
          ),
          HorizontalSpacing.zero,
          VerticalSpacing.zero,
          VerticalSpacing.zero,
          null,
        ),
      ),
    ),
  );

  @override
  void dispose() {
    controller.removeListener(_changed);
    controller.dispose();
    focusNode.dispose();
    scrollController.dispose();
    super.dispose();
  }
}

/// A true block widget occupying interparagraph layout space.
class DiscussionEmbedBuilder extends EmbedBuilder {
  const DiscussionEmbedBuilder();
  @override
  String get key => PlainProjection.discussionType;
  @override
  String toPlainText(Embed node) => '';
  @override
  Widget build(BuildContext context, EmbedContext embedContext) =>
      const SizedBox(
        height: 160,
        width: double.infinity,
        child: ColoredBox(
          color: Color(0xfff3f4f6),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('合成段下讨论 · Quill block embed'),
          ),
        ),
      );
}
