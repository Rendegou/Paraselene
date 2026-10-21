// 讨论线程注册表：按作品/章节加载作者快照与服务端操作，去抖后串行保存。
// 关键不变量：保存带 CAS revision；失败保留未保存快照；晚到的加载结果不得覆盖另一章节；
// 服务端操作只作为投影缓存，作者快照持久化时剔除服务端派生字段。

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../editor/editor_anchor.dart';
import '../workspace/data/workspace_repository.dart';
import 'discussion_repository.dart';
import 'discussion_thread.dart';
import 'generation_repository.dart';
import 'discussion_generations.dart';

/// Serial durable author snapshots; late loads never replace another chapter.
///
/// 按作品/章节管理作者快照与服务端操作投影：修改先去抖再串行保存，
/// 保存使用 revision 做 CAS；晚到的加载结果因 epoch 变化被丢弃。
final class DiscussionRegistry extends ChangeNotifier {
  DiscussionRegistry(this.repository) {
    generations = DiscussionGenerations(
      repository is GenerationRepository
          ? repository as GenerationRepository
          : null,
    )..addListener(_emit);
  }
  final DiscussionRepository repository;

  /// 生成运行态由注册表持有，不随讨论面板的挂载生命周期变化。
  late final DiscussionGenerations generations;
  String? _activeThreadId;

  /// 当前正在查看的讨论目标；没有活动讨论时为 null。
  String? get activeThreadId => _activeThreadId;

  /// 选择当前讨论目标，仅改展示状态，不创建线程或写入作者快照。
  void setActiveThread(String? id) {
    if (id == _activeThreadId || _disposed) return;
    if (id != null && byId(id) == null) {
      throw const WorkspaceFailure('discussion_context_conflict');
    }
    _activeThreadId = id;
    _emit();
  }

  String? work;
  String? chapter;
  String? error;
  bool loading = false;
  bool _disposed = false;
  int _epoch = 0;
  List<DiscussionThread> _threads = [];
  List<Map<String, dynamic>> _operations = [];
  Future<void>? _saving;
  Timer? _timer;

  /// 当前章节的线程只读视图；每次访问返回不可修改列表。
  List<DiscussionThread> get threads => List.unmodifiable(_threads);

  /// 当前章节的服务端操作投影只读视图。
  List<Map<String, dynamic>> get operations => List.unmodifiable(_operations);

  /// 是否存在尚未成功落盘的线程修改。
  bool get dirty => _threads.any((thread) => thread.dirty);

  /// Loads all discussion data before publishing a new chapter identity.
  ///
  /// 切换作品/章节前先 flush 旧章节；加载完成前不发布新身份，epoch 变化后丢弃晚到结果。
  /// 加载失败记录 discussion_load_failed 并向上抛出，不保留半加载状态。
  Future<void> open(String? nextWork, String? nextChapter) async {
    if (work == nextWork && chapter == nextChapter) return;
    await flush();
    final epoch = ++_epoch;
    loading = true;
    _emit();
    try {
      final rows = nextWork == null || nextChapter == null
          ? <Map<String, dynamic>>[]
          : await repository.listThreads(nextWork, nextChapter);
      final operations = nextWork == null || nextChapter == null
          ? <Map<String, dynamic>>[]
          : await repository.listOperations(nextWork, nextChapter);
      if (_disposed || epoch != _epoch) return;
      if (repository case final GenerationRepository generation) {
        await generation.activateScope(nextWork, nextChapter);
      }
      if (_disposed || epoch != _epoch) return;
      work = nextWork;
      chapter = nextChapter;
      _threads = rows.map(DiscussionThread.fromRow).toList();
      _operations = operations;
      _activeThreadId = null;
      generations.setScope(nextWork, nextChapter);
      error = null;
    } catch (_) {
      if (!_disposed && epoch == _epoch) error = 'discussion_load_failed';
      rethrow;
    } finally {
      if (!_disposed && epoch == _epoch) {
        loading = false;
        _emit();
      }
    }
  }

  /// Creates a globally unique author thread; no operation or request is sent.
  ///
  /// 生成 16 字节安全随机 ID 并插入当前章节；只改内存并安排保存，不发送生成请求。
  DiscussionThread create(EditorAnchor anchor) {
    final thread = DiscussionThread.create(_newId(), _openChapterId(), anchor);
    _threads.add(thread);
    _changed();
    return thread;
  }

  /// Returns the single whole-chapter thread, creating it only when absent.
  /// No model request is sent; generation still needs a selection.
  ///
  /// 每章最多一个整章讨论；它没有冻结选段，因此只能讨论，不能生成候选。
  DiscussionThread chapterThread() {
    for (final thread in _threads) {
      if (thread.isChapter) return thread;
    }
    final thread = DiscussionThread.createChapter(_newId(), _openChapterId());
    _threads.add(thread);
    _changed();
    return thread;
  }

