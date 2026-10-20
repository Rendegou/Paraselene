// 共写讨论面板：编辑作者草稿、预览并确认候选生成、展示服务端操作与候选差异。
// 写边界：草稿只进入作者快照；服务端操作仅作为投影展示，不回写作者快照。
// 生成必须经过完整材料预览与显式确认；取消或章节切换会丢弃票据，不产生候选。
//
// 面板既用于段下展开卡片，也用于整章/失效线程的临时对话框。段下卡片按内容
// 自然测量高度，超过上限时内部滚动；收起只改展示态，不取消真实生成操作。

import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';
import '../workspace/workspace_controller.dart';
import 'discussion_thread.dart';
import 'candidate_diff.dart';
import 'generation_repository.dart';
import 'discussion_generations.dart';
import 'discussion_generation_flow.dart';
import '../lore/lore_picker.dart';
import '../workspace/data/real_workspace_repository.dart';

/// Stable editable draft host. Server history is displayed independently.
///
/// 稳定的作者草稿编辑宿主：草稿变更经 [DiscussionRegistry] 去抖保存；
/// 服务端操作历史与候选只作为独立投影展示，不回写作者快照。
///
/// 传入 [onCollapse] 时显示收起入口；整章讨论的临时对话框不传该回调，
/// 由对话框自带关闭按钮关闭。
class DiscussionPanel extends StatefulWidget {
  const DiscussionPanel({
    required this.thread,
    required this.workspace,
    this.onCollapse,
    this.autofocusDraft = false,
    super.key,
  });
  final DiscussionThread thread;
  final WorkspaceController workspace;

  /// 段下卡片收起入口；为空表示当前宿主由对话框管理生命周期。
  final VoidCallback? onCollapse;

  /// 新建线程后首次展开时把焦点交给草稿输入框，作者可直接输入。
  final bool autofocusDraft;
  @override
  State<DiscussionPanel> createState() => _DiscussionPanelState();
}

class _DiscussionPanelState extends State<DiscussionPanel> {
  late final TextEditingController _draft = TextEditingController(
    text: widget.thread.draft,
  );

  /// 草稿焦点由面板持有，便于新建后自动聚焦、资料对话框关闭后返回。
  late final FocusNode _draftFocus = FocusNode(debugLabel: 'discussion-draft');
  bool _compare = false;
  bool _history = false;
  String _outputLanguage = 'preserve';

  DiscussionGenerationRun? get _run =>
      widget.workspace.discussions?.generations.forThread(widget.thread.id);
  bool get _running => _run?.running ?? false;
  bool get _failed => _run?.failed ?? false;

  /// 最近一次采纳失败的操作 ID；只用于就地提示候选为何没有写入编辑稿。
  String? _applyFailedOperation;

