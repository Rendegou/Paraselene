// 已确认版本弹窗：缓存只读查询，区分加载/失败/空/内容并提供显式重试。
// 依赖工作区控制器与本地化标签；查询、预览和回滚始终绑定打开时的作品/章节。
// 回滚仍经控制器屏障；迟到成功只能关闭原弹窗，不能弹出后来打开的 route。
import 'package:flutter/material.dart';

import '../data/workspace_repository.dart';
import '../workspace_controller.dart';
import 'workbench_labels.dart';

/// 已确认版本列表与精确正文预览；回滚必须经过二次确认和控制器屏障。
class VersionsDialog extends StatefulWidget {
  const VersionsDialog({
    required this.controller,
    required this.labels,
    super.key,
  });

  /// 版本查询与回滚的权威入口；弹窗冻结打开时的作品和章节身份。
  final WorkspaceController controller;

  /// 当前界面文案，不转换版本正文或作品语言。
  final WorkbenchLabels labels;

  @override
  State<VersionsDialog> createState() => _VersionsDialogState();
}

class _VersionsDialogState extends State<VersionsDialog> {
  late final WorkspaceController _controller;
  late final String? _workId;
  late final String? _chapterId;
  late Future<List<VersionEntry>> _versions;
  String? _rollbackErrorCode;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller;
    _workId = _controller.currentWork?.id;
    _chapterId = _controller.currentChapter?.id;
    _versions = _readVersions();
  }

  bool get _sameTarget =>
      identical(widget.controller, _controller) &&
      _controller.currentWork?.id == _workId &&
      _controller.currentChapter?.id == _chapterId;

  Future<List<VersionEntry>> _readVersions() async {
    if (!_sameTarget) throw const WorkspaceFailure('versions_target_changed');
    return _controller.listVersions();
  }

  void _retry() {
    if (!_sameTarget) return;
    setState(() {
      _versions = _readVersions();
    });
  }

  Future<void> _rollback(VersionEntry version) async {
    if (!_sameTarget || _controller.isBusy) return;
    final route = ModalRoute.of(context);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (_) => _VersionRollbackPrompt(labels: widget.labels),
    );
    if (accepted != true ||
        !mounted ||
        !_sameTarget ||
        route?.isCurrent != true) {
      return;
    }
    setState(() => _rollbackErrorCode = null);
    final rolledBack = await _controller.rollbackChapter(version.id);
    if (!mounted || !_sameTarget) return;
    if (rolledBack) {
      if (route?.isCurrent == true) await Navigator.of(context).maybePop();
    } else {
      setState(() {
        _rollbackErrorCode =
            _controller.errorCode ?? 'versions_rollback_failed';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels = widget.labels;
    final s = labels.strings;
    return AlertDialog(
      title: Text(labels(s.versionsTitle)),
      content: SizedBox(
        width: 560,
        height: 420,
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => _VersionHistoryView(
            labels: labels,
            versions: _versions,
            sameTarget: _sameTarget,
            canRollback: !_controller.isBusy,
            rollbackErrorCode: _rollbackErrorCode,
            onRetry: _retry,
            onRollback: _rollback,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(labels(s.closeDialog)),
        ),
      ],
    );
  }
}

class _VersionHistoryView extends StatelessWidget {
  const _VersionHistoryView({
    required this.labels,
    required this.versions,
    required this.sameTarget,
    required this.canRollback,
    required this.rollbackErrorCode,
    required this.onRetry,
    required this.onRollback,
  });
  final WorkbenchLabels labels;
  final Future<List<VersionEntry>> versions;
  final bool sameTarget;
  final bool canRollback;
  final String? rollbackErrorCode;
  final VoidCallback onRetry;
  final Future<void> Function(VersionEntry) onRollback;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (sameTarget && rollbackErrorCode != null)
        Padding(
          padding: const EdgeInsetsDirectional.only(bottom: 8),
          child: _VersionHistoryFailure(
            labels: labels,
            code: rollbackErrorCode!,
          ),
        ),
      Expanded(
        child: FutureBuilder<List<VersionEntry>>(
          future: versions,
          builder: (context, snapshot) => _VersionHistoryContent(
            labels: labels,
            snapshot: snapshot,
            sameTarget: sameTarget,
            canRollback: canRollback,
            onRetry: onRetry,
            onRollback: onRollback,
          ),
        ),
      ),
    ],
  );
}

class _VersionHistoryContent extends StatelessWidget {
  const _VersionHistoryContent({
    required this.labels,
    required this.snapshot,
    required this.sameTarget,
    required this.canRollback,
    required this.onRetry,
    required this.onRollback,
  });
  final WorkbenchLabels labels;
  final AsyncSnapshot<List<VersionEntry>> snapshot;
  final bool sameTarget;
  final bool canRollback;
  final VoidCallback onRetry;
  final Future<void> Function(VersionEntry) onRollback;

  @override
  Widget build(BuildContext context) {
    if (!sameTarget) {
      return _VersionHistoryFailure(
        labels: labels,
        code: 'versions_target_changed',
      );
    }
    if (snapshot.connectionState != ConnectionState.done) {
      return const LinearProgressIndicator();
    }
    if (snapshot.hasError) {
      return _VersionHistoryFailure(
        labels: labels,
        code: 'versions_load_failed',
        onRetry: onRetry,
      );
    }
    final versions = snapshot.requireData;
    if (versions.isEmpty) return Text(labels(labels.strings.emptyVersions));
    return ListView.builder(
      itemCount: versions.length,
      itemBuilder: (context, index) => _VersionHistoryEntry(
        labels: labels,
        version: versions[index],
        canRollback: canRollback,
        onRollback: onRollback,
      ),
    );
  }
}

class _VersionHistoryFailure extends StatelessWidget {
  const _VersionHistoryFailure({
    required this.labels,
    required this.code,
    this.onRetry,
  });
  final WorkbenchLabels labels;
  final String code;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        liveRegion: true,
        child: Text(labels(labels.strings.errorCode('\u2068$code\u2069'))),
      ),
      if (onRetry != null)
        TextButton(
          onPressed: onRetry,
          child: Text(labels(labels.strings.retry)),
        ),
    ],
  );
}

class _VersionHistoryEntry extends StatelessWidget {
  const _VersionHistoryEntry({
    required this.labels,
    required this.version,
    required this.canRollback,
    required this.onRollback,
  });
  final WorkbenchLabels labels;
  final VersionEntry version;
  final bool canRollback;
  final Future<void> Function(VersionEntry) onRollback;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    key: ValueKey('version-${version.id}'),
    title: Text(version.createdAt),
    subtitle: version.isHead
        ? Text(labels(labels.strings.versionCurrent))
        : null,
    children: [
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: const EdgeInsetsDirectional.all(16),
          child: SelectableText(
            version.body,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ),
      if (!version.isHead)
        Padding(
          padding: const EdgeInsetsDirectional.only(bottom: 12),
          child: TextButton(
            onPressed: canRollback
                ? () async {
                    await onRollback(version);
                  }
                : null,
            child: Text(labels(labels.strings.rollbackAction)),
          ),
        ),
    ],
  );
}

class _VersionRollbackPrompt extends StatelessWidget {
  const _VersionRollbackPrompt({required this.labels});
  final WorkbenchLabels labels;

  @override
  Widget build(BuildContext context) {
    final s = labels.strings;
    return AlertDialog(
      title: Text(labels(s.rollbackTitle)),
      content: Text(labels(s.rollbackNotice)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(labels(s.cancelAction)),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(labels(s.rollbackAction)),
        ),
      ],
    );
  }
}
