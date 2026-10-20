// 保存协调器：按（workId, documentId）维护串行 CAS 保存状态机。
//
// 职责：记录精确正文、350ms 防抖、串行提交、冲突/错误分类、导航与关闭前的持久化栏栅。
// 不拥有 repository（构造时注入保存函数），不直接修改正文，只搬运调用方传入的字符串。
// 错误统一以稳定错误码暴露：identity_mismatch、invalid_save_reply 及后端 WorkspaceFailure 码；
// 冲突码集合见 _conflicts。dispose 拒绝未保存或仍在飞行中的文本，绝不静默丢弃。
import 'dart:async';

import '../../workspace/data/workspace_repository.dart';
import 'save_state.dart';

export 'save_state.dart';

/// Saves a fixed document snapshot using its original CAS revision.
///
/// 用快照自带的原始 CAS revision 保存该固定快照；返回值应反映后端确认后的
/// 身份、正文与 revision。
typedef SaveDocument =
    Future<ChapterDocument> Function(ChapterDocument snapshot);

/// Schedules a callback after [delay]; the returned function cancels it.
///
/// 安排一次延迟回调并返回取消函数；默认实现基于 dart:async 的 Timer，
/// 测试可注入假调度器。
typedef SaveScheduler =
    void Function() Function(Duration delay, void Function() callback);

/// Serial per-document CAS writer and navigation/close persistence barrier.
/// Owns debounce timers, never the repository. Dispose rejects unsaved text.
///
/// 按文档串行提交的 CAS 写入器，同时充当导航与关闭前的持久化栏栅。拥有防抖
/// 定时器但不拥有 repository；dispose 会拒绝未保存文本，绝不静默丢弃。
final class SaveCoordinator {
  SaveCoordinator(WorkspaceRepository repository, {SaveScheduler? schedule})
    : this.withSave(
        (snapshot) => repository.saveDocument(
          snapshot.workId,
          snapshot.documentId,
          snapshot.revision,
          snapshot.body,
        ),
        schedule: schedule,
      );

  /// 直接注入保存函数与调度器的构造方式，便于测试或替换后端；生产环境使用仓储构造。
  SaveCoordinator.withSave(this._save, {SaveScheduler? schedule})
    : _schedule = schedule ?? _timer;

  /// 编辑后启动保存的防抖间隔；只影响体验，不改变 CAS 语义。
  static const debounce = Duration(milliseconds: 350);
  final SaveDocument _save;
  final SaveScheduler _schedule;
  final _slots = <(String, String), _Slot>{};
  final _listenerErrors = <Object>[];
  int _generation = 0;
  bool _disposed = false;

  /// Listener failures are diagnostics, never persistence failures.
  ///
  /// 监听器抛出的异常只在此记录为诊断，不会转化为保存失败，也不会打断其他监听器。
  List<Object> get listenerErrors => List.unmodifiable(_listenerErrors);

  /// Bounded loaded-slot snapshots, including dirty text for recovery export.
  ///
  /// 当前已装载文档的只读快照列表，包含尚未保存的正文，供恢复导出使用；
  /// 已释放的文档不在其中。
  List<SaveState> get loadedStates =>
      List.unmodifiable(_slots.values.map((slot) => slot.state));

  static void Function() _timer(Duration delay, void Function() callback) {
    final timer = Timer(delay, callback);
    return timer.cancel;
  }

  /// Installs a clean native snapshot; rejects dirty/in-flight replacement.
  ///
  /// 安装一份干净的原生快照；同一文档仍有未保存或飞行中的文本时抛 StateError，
  /// 防止覆盖。通过校验时递增 generation 并保留原有订阅。
  SaveState hydrate(ChapterDocument document) {
    _checkActive();
    final key = (document.workId, document.documentId);
    final previous = _slots[key];
    if (previous != null) _requireSettled(previous);
    final slot = _Slot(
      SaveState(document: document, generation: ++_generation),
    );
    if (previous != null) {
      previous.cancelTimer?.call();
      slot.listeners.addAll(previous.listeners);
    }
    _slots[key] = slot;
    _publish(slot);
    return slot.state;
  }

