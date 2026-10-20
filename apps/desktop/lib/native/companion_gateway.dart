// 桌面伴侣原生网关：只负责版本化通道 paraselene/companion/v1 的调用与故障回传。
// 不写库；业务设置由 Rust 持有，原生故障在这里转为可见结果事件并关闭本地开启状态。

import 'dart:async';
import 'package:flutter/services.dart';
import '../legacy/companion_service.dart';

/// Owns only the versioned companion channel; business settings stay in Rust.
///
/// 只负责版本化通道 paraselene/companion/v1：把方法调用与原生故障转成结果对象。
/// 不读写数据库；[enabled] 只反映本进程最近一次成功配置，不是持久化状态。
final class NativeCompanionGateway implements CompanionService {
  NativeCompanionGateway() {
    _channel.setMethodCallHandler((call) async {
      // 原生窗口故障后立即认为功能不可用，避免界面继续显示已开启。
      if (call.method == 'fault') {
        _enabled = false;
        _events.add(const CompanionOutcome(errorCode: 'companion_unavailable'));
      }
    });
  }
  final _events = StreamController<CompanionOutcome>.broadcast(sync: true);

  /// 原生故障或状态事件；故障会同时关闭本地开启状态。
  @override
  Stream<CompanionOutcome> get events => _events.stream;
  bool _enabled = false;

  /// 本进程最近一次是否成功开启原生伴侣。
  @override
  bool get enabled => _enabled;
  static const _channel = MethodChannel('paraselene/companion/v1');

  /// 显式配置桌面伴侣；以结果对象返回成功或失败码，不以异常表示失败。
  ///
  /// 通道返回版本不等于 1 时视为契约不一致（companion_contract_mismatch）；
  /// 原生不可用会关闭本地开启状态并广播失败事件。
  @override
  Future<CompanionOutcome> configure({
    required bool enabled,
    required String appearance,
    required String name,
    required String openLabel,
    required String hideLabel,
    required String quitLabel,
  }) async {
    try {
      final result = await _channel
          .invokeMapMethod<String, Object?>('configure', {
            'version': 1,
            'enabled': enabled,
            'appearance': appearance,
            'name': name,
            'openLabel': openLabel,
            'hideLabel': hideLabel,
            'quitLabel': quitLabel,
          });
      if (result?['version'] != 1) {
        // 版本不一致视为契约失败，不采信其余返回字段。
        return const CompanionOutcome(errorCode: 'companion_contract_mismatch');
      }
      _enabled = enabled;
      _events.add(
        CompanionOutcome(
          visible: result?['visible'] == true,
          quiet: result?['quiet'] == true,
        ),
      );
      return CompanionOutcome(
        visible: result?['visible'] == true,
        quiet: result?['quiet'] == true,
      );
    } on PlatformException catch (failure) {
      // 原生明确报告不可用时同步关闭本地状态；其他错误码只回传。
      if (failure.code == 'companion_unavailable') {
        _enabled = false;
        _events.add(CompanionOutcome(errorCode: failure.code));
      }
      return CompanionOutcome(errorCode: failure.code);
    } on MissingPluginException {
      return const CompanionOutcome(errorCode: 'companion_unavailable');
    }
  }
}
