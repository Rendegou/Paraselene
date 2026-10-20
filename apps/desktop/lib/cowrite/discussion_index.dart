// 讨论索引：列出当前章节全部讨论线程，包括锚点已失效和未发草稿的线程。
// 只读交互：选择条目只把真实线程对象交回工作区，不新建“相似”线程、不修改
// 线程、不写库、不发请求；索引本身不载入正文。

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import 'discussion_thread.dart';

/// 打开当前章节的完整讨论索引面板。
///
/// 面板列出本章全部线程（有效、失效、整章、未发草稿），每项显示冻结引文或
/// 整章标题、当前状态与草稿提示。选择条目先关闭面板，再把原线程交回
/// [onOpen]，由工作区按线程 ID 重新展开或打开失效线程的临时面板；因此重开
/// 不会创建新线程，也不依赖正文相似句搜索。
///
/// 返回的 Future 在面板关闭后完成；调用方可在完成后恢复焦点。
Future<void> showDiscussionIndex(
  BuildContext context, {
  required List<DiscussionThread> threads,
  required ValueChanged<DiscussionThread> onOpen,
  required AppLocalizations strings,
}) => showDialog<void>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    key: const ValueKey('discussion-index-panel'),
    title: Row(
      children: [
        Expanded(child: Text(strings.discussionIndex(threads.length))),
        IconButton(
          key: const ValueKey('discussion-index-close'),
          tooltip: strings.closeDialog,
          icon: const Icon(Icons.close, size: 18),
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
      ],
    ),
    content: ConstrainedBox(
      // 窄窗下对话框内容随可用宽度收缩；条目较少，用 Column 支持固有宽度。
      constraints: const BoxConstraints(maxWidth: 360, maxHeight: 320),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final thread in threads)
              InkWell(
                key: ValueKey('discussion-index-entry-${thread.id}'),
                borderRadius: BorderRadius.circular(6),
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  onOpen(thread);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  child: DiscussionIndexEntry(thread: thread, strings: strings),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(dialogContext).pop(),
        child: Text(strings.closeDialog),
      ),
    ],
  ),
);

/// 单条索引项：第一行是冻结引文（或整章标题），第二行是状态与草稿提示。
class DiscussionIndexEntry extends StatelessWidget {
  const DiscussionIndexEntry({
    required this.thread,
    required this.strings,
    super.key,
  });

  final DiscussionThread thread;
  final AppLocalizations strings;

  String get _title {
    // 按 Unicode 标量截断标题，避免从中间切开代理对。
    if (thread.isChapter) return strings.discussionWholeChapter;
    final target = thread.snapshot['target'];
    final text = target is Map ? target['text'] as String? ?? '' : '';
    final runes = text.runes.toList();
    if (runes.length <= 32) return text;
    return '${String.fromCharCodes(runes.take(32))}…';
  }

  String get _status {
    // 整章讨论没有锚点，视为始终有效；有草稿只提示存在，不改变有效性。
    final state = thread.isChapter || thread.valid
        ? strings.discussionValid
        : strings.discussionInvalid;
    return thread.draft.isEmpty
        ? state
        : '$state · ${strings.discussionHasDraft}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _title.isEmpty ? strings.discussionSelection : _title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          _status,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