  /// 按线程 ID 查找当前章节的线程；不存在时返回 null。
  DiscussionThread? byId(String id) {
    for (final thread in _threads) {
      if (thread.id == id) return thread;
    }
    return null;
  }

  String _openChapterId() {
    // 未打开章节或仍在加载时不允许创建线程。
    final current = chapter;
    if (current == null || loading) {
      throw const WorkspaceFailure('no_open_chapter');
    }
    return current;
  }

  String _newId() {
    // 16 字节加密随机数，作为跨设备的线程全局 ID。
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  /// 更新线程草稿并递增本地代数；文本未变化时忽略，不触发保存。
  void editDraft(String id, String draft) {
    final thread = _threads.firstWhere((thread) => thread.id == id);
    if (thread.draft == draft) return;
    thread.update({'draft': draft});
    _changed();
  }

  /// References are explicit IDs; Rust freezes confirmed versions at preview.
  ///
  /// 引用为显式资料条目 ID，最多 32 个且不可重复；非法输入抛
  /// [WorkspaceFailure]（错误码 invalid_input）。版本冻结发生在预览阶段。
  void attachReferences(String id, List<String> references) {
    if (references.length > 32 ||
        references.toSet().length != references.length) {
      throw const WorkspaceFailure('invalid_input');
    }
    _threads.firstWhere((thread) => thread.id == id).update({
      'attached': List<String>.of(references),
    });
    _changed();
  }

  /// Live coordinates are separate from frozen source; invalidity survives edits.
  ///
  /// 用正文 before→after 的一次连续替换更新各线程活动坐标；
  /// 冻结选段不变，映射失败只把 valid 置为 false，且不会被后续编辑重置。
  void mapBody(String before, String after) {
    if (before == after) return;
    for (final thread in _threads) {
      final next = thread.anchor?.map(before, after);
      if (next != null) {
        thread.update({
          'anchor': {'from': next.from, 'to': next.to, 'valid': next.valid},
        });
      }
    }
    _changed();
  }

  void _changed() {
    // 去抖 350 毫秒合并连续输入，减少原生写入次数。
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 350), () {
      unawaited(_flushInBackground());
    });
    _emit();
  }

  Future<void> _flushInBackground() async {
    try {
      await flush();
    } catch (failure) {
      // 去抖计时器是后台 Future 的最终所有者：保留脏稿与可重试错误，
      // 并记录脱敏诊断；显式 flush 的调用方仍收到原异常。
      error = 'discussion_save_failed';
      debugPrint('discussion_background_save_failed: ${failure.runtimeType}');
      _emit();
    }
  }

  /// Coalesces mutations during writes; failure keeps every unsaved snapshot.
  ///
  /// 返回当前写入 Future 供上层等待；写入期间的修改由循环继续消费。
  /// 失败时记录 discussion_save_failed 并向上抛出，脏快照不会丢失。
  Future<void> flush() {
    _timer?.cancel();
    return _saving ??= _flush().whenComplete(() => _saving = null);
  }

  Future<void> _flush() async {
    final currentWork = work;
    final currentChapter = chapter;
    if (currentWork == null || currentChapter == null) return;
    try {
      // 一次写入期间可能产生新修改，循环直到没有脏线程。
      while (dirty) {
        final thread = _threads.firstWhere((thread) => thread.dirty);
        final generation = thread.generation;
        final saved = await repository.saveThread(
          currentWork,
          currentChapter,
          thread.id,
          thread.revision,
          thread.persistenceSnapshot(),
        );
        thread.revision = saved['revision'] as int;
        thread.savedGeneration = generation;
      }
      error = null;
    } catch (_) {
      error = 'discussion_save_failed';
      rethrow;
    } finally {
      _emit();
    }
  }

  /// Refresh projections after apply/reject. Author drafts remain untouched.
  ///
  /// 重新读取服务端操作投影；作者草稿与线程快照不因此改变，旧 epoch 结果丢弃。
  Future<void> refreshOperations() async {
    final epoch = _epoch;
    final currentWork = work;
    final currentChapter = chapter;
    if (currentWork == null || currentChapter == null) return;
    final next = await repository.listOperations(currentWork, currentChapter);
    if (!_disposed && epoch == _epoch) {
      _operations = next;
      _emit();
    }
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _timer?.cancel();
    generations.removeListener(_emit);
    generations.dispose();
    super.dispose();
  }
}
