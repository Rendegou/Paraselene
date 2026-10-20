// 正文出处标记控制器：异步读取当前章节正文的资料出处标记并发布给编辑器装饰。
// 关键不变量：过期请求或旧 epoch 结果不得发布；head 变化或偏移非法时清空标记并置失败。
// 纯 Dart 控制器，不写库、不修改正文。

import 'package:flutter/foundation.dart';
import '../editor/editor_source_mark.dart';

/// 出处标记读取接缝：返回 headVersion 与 marks，供编辑器绘制资料标记。
abstract interface class SourceMarkRepository {
  /// 读取指定作品/章节正文的出处标记；body 用于与记录时的正文比对。
  Future<Map<String, dynamic>> sourceMarks(
    String work,
    String chapter,
    String body,
  );
}

/// 可注入的出处读取宿主：仓库实现该接口即可让编辑器读取来源装饰。
///
/// 真实仓库通过 [RealWorkspaceRepository.lore] 暴露读取器；合成测试仓库实现
/// 本接口即可注入受控的 loading/empty/error 响应，而不必伪造整个真实仓库。
abstract interface class SourceMarkHost {
  /// 出处标记读取器；生命周期由宿主仓库持有。
  SourceMarkRepository get sourceMarks;
}

/// 出处装饰的可见状态；正文区据此区分加载中、无出处、失败与有内容。
enum SourceMarkState {
  /// 当前作用域正在读取出处。
  loading,

  /// 当前作用域读取失败，需要显式重试。
  error,

  /// 当前作用域读取成功但没有出处标记。
  empty,

  /// 当前作用域有可绘制的出处标记。
  content,
}

/// Stale asynchronous reads cannot publish decorations for another document/body.
///
/// 过期异步读取不能给其它文档/正文发布装饰：只有 work/chapter/head/body
/// 四元身份全部匹配已发布结果时，[visible] 才返回标记。
final class SourceMarkController extends ChangeNotifier {
  SourceMarkController(this.repository);
  final SourceMarkRepository repository;
  int _epoch = 0;
  bool _closed = false;

  bool _loading = false;
  bool _loaded = false;
  bool _failed = false;

  String? _work, _chapter, _head, _body;
  List<EditorSourceMark> _marks = const [];

  /// 最近一次加载是否仍在进行；用于区分 loading 与 empty 状态。
  bool get loading => _loading;

  /// 最近一次加载是否已经结束（成功或失败）；首次请求前为 false。
  bool get loaded => _loaded;

  /// 最近一次加载是否失败；失败时已发布标记被清空。
  bool get failed => _failed;

  /// 当前作用域的出处状态；调用方须确保调用前已用当前正文发起 [load]。
  SourceMarkState stateFor(
    String? work,
    String? chapter,
    String? head,
    String body,
  ) {
    if (_loading) return SourceMarkState.loading;
    if (_failed) return SourceMarkState.error;
    if (!_loaded) return SourceMarkState.loading;
    return visible(work, chapter, head, body).isEmpty
        ? SourceMarkState.empty
        : SourceMarkState.content;
  }

  /// 仅当四元身份完全匹配已发布结果时返回标记，否则返回空列表。
  List<EditorSourceMark> visible(
    String? work,
    String? chapter,
    String? head,
    String body,
  ) => work == _work && chapter == _chapter && head == _head && body == _body
      ? _marks
      : const [];

  /// 加载正文的出处标记。
  ///
  /// 以 epoch 丢弃过期结果；返回的 headVersion 与传入 [head] 不一致视为 head 已变化，
  /// 偏移非法则整批拒绝。失败时清空标记并置 [failed]，不修改正文、不写库。
  Future<void> load(
    String work,
    String chapter,
    String? head,
    String body,
  ) async {
    final epoch = ++_epoch;
    _loading = true;
    _loaded = false;
    _failed = false;
    _marks = const [];
    notifyListeners();
    try {
      final result = await repository.sourceMarks(work, chapter, body);
      if (_closed || epoch != _epoch) return;
      if (result['headVersion'] != head) {
        // 正文 head 已变化时，按旧正文计算的标记不再可信。
        throw StateError('source_head_changed');
      }
      final marks = <EditorSourceMark>[];
      for (final row in result['marks'] as List) {
        final from = (row as Map)['from'] as int;
        final to = row['to'] as int;
        if (from < 0 || from >= to || to > body.length) {
          // 偏移必须落在当前正文内，否则整批标记都拒绝发布。
          throw StateError('invalid_source');
        }
        marks.add(
          EditorSourceMark(
            entryId: row['entryId'] as String,
            name: row['name'] as String,
            from: from,
            to: to,
          ),
        );
      }
      _work = work;
      _chapter = chapter;
      _head = head;
      _body = body;
      _marks = List.unmodifiable(marks);
      _loaded = true;
    } catch (_) {
      if (!_closed && epoch == _epoch) {
        _marks = const [];
        _failed = true;
        _loaded = true;
      }
    } finally {
      if (!_closed && epoch == _epoch) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  /// Invalidate even in-flight requests on an empty directory or scope transition.
  ///
  /// 递增 epoch 使在途请求作废，并清空已发布身份与标记；不写库。
  void clear() {
    ++_epoch;
    _loading = false;
    _loaded = false;
    _failed = false;
    _marks = const [];
    _work = null;
    _chapter = null;
    _head = null;
    _body = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    ++_epoch;
    super.dispose();
  }
}
