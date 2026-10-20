// 资料目录状态机：按作品身份与请求 epoch 管理资料页签的 loading/data/error。
//
// 读边界：只通过注入的 loader 读取资料行，本文件不直接访问原生会话。
// 写边界：不写作品、不写资料库；仅维护呈现层快照。
// 关键不变量：旧 epoch、已切换作品或已 dispose 的请求完成/失败/清理都不能修改
// 当前状态，因此切换作品后不会出现旧作品资料冒充当前作品或 loading 卡死。
import 'dart:async';

import 'package:flutter/foundation.dart';

/// 资料行 loader：按作品 id 读取资料条目行，每行含 entry 与 head 对象。
typedef LoreLoader = Future<List<Map<String, dynamic>>> Function(String workId);

/// 侧栏资料目录的加载状态机。
///
/// [currentWorkId] 在每次 [sync] 时读取，作为资料集合的身份来源；
/// [loader] 负责实际读取，失败只记录 [errorCode] 而不向上抛出。
class LoreDirectory extends ChangeNotifier {
  /// 创建状态机；[loader] 读取资料行，[currentWorkId] 返回当前作品 id。
  LoreDirectory({required this.loader, required this.currentWorkId});

  /// 按作品读取资料行的注入点。
  final LoreLoader loader;

  /// 当前作品身份来源，无作品时返回 null。
  final String? Function() currentWorkId;

  List<Map<String, dynamic>> _rows = const [];
  bool _loading = false;
  String? _errorCode;
  String? _rowsWorkId;
  String? _settledWorkId;
  String? _inFlightWorkId;
  int _epoch = 0;
  bool _disposed = false;

  /// 最近一次成功读取的资料行；只会属于 [rowsWorkId]。
  List<Map<String, dynamic>> get rows => _rows;

  /// 当前作品是否正在读取资料。
  bool get loading => _loading;

  /// 最近一次读取失败的错误码；null 表示没有待重试的失败。
  String? get errorCode => _errorCode;

  /// [rows] 所属作品 id；没有成功数据时为 null。
  String? get rowsWorkId => _rowsWorkId;

  /// 同步当前作品：作品变化时立即失效旧请求并读取新作品，无作品时清空。
  ///
  /// [force] 为 true 时对当前作品显式重读（例如关闭资料库后刷新）；
  /// 同一作品已有在途请求时不会重复发起，避免状态通知放大成请求风暴。
  void sync({bool force = false}) {
    if (_disposed) return;
    final workId = currentWorkId();
    if (workId == null) {
      _reset();
      return;
    }
    if (workId == _inFlightWorkId) return;
    if (!force && workId == _settledWorkId) return;
    _start(workId);
  }

  /// 显式重试当前作品的资料读取；无作品时清空为初始状态。
  void retry() {
    if (_disposed) return;
    final workId = currentWorkId();
    if (workId == null) {
      _reset();
      return;
    }
    _start(workId);
  }

  /// 清空为初始状态（例如当前仓库不具备资料能力）；在途请求随之失效。
  void clear() {
    if (_disposed) return;
    _reset();
  }

  void _start(String workId) {
    final epoch = ++_epoch;
    _inFlightWorkId = workId;
    _settledWorkId = null;
    _rowsWorkId = null;
    _rows = const [];
    _loading = true;
    _errorCode = null;
    notifyListeners();
    unawaited(_load(workId, epoch));
  }

  Future<void> _load(String workId, int epoch) async {
    try {
      final rows = await loader(workId);
      // 旧请求、已切换作品或已销毁时直接丢弃，不碰新请求的 loading/data。
      if (!_isCurrent(epoch, workId)) return;
      _rows = List<Map<String, dynamic>>.unmodifiable(rows);
      _rowsWorkId = workId;
      _settledWorkId = workId;
      _inFlightWorkId = null;
      _loading = false;
      _errorCode = null;
      notifyListeners();
    } catch (_) {
      if (!_isCurrent(epoch, workId)) return;
      _rows = const [];
      _rowsWorkId = null;
      _settledWorkId = workId;
      _inFlightWorkId = null;
      _loading = false;
      _errorCode = 'lore_read_failed';
      notifyListeners();
    }
  }

  bool _isCurrent(int epoch, String workId) =>
      !_disposed && epoch == _epoch && currentWorkId() == workId;

  void _reset() {
    if (_loading ||
        _errorCode != null ||
        _rows.isNotEmpty ||
        _inFlightWorkId != null ||
        _settledWorkId != null ||
        _rowsWorkId != null) {
      _epoch++; // 让在途请求返回后不再修改状态
      _rows = const [];
      _rowsWorkId = null;
      _settledWorkId = null;
      _inFlightWorkId = null;
      _loading = false;
      _errorCode = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++; // 在途请求完成后直接丢弃，不再通知已销毁的界面
    super.dispose();
  }
}
