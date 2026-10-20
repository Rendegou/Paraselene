// R09 资料查阅、带入讨论与完整编辑分离的支持层。
// 预览卡只读展示当前 head 与历史请求提交时的引用快照，不写库、不发模型请求；
// 只有作者明确点击“带入讨论”才把条目 ID 写入绑定的当前讨论引用集合。

import 'dart:async';

import 'package:flutter/material.dart';

import '../../cowrite/discussion_thread.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/workbench_theme.dart';

export 'lore_discussion_target.dart';

/// 侧栏资料行投影出的只读预览数据，全部字段都是展示副本。
class LorePreviewData {
  const LorePreviewData({
    required this.entryId,
    required this.name,
    required this.kind,
    required this.status,
    required this.version,
    required this.origin,
    required this.confirmed,
    required this.body,
  });

  /// 从 `{entry: ..., head: ...}` 行解析预览数据。
  ///
  /// [row] 结构缺失或没有条目 ID 时返回 null：调用方应提示条目缺失，
  /// 不能用其它条目冒充。head 为空时正文为空、版本为 0。
  static LorePreviewData? fromRow(Map<String, dynamic> row) {
    final entry = row['entry'];
    if (entry is! Map) return null;
    final entryId = entry['id'];
    final name = entry['name'];
    if (entryId is! String || entryId.isEmpty || name is! String) return null;
    final head = row['head'];
    final headFields = head is Map ? head : const <String, dynamic>{};
    final version = headFields['version'];
    final body = headFields['body'];
    final origin = headFields['origin'];
    final kind = entry['kind'];
    final status = entry['status'];
    return LorePreviewData(
      entryId: entryId,
      name: name,
      kind: kind is String ? kind : '',
      status: status is String ? status : '',
      version: version is int ? version : 0,
      origin: origin is String && origin.isNotEmpty ? origin : null,
      confirmed: headFields['confirmed'] == true,
      body: body is String ? body : '',
    );
  }

  /// 条目 ID；点击带入时写入讨论线程 attached 的值。
  final String entryId;
  final String name;
  final String kind;
  final String status;
  final int version;
  final String? origin;
  final bool confirmed;
  final String body;
}

/// 在已加载的资料行里按条目 ID 精确查找；找不到返回 null。
Map<String, dynamic>? loreRowById(
  Iterable<Map<String, dynamic>> rows,
  String entryId,
) {
  if (entryId.isEmpty) return null;
  for (final row in rows) {
    final entry = row['entry'];
    if (entry is Map && entry['id'] == entryId) return row;
  }
  return null;
}

/// 历史请求提交时的单条资料引用快照；不随之后编辑的资料变化。
class LoreRequestSnapshot {
  const LoreRequestSnapshot({
    required this.threadId,
    required this.requestIndex,
    required this.requestText,
    required this.name,
    required this.body,
  });

  final String threadId;
  final int requestIndex;
  final String requestText;
  final String name;
  final String body;
}

/// 收集线程快照里引用过 [entryId] 的历史请求，返回提交时冻结的名称与正文。
///
/// 只读 `thread.snapshot['requests']` 中的作者数据，不查询当前资料，
/// 因此资料之后被编辑也不会覆盖历史依据。
List<LoreRequestSnapshot> loreRequestSnapshots(
  Iterable<DiscussionThread> threads,
  String entryId,
) {
  final snapshots = <LoreRequestSnapshot>[];
  if (entryId.isEmpty) return snapshots;
  for (final thread in threads) {
    final requests = thread.snapshot['requests'];
    if (requests is! List) continue;
    for (var index = 0; index < requests.length; index++) {
      final request = requests[index];
      if (request is! Map) continue;
      final references = request['references'];
      if (references is! List) continue;
      for (final reference in references) {
        if (reference is! Map || reference['id'] != entryId) continue;
        final name = reference['name'];
        final body = reference['body'];
        final text = request['text'];
        snapshots.add(
          LoreRequestSnapshot(
            threadId: thread.id,
            requestIndex: index,
            requestText: text is String ? text : '',
            name: name is String ? name : '',
            body: body is String ? body : '',
          ),
        );
      }
    }
  }
  return snapshots;
}

/// 资料类型的中文本地化标签；未知类型原样显示。
String loreKindLabel(AppLocalizations strings, String kind) {
  return switch (kind) {
    'character' => strings.loreGroupCharacters,
    'world' => strings.loreGroupWorld,
    'location' => strings.loreGroupLocations,
    'timeline' => strings.loreGroupTimeline,
    'taboo' => strings.loreGroupTaboo,
    'style' => strings.loreGroupStyle,
    _ => kind.isEmpty ? strings.loreTitle : kind,
  };
}

/// 轻量只读资料预览：宽窗靠右临时卡、窄窗面板，复用同一份内容。
///
/// 预览本身不改变讨论引用、不增加模型上下文；[onAttach] 与 [onRemove]
/// 返回 true 时才更新按钮状态。历史快照区展示提交时的名称与正文，
/// “查看当前资料”只滚动到当前内容，不会用最新内容覆盖历史。
class LorePreview extends StatefulWidget {
  const LorePreview({
    required this.data,
    this.history = const [],
    this.attached = false,
    this.onAttach,
    this.onRemove,
    this.onEdit,
    required this.onClose,
    super.key,
  });

