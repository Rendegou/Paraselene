// 覆盖编辑历史的快照容量与最旧淘汰，保持精确 UTF-16 值不被改写。
// 纯 Dart 单元测试，不代表原生撤销栈或真实输入时序通过。

import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/editor/editor_history.dart';

void main() {
  test('snapshot count evicts oldest while preserving newest exact values', () {
    final history = EditorHistory();
    for (var index = 0; index < 140; index++) {
      history.add(TextEditingValue(text: '$index 👩‍💻\r\né é'));
    }
    final values = <String>[];
    while (history.isNotEmpty) {
      values.add(history.removeLast().text);
    }
    expect(values.length, 128);
    expect(values.first, '139 👩‍💻\r\né é');
    expect(values.last, '12 👩‍💻\r\né é');
  });

  test(
    'UTF16 budget bounds old snapshots without truncating oversized deletion undo',
    () {
      final history = EditorHistory();
      final first = '文' * 4_000_001;
      final newest = '👩‍💻\r\né é' * 900_000;
      history.add(TextEditingValue(text: first));
      history.add(TextEditingValue(text: newest));
      expect(history.removeLast().text, newest);
      expect(history.isEmpty, isTrue);
      history.add(const TextEditingValue(text: 'next'));
      history.clear();
      expect(history.isEmpty, isTrue);
    },
  );
}
