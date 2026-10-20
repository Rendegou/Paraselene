// 覆盖 M2 已发布 locale 集合与脚本感知回退的边界。
// 纯 Dart/Flutter 单元测试，不代表真实系统 locale 或 ARB 翻译质量通过。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/workspace/workbench_app.dart';

void main() {
  test(
    'published locales and explicit script-aware fallback remain bounded',
    () {
      expect(workbenchLocales.map((locale) => locale.toLanguageTag()), [
        'en',
        'zh-Hans',
      ]);
      for (final locale in [
        const Locale('zh', 'CN'),
        const Locale('zh', 'SG'),
        workbenchLocales[1],
      ]) {
        expect(resolveWorkbenchLocale(locale), workbenchLocales[1]);
      }
      for (final locale in [
        const Locale('zh'),
        const Locale('zh', 'TW'),
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
        const Locale('ar'),
        const Locale('de'),
      ]) {
        expect(resolveWorkbenchLocale(locale), workbenchLocales[0]);
      }
      expect(
        resolveWorkbenchLocale(const Locale('en', 'GB')),
        workbenchLocales[0],
      );
    },
  );
}
