// 输入客户端的剪贴板扩展（私有扩展 _EditorClipboard on EditorInputClient）。
//
// copy/cut/paste 都是异步操作：每次 await 之后必须重新核对输入代次、持久化栏栅代次
// 和正文快照，任何一项变化都放弃本次回写，避免把过期内容写进新正文。
// 只读时仅允许 copy；IME 组合期间全部拒绝。本扩展不直接改文档，统一走 replace。
part of 'editor_input_client.dart';

/// Clipboard completions are fenced by both content and persistence epochs.
///
/// 剪贴板操作以内容与持久化代次双重围栏：粘贴先读剪贴板再校验，剪切先写剪贴板
/// 再校验，任一 await 期间正文、只读状态或栏栅发生变化就取消本次变更。
/// 失败通过输入客户端的 error 暴露，不向调用方抛出异常。
extension _EditorClipboard on EditorInputClient {
  Future<void> _clipboard(String operation) async {
    if (composing || (readOnly && operation != 'copy')) return;
    final before = value;
    final generation = _inputGeneration;
    final barrier = _barrierEpoch?.call();
    try {
      if (operation == 'paste') {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        if (_disposed ||
            readOnly ||
            generation != _inputGeneration ||
            barrier != _barrierEpoch?.call()) {
          return;
        }
        if (value != before) {
          _failure('Paste cancelled: document changed while reading clipboard');
          return;
        }
        if (data != null) replace(data.text ?? '');
      } else {
        await Clipboard.setData(
          ClipboardData(text: before.selection.textInside(before.text)),
        );
        if (_disposed) return;
        if (operation == 'cut') {
          if (readOnly ||
              generation != _inputGeneration ||
              barrier != _barrierEpoch?.call()) {
            return;
          }
          if (value != before) {
            _failure('Cut cancelled: document changed while writing clipboard');
            return;
          }
          replace('');
        }
      }
    } catch (exception) {
      if (!_disposed) _failure('Clipboard $operation failed: $exception');
    }
  }
}
