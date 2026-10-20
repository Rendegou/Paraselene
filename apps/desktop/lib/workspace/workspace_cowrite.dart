// workspace_controller 的 part：讨论候选采纳/拒绝与写作生成准备的意图入口。
// 读边界：正文锚点取自 EditingSession 的内存快照，不额外读取其他章节。
// 写边界：候选与生成都复用工作区持久化屏障，直接调用 Rust 讨论/生成仓库，由原生侧做原子提交。
// 关键不变量：采纳候选后必须重载文档并保留编辑器历史；拒绝只作用于服务端候选，线程内未发送草稿仍保留。
part of 'workspace_controller.dart';

/// Candidate and generation intents share the workspace persistence barrier.
mixin _CowriteOperations on _WorkspaceState {
  String _discussionBody = '';

  // 正文变化同步到讨论锚点映射；该映射只留在内存，不触发落盘。
  void _mapDiscussionBody() {
    final before = _discussionBody;
    _discussionBody = editing.body;
    discussions?.mapBody(before, editing.body);
  }

  /// Flushes exact author state, then lets Rust atomically adopt the candidate.
  ///
  /// 采纳前先 flush 正文；Rust 原子提交候选后重载文档并保留编辑器历史，随后刷新操作列表。
  Future<bool> applyCandidate(String operationId) =>
      persistenceBarrier(() async {
        final registry = discussions;
        final document = editing.document;
        if (registry == null || document == null) {
          throw const WorkspaceFailure('no_open_chapter');
        }
        await registry.repository.applyOperation(
          document.workId,
          document.documentId,
          operationId,
          editing.saveState?.revision,
        );
        final loaded = await repository.loadDocument(
          document.workId,
          document.documentId,
        );
        editing.adopt(loaded, preserveEditorHistory: true);
        await registry.refreshOperations();
      });

  /// Rejects only the server candidate; the thread's next unsent draft survives.
  ///
  /// 只拒绝服务端候选并刷新操作列表，线程内尚未发送的草稿不受影响。
  Future<bool> rejectCandidate(String operationId) =>
      persistenceBarrier(() async {
        final registry = discussions;
        if (registry?.work == null || registry?.chapter == null) {
          throw const WorkspaceFailure('no_open_chapter');
        }
        await registry!.repository.rejectOperation(
          registry.work!,
          registry.chapter!,
          operationId,
        );
        await registry.refreshOperations();
      });

  /// Flushes the exact quote and draft, then prepares full messages for review.
  ///
  /// 先 flush 引文与草稿，再组装完整消息供用户确认；没有打开章节、锚点失效或仓库不支持生成时抛出稳定错误码。
  Future<Map<String, dynamic>?> prepareGeneration(
    String threadId, {
    String outputLanguage = 'preserve',
  }) async {
    Map<String, dynamic>? preview;
    await persistenceBarrier(() async {
      final registry = discussions;
      final source = registry?.repository;
      if (registry == null || source is! GenerationRepository) {
        throw const WorkspaceFailure('generation_unavailable');
      }
      final thread = registry.threads.firstWhere(
        (thread) => thread.id == threadId,
      );
      final anchor = thread.anchor;
      final document = editing.document;
      if (anchor == null || !anchor.valid || document == null) {
        throw const WorkspaceFailure('generation_context_conflict');
      }
      final id = '${thread.id}-${DateTime.now().microsecondsSinceEpoch}';
      preview = await (source as GenerationRepository).prepare({
        'workId': document.workId,
        'documentId': document.documentId,
        'threadId': thread.id,
        'operationId': id,
        'expectedRevision': editing.saveState?.revision,
        'baseBody': editing.body,
        'from': anchor.from,
        'to': anchor.to,
        'selectedText': anchor.text,
        'instruction': thread.draft,
        'referenceIds': thread.snapshot['attached'],
        'outputLanguage': outputLanguage,
      });
      preview = {
        ...preview!,
        'operationId': id,
        'workId': document.workId,
        'documentId': document.documentId,
      };
    });
    return preview;
  }
}
