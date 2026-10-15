import 'package:flutter/services.dart';

/// Fails startup if a diagnostic font is absent from the actual asset bundle.
Future<void> loadSpikeFonts() async {
  for (final face in const {
    'Notebook Sans': 'NotoSansSC-Regular.ttf',
    'Notebook Serif': 'NotoSerifSC-Regular.ttf',
    'Noto Arabic': 'NotoNaskhArabic.ttf',
  }.entries) {
    final loader = FontLoader(face.key);
    loader.addFont(rootBundle.load('assets/fonts/${face.value}'));
    await loader.load();
  }
}
