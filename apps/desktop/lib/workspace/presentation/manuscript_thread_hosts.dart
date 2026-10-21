// 段下讨论的展示状态与槽位协调，注册表仍是草稿和运行态的权威。
import 'dart:async';
import 'package:flutter/material.dart';
import '../../cowrite/discussion_thread.dart';
import '../../editor/editor_input_client.dart';
import '../../editor/editor_thread_slot.dart';
import '../workspace_controller.dart';

/// 同一时间只展开一个讨论槽位，收起保留草稿和注册表中的运行状态。
class ManuscriptThreadHosts extends ChangeNotifier {
  ManuscriptThreadHosts({
    required this.workspace,
    required this.client,
    required this.onReveal,
  });

  /// 当前作品会话，不在此组件创建仓库。
  final WorkspaceController workspace;

  /// 原始 UTF-16 编辑客户端，全部编辑走其合同。
  final EditorInputClient client;

  /// 下一帧让明确线程进入可见范围。
  final ValueChanged<String> onReveal;
  final Map<String, double> _heights = {};
  String? _activeId;
  String? _autofocusId;
  String _signature = '';
  bool _disposed = false;

  /// 当前唯一活动槽位身份。
  String? get activeId => _activeId;

  /// 新创建讨论首次展开时需要聚焦草稿的身份。
  String? get autofocusId => _autofocusId;

  /// 当前活动线程；失效身份不会猜测其它目标。
  DiscussionThread? get active =>
      _activeId == null ? null : workspace.discussions?.byId(_activeId!);

  /// 新正文身份不沿用上章展示态和测量缓存。
  void reset() {
    _activeId = null;
    _autofocusId = null;
    _heights.clear();
    _signature = '';
  }

  /// 只在槽位内容变化时更新排版，避免保存通知导致全文重排。
  void sync() {
    final registry = workspace.discussions;
    final threads = registry?.threads ?? const <DiscussionThread>[];
    if (_activeId != null &&
        !threads.any(
          (thread) =>
              thread.id == _activeId && !thread.isChapter && thread.valid,
        )) {
      final previous = _activeId;
      _activeId = null;
      if (registry?.activeThreadId == previous) registry?.setActiveThread(null);
    }
    final slots = <EditorThreadSlot>[
      for (final thread in threads)
        if (!thread.isChapter && thread.valid)
          EditorThreadSlot(
            id: thread.id,
            offset: thread.offset.clamp(0, client.length),
            height: thread.id == _activeId ? (_heights[thread.id] ?? 260) : 0,
          ),
    ];
    final signature = slots
        .map((slot) => '${slot.id}:${slot.offset}:${slot.height}')
        .join('|');
    if (_signature == signature) return;
    _signature = signature;
    client.layout.setThreadSlots(slots);
  }

  Future<void> _flush() async {
    final registry = workspace.discussions;
    if (registry == null) return;
    try {
      await registry.flush();
    } catch (error, stack) {
      // 注册表已经发布可重试错误；未知异常仍交给框架错误通道。
      if (registry.error == null) {
        FlutterError.reportError(
          FlutterErrorDetails(exception: error, stack: stack),
        );
      }
    }
  }

  /// 展开明确线程并恢复其精确选段；下一帧露出卡片。
  void activate(DiscussionThread thread, {bool focusDraft = false}) {
    final registry = workspace.discussions;
    if (_disposed || registry == null || thread.isChapter || !thread.valid) {
      return;
    }
    unawaited(_flush());
    _activeId = thread.id;
    _autofocusId = focusDraft ? thread.id : null;
    registry.setActiveThread(thread.id);
    sync();
    final anchor = thread.anchor;
    if (anchor != null) {
      final start = anchor.from.clamp(0, client.length);
      client.select(
        TextSelection(
          baseOffset: start,
          extentOffset: anchor.to.clamp(start, client.length),
        ),
      );
    }
    notifyListeners();
    _revealNextFrame(thread.id);
  }

  /// 只关闭展示，不取消生成或删除讨论，并把正文光标还给目标末尾。
  void collapse() {
    final registry = workspace.discussions;
    final thread = active;
    if (registry?.activeThreadId == thread?.id) registry?.setActiveThread(null);
    unawaited(_flush());
    _activeId = null;
    _autofocusId = null;
    sync();
    final anchor = thread?.anchor;
    if (anchor != null) {
      client.select(
        TextSelection.collapsed(offset: anchor.to.clamp(0, client.length)),
      );
    }
    client.focusNode.requestFocus();
    if (!_disposed) notifyListeners();
  }

  /// 超过半逻辑像素的高度变化才触发重排。
  void measured(String id, double height) {
    if (_disposed || id != _activeId) return;
    final previous = _heights[id];
    if (previous != null && (height - previous).abs() < 0.5) return;
    _heights[id] = height;
    sync();
    notifyListeners();
    _revealNextFrame(id);
  }

  void _revealNextFrame(String id) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && _activeId == id) onReveal(id);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
