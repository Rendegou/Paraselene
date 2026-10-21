// ARB 占位符扫描：识别嵌套 plural/select 与 ICU 引号，不把分支正文当参数。

/// 按项目 use-escaping:true 返回占位符；格式错误不暴露原文。
Set<String> messageFields(String message) {
  final reader = _IcuReader(message);
  reader.readMessage(nested: false);
  return reader.fields;
}

class _IcuReader {
  _IcuReader(this.source);
  final String source;
  final fields = <String>{};
  var position = 0;

  void readMessage({required bool nested}) {
    while (position < source.length) {
      final character = source[position];
      if (character == "'") {
        _quote();
      } else if (character == '{') {
        _argument();
      } else if (character == '}') {
        if (!nested) throw const FormatException('Unmatched closing brace');
        position++;
        return;
      } else {
        position++;
      }
    }
    if (nested) throw const FormatException('Unclosed argument');
  }

  void _quote() {
    position++;
    if (position >= source.length) {
      throw const FormatException('Unclosed quoted syntax');
    }
    if (source[position] == "'") {
      position++;
      return;
    }
    while (position < source.length) {
      if (source[position++] != "'") continue;
      if (position < source.length && source[position] == "'") {
        position++;
      } else {
        return;
      }
    }
    throw const FormatException('Unclosed quoted syntax');
  }

  void _argument() {
    position++;
    _spaces();
    final name = _identifier();
    fields.add(name);
    _spaces();
    if (_consume('}')) return;
    _expect(',');
    _spaces();
    final kind = _identifier();
    if (!{'plural', 'select', 'selectordinal'}.contains(kind)) {
      throw const FormatException('Unsupported ICU argument kind');
    }
    _spaces();
    _expect(',');
    _branches();
  }

  void _branches() {
    var hasOther = false;
    _spaces();
    if (source.startsWith('offset:', position)) {
      position += 'offset:'.length;
      _spaces();
      _word();
      _spaces();
    }
    while (position < source.length && source[position] != '}') {
      final selector = _word();
      if (selector.isEmpty) throw const FormatException('Missing ICU selector');
      hasOther |= selector == 'other';
      _spaces();
      _expect('{');
      readMessage(nested: true);
      _spaces();
    }
    _expect('}');
    if (!hasOther) throw const FormatException('ICU requires an other branch');
  }

  String _identifier() {
    final match = RegExp(
      r'[A-Za-z_][A-Za-z0-9_]*',
    ).matchAsPrefix(source, position);
    if (match == null) throw const FormatException('Invalid placeholder name');
    position = match.end;
    return match.group(0)!;
  }

  String _word() {
    final start = position;
    while (position < source.length &&
        !RegExp(r'\s|[{}]').hasMatch(source[position])) {
      position++;
    }
    return source.substring(start, position);
  }

  void _spaces() {
    while (position < source.length &&
        RegExp(r'\s').hasMatch(source[position])) {
      position++;
    }
  }

  bool _consume(String expected) {
    if (position >= source.length || source[position] != expected) return false;
    position++;
    return true;
  }

  void _expect(String expected) {
    if (!_consume(expected))
      throw const FormatException('Invalid ICU structure');
  }
}
