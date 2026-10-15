import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'c_native.dart';
import 'c_layout.dart';
import 'c_scene.dart';

/// Visible-page canvas with one global focus/native input client.
class CViewport extends StatefulWidget {
  const CViewport({required this.editor, super.key});
  final CNativeEditor editor;
  @override
  State<CViewport> createState() => CViewportState();
}

class CViewportState extends State<CViewport> {
  final scroll = ScrollController();
  final painters = CVisiblePainters();
  late final TextPainter _slotLabel;
  CScene? scene;
  Size _size = Size.zero;
  int _revision = 0;
  int _anchor = 0;
  int _lastExtent = -1;
  CNativeEditor get editor => widget.editor;
  @override
  void initState() {
    super.initState();
    _slotLabel = TextPainter(
      text: const TextSpan(
        text: '  ◇ SLOT A       ◇ SLOT B — transient inter-paragraph space',
        style: TextStyle(
          fontFamily: 'Notebook Sans',
          fontSize: 13,
          color: Color(0xff3f573e),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    editor.addListener(_changed);
    editor.focusNode.addListener(_focus);
    scroll.addListener(_scroll);
  }

  @override
  void didUpdateWidget(CViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editor != editor) {
      oldWidget.editor.removeListener(_changed);
      oldWidget.editor.focusNode.removeListener(_focus);
      editor.addListener(_changed);
      editor.focusNode.addListener(_focus);
    }
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    final extent = editor.value.selection.extentOffset;
    if (_lastExtent != extent) {
      _lastExtent = extent;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ensureCaret();
      });
    }
  }

  void _focus() {
    if (editor.focusNode.hasFocus) {
      editor.attach(View.of(context).viewId);
    } else {
      editor.detach();
    }
  }

