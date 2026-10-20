// 覆盖线程槽位布局：同一段落两组稳定宿主矩形与非法输入拒绝。
// 纯 Dart 布局单元测试，不代表真实侧栏/浮层绘制或交互通过。

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/editor/editor_layout.dart';
import 'package:paraselene_flutter/editor/editor_thread_slot.dart';

void main() {
  test(
    'two stable hosts in one paragraph reserve independent exact rectangles',
    () {
      final layout = EditorLayout(
        width: 400,
        style: const TextStyle(fontSize: 20),
      );
      layout.update('first\r\nsecond 👩‍💻');
      layout.materializeAll();
      final initialHeight = layout.height;
      layout.setThreadSlots(const [
        EditorThreadSlot(id: 'a', offset: 1, height: 120),
        EditorThreadSlot(id: 'b', offset: 3, height: 180),
      ]);
      expect(layout.threadGeometry.map((host) => host.id), ['a', 'b']);
      expect(
        layout.threadGeometry[1].rect.top,
        layout.threadGeometry[0].rect.bottom,
      );
      expect(layout.height, initialHeight + 300);
      expect(layout.raw, 'first\r\nsecond 👩‍💻');
      layout.setThreadSlots(const []);
      expect(layout.height, initialHeight);
    },
  );

  test('collapsed hosts get a zero-height anchor without reserving space', () {
    final layout = EditorLayout(
      width: 400,
      style: const TextStyle(fontSize: 20),
    );
    layout.update('first\r\nsecond');
    layout.materializeAll();
    final initialHeight = layout.height;
    layout.setThreadSlots(const [
      EditorThreadSlot(id: 'open', offset: 1, height: 120),
      EditorThreadSlot(id: 'collapsed', offset: 3, height: 0),
    ]);
    // 收起线程仍需要段末几何来放标记，但不增加文档高度。
    expect(layout.threadGeometry.map((host) => host.id), ['open', 'collapsed']);
    expect(
      layout.threadGeometry[1].rect.top,
      layout.threadGeometry[0].rect.bottom,
    );
    expect(layout.threadGeometry[1].rect.height, 0);
    expect(layout.height, initialHeight + 120);
    layout.setThreadSlots(const []);
    expect(layout.height, initialHeight);
  });

  test('duplicate host identities and nonfinite heights reject', () {
    final layout = EditorLayout(style: const TextStyle())..update('a');
    expect(
      () => layout.setThreadSlots(const [
        EditorThreadSlot(id: 'a', offset: 0),
        EditorThreadSlot(id: 'a', offset: 1),
      ]),
      throwsArgumentError,
    );
    expect(
      () => layout.setThreadSlots(const [
        EditorThreadSlot(id: 'a', offset: 0, height: double.nan),
      ]),
      throwsArgumentError,
    );
  });
}
