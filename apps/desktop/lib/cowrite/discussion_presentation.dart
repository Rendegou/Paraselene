// 讨论展示快照与动作接口：把稳定编辑宿主和无状态视图解耦。
// 只传递已有线程投影与回调；不持有数据库、计时器或编辑控制器。
import 'package:flutter/foundation.dart';
import 'discussion_thread.dart';

/// 一次重建所需的讨论状态，业务写入仍由工作区与 Registry 负责。
class DiscussionPresentation {
  const DiscussionPresentation({
    required this.thread,
    required this.operations,
    required this.title,
    required this.status,
    required this.outputLanguage,
    required this.running,
    required this.cancelling,
    required this.failed,
    required this.busy,
    required this.inDialog,
    required this.compare,
    required this.history,
    required this.applyFailed,
    required this.canGenerate,
    required this.canReference,
    required this.saveFailed,
  });

  /// 当前真实线程，包含冻结目标和未发送草稿。
  final DiscussionThread thread;

  /// 当前线程的服务端操作只读投影。
  final List<Map<String, dynamic>> operations;

  /// 已按冻结引文生成的展示标题。
  final String title;

  /// 有效性说明；整章线程为空字符串。
  final String status;

  /// 本次生成运行态或下一份草稿的输出语言。
  final String outputLanguage;

  /// 是否存在仍可取消的生成操作。
  final bool running;

  /// 是否已发起取消，当前不应重复提交取消。
  final bool cancelling;

  /// 最近生成是否失败。
  final bool failed;

  /// 工作区是否暂时禁止写入。
  final bool busy;

  /// 是否由对话框提供外部表面。
  final bool inDialog;

  /// 是否展开候选对比。
  final bool compare;

  /// 是否展开历史投影。
  final bool history;

  /// 最近采纳是否失败且需要提示。
  final bool applyFailed;

  /// 仓库是否支持完整预览与显式确认的生成流程。
  final bool canGenerate;

  /// 是否可从真实资料仓库选择引用。
  final bool canReference;

  /// Registry 是否保留线程写入失败状态。
  final bool saveFailed;
}

/// 作者操作接口；异步动作由原编辑宿主执行并处理失败。
class DiscussionPanelActions {
  const DiscussionPanelActions({
    required this.onCollapse,
    required this.onRetry,
    required this.onDraft,
    required this.onLanguage,
    required this.onReferences,
    required this.onGenerate,
    required this.onCancel,
    required this.onCompare,
    required this.onHistory,
    required this.onApply,
    required this.onReject,
  });

  /// 收起段下讨论或关闭对话框。
  final VoidCallback? onCollapse;

  /// 重试保存；失败仍通过 Registry 状态提示。
  final AsyncCallback onRetry;

  /// 修改未发送草稿，不写入作者正文。
  final ValueChanged<String> onDraft;

  /// 改变下一次生成的输出语言。
  final ValueChanged<String> onLanguage;

  /// 打开资料选择并保留原讨论目标。
  final AsyncCallback onReferences;

  /// 开始完整预览及显式确认流程。
  final AsyncCallback onGenerate;

  /// 取消已有生成操作。
  final AsyncCallback onCancel;

  /// 展开或收起候选比较。
  final VoidCallback onCompare;

  /// 展开或收起历史记录。
  final VoidCallback onHistory;

  /// 采纳指定持久操作；失败由宿主显示。
  final Future<void> Function(String) onApply;

  /// 拒绝指定持久操作。
  final Future<void> Function(String) onReject;
}
