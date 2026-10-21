// 严格 ARB 门禁入口；可独立执行，不需要 Flutter 或网络。
import 'dart:convert';
import 'dart:io';
import '../lib/arb_checks.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart check_arb.dart <arb-directory>');
    exitCode = 2;
    return;
  }
  final report = checkArbDirectory(arguments.single);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
  exitCode = report['status'] == 'PASS' ? 0 : 1;
}