  void requestFocus() {
    editor.focusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && editor.focusNode.hasFocus) {
        editor.attach(View.of(context).viewId);
      }
    });
  }

  void _scroll() {
    if (mounted) setState(() {});
  }

  void ensureCaret() {
    if (!scroll.hasClients || _size.height == 0) return;
    editor.layout.ensureOffset(editor.value.selection.extentOffset);
    final page = editor
        .layout
        .pages[editor.layout.pageAtOffset(editor.value.selection.extentOffset)];
    final caret = cCaret(
      painters.get(editor.layout, page),
      page,
      editor.value.selection.extentOffset,
      Offset(0, page.y),
    );
    var target = scroll.offset;
    if (caret.top < target + 12) target = caret.top - 12;
    if (caret.bottom > target + _size.height - 12) {
      target = caret.bottom - _size.height + 12;
    }
    target = target.clamp(0, scroll.position.maxScrollExtent);
    if ((target - scroll.offset).abs() > .1) scroll.jumpTo(target);
  }

  void _geometry() {
    if (!mounted || scene == null) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    var composing = scene!.caret;
    for (final rect in scene!.composing) {
      composing = composing.expandToInclude(rect);
    }
    editor.geometry(
      box.size,
      box.getTransformTo(null),
      scene!.caret,
      composing,
    );
  }

  int _hit(Offset point) {
    final raw = editor.document.raw;
    final hit = scene!.hit(point).clamp(0, raw.length);
    final range = CharacterRange.at(raw, hit);
    return range.stringBeforeLength;
  }

  void _tap(TapDownDetails details) {
    if (editor.composing || scene == null) return;
    requestFocus();
    editor.select(TextSelection.collapsed(offset: _hit(details.localPosition)));
  }

  void _dragStart(DragStartDetails details) {
    if (editor.composing || scene == null) return;
    requestFocus();
    _anchor = _hit(details.localPosition);
    editor.select(TextSelection.collapsed(offset: _anchor));
  }

  void _drag(DragUpdateDetails details) {
    if (editor.composing || scene == null) return;
    editor.select(
      TextSelection(
        baseOffset: _anchor,
        extentOffset: _hit(details.localPosition),
      ),
    );
    if (!scroll.hasClients) return;
    final dy = details.localPosition.dy;
    if (dy < 16 || dy > _size.height - 16) {
      scroll.jumpTo(
        (scroll.offset + (dy < 16 ? -24 : 24)).clamp(
          0,
          scroll.position.maxScrollExtent,
        ),
      );
    }
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
        !editor.composing &&
        !HardwareKeyboard.instance.isControlPressed) {
      final key = event.logicalKey;
      if ([
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.home,
        LogicalKeyboardKey.end,
      ].contains(key)) {
        _geometryMove(key, HardwareKeyboard.instance.isShiftPressed);
        return KeyEventResult.handled;
      }
    }
    return editor.key(node, event);
  }

  void _geometryMove(LogicalKeyboardKey key, bool shift) {
    final layout = editor.layout;
    final offset = editor.value.selection.extentOffset;
    layout.ensureOffset(offset);
    final page = layout.pages[layout.pageAtOffset(offset)];
    final painter = painters.get(layout, page);
    final local = TextPosition(
      offset: (offset - page.start).clamp(0, page.text.length),
    );
    int next;
    if (key == LogicalKeyboardKey.home || key == LogicalKeyboardKey.end) {
      final line = painter.getLineBoundary(local);
      next =
          page.start + (key == LogicalKeyboardKey.home ? line.start : line.end);
    } else {
      final caret = cCaret(painter, page, offset, Offset(0, page.y));
      final lineHeight = painter.computeLineMetrics().first.height;
      final y =
          caret.center.dy +
          (key == LogicalKeyboardKey.arrowUp ? -lineHeight : lineHeight);
      var target = layout.pages.first;
      for (final candidate in layout.pages) {
        if (candidate.y <= y) target = candidate;
        if (candidate.y > y) break;
      }
      next =
          target.start +
          painters
              .get(layout, target)
              .getPositionForOffset(Offset(caret.left, y - target.y))
              .offset;
    }
    final range = CharacterRange.at(
      editor.document.raw,
      next.clamp(0, editor.length),
    );
    editor.move(range.stringBeforeLength, shift);
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: editor.focusNode,
    onKeyEvent: _key,
    child: LayoutBuilder(
      builder: (context, constraints) {
        if (editor.renderingError != null) {
          return Semantics(
            textField: true,
            value: editor.document.raw,
            child: Center(child: Text(editor.renderingError!)),
          );
        }
        _size = constraints.biggest;
        editor.width(math.min(760, math.max(80, _size.width - 48)));
        return Scrollbar(
          controller: scroll,
          thumbVisibility: true,
          child: Scrollable(
            controller: scroll,
            viewportBuilder: (context, offset) {
              offset.applyViewportDimension(_size.height);
              final corrected = editor.layout.prepareViewport(
                offset.pixels,
                _size.height,
                caret: editor.value.selection.extentOffset,
              );
              if ((corrected - offset.pixels).abs() > .01) {
                offset.correctBy(corrected - offset.pixels);
              }
              offset.applyContentDimensions(
                0,
                math.max(0, editor.layout.height - _size.height),
              );
              scene = cBuildScene(
                layout: editor.layout,
                cache: painters,
                value: editor.value,
                viewport: _size,
                scroll: offset.pixels,
                revision: ++_revision,
                slotLabel: _slotLabel,
              );
              WidgetsBinding.instance.addPostFrameCallback((_) => _geometry());
              return Semantics(
                textField: true,
                multiline: true,
                focused: editor.focusNode.hasFocus,
                label: 'Candidate C synthetic document',
                value: editor.document.raw,
                onTap: requestFocus,
                onSetSelection: (selection) => editor.select(selection),
                onSetText: (text) => editor.apply(
                  TextEditingValue(
                    text: text,
                    selection: TextSelection.collapsed(offset: text.length),
                  ),
                ),
                child: ExcludeSemantics(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: _tap,
                    onPanStart: _dragStart,
                    onPanUpdate: _drag,
                    child: ClipRect(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          size: _size,
                          painter: CScenePainter(
                            scene!,
                            editor.focusNode.hasFocus,
                          ),
                          isComplex: true,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    ),
  );

  @override
  void dispose() {
    editor.removeListener(_changed);
    editor.focusNode.removeListener(_focus);
    scroll.dispose();
    painters.dispose();
    _slotLabel.dispose();
    super.dispose();
  }
}
