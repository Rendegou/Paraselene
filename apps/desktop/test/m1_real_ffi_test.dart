// 覆盖 M1 真实 FFI 冒烟：DLL 合同、合成会话创建与释放。
// 需要真实 paraselene_bridge.dll 与合成目录，不代表 Windows UI、IME 或 Release 打包通过。

import 'package:flutter_test/flutter_test.dart';
import 'package:paraselene_flutter/probe/probe.dart';

void main() {
  test(
    'real DLL preserves synthetic contracts and releases sessions',
    () async {
      final report = (await runM1Probe(diagnosticOverride: true)).toJson();
      expect(report['status'], 'PASS');
      expect(report['works'], 2);
      expect(report['chapters'], 1);
      expect(report['contentHash'], matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(report['cloudEnabled'], isFalse);
      expect(report['checks'], contains('revision_conflict'));
      expect(report['checks'], contains('closed'));
    },
  );
}