  /// Records exact text synchronously, including empty text; debounces in ms.
  ///
  /// 同步记录精确正文（空文本也算有效编辑），随后按 debounce 防抖提交。
  /// 已有错误码或飞行中的保存不会被本次编辑覆盖；正文未变化时直接返回。
  void edit(String workId, String documentId, String body) {
    final slot = _slot(workId, documentId);
    final old = slot.state;
    if (body == old.body) return;
    slot.state = old.copyWith(
      document: ChapterDocument(
        workId: workId,
        documentId: documentId,
        body: body,
        revision: old.revision,
        baseHeadVersion: old.baseHead,
        headVersionId: old.head,
      ),
      editSequence: old.editSequence + 1,
      status: old.errorCode != null
          ? old.status
          : slot.flight != null
          ? SaveStatus.saving
          : SaveStatus.dirty,
      errorCode: old.errorCode,
    );
    slot.cancelTimer?.call();
    slot.cancelTimer = null;
    if (old.errorCode == null && slot.flight == null) {
      slot.cancelTimer = _schedule(debounce, () {
        slot.cancelTimer = null;
        if (slot.state.dirty && slot.state.errorCode == null) _start(slot);
      });
    }
    _publish(slot);
  }

  /// 返回该文档当前保存状态；文档未 hydrate 时抛 StateError('document_must_be_hydrated')。
  SaveState getState(String workId, String documentId) =>
      _slot(workId, documentId).state;

  /// [getState] 的别名，保留给既有调用点。
  SaveState stateFor(String workId, String documentId) =>
      getState(workId, documentId);

  /// Returns idempotent unsubscription for this identity only.
  ///
  /// 返回幂等的取消订阅函数，只影响该（workId, documentId）槽位；
  /// 干净 hydrate 后订阅仍然保留。
  void Function() subscribe(
    String workId,
    String documentId,
    void Function(SaveState) listener,
  ) {
    final slot = _slot(workId, documentId);
    slot.listeners.add(listener);
    // Resolve the current slot because clean hydrate preserves subscriptions.
    return () => _slots[(workId, documentId)]?.listeners.remove(listener);
  }

  /// Waits for latest text and flight completion; throws stable WorkspaceFailure.
  ///
  /// 等待最新正文落盘并等当前飞行完成；出现错误码时抛带稳定错误码的
  /// WorkspaceFailure。循环重查以覆盖等待期间产生的新编辑。
  Future<void> flushDocument(String workId, String documentId) async {
    final slot = _slot(workId, documentId);
    slot.cancelTimer?.call();
    slot.cancelTimer = null;
    while (slot.state.dirty || slot.flight != null) {
      if (slot.state.errorCode case final String code) {
        throw WorkspaceFailure(code);
      }
      if (slot.flight == null) _start(slot);
      await slot.flight;
    }
  }

  /// Rechecks all loaded slots after awaits to capture edits during the barrier.
  ///
  /// 对全部已装载文档执行持久化栏栅，并在每个等待之后重新检查，
  /// 以捕获栏栅期间产生的新编辑。
  Future<void> flushAll() async {
    _checkActive();
    do {
      await Future.wait([
        for (final key in _slots.keys.toList()) flushDocument(key.$1, key.$2),
      ]);
    } while (_slots.values.any((s) => s.state.dirty || s.flight != null));
  }

  /// Retries exact retained text without refreshing or bypassing CAS revision.
  ///
  /// 用保留的精确正文重试保存；不刷新 revision，也不绕过 CAS。
  /// 重试仍走与普通保存相同的串行队列。
  Future<void> retryDocument(String workId, String documentId) async {
    final slot = _slot(workId, documentId);
    if (slot.flight != null) await slot.flight;
    slot.state = slot.state.copyWith(
      status: slot.state.dirty ? SaveStatus.dirty : SaveStatus.saved,
    );
    _publish(slot);
    await flushDocument(workId, documentId);
  }

  /// Releases only clean, settled, unobserved text.
  ///
  /// 仅释放干净、已结清且无订阅者的文档槽；仍有未保存文本、飞行中的保存
  /// 或订阅者时抛 StateError。
  void releaseDocument(String workId, String documentId) {
    final slot = _slot(workId, documentId);
    _requireSettled(slot);
    if (slot.listeners.isNotEmpty) throw StateError('unsubscribe_required');
    slot.cancelTimer?.call();
    _slots.remove((workId, documentId));
  }

