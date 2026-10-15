import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Makes every packaged font's redistribution terms available offline.
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
