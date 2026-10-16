import 'dart:async';

import '../../workspace/data/workspace_repository.dart';
import 'save_state.dart';

export 'save_state.dart';

/// Saves a fixed document snapshot using its original CAS revision.
typedef SaveDocument =
    Future<ChapterDocument> Function(ChapterDocument snapshot);

/// Schedules a callback after [delay]; the returned function cancels it.
typedef SaveScheduler =
    void Function() Function(Duration delay, void Function() callback);

/// Serial per-document CAS writer and navigation/close persistence barrier.
/// Owns debounce timers, never the repository. Dispose rejects unsaved text.
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

  SaveCoordinator.withSave(this._save, {SaveScheduler? schedule})
    : _schedule = schedule ?? _timer;

  static const debounce = Duration(milliseconds: 350);
  final SaveDocument _save;
  final SaveScheduler _schedule;
  final _slots = <(String, String), _Slot>{};
  final _listenerErrors = <Object>[];
  int _generation = 0;
  bool _disposed = false;

  /// Listener failures are diagnostics, never persistence failures.
  List<Object> get listenerErrors => List.unmodifiable(_listenerErrors);

  /// Bounded loaded-slot snapshots, including dirty text for recovery export.
  List<SaveState> get loadedStates =>
      List.unmodifiable(_slots.values.map((slot) => slot.state));

  static void Function() _timer(Duration delay, void Function() callback) {
    final timer = Timer(delay, callback);
    return timer.cancel;
  }

  /// Installs a clean native snapshot; rejects dirty/in-flight replacement.
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

  SaveState getState(String workId, String documentId) =>
      _slot(workId, documentId).state;
  SaveState stateFor(String workId, String documentId) =>
      getState(workId, documentId);

  /// Returns idempotent unsubscription for this identity only.
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
  Future<void> flushAll() async {
    _checkActive();
    do {
      await Future.wait([
        for (final key in _slots.keys.toList()) flushDocument(key.$1, key.$2),
      ]);
    } while (_slots.values.any((s) => s.state.dirty || s.flight != null));
  }

  /// Retries exact retained text without refreshing or bypassing CAS revision.
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
  void releaseDocument(String workId, String documentId) {
    final slot = _slot(workId, documentId);
    _requireSettled(slot);
    if (slot.listeners.isNotEmpty) throw StateError('unsubscribe_required');
    slot.cancelTimer?.call();
    _slots.remove((workId, documentId));
  }

  /// Cancels owned timers after all text has been saved; never drops dirty text.
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
