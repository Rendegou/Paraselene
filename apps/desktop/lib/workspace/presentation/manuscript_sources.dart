// 手稿出处读取协调：范围绑定作品/章节/head，失败在当前纸面可见且能重试。
import 'dart:async';
import 'package:flutter/material.dart';
import '../../editor/editor_input_client.dart';
import '../../editor/editor_source_mark.dart';
import '../../lore/source_mark_controller.dart';
import '../data/real_workspace_repository.dart';
import '../workspace_controller.dart';
import 'source_navigation.dart';

/// 只管理当前稿件的出处请求与打开失败，不拥有正文内容。
class ManuscriptSources extends ChangeNotifier {
  ManuscriptSources({
    required this.workspace,
    required this.client,
    required this.context,
    required this.isMounted,
  }) {
    final repository = workspace.repository;
    final SourceMarkRepository? loader;
    if (repository is RealWorkspaceRepository) {
      loader = repository.lore;
    } else if (repository is SourceMarkHost) {
      loader = (repository as SourceMarkHost).sourceMarks;
    } else {
      loader = null;
    }
    _source = loader == null ? null : SourceMarkController(loader);
    _source?.addListener(_changed);
    sync();
  }

  /// 当前作品会话，不在此组件创建仓库。
  final WorkspaceController workspace;

  /// 原始 UTF-16 编辑客户端，全部编辑走其合同。
  final EditorInputClient client;

  /// 只在 isMounted 为真时读取的宿主上下文。
  final BuildContext Function() context;

  /// 异步完成后检查宿主是否仍有效。
  final bool Function() isMounted;
  SourceMarkController? _source;
  (String, String, String?)? _scope;
  List<EditorSourceMark>? _failed;
  bool _disposed = false;

  /// 没有出处能力的仓库不会展示假入口。
  bool get available => _source != null;

  /// 打开失败的原标记集合；重试时再次校验其作用域。
  List<EditorSourceMark>? get failedMarks => _failed;

  /// 当前正文身份下已验证的可见标记。
  List<EditorSourceMark> get marks {
    final doc = workspace.editing.document;
    return _source?.visible(
          doc?.workId,
          doc?.documentId,
          doc?.headVersionId,
          client.document.raw,
        ) ??
        const [];
  }

  /// 当前加载状态，读取错误不作为空态。
  SourceMarkState? get state {
    final doc = workspace.editing.document;
    return _source?.stateFor(
      doc?.workId,
      doc?.documentId,
      doc?.headVersionId,
      client.document.raw,
    );
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// 按当前身份幂等读取，强制刷新仅用于作者点击重试。
  void sync({bool force = false}) {
    final doc = workspace.editing.document;
    final next = doc == null
        ? null
        : (doc.workId, doc.documentId, doc.headVersionId);
    if (!force && next == _scope) return;
    _scope = next;
    if (doc == null) {
      _source?.clear();
      return;
    }
    final source = _source;
    if (source != null) {
      unawaited(
        source.load(
          doc.workId,
          doc.documentId,
          doc.headVersionId,
          client.document.raw,
        ),
      );
    }
  }

  /// 打开已验证出处，失败保留原目标供就地重试，不修改正文。
  Future<void> open(List<EditorSourceMark> requested) async {
    final current = marks;
    final valid = requested.where(current.contains).toList();
    if (valid.isEmpty || !isMounted()) return;
    try {
      await openMarkedLore(context(), workspace, client, valid);
      if (_disposed || !isMounted()) return;
      _failed = null;
      sync(force: true);
    } catch (_) {
      if (_disposed || !isMounted()) return;
      _failed = valid;
    }
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _source?.removeListener(_changed);
    _source?.dispose();
    super.dispose();
  }
}