  /// Cancels owned timers after all text has been saved; never drops dirty text.
  ///
  /// 在全部文本保存完成后取消所有定时器并清空槽位；存在未保存或飞行中文本时
  /// 抛 StateError，绝不静默丢弃。
  void dispose() {
    if (_disposed) return;
    for (final slot in _slots.values) {
      _requireSettled(slot);
    }
    for (final slot in _slots.values) {
      slot.cancelTimer?.call();
    }
    _slots.clear();
    _disposed = true;
  }

  void _start(_Slot slot) {
    slot.cancelTimer?.call();
    slot.cancelTimer = null;
    // Install flight before a listener or backend can synchronously reenter.
    // 先安装飞行 Future，再让监听器或后端有机会同步重入。
    final completion = Completer<void>();
    slot.flight = completion.future;
    unawaited(_run(slot, completion));
  }

  Future<void> _run(_Slot slot, Completer<void> completion) async {
    try {
      await _drain(slot);
    } catch (error) {
      final code = error is WorkspaceFailure ? error.code : 'save_failed';
      slot.state = slot.state.copyWith(
        status: _conflicts.contains(code)
            ? SaveStatus.conflict
            : SaveStatus.error,
        errorCode: code,
      );
      _publish(slot);
    } finally {
      slot.flight = null;
      completion.complete();
    }
  }

  Future<void> _drain(_Slot slot) async {
    while (slot.state.dirty) {
      final submitted = slot.state;
      slot.state = slot.state.copyWith(status: SaveStatus.saving);
      _publish(slot);
      final saved = await _save(submitted.document);
      _validateReply(submitted, saved);
      final current = slot.state;
      // 用编辑序号判断提交期间是否又有新输入；比逐字比较更便宜，也覆盖重输相同文本。
      final dirty = current.editSequence != submitted.editSequence;
      slot.state = current.copyWith(
        document: ChapterDocument(
          workId: saved.workId,
          documentId: saved.documentId,
          body: current.body,
          revision: saved.revision,
          baseHeadVersion: saved.baseHeadVersion,
          headVersionId: saved.headVersionId,
          contentHash: dirty ? null : saved.contentHash,
        ),
        savedSequence: submitted.editSequence,
        status: dirty ? SaveStatus.dirty : SaveStatus.saved,
      );
      _publish(slot);
    }
  }

  void _validateReply(SaveState submitted, ChapterDocument saved) {
    if (saved.workId != submitted.workId ||
        saved.documentId != submitted.documentId ||
        saved.body != submitted.body) {
      throw const WorkspaceFailure('identity_mismatch');
    }
    if (saved.revision == null ||
        saved.revision! <= (submitted.revision ?? 0)) {
      throw const WorkspaceFailure('invalid_save_reply');
    }
  }

  static const _conflicts = {
    'revision_conflict',
    'head_conflict',
    'base_conflict',
    'context_conflict',
  };

  _Slot _slot(String workId, String documentId) {
    _checkActive();
    return _slots[(workId, documentId)] ??
        (throw StateError('document_must_be_hydrated'));
  }

  void _checkActive() {
    if (_disposed) throw StateError('coordinator_disposed');
  }

  void _requireSettled(_Slot slot) {
    if (slot.state.dirty || slot.flight != null) {
      throw StateError('unsaved_or_in_flight');
    }
  }

  void _publish(_Slot slot) {
    final state = slot.state;
    for (final listener in slot.listeners.toList()) {
      // A listener may synchronously edit or hydrate and publish newer state.
      // That nested publication owns delivery; never resume an older snapshot.
      // 监听器可能同步编辑或 hydrate 并发布更新状态；此时由嵌套发布负责投递，
      // 不再继续投递旧快照。
      if (!identical(slot.state, state) ||
          !identical(_slots[(state.workId, state.documentId)], slot)) {
        break;
      }
      if (!slot.listeners.contains(listener)) continue;
      try {
        listener(state);
      } catch (error) {
        _listenerErrors.add(error);
      }
    }
  }
}

final class _Slot {
  _Slot(this.state);
  SaveState state;
  Future<void>? flight;
  void Function()? cancelTimer;
  final listeners = <void Function(SaveState)>{};
}
