// 字体许可登记：把随包字体的 OFL 许可文本注册进 Flutter LicenseRegistry。
//
// 只读取 assets/fonts 下的许可文本，保证离线可查；无网络、无写库操作。
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Makes every packaged font's redistribution terms available offline.
///
/// 为每个随包字体登记离线可查的再分发许可条款：Notebook Sans/Serif 与 Noto Arabic
/// 分别对应各自的 OFL 文本。
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final item in const {
      'Notebook Sans': 'NotoSansSC-OFL.txt',
      'Notebook Serif': 'NotoSerifSC-OFL.txt',
      'Noto Arabic': 'NotoNaskhArabic-OFL.txt',
    }.entries) {
      final text = await rootBundle.loadString('assets/fonts/${item.value}');
      yield LicenseEntryWithLineBreaks([item.key], text);
    }
  });
}
