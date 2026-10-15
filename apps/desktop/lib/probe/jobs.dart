import 'dart:async';

import '../native/generated/api.dart';
import '../native/generated/api/models.dart';
import 'assertions.dart';

/// Waits for observed backend pending state within a bounded deadline.
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
final class ProbeJobs {
  final List<Future<BridgeJob>> _pending = [];

  Future<BridgeJob> start(CoreSession session, String id, int delay) {
    final future = session.syntheticJob(jobId: id, delayMs: BigInt.from(delay));
    // Attach an error listener immediately; cleanup still observes the original.
    unawaited(future.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
    _pending.add(future);
    return future;
  }

  Future<void> settle() async {
    await Future.wait(_pending, eagerError: false);
  }

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
