// 覆盖编辑器锚点的捕获与映射：重复文本歧义、失效锚点与代理对边界拒绝。
// 纯 Dart 单元测试，不代表 Windows IME、原生文本服务或真实布局通过。

import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/editor/editor_anchor.dart';

void main() {
  test('ambiguous repeated text never retargets a new occurrence as valid', () {
    final anchor = EditorAnchor.capture('abcabc', 0, 3);
    expect(anchor.map('abcabc', 'abcabcabc').valid, isFalse);
    expect(
      anchor.map('abcabc', 'abcabcabc').map('abcabcabc', 'abcabc').valid,
      isTrue,
    );
  });
  test(
    'UTF-16 quote maps boundary insertions without Unicode normalization',
    () {
      const body = 'A👩‍💻 é\r\nمرحبا Z';
      final from = body.indexOf('مرحبا');
      final quote = EditorAnchor.capture(body, from, from + 5);
      final before = body.replaceRange(from, from, '前');
      final mapped = quote.map(body, before);
      expect(mapped.from, from + 1);
      expect(mapped.text, 'مرحبا');
      expect(mapped.valid, isTrue);
      final after = before.replaceRange(mapped.to, mapped.to, '!');
      expect(mapped.map(before, after).to, mapped.to);
      expect(mapped.map(before, body).from, from);
    },
  );

  test(
    'invalid quote cannot jump to duplicate; exact frozen undo restores',
    () {
      const body = 'same same';
      final anchor = EditorAnchor.capture(body, 0, 4);
      final changed = anchor.map(body, 'X same');
      expect(changed.valid, isFalse);
      expect(changed.from, lessThan(3));
      expect(changed.map('X same', body).valid, isTrue);
      expect(changed.map('X same', body).to, 4);
    },
  );

  test('split surrogate capture rejects', () {
    expect(() => EditorAnchor.capture('👩', 1, 2), throwsArgumentError);
  });
}
