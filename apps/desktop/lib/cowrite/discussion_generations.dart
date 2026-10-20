// 讨论生成运行态：生命周期属于 Registry，不随段下卡片收起或重建而丢失。
// 只操作显式预览/确认发送/取消接缝；不访问凭据，不把预览写入作者快照。
import 'package:flutter/foundation.dart';
import 'generation_repository.dart';

/// 单次请求阶段；finished 后不再持有外发材料。
enum DiscussionGenerationPhase { preparing, preview, sending, finished }

/// 一次生成的冻结作用域和作者指令；可变运行态仅由 owner 修改。
final class DiscussionGenerationRun {
  DiscussionGenerationRun({
    required this.work,
    required this.chapter,
    required this.thread,
    required this.draft,
    required this.outputLanguage,
  });

  /// 本次请求所属作品 ID，不随导航变化。
  final String work;

  /// 本次请求所属文档 ID。
  final String chapter;

  /// 本次请求所属线程 ID。
  final String thread;

  /// 发起预览时的作者指令，用于发送后判断能否清空草稿。
  final String draft;

  /// 已预览的输出语言标记。
  final String outputLanguage;
  DiscussionGenerationPhase _phase = DiscussionGenerationPhase.preparing;
  Map<String, dynamic>? _preview;
  String? _operation;
  bool _failed = false;
  bool _cancelRequested = false;
  bool _cancelAcknowledged = false;
  Future<void>? _cancelFlight;

  /// 仍在准备、等待确认或发送；收起面板不会改变此值。
  bool get running => _phase != DiscussionGenerationPhase.finished;

  /// 最近一次准备、发送或取消失败，供当前面板显示。
  bool get failed => _failed;

  /// 已请求取消，不能再发送预览票据。
  bool get cancelRequested => _cancelRequested;

  /// 服务端取消操作正在进行。
  bool get cancelling => _cancelFlight != null;

  /// 等待作者确认的完整预览；完成后释放，不持久化。
  Map<String, dynamic>? get preview => _preview;
}

/// 按作品/文档/线程管理运行态；同一线程至多一条在途请求。
final class DiscussionGenerations extends ChangeNotifier {
  DiscussionGenerations(this.source);

  /// 可选原生生成能力；没有能力时不能开始请求。
  final GenerationRepository? source;
  final _runs = <(String, String, String), DiscussionGenerationRun>{};
  String? _work, _chapter;
  bool _disposed = false;

  /// 当前线程的运行态；仅返回当前作品与文档的状态。
  DiscussionGenerationRun? forThread(String thread) =>
      _runs[(_work ?? '', _chapter ?? '', thread)];

  /// 导航成功后切换作用域；原生 activateScope 已负责取消旧作用域。
  void setScope(String? work, String? chapter) {
    if (_work == work && _chapter == chapter) return;
    for (final run in _runs.values) {
      run._cancelRequested = true;
    }
    _runs.clear();
    _work = work;
    _chapter = chapter;
    _emit();
  }

  /// 冻结作者指令后准备一次预览；不发送，同线程在途时返回 null。
  Future<DiscussionGenerationRun?> prepare({
    required String thread,
    required String draft,
    required String outputLanguage,
    required Future<Map<String, dynamic>?> Function() buildPreview,
  }) async {
    if (_disposed || source == null || _work == null || _chapter == null) {
      return null;
    }
    if (forThread(thread)?.running ?? false) return null;
    final run = DiscussionGenerationRun(
      work: _work!,
      chapter: _chapter!,
      thread: thread,
      draft: draft,
      outputLanguage: outputLanguage,
    );
    _runs[(run.work, run.chapter, run.thread)] = run;
    _emit();
    try {
      final preview = await buildPreview();
      if (preview == null) {
        _finish(run, failed: !run.cancelRequested);
        return null;
      }
      run._preview = Map<String, dynamic>.unmodifiable(preview);
      run._operation = preview['operationId'] as String;
      if (!_current(run) ||
          run.cancelRequested ||
          preview['workId'] != run.work ||
          preview['documentId'] != run.chapter) {
        await cancel(run);
        _finish(run);
        return null;
      }
      run._phase = DiscussionGenerationPhase.preview;
      _emit();
      return run;
    } catch (_) {
      _finish(run, failed: !run.cancelRequested);
      return null;
    }
  }

  /// 发送已经明确确认的预览一次；取消、过期或重复发送均返回 false。
  Future<bool> send(DiscussionGenerationRun run) async {
    final preview = run._preview;
    if (!_current(run) ||
        run.cancelRequested ||
        preview == null ||
        run._phase != DiscussionGenerationPhase.preview) {
      return false;
    }
    run._phase = DiscussionGenerationPhase.sending;
    _emit();
    try {
      await source!.send(run.work, preview['id'] as String, confirmed: true);
      return !run.cancelRequested;
    } catch (_) {
      run._failed = !run.cancelRequested;
      return false;
    } finally {
      _finish(run);
    }
  }

  /// 取消冻结的 operation；准备尚未返回时记住意图，拿到票据后再取消。
  Future<void> cancel(DiscussionGenerationRun run) {
    run._cancelRequested = true;
    _emit();
    if (source == null || run._operation == null || run._cancelAcknowledged) {
      return Future.value();
    }
    return run._cancelFlight ??= _cancelTicket(run).whenComplete(() {
      run._cancelFlight = null;
      _emit();
    });
  }

  Future<void> _cancelTicket(DiscussionGenerationRun run) async {
    try {
      await source!.cancel(run.work, run._operation!);
      run._cancelAcknowledged = true;
      if (run._phase == DiscussionGenerationPhase.preview) _finish(run);
    } catch (_) {
      run._failed = true;
    } finally {
      _emit();
    }
  }

  /// 操作投影刷新失败也必须可见；不清除草稿或重新发送。
  void recordFailure(DiscussionGenerationRun run) {
    run._failed = true;
    _emit();
  }

  bool _current(DiscussionGenerationRun run) =>
      !_disposed &&
      _work == run.work &&
      _chapter == run.chapter &&
      identical(_runs[(run.work, run.chapter, run.thread)], run);

  void _finish(DiscussionGenerationRun run, {bool failed = false}) {
    run._phase = DiscussionGenerationPhase.finished;
    run._failed = run._failed || failed;
    run._preview = null;
    _emit();
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final run in _runs.values) {
      run._cancelRequested = true;
    }
    _runs.clear();
    super.dispose();
  }
}