  final LorePreviewData data;
  final List<LoreRequestSnapshot> history;
  final bool attached;
  final bool Function()? onAttach;
  final bool Function()? onRemove;
  final VoidCallback? onEdit;
  final VoidCallback onClose;

  @override
  State<LorePreview> createState() => _LorePreviewState();
}

class _LorePreviewState extends State<LorePreview> {
  final ScrollController _scroll = ScrollController();
  final GlobalKey _currentKey = GlobalKey();
  late bool _attached = widget.attached;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 720;
    return Dialog(
      key: const ValueKey('lore-preview-card'),
      alignment: wide ? AlignmentDirectional.centerEnd : Alignment.center,
      insetPadding: EdgeInsets.all(wide ? 24 : 8),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: wide ? 400 : 520,
          maxHeight: size.height * (wide ? 0.72 : 0.86),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  controller: _scroll,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _summary(context),
                      if (widget.history.isNotEmpty) ...[
                        const Divider(height: 24),
                        _history(context),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        AppLocalizations.of(context).lorePreviewHint,
                        style: WorkbenchTokens.ui(
                          size: 12,
                          color: WorkbenchTokens.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _actions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            widget.data.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: WorkbenchTokens.ui(size: 16, weight: FontWeight.w600),
          ),
        ),
        IconButton(
          key: const ValueKey('lore-preview-close'),
          onPressed: widget.onClose,
          tooltip: strings.close,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.close, size: 18),
        ),
      ],
    );
  }

  Widget _summary(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final data = widget.data;
    final meta = <String>[
      loreKindLabel(strings, data.kind),
      'v${data.version}',
      if (data.status.isNotEmpty) data.status,
      if (data.origin != null) data.origin!,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          meta.join(' · '),
          style: WorkbenchTokens.ui(size: 12, color: WorkbenchTokens.muted),
        ),
        const SizedBox(height: 10),
        Container(
          key: _currentKey,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: WorkbenchTokens.paper,
            borderRadius: BorderRadius.circular(WorkbenchTokens.radius),
            border: Border.all(color: WorkbenchTokens.stroke),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.currentLoreContent,
                key: const ValueKey('lore-preview-current'),
                style: WorkbenchTokens.ui(
                  size: 12,
                  color: WorkbenchTokens.muted,
                ),
              ),
              const SizedBox(height: 6),
              SelectableText(
                data.body.isEmpty ? strings.referenceEmpty : data.body,
                style: WorkbenchTokens.ui(size: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _history(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.historyReferences,
          key: const ValueKey('lore-preview-history'),
          style: WorkbenchTokens.ui(size: 12, weight: FontWeight.w600),
        ),
        for (var index = 0; index < widget.history.length; index++)
          _historyItem(strings, index),
      ],
    );
  }

  Widget _historyItem(AppLocalizations strings, int index) {
    final snapshot = widget.history[index];
    return Container(
      key: ValueKey('lore-preview-history-item-$index'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: WorkbenchTokens.frame,
        borderRadius: BorderRadius.circular(WorkbenchTokens.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (snapshot.requestText.isNotEmpty)
            Text(
              snapshot.requestText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: WorkbenchTokens.ui(size: 12, color: WorkbenchTokens.muted),
            ),
          const SizedBox(height: 4),
          Text(
            snapshot.name,
            style: WorkbenchTokens.ui(size: 13, weight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          SelectableText(snapshot.body, style: WorkbenchTokens.ui(size: 13)),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              key: ValueKey('lore-preview-view-current-$index'),
              onPressed: _scrollToCurrent,
              child: Text(strings.viewCurrentLore),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Row(
      children: [
        TextButton(
          key: const ValueKey('lore-preview-edit'),
          onPressed: widget.onEdit,
          child: Text(strings.expandLoreEdit),
        ),
        const Spacer(),
        if (_attached)
          TextButton(
            key: const ValueKey('lore-preview-remove'),
            onPressed: widget.onRemove == null ? null : _remove,
            child: Text(strings.removeReference),
          )
        else
          FilledButton(
            key: const ValueKey('lore-preview-attach'),
            onPressed: widget.onAttach == null ? null : _attach,
            child: Text(strings.attachToDiscussion),
          ),
      ],
    );
  }

  void _attach() {
    final onAttach = widget.onAttach;
    if (onAttach == null || !onAttach()) return;
    setState(() => _attached = true);
  }

  void _remove() {
    final onRemove = widget.onRemove;
    if (onRemove == null || !onRemove()) return;
    setState(() => _attached = false);
  }

  void _scrollToCurrent() {
    final target = _currentKey.currentContext;
    if (target == null) {
      if (_scroll.hasClients) {
        unawaited(
          _scroll.animateTo(
            0,
            duration: _scrollDuration,
            curve: Curves.easeOut,
          ),
        );
      }
      return;
    }
    unawaited(
      Scrollable.ensureVisible(
        target,
        duration: _scrollDuration,
        curve: Curves.easeOut,
      ),
    );
  }

  static const Duration _scrollDuration = Duration(milliseconds: 180);
}
