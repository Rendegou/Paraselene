import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';

/// Lossless raw text projection while a transient discussion block is intact.
/// Quill offsets are UTF-16; a block and its synthetic newline occupy two units.
final class PlainProjection {
  PlainProjection(this.rawText);
  String rawText;
  static const discussionType = 'm3-discussion';

  Document document({required bool discussion}) {
    final text = '$rawText\n';
    final boundary = text.indexOf('\n') + 1;
    if (!discussion) {
      return Document.fromJson([
        {'insert': text},
      ]);
    }
    return Document.fromJson([
      {'insert': text.substring(0, boundary)},
      {
        'insert': {discussionType: 'transient'},
      },
      {'insert': '\n${text.substring(boundary)}'},
    ]);
  }

  /// Removes intact discussion blocks and one mandatory Quill final newline.
  /// Deleted block boundaries cannot be recovered by this projection alone.
  String read(Document document) {
    final output = StringBuffer();
    var skipNewline = false;
    for (final operation in document.toDelta().toList()) {
      final data = operation.data;
      if (data is Map && data.containsKey(discussionType)) {
        skipNewline = true;
      } else if (data is String) {
        var text = data;
        if (skipNewline && text.startsWith('\n')) {
          text = text.substring(1);
        }
        skipNewline = false;
        output.write(text);
      } else {
        throw StateError('unsupported-embed');
      }
    }
    final text = output.toString();
    if (!text.endsWith('\n')) throw StateError('missing-quill-sentinel');
    return text.substring(0, text.length - 1);
  }

  /// Rejects offsets splitting a UTF-16 surrogate pair.
  static int scalarOffset(String text, int offset) {
    if (offset < 0 || offset > text.length) throw RangeError.value(offset);
    if (offset > 0 && offset < text.length) {
      final left = text.codeUnitAt(offset - 1);
      final right = text.codeUnitAt(offset);
      if (left >= 0xd800 &&
          left <= 0xdbff &&
          right >= 0xdc00 &&
          right <= 0xdfff) {
        throw ArgumentError('surrogate-split');
      }
    }
    return text.substring(0, offset).runes.length;
  }

  /// Maps intact block offsets to raw UTF-16 offsets for save/CAS selection.
  TextSelection selection(Document document, TextSelection selection) {
    int map(int offset) {
      var display = 0;
      var raw = 0;
      var skipNewline = false;
      for (final operation in document.toDelta().toList()) {
        final data = operation.data;
        if (data is Map) {
          if (offset <= display + 1) return raw;
          display++;
          skipNewline = true;
        } else if (data is String) {
          final skipped = skipNewline && data.startsWith('\n') ? 1 : 0;
          final consumed = (offset - display).clamp(0, data.length);
          if (offset <= display + data.length) {
            return (raw + consumed - skipped).clamp(0, read(document).length);
          }
          display += data.length;
          raw += data.length - skipped;
          skipNewline = false;
        }
      }
      return read(document).length;
    }

    final text = read(document);
    final base = map(selection.baseOffset);
    final extent = map(selection.extentOffset);
    scalarOffset(text, base);
    scalarOffset(text, extent);
    return TextSelection(baseOffset: base, extentOffset: extent);
  }
}
