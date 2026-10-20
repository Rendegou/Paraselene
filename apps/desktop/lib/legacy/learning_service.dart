// 学习服务接缝：只打开固定的隔离练习窗口，学习者代码不跨越此边界。
// 不可用实现返回稳定错误码 learning_unavailable。

/// Opens only the fixed isolated exercise; no learner code crosses this boundary.
///
/// 只打开固定的隔离练习窗口，学习者代码不跨越此边界。
abstract interface class LearningService {
  /// 原生故障码流；null 表示最近一次调用成功。
  Stream<String?> get errors;

  /// 打开隔离练习窗口；返回错误码，null 表示成功。
  Future<String?> open({required String locale, required String title});
}

/// 无可用的学习练习实现：open 恒返回 learning_unavailable。
final class UnavailableLearningService implements LearningService {
  const UnavailableLearningService();
  @override
  Stream<String?> get errors => const Stream.empty();
  @override
  Future<String?> open({required String locale, required String title}) async =>
      'learning_unavailable';
}
