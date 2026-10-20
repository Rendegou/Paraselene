// 资料引用目标：在预览打开时冻结作品、章节和当前讨论，拒绝异步串写。
import '../../cowrite/discussion_registry.dart';
import '../../cowrite/discussion_thread.dart';
import '../data/workspace_repository.dart';

/// 资料预览打开时的讨论身份；threadId 为空时才允许整章回退。
final class LoreDiscussionTarget {
  const LoreDiscussionTarget({
    required this.work,
    required this.chapter,
    required this.threadId,
  });

  /// 目标作品 ID。
  final String work;

  /// 目标文档 ID。
  final String chapter;

  /// 目标讨论 ID；null 表示打开预览时没有活动讨论。
  final String? threadId;

  /// 捕获当前作用域；未打开章节或正在加载时返回 null，不创建讨论。
  static LoreDiscussionTarget? capture(DiscussionRegistry registry) {
    if (registry.work == null || registry.chapter == null || registry.loading) {
      return null;
    }
    return LoreDiscussionTarget(
      work: registry.work!,
      chapter: registry.chapter!,
      threadId: registry.activeThreadId,
    );
  }

  /// 目标仍属于当前作用域；有指定线程时还必须存在该线程。
  bool matches(DiscussionRegistry registry) =>
      !registry.loading &&
      work == registry.work &&
      chapter == registry.chapter &&
      (threadId == null || registry.byId(threadId!) != null);
}

/// 读取显式资料 ID，不修改作者快照。
List<String> loreAttachedIds(DiscussionThread thread) {
  final attached = thread.snapshot['attached'];
  if (attached is! List) return const [];
  return [
    for (final id in attached)
      if (id is String && id.isNotEmpty) id,
  ];
}

/// 查找整章讨论，不创建线程。
DiscussionThread? chapterDiscussion(Iterable<DiscussionThread> threads) {
  for (final thread in threads) {
    if (thread.isChapter) return thread;
  }
  return null;
}

/// 检查指定讨论已带入的资料；未指定讨论时只读整章回退。
bool loreEntryAttached(
  Iterable<DiscussionThread> threads,
  String entryId, {
  String? threadId,
}) {
  for (final thread in threads) {
    if (threadId == null ? thread.isChapter : thread.id == threadId) {
      return loreAttachedIds(thread).contains(entryId);
    }
  }
  return false;
}

DiscussionThread? _targetThread(
  DiscussionRegistry registry,
  LoreDiscussionTarget? target, {
  bool create = false,
}) {
  final captured = target ?? LoreDiscussionTarget.capture(registry);
  if (captured == null) throw const WorkspaceFailure('no_open_chapter');
  if (!captured.matches(registry)) {
    throw const WorkspaceFailure('discussion_context_conflict');
  }
  if (captured.threadId != null) return registry.byId(captured.threadId!);
  return create
      ? registry.chapterThread()
      : chapterDiscussion(registry.threads);
}

/// 带入目标讨论；仅无活动讨论时创建整章回退，最多 32 项且不可重复。
void attachLoreReference(
  DiscussionRegistry registry,
  String entryId, {
  LoreDiscussionTarget? target,
}) {
  if (entryId.isEmpty) throw const WorkspaceFailure('invalid_input');
  final thread = _targetThread(registry, target, create: true)!;
  final attached = loreAttachedIds(thread);
  if (attached.contains(entryId)) return;
  if (attached.length >= 32) throw const WorkspaceFailure('invalid_input');
  registry.attachReferences(thread.id, [...attached, entryId]);
}

/// 从同一冻结目标移除引用；旧作用域报错，不修改新打开的章节。
void removeLoreReference(
  DiscussionRegistry registry,
  String entryId, {
  LoreDiscussionTarget? target,
}) {
  final thread = _targetThread(registry, target);
  if (thread == null) return;
  final attached = loreAttachedIds(thread);
  if (!attached.contains(entryId)) return;
  registry.attachReferences(thread.id, [
    for (final id in attached)
      if (id != entryId) id,
  ]);
}
