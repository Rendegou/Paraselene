// 编辑会话：独占当前打开章节的精确正文、CAS 修订与保存状态，是作者正文的唯一内存权威。
// 读边界：正文只从 WorkspaceRepository.loadDocument 载入；保存状态由 SaveCoordinator 提供。
// 写边界：edit 只改内存，落盘由 SaveCoordinator 防抖或显式 flush 完成；本文件不直接写数据库。
// 关键不变量：contentEpoch 只在外部内容重置时递增；保存状态更新不得改写作者正文；输入锁定期间拒绝新输入。
import 'package:flutter/foundation.dart';

import '../domain/editing/save_coordinator.dart';
import 'data/workspace_repository.dart';

/// Owns the exact text of the currently open chapter and its persistence
/// lifecycle through the SaveCoordinator. The editor widget mirrors [body]
/// only when [contentEpoch] changes (navigation, confirm, rollback); save
/// status updates never rewrite author text.
///
/// 编辑会话持有作者正文的唯一内存权威；界面只在 contentEpoch 变化时镜像正文，保存状态更新不会重写文本。
final class EditingSession extends ChangeNotifier {
  EditingSession(this._repository, {SaveScheduler? schedule})
    : _saves = SaveCoordinator(_repository, schedule: schedule);

  final WorkspaceRepository _repository;
  final SaveCoordinator _saves;
  ChapterDocument? _document;
  String _body = '';
  SaveState? _saveState;
  int _contentEpoch = 0;
  bool _preserveEditorHistory = false;

  /// True only for a persisted candidate adoption in the current chapter.
  ///
  /// 只表示当前章节采纳了已持久化的候选；切换章节或内容重置后为 false。
  bool get preserveEditorHistory => _preserveEditorHistory;
  void Function()? _unsubscribe;
  bool _disposed = false;

  /// Blocks new input while a navigation or recovery snapshot is committed.
  bool _inputLocked = false;
  int _inputBarrierEpoch = 0;

  /// 导航或恢复快照提交期间为 true，此时新的正文输入会被丢弃。
  bool get inputLocked => _inputLocked;

  /// Synchronous barrier generation also detects lock/unlock between frames.
  ///
  /// 同步屏障代号在每次加锁或解锁时递增，供编辑器检测两次帧之间的状态切换。
  int get inputBarrierEpoch => _inputBarrierEpoch;

  /// 切换输入锁；状态真正变化时才递增屏障代号，供监听者检测帧间变化。
  set inputLocked(bool next) {
    if (_inputLocked == next) return;
    _inputLocked = next;
    _inputBarrierEpoch++;
  }

  /// The loaded document of the open chapter, including CAS revision/head.
  ///
  /// 已加载章节文档，含 CAS 修订与版本头；未打开章节时为 null。
  ChapterDocument? get document => _document;

  /// Exact in-memory text; may be newer than the last saved snapshot.
  ///
  /// 精确内存正文，可能比最近一次成功保存更新；未打开章节时为空串。
  String get body => _body;

  /// Monotonic per external content reset (open/confirm/rollback/release).
  ///
  /// 每次外部内容重置（打开、确认、回滚、释放）时单调递增。
  int get contentEpoch => _contentEpoch;

  /// Latest persistence state of the open chapter.
  ///
  /// 当前章节最近一次保存状态；未打开章节时为 null。
  SaveState? get saveState => _saveState;

  /// 是否已加载打开章节；释放后为 false。
  bool get hasOpenChapter => _document != null;

  /// Bounded snapshots of all loaded slots, including dirty text for export.
  ///
  /// 所有已加载槽位的保存状态快照，包含脏文本，用于恢复导出；调用方只读使用。
  List<SaveState> get loadedStates => _saves.loadedStates;

  /// Opens a chapter's exact working text. The previous slot is released only
  /// after the new document loaded successfully, so a failed load keeps the
  /// current chapter fully intact.
  ///
  /// 只有新文档加载成功后才替换当前章节；加载失败时原章节与正文保持不变。
  Future<void> open(String workId, WorkspaceChapter chapter) async {
    _checkActive();
    final loaded = await _repository.loadDocument(workId, chapter.id);
    if (_disposed) return;
    adopt(loaded);
  }

  /// Installs an already loaded document after the caller's identity checks.
  /// The previous slot must be clean; no repository operation is performed.
  ///
  /// preserveEditorHistory 仅在作品与文档都未变化且调用方确认候选已持久化时生效。
  void adopt(ChapterDocument loaded, {bool preserveEditorHistory = false}) {
    _checkActive();
    _unsubscribe?.call();
    _unsubscribe = null;
    final previous = _document;
    if (previous != null) {
      _saves.releaseDocument(previous.workId, previous.documentId);
    }
    _document = loaded;
    _preserveEditorHistory =
        preserveEditorHistory &&
        previous?.workId == loaded.workId &&
        previous?.documentId == loaded.documentId;
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
  ///
  /// 正文变化只写内存并由协调器防抖落盘；输入锁定、未打开章节或文本未变时忽略。
  void edit(String body) {
    final document = _document;
    if (_disposed || inputLocked || document == null || body == _body) return;
    _body = body;
    _saves.edit(document.workId, document.documentId, body);
  }

  /// Waits for the latest text of every loaded slot to be durably saved;
  /// conflict/error states throw their stable code and keep the draft.
  ///
  /// 等待全部已加载槽位的最新正文落盘；冲突或错误以稳定错误码抛出并保留草稿。
  Future<void> flushAll() => _saves.flushAll();

  /// Retries the open chapter's retained exact text with the same CAS revision.
  ///
  /// 用同一 CAS 修订重试当前章节的保留正文，不清空草稿。
  Future<void> retrySave() async {
    final document = _document;
    if (document == null) return;
    await _saves.retryDocument(document.workId, document.documentId);
  }

  /// Flushes, then prepares the review binding body/head/revision/context.
  /// A chapter with no saved draft cannot be confirmed (`draft_missing`).
  ///
  /// 没有打开章节时抛 no_open_chapter，没有已保存草稿时抛 draft_missing；本调用先 flush 但不确认。
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
  ///
  /// 确认成功后重新加载文档以取得重定基后的修订号；令牌被更新编辑作废时以稳定错误码失败。
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
  ///
  /// 回滚前先 flush；成功后重新加载快照替换工作副本，历史版本本身不被删除。
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
  ///
  /// 释放当前打开章节；脏文本不会被静默丢弃，落盘失败由调用方处理。
  void release() {
    _unsubscribe?.call();
    _unsubscribe = null;
    final document = _document;
    if (document != null) {
      _saves.releaseDocument(document.workId, document.documentId);
    }
    _document = null;
    _preserveEditorHistory = false;
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
    _preserveEditorHistory = false;
    _body = reloaded.body;
    _contentEpoch++;
    _saveState = _saves.hydrate(reloaded);
    notifyListeners();
  }

  /// Cancels owned timers after all text has been saved. Dispose is not a
  /// persistence barrier: callers must flush first, dirty text then throws.
  ///
  /// 取消订阅与保存协调器；dispose 不是持久化屏障，脏文本未保存时会向调用方抛出。
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