  @override
  void initState() {
    super.initState();
    // 线程保存失败由 Registry 发布；面板自己订阅才能在临时对话框里立即显示
    // “讨论保存失败”与重试入口，不依赖父级 controller 是否重建。
    widget.workspace.discussions?.addListener(_onRegistryChanged);
    if (widget.autofocusDraft) {
      // 首帧后再请求焦点：此时卡片已完成测量并挂载在可见位置。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _draftFocus.requestFocus();
      });
    }
  }

  void _onRegistryChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.workspace.discussions?.removeListener(_onRegistryChanged);
    _draftFocus.dispose();
    _draft.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(DiscussionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_draft.text != widget.thread.draft) _draft.text = widget.thread.draft;
    if (oldWidget.thread.id != widget.thread.id) _applyFailedOperation = null;
  }

  /// 线程标题：冻结引文摘要或整章讨论名称。
  String get _title {
    final strings = AppLocalizations.of(context);
    final target = widget.thread.snapshot['target'];
    final text = target is Map ? target['text'] as String? ?? '' : '';
    if (text.isEmpty) {
      return widget.thread.isChapter
          ? strings.discussionWholeChapter
          : strings.discussionSelection;
    }
    final runes = text.runes.toList();
    if (runes.length <= 36) return text;
    return '${String.fromCharCodes(runes.take(36))}…';
  }

  /// 线程状态：整章讨论没有锚点；失效线程只提示原目标已变化，不隐藏历史。
  String get _statusText {
    final strings = AppLocalizations.of(context);
    if (widget.thread.isChapter) return strings.discussionWholeChapter;
    return widget.thread.valid
        ? strings.discussionValid
        : strings.discussionInvalid;
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final registry = widget.workspace.discussions!;
    final operations = registry.operations
        .where((row) => row['threadId'] == widget.thread.id)
        .toList();
    final candidates = operations
        .where((row) => row['patchStatus'] == 'pending')
        .toList();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ConstrainedBox(
        // 卡片按内容自然测量高度，但超长历史在有界区域内滚动。
        constraints: const BoxConstraints(maxHeight: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.thread.draftPending
                              ? '$_statusText · ${strings.discussionDraft}'
                              : _statusText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (widget.onCollapse != null)
                    IconButton(
                      tooltip: strings.closeDialog,
                      onPressed: widget.onCollapse,
                      icon: const Icon(Icons.unfold_less, size: 18),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              // 整章讨论没有冻结选段，失效线程的原目标已变化：两者都能保留
              // 草稿与查看历史，但不能凭空生成候选；先说明原因，不偷偷全选。
              if (registry.repository is GenerationRepository &&
                  (widget.thread.isChapter || !widget.thread.valid))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    strings.discussionGenerationUnavailable,
                    key: const ValueKey('discussion-generation-unavailable'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              // 线程保存失败时保留脏草稿并在卡片内提供重新保存入口；
              // 错误码只描述线程写入，不冒充正文保存状态。
              if (registry.error == 'discussion_save_failed')
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    key: const ValueKey('discussion-save-failed'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          strings.discussionSaveFailed,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      TextButton(
                        key: const ValueKey('discussion-save-retry'),
                        onPressed: () async {
                          try {
                            // 失败由 Registry 记录并重新发布，这里只触发重试。
                            await registry.flush();
                          } catch (_) {
                            /* error stays visible on the panel */
                          }
                        },
                        child: Text(strings.retrySave),
                      ),
                    ],
                  ),
                ),
              TextField(
                controller: _draft,
                focusNode: _draftFocus,
                enabled: !widget.workspace.isBusy,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(labelText: strings.discussionDraft),
                onChanged: (text) => registry.editDraft(widget.thread.id, text),
              ),
              Wrap(
                spacing: 8,
                children: [
                  DropdownButton<String>(
                    value: _running ? _run!.outputLanguage : _outputLanguage,
                    items: [
                      DropdownMenuItem(
                        value: 'preserve',
                        child: Text(strings.preserveTextLanguage),
                      ),
                      DropdownMenuItem(
                        value: 'zh-Hans',
                        child: Text(strings.chineseLabel),
                      ),
                      DropdownMenuItem(
                        value: 'en',
                        child: Text(strings.englishLabel),
                      ),
                    ],
                    onChanged: _running || widget.workspace.isBusy
                        ? null
                        : (value) => setState(() => _outputLanguage = value!),
                  ),
                  if (widget.workspace.repository is RealWorkspaceRepository)
                    TextButton(
                      onPressed: widget.workspace.isBusy ? null : _references,
                      child: Text(
                        '${strings.referenceMaterials} (${(widget.thread.snapshot['attached'] as List).length})',
                      ),
                    ),
                  if (registry.repository is GenerationRepository)
                    TextButton(
                      onPressed:
                          widget.workspace.isBusy ||
                              _running ||
                              !widget.thread.valid
                          ? null
                          : _generate,
                      child: Text(strings.generationPreview),
                    ),
                  if (_running)
                    TextButton(
                      onPressed:
                          (_run?.cancelling ?? false) ||
                              ((_run?.cancelRequested ?? false) && !_failed)
                          ? null
                          : _cancel,
                      child: Text(strings.generationCancel),
                    ),
                  TextButton(
                    onPressed: () => setState(() => _compare = !_compare),
                    child: Text(strings.candidateCompare),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _history = !_history),
                    child: Text(strings.discussionHistory),
                  ),
                ],
              ),
              if (_running) const LinearProgressIndicator(),
              if (_failed)
                Semantics(
                  liveRegion: true,
                  child: Text(strings.generationFailed),
                ),
              if (candidates.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    strings.candidateApplyNotice,
                    key: const ValueKey('candidate-apply-notice'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (_applyFailedOperation != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      strings.candidateApplyFailed,
                      key: const ValueKey('candidate-apply-failed'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              for (final operation in candidates) ...[
                if (_compare)
                  CandidateDiff(
                    before:
                        (((operation['binding'] as Map)['request']
                                as Map)['selectedText']
                            as String),
                    after: operation['output'] as String? ?? '',
                  ),
                if (_compare) ...[
                  Text(
                    strings.candidateOriginal,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  SelectableText(
                    ((operation['binding'] as Map?)?['request']
                                as Map?)?['selectedText']
                            as String? ??
                        '',
                  ),
                ],
                Text(
                  strings.candidateReplacement,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                SelectableText(operation['output'] as String? ?? ''),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      // 候选绑定冻结选段；线程失效后拒绝采纳，避免写入错位文本。
                      onPressed: widget.workspace.isBusy || !widget.thread.valid
                          ? null
                          : () => _applyCandidate(
                              operation['operationId'] as String,
                            ),
                      child: Text(strings.candidateApply),
                    ),
                    TextButton(
                      onPressed: widget.workspace.isBusy
                          ? null
                          : () => widget.workspace.rejectCandidate(
                              operation['operationId'] as String,
                            ),
                      child: Text(strings.candidateReject),
                    ),
                  ],
                ),
              ],
              if (_history) ...[
                ThreadVersionHistory(
                  thread: widget.thread,
                  operations: operations,
                ),
                for (final request
                    in widget.thread.snapshot['requests'] as List)
                  SelectableText((request as Map)['text'] as String? ?? ''),
                for (final operation in operations)
                  SelectableText(
                    '${((operation['binding'] as Map?)?['request'] as Map?)?['instruction'] ?? ''}\n${operation['output'] ?? ''}',
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 采纳候选并把失败原因留在面板内；成功后清除失败提示。
  ///
  /// 失败由持久化屏障记录稳定错误码（如 revision_conflict）；正文与草稿保持
  /// 原样，作者需要重新预览后再采纳，不能假装候选已经写入。
  Future<void> _applyCandidate(String operationId) async {
    final ok = await widget.workspace.applyCandidate(operationId);
    if (!mounted) return;
    setState(() => _applyFailedOperation = ok ? null : operationId);
  }

  Future<void> _generate() => generateDiscussion(
    workspace: widget.workspace,
    thread: widget.thread,
    outputLanguage: _outputLanguage,
    isMounted: () => mounted,
    approve: (preview) async =>
        await showDialog<bool>(
          context: context,
          builder: (_) => GenerationPreviewDialog(preview: preview),
        ) ==
        true,
  );

  Future<void> _cancel() async {
    final run = _run;
    if (run != null) {
      await widget.workspace.discussions!.generations.cancel(run);
    }
  }

  Future<void> _references() async {
    final source = widget.workspace.repository as RealWorkspaceRepository;
    final registry = widget.workspace.discussions!;
    final work = registry.work;
    if (work == null) return;
    final selected = await showDialog<List<String>>(
      context: context,
      builder: (context) => LorePicker(
        repository: source.lore,
        work: work,
        selected: (widget.thread.snapshot['attached'] as List).cast<String>(),
      ),
    );
    if (mounted && selected != null && registry.work == work) {
      // 选择期间可能切换作品，返回后必须仍是同一作品才写入引用。
      registry.attachReferences(widget.thread.id, selected);
    }
    // 资料对话框关闭后把焦点还给发起讨论的草稿，避免作者重新寻找输入框。
    if (mounted) _draftFocus.requestFocus();
  }
}
