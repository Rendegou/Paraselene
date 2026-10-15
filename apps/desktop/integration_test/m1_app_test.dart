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
    await tester.tap(find.text('运行 M1 合成验收'));
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
      final label = tester
          .widget<Text>(find.byKey(const Key('probe-status')))
          .data!;
      if (label.startsWith('PASS') || label.startsWith('FAIL')) break;
    }
    expect(
      tester.widget<Text>(find.byKey(const Key('probe-status'))).data,
      startsWith('PASS'),
    );
  });
}
