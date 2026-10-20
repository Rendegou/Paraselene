// workspace_controller 的 part：统一窗口关闭、恢复导出与仓库释放的生命周期。
// 读边界：本文件不读写正文；关闭前由屏障 flush 正文与偏好，恢复导出则使用未 flush 的内存快照。
// 写边界：仓库关闭只发生一次；恢复导出成功且用户确认后才封存会话。
// 关键不变量：并发的关闭请求共享同一个 Future；失败时窗口保持打开且不丢弃脏文本。
part of 'workspace_controller.dart';

/// Shared close/export lifecycle uses the same persistence barrier.
mixin _WorkspaceClose on _WorkspaceState {
  Future<bool> _barrier(Future<void> Function() action, {bool flush = true});

  /// Two-phase close: flush text and preferences, then release the repository.
  /// Failure keeps the window open; the draft stays in memory for export.
  ///
  /// 两阶段关闭：先 flush 正文与偏好，再释放仓库；屏障失败时窗口保持打开以便重试或导出。
  Future<bool> closeBarrier() =>
      _closeFlight ??= Future<bool>.microtask(_closeBarrier);

  Future<bool> _closeBarrier() async {
    try {
      while (_busy) {
        await _idle!.future;
      }
      if (_closed) return true;
      return await _barrier(() async {
        await repository.close();
        _closed = true;
      });
    } finally {
      _closeFlight = null;
    }
  }

  /// Runs recovery with a stable memory snapshot, including its exit decision.
  ///
  /// 恢复导出使用不 flush 的内存快照，动作内包含用户是否接受导出的决定。
  Future<bool> recoveryBarrier(Future<void> Function() action) =>
      _barrier(action, flush: false);

  /// Releases repository resources once. Not a persistence barrier: callers
  /// closing the window must go through [closeBarrier] instead.
  ///
  /// 只取消定时器并释放仓库，不承担落盘职责；关闭窗口必须走 closeBarrier。
  Future<void> close() async {
    _prefsTimer?.cancel();
    if (!_disposed) dispose();
    await repository.close();
  }
}
