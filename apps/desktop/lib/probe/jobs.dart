// M1 作业探针：验证 pending/取消/有界通知/权威状态与关闭语义。
//
// 记录所有原生作业 Future 并在会话销毁前结清，避免悬挂回调；不写库。
import 'dart:async';

import '../native/generated/api.dart';
import '../native/generated/api/models.dart';
import 'assertions.dart';

/// Waits for observed backend pending state within a bounded deadline.
///
/// 在 10 秒内轮询到作业处于 pending 即返回；期间 job_not_found 视为尚未登记，
/// 其它 BridgeError 立即抛出，超时抛 StateError('pending_timeout')。
Future<void> observePending(CoreSession session, String id) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    try {
      final job = await session.jobStatus(jobId: id);
      require(job.status == 'pending', 'job_never_pending');
      return;
    } on BridgeError catch (error) {
      if (error.code != 'job_not_found') rethrow;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  throw StateError('pending_timeout');
}

/// Tracks every native job future and settles it before opaque disposal.
///
/// 跟踪所有原生作业 Future，在会话 dispose 之前统一结清；单个作业失败不影响
/// 其它作业完成。
final class ProbeJobs {
  final List<Future<BridgeJob>> _pending = [];

  /// 启动一个合成作业并登记其 Future；立即挂接错误监听，避免未处理异常。
  Future<BridgeJob> start(CoreSession session, String id, int delay) {
    final future = session.syntheticJob(jobId: id, delayMs: BigInt.from(delay));
    // Attach an error listener immediately; cleanup still observes the original.
    unawaited(future.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
    _pending.add(future);
    return future;
  }

  /// 等待所有已登记作业结束；任一失败也会等其余完成后再抛出。
  Future<void> settle() async {
    await Future.wait(_pending, eagerError: false);
  }

  /// 跑完整套作业语义：取消、通知容量溢出后的权威状态、退订错误与关闭后的作业状态。
  Future<void> exercise(CoreSession session) async {
    final cancelled = start(session, 'cancel', 60000);
    await observePending(session, 'cancel');
    await session.cancelJob(jobId: 'cancel');
    require((await cancelled).status == 'cancelled', 'cancel_result');
    final subscription = await session.subscribe(capacity: 1);
    for (var i = 0; i < 4; i++) {
      require(
        (await start(session, 'overflow-$i', 0)).status == 'completed',
        'job_completion',
      );
    }
    final events = await session.pollEvents(subscription: subscription);
    require(
      events.events.length == 1 && events.dropped == BigInt.from(3),
      'bounded_notifications',
    );
    for (var i = 0; i < 4; i++) {
      require(
        (await session.jobStatus(jobId: 'overflow-$i')).status == 'completed',
        'authoritative_status',
      );
    }
    await session.unsubscribe(subscription: subscription);
    await expectBridgeError(
      'subscription_not_found',
      () => session.pollEvents(subscription: subscription),
    );
    final closed = start(session, 'close', 60000);
    await observePending(session, 'close');
    await session.close();
    require((await closed).status == 'closed', 'closed_job');
    require(
      (await session.jobStatus(jobId: 'close')).status == 'closed',
      'closed_job_status',
    );
  }
}
