// 编辑器与顶层工具栏之间的动作注册表：编辑器注册查找、讨论与选区状态，
// 工具栏只读取并触发；不持有业务数据、不写库。
import 'package:flutter/foundation.dart';

import '../../cowrite/discussion_thread.dart';
import '../../editor/editor_input_client.dart';

/// 工具栏动作桥。
///
/// 编辑器挂载时注册自身回调与选区信息，卸载时清空；工具栏在自身构建期
/// 通过 [ListenableBuilder] 读取，不跨会话保存任何状态。
final class EditorActionRegistry extends ChangeNotifier {
  /// 当前编辑器输入客户端；工具栏上的“绑定出处”等动作需要它。
  EditorInputClient? editor;

  /// 打开章内查找。
  VoidCallback? onFind;

  /// 查找栏当前是否打开，用于按钮按下态。
  bool findOpen = false;

  /// 打开/创建全章讨论。
  VoidCallback? onChapterDiscussion;

  /// 打开已有讨论（滚动到宿主或打开全章讨论对话框）。
  ValueChanged<DiscussionThread>? onOpenThread;

  /// 讨论当前选区。
  VoidCallback? onDiscussSelection;

  /// 重新读取正文出处装饰（失败时也可用于重试）。
  VoidCallback? onRefreshSources;

  /// 当前章节的全部讨论线程，供“讨论记录 · N”读取。
  List<DiscussionThread> threads = const [];

  /// 当前选区包含的 Unicode 码点数；0 表示没有选区。
  int selectedCodePoints = 0;

  /// 工作区忙碌时工具栏动作应禁用。
  bool busy = false;

  /// 是否有可讨论的选区。
  bool get canDiscuss => selectedCodePoints > 0 && !busy;

  /// 注册编辑器回调；编辑器重建时重复调用是安全的。
  void bind({
    required EditorInputClient? editor,
    required VoidCallback? onFind,
    required VoidCallback? onChapterDiscussion,
    required ValueChanged<DiscussionThread>? onOpenThread,
    required VoidCallback? onDiscussSelection,
    required VoidCallback? onRefreshSources,
  }) {
    this.editor = editor;
    this.onFind = onFind;
    this.onChapterDiscussion = onChapterDiscussion;
    this.onOpenThread = onOpenThread;
    this.onDiscussSelection = onDiscussSelection;
    this.onRefreshSources = onRefreshSources;
  }

  /// 注销当前编辑器，避免工具栏持有已释放的输入客户端。
  void unbind(EditorInputClient editor) {
    if (this.editor != editor) return;
    this.editor = null;
    onFind = null;
    onChapterDiscussion = null;
    onOpenThread = null;
    onDiscussSelection = null;
    onRefreshSources = null;
    threads = const [];
    selectedCodePoints = 0;
  }

  /// 更新查找栏打开状态。
  void setFindOpen(bool value) {
    if (findOpen == value) return;
    findOpen = value;
    notifyListeners();
  }

  /// 更新选区长度（按 Unicode 码点，与章节字数口径一致）。
  void setSelection(int codePoints) {
    if (selectedCodePoints == codePoints) return;
    selectedCodePoints = codePoints;
    notifyListeners();
  }

  /// 更新讨论线程列表。
  void setThreads(List<DiscussionThread> next) {
    if (listEquals(threads, next)) return;
    threads = next;
    notifyListeners();
  }

  /// 更新忙碌状态。
  void setBusy(bool value) {
    if (busy == value) return;
    busy = value;
    notifyListeners();
  }
}
