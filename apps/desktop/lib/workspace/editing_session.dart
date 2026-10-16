import 'package:flutter/foundation.dart';

import '../domain/editing/save_coordinator.dart';
import 'data/workspace_repository.dart';

/// Owns the exact text of the currently open chapter and its persistence
/// lifecycle through the SaveCoordinator. The editor widget mirrors [body]
/// only when [contentEpoch] changes (navigation, confirm, rollback); save
/// status updates never rewrite author text.
final class EditingSession extends ChangeNotifier {
  EditingSession(this._repository, {SaveScheduler? schedule})
    : _saves = SaveCoordinator(_repository, schedule: schedule);

  final WorkspaceRepository _repository;
  final SaveCoordinator _saves;
  ChapterDocument? _document;
  String _body = '';
  SaveState? _saveState;
  int _contentEpoch = 0;
  void Function()? _unsubscribe;
  bool _disposed = false;

  /// Blocks new input while a navigation or recovery snapshot is committed.
  bool inputLocked = false;

  /// The loaded document of the open chapter, including CAS revision/head.
  ChapterDocument? get document => _document;

  /// Exact in-memory text; may be newer than the last saved snapshot.
  String get body => _body;

  /// Monotonic per external content reset (open/confirm/rollback/release).
  int get contentEpoch => _contentEpoch;

  /// Latest persistence state of the open chapter.
  SaveState? get saveState => _saveState;
  bool get hasOpenChapter => _document != null;

  /// Bounded snapshots of all loaded slots, including dirty text for export.
  List<SaveState> get loadedStates => _saves.loadedStates;

  /// Opens a chapter's exact working text. The previous slot is released only
  /// after the new document loaded successfully, so a failed load keeps the
  /// current chapter fully intact.
  Future<void> open(String workId, WorkspaceChapter chapter) async {
    _checkActive();
    final loaded = await _repository.loadDocument(workId, chapter.id);
    if (_disposed) return;
    adopt(loaded);
  }

  /// Installs an already loaded document after the caller's identity checks.
  /// The previous slot must be clean; no repository operation is performed.
  void adopt(ChapterDocument loaded) {
    _checkActive();
    _unsubscribe?.call();
    _unsubscribe = null;
    final previous = _document;
    if (previous != null) {
      _saves.releaseDocument(previous.workId, previous.documentId);
    }
    _document = loaded;
    _body = loaded.body;
    _contentEpoch++;
    _saveState = _saves.hydrate(loaded);
    _unsubscribe = _saves.subscribe(loaded.workId, loaded.documentId, (state) {
      _saveState = state;
      if (!_disposed) notifyListeners();
    });
    notifyListeners();
  }

  /// Records exact text synchronously (including empty); the coordinator
  /// debounces persistence. The editor is never rewritten by this path.
  void edit(String body) {
    final document = _document;
    if (_disposed || inputLocked || document == null || body == _body) return;
    _body = body;
    _saves.edit(document.workId, document.documentId, body);
  }

  /// Waits for the latest text of every loaded slot to be durably saved;
  /// conflict/error states throw their stable code and keep the draft.
  Future<void> flushAll() => _saves.flushAll();

  /// Retries the open chapter's retained exact text with the same CAS revision.
  Future<void> retrySave() async {
    final document = _document;
    if (document == null) return;
    await _saves.retryDocument(document.workId, document.documentId);
  }

  /// Flushes, then prepares the review binding body/head/revision/context.
  /// A chapter with no saved draft cannot be confirmed (`draft_missing`).
  Future<PreparedConfirmation> prepareConfirmation() async {
    final document = _document;
    if (document == null) throw const WorkspaceFailure('no_open_chapter');
    await flushAll();
    final state = _saveState;
    final revision = state?.revision;
    if (revision == null) throw const WorkspaceFailure('draft_missing');
    return _repository.prepareConfirmation(
      document.workId,
      document.documentId,
      state?.head,
      revision,
    );
  }

  /// Confirms exactly the reviewed token, then rehydrates with the rebased
  /// revision. A token invalidated by newer edits fails with a stable code.
  Future<void> confirm(String reviewToken) async {
    final document = _document;
    if (document == null) throw const WorkspaceFailure('no_open_chapter');
    await _repository.confirmChapter(
      document.workId,
      document.documentId,
      reviewToken,
    );
    await _reload();
  }

  /// Rolls the head back to [versionId] after flushing; the working copy is
  /// discarded by the backend and the reloaded snapshot replaces the slot.
  Future<void> rollback(String versionId) async {
    final document = _document;
    if (document == null) throw const WorkspaceFailure('no_open_chapter');
    await flushAll();
    final state = _saveState;
    await _repository.rollbackChapter(
      document.workId,
      document.documentId,
      versionId,
      state?.head,
      state?.revision,
    );
    await _reload();
  }

  /// Releases the open chapter after a successful flush; never drops dirty
  /// text silently (a failed flush keeps the chapter open in the caller).
  void release() {
    _unsubscribe?.call();
    _unsubscribe = null;
    final document = _document;
    if (document != null) {
      _saves.releaseDocument(document.workId, document.documentId);
    }
    _document = null;
    _body = '';
    _saveState = null;
    _contentEpoch++;
    if (!_disposed) notifyListeners();
  }

  Future<void> _reload() async {
    final document = _document!;
    final reloaded = await _repository.loadDocument(
      document.workId,
      document.documentId,
    );
    if (_disposed) return;
    _document = reloaded;
    _body = reloaded.body;
    _contentEpoch++;
    _saveState = _saves.hydrate(reloaded);
    notifyListeners();
  }

  /// Cancels owned timers after all text has been saved. Dispose is not a
  /// persistence barrier: callers must flush first, dirty text then throws.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _unsubscribe?.call();
    _saves.dispose();
    super.dispose();
  }

  void _checkActive() {
    if (_disposed) throw StateError('editing_session_disposed');
  }
}
