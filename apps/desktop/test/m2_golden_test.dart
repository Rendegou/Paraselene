@Tags(['golden'])
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/workspace/data/demo_content.dart';

import 'support/m2_harness.dart';

// Baseline host: Windows, Flutter 3.32.1 / Dart 3.8.1, DPR 1,
// 1280 x 900 logical pixels, text scale 1. Bless only after the layout matrix
// passes and a human reviews Chinese glyphs, Arabic joining and RTL mirroring.
void main() {
  setUpAll(loadM2Fonts);
  for (final rtl in [false, true]) {
    testWidgets(
      rtl
          ? 'RTL mirrored directory and Arabic specimen'
          : 'Chinese manuscript with bundled fonts',
      (tester) async {
        expect(
          Platform.isWindows,
          isTrue,
          reason: 'Real-font baselines are pinned to Windows',
        );
        tester.useSurface(const Size(1280, 900));
        await tester.pumpWorkbench(rtl: rtl);
        expect(
          tester.widget<SelectableText>(find.byKey(manuscriptKey)).data,
          demoBody,
        );
        expect(find.textContaining('العربية'), findsOneWidget);
        final chapter = tester.getRect(
          find.byKey(const ValueKey('chapter-demo-chapter')),
        );
        final body = tester.getRect(find.byKey(manuscriptKey));
        expect(
          rtl ? chapter.left >= body.right : chapter.right <= body.left,
          isTrue,
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            rtl
                ? 'goldens/m2_windows_rtl_arabic.png'
                : 'goldens/m2_windows_chinese.png',
          ),
        );
      },
    );
  }
}
