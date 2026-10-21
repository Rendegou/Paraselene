// 共写讨论面板：编辑作者草稿、预览并确认候选生成、展示服务端操作与候选差异。
// 写边界：草稿只进入作者快照；服务端操作仅作为投影展示，不回写作者快照。
// 生成必须经过完整材料预览与显式确认；取消或章节切换会丢弃票据，不产生候选。
//
// 面板既用于段下展开卡片，也用于整章/失效线程的临时对话框。段下卡片按内容
// 自然测量高度，超过上限时内部滚动；收起只改展示态，不取消真实生成操作。

import 'package:flutter/material.dart';
import 'discussion_panel_content.dart';
import 'discussion_presentation.dart';
import '../l10n/generated/app_localizations.dart';
import '../workspace/workspace_controller.dart';
import 'discussion_thread.dart';
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
/// [inDialog] 区分段下收起与弹窗关闭；外层宿主提供 [onCollapse] 回调。
class DiscussionPanel extends StatefulWidget {
  const DiscussionPanel({
    required this.thread,
    required this.workspace,
    this.onCollapse,
    this.autofocusDraft = false,
    this.inDialog = false,
    super.key,
  });

  /// Dialog owns the outer surface; embedded hosts own one paper border.
  final bool inDialog;
  final DiscussionThread thread;
  final WorkspaceController workspace;

  /// 关闭当前展示；段下宿主收起，弹窗宿主退出路由。
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
    if (widget.thread.isChapter) return '';
    return widget.thread.valid
        ? strings.discussionValid
        : strings.discussionInvalid;
  }

  @override
  Widget build(BuildContext context) {
    final registry = widget.workspace.discussions!;
    final operations = registry.operations
        .where((row) => row['threadId'] == widget.thread.id)
        .toList();
    final view = DiscussionPresentation(
      thread: widget.thread,
      operations: operations,
      title: _title,
      status: _statusText,
      outputLanguage: _running ? _run!.outputLanguage : _outputLanguage,
      running: _running,
      cancelling:
          (_run?.cancelling ?? false) ||
          ((_run?.cancelRequested ?? false) && !_failed),
      failed: _failed,
      busy: widget.workspace.isBusy,
      inDialog: widget.inDialog,
      compare: _compare,
      history: _history,
      applyFailed: _applyFailedOperation != null,
      canGenerate: registry.repository is GenerationRepository,
      canReference: widget.workspace.repository is RealWorkspaceRepository,
      saveFailed: registry.error == 'discussion_save_failed',
    );
    return DiscussionPanelContent(
      view: view,
      draft: _draft,
      draftFocus: _draftFocus,
      actions: DiscussionPanelActions(
        onCollapse: widget.onCollapse,
        onRetry: _retrySave,
        onDraft: (text) => registry.editDraft(widget.thread.id, text),
        onLanguage: (value) => setState(() => _outputLanguage = value),
        onReferences: _references,
        onGenerate: _generate,
        onCancel: _cancel,
        onCompare: () => setState(() => _compare = !_compare),
        onHistory: () => setState(() => _history = !_history),
        onApply: _applyCandidate,
        onReject: _rejectCandidate,
      ),
    );
  }

  Future<void> _rejectCandidate(String operationId) async {
    await widget.workspace.rejectCandidate(operationId);
  }

  Future<void> _retrySave() async {
    try {
      await widget.workspace.discussions!.flush();
    } catch (_) {
      // Registry 已记录稳定错误码；刷新面板让重试结果立即可见。
      if (mounted) setState(() {});
    }
  }

  /// 采纳候选并把失败原因留在面板内；成功后清除失败提示。
  ///
  /// 失败由持久化屏障记录稳定错误码（如 revision_conflict）；正文与草稿保持
  /// 原样，作者需要重新预览后再采纳，不能假装候选已经写入。
  Future<void> _applyCandidate(String operationId) async {
    final threadId = widget.thread.id;
    final ok = await widget.workspace.applyCandidate(operationId);
    if (!mounted || widget.thread.id != threadId) return;
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
    final chapter = registry.chapter;
    final thread = widget.thread;
    if (work == null) return;
    final selected = await showDialog<List<String>>(
      context: context,
      builder: (context) => LorePicker(
        repository: source.lore,
        work: work,
        selected: (thread.snapshot['attached'] as List).cast<String>().toList(
          growable: false,
        ),
      ),
    );
    if (mounted &&
        selected != null &&
        registry.work == work &&
        registry.chapter == chapter &&
        widget.thread.id == thread.id) {
      // 选择期间可能切换作品，返回后必须仍是同一作品才写入引用。
      registry.attachReferences(thread.id, selected);
    }
    // 资料对话框关闭后把焦点还给发起讨论的草稿，避免作者重新寻找输入框。
    if (mounted && widget.thread.id == thread.id) _draftFocus.requestFocus();
  }
}
