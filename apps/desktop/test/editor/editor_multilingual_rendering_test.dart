// 覆盖多语言渲染：阿拉伯文实际字形前进宽度与离线字体回退。
// 依赖测试字体与 Flutter 测试绑定，不代表 Windows 系统字体回退或真机渲染通过。

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/editor/editor_viewport.dart';
import 'package:paraselene_flutter/workspace/data/demo_content.dart';

import '../support/m2_harness.dart';

void main() {
  setUpAll(loadM2Fonts);

  testWidgets('workbench offline fonts give Arabic actual glyph advance', (
    tester,
  ) async {
    tester.useSurface(const Size(1280, 900));
    await tester.pumpWorkbench();
    final controller = tester
        .widget<EditorViewport>(find.byKey(manuscriptKey))
        .controller;
    expect(controller.document.raw, demoBody);
    final painter = controller.layout.painter('العربية', TextDirection.rtl);
    addTearDown(painter.dispose);
    final boxes = painter.getBoxesForSelection(
      const TextSelection(baseOffset: 0, extentOffset: 7),
    );
    final advance = boxes.fold<double>(
      0,
      (sum, box) => sum + box.right - box.left,
    );
    expect(
      advance,
      greaterThan(20),
      reason: 'Arabic must occupy visible space',
    );
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), Offset.zero);
    final picture = recorder.endRecording();
    addTearDown(picture.dispose);
    final image = await tester.runAsync(
      () => picture.toImage(painter.width.ceil(), painter.height.ceil()),
    );
    addTearDown(image!.dispose);
    final pixels = await tester.runAsync(() => image.toByteData());
    var visiblePixels = 0;
    for (var index = 3; index < pixels!.lengthInBytes; index += 4) {
      if (pixels.getUint8(index) > 32) visiblePixels++;
    }
    expect(
      visiblePixels,
      greaterThan(50),
      reason: 'Arabic glyph ink must render',
    );
    await tester.pumpWidget(const SizedBox());
  });
}
