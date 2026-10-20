// 编辑会话适配器：把 EditorInputClient 接到 EditingSession 的持久化生命周期。
//
// 客户端每次正文变化都同步转发给会话；会话 contentEpoch 变化（打开、确认、回滚）时，
// 按 preserveEditorHistory 决定是保留撤销历史地采纳还是整篇装载。适配器只做桥接，
// 不直接写库，也不改变正文内容。
import 'package:flutter/widgets.dart';

import 'editor_input_client.dart';
import '../workspace/editing_session.dart';

/// Adapts [EditorInputClient] to the [EditingSession] persistence lifecycle.
///
/// The adapter owns the input client's document body and forwards edits to the
/// session. When the session's [EditingSession.contentEpoch] changes (open,
/// confirm, rollback), the adapter resets the input client's document.
///
/// 把 [EditorInputClient] 接到 [EditingSession] 的持久化生命周期：客户端正
/// 文变化立即转发给会话；会话 contentEpoch 变化（打开、确认、回滚）时按
/// preserveEditorHistory 选择保留历史地采纳候选，还是整篇重新装载。
final class EditorSessionAdapter extends ChangeNotifier {
  EditorSessionAdapter({
    required EditingSession session,
    required TextStyle style,
    double width = 760,
  }) : _session = session,
       _lastEpoch = session.contentEpoch,
       _client = EditorInputClient(
         session.body,
         width: width,
         style: style,
         inputBlocked: () => session.inputLocked,
         barrierEpoch: () => session.inputBarrierEpoch,
       ) {
    _session.addListener(_onSessionChanged);
    _client.addListener(_onClientChanged);
  }

  final EditingSession _session;
  final EditorInputClient _client;
  int _lastEpoch;

  /// 被适配的输入客户端；正文与撤销历史都由它持有。
  EditorInputClient get client => _client;

  /// 当前编辑会话；正文变化会转发到它的 edit 方法。
  EditingSession get session => _session;

  void _onSessionChanged() {
    if (_session.contentEpoch != _lastEpoch) {
      _lastEpoch = _session.contentEpoch;
      if (_session.preserveEditorHistory) {
        _client.adoptPersisted(_session.body);
      } else {
        _client.load(_session.body);
      }
      notifyListeners();
    }
  }

  void _onClientChanged() {
    final body = _client.document.raw;
    if (body != _session.body) {
      _session.edit(body);
    }
    notifyListeners();
  }

  /// 转发新宽度到输入客户端；宽度单位为逻辑像素。
  void updateWidth(double width) {
    _client.width(width);
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    _client.removeListener(_onClientChanged);
    _client.dispose();
    super.dispose();
  }
}
