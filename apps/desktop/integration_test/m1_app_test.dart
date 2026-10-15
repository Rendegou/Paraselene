import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:paraselene_flutter/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Windows app runs actual M1 synthetic acceptance', (
    tester,
  ) async {
    await tester.pumpWidget(const MainApp(diagnosticOverride: true));
    await tester.tap(find.text('运行原生验收'));
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
      final label = tester
          .widget<Text>(find.byKey(const Key('probe-status')))
          .data!;
      if (label == '原生验收通过。' || label.startsWith('原生验收失败。')) break;
    }
    expect(
      tester.widget<Text>(find.byKey(const Key('probe-status'))).data,
      '原生验收通过。',
    );
  });
}
