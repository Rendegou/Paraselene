// 覆盖输入冻结：冻结后迟到的原生文本与剪贴板操作不得改写正文或撤销历史。
// 模拟文本输入连接回调，不代表真实 Windows 输入法或线程时序通过。

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/editor/editor_input_client.dart';

const style = TextStyle(fontSize: 20);
const changed = TextEditingValue(
  text: 'late native text',
  selection: TextSelection.collapsed(offset: 16),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('frozen native and local edits retain text and undo history', () {
    final client = EditorInputClient('原稿\r\ne\u0301👩‍💻', style: style);
    addTearDown(client.dispose);
    client.select(TextSelection.collapsed(offset: client.length));
    client.replace('A');
    final before = client.value;
    client.readOnly = true;
    client.updateEditingValue(changed);
    expect(client.value, before);
    client.apply(changed);
    client.replace('B');
    client.undo();
    client.redo();
    client.performAction(TextInputAction.newline);
    expect(client.value, before);
    client.readOnly = false;
    client.undo();
    expect(client.document.raw, '原稿\r\ne\u0301👩‍💻');
    client.redo();
    expect(client.value, before);
  });

  for (final operation in ['paste', 'cut']) {
    test('in-flight clipboard $operation cannot edit after freeze', () async {
      final client = EditorInputClient('原稿\r\n', style: style);
      addTearDown(client.dispose);
      client.select(TextSelection(baseOffset: 0, extentOffset: client.length));
      final before = client.value;
      final response = Completer<Object?>();
      final requested = Completer<void>();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) {
        if (call.method.startsWith('Clipboard.')) {
          requested.complete();
          return response.future;
        }
        return Future<Object?>.value();
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final pending = client.clipboard(operation);
      await requested.future;
      client.readOnly = true;
      response.complete(operation == 'paste' ? {'text': 'late paste'} : null);
      await pending;
      expect(client.value, before);
    });
  }
}
