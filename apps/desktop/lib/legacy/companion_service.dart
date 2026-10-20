// 桌面伴侣服务接缝：用可审计的结果对象返回成功/失败，不可用是可见数据。
// 实现不得在失败时伪造开启状态；业务设置与持久化不在此层。

/// Native desktop companion outcome; unavailable is visible data, never success.
///
/// 桌面伴侣调用结果：不可用是可见数据，不是成功；errorCode 为 null 才算成功。
final class CompanionOutcome {
  const CompanionOutcome({
    this.errorCode,
    this.visible = false,
    this.quiet = false,
  });

  /// 稳定失败码；null 表示成功。
  final String? errorCode;

  /// 原生窗口当前是否可见。
  final bool visible;

  /// 原生侧是否要求静默显示（不主动弹出窗口）。
  final bool quiet;

  /// 是否成功；只有 [errorCode] 为空才算成功。
  bool get succeeded => errorCode == null;
}

/// 桌面伴侣服务接缝：显式配置与开关由原生层执行，UI 通过 [events] 感知故障。
abstract interface class CompanionService {
  /// Whether this process last enabled the native companion successfully.
  ///
  /// 本进程最近一次是否成功开启原生伴侣；失败时保持 false。
  bool get enabled;

  /// 原生故障/状态结果事件流；只广播当前结果，不重放历史。
  Stream<CompanionOutcome> get events;

  /// 显式配置伴侣；返回失败码时不改变已生效状态，也不以异常表示失败。
  Future<CompanionOutcome> configure({
    required bool enabled,
    required String appearance,
    required String name,
    required String openLabel,
    required String hideLabel,
    required String quitLabel,
  });
}

/// 无原生伴侣时的降级实现：开关恒为关闭，configure 恒返回 companion_unavailable。
final class UnavailableCompanionService implements CompanionService {
  const UnavailableCompanionService();
  @override
  bool get enabled => false;
  @override
  Stream<CompanionOutcome> get events => const Stream.empty();
  @override
  Future<CompanionOutcome> configure({
    required bool enabled,
    required String appearance,
    required String name,
    required String openLabel,
    required String hideLabel,
    required String quitLabel,
  }) async => const CompanionOutcome(errorCode: 'companion_unavailable');
}
