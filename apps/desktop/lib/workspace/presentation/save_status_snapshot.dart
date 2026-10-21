// 保存状态只读投影：把 coordinator/controller 的真实状态转为界面所需事实。
// 不订阅、不写库；错误码仅用于本地化展示，保留草稿基线差异。
import '../../domain/editing/save_coordinator.dart';
import '../workspace_controller.dart';
import 'workbench_chrome.dart';

/// 一帧保存状态快照；不持有正文，也不改变保存或冲突状态。
final class SaveStatusSnapshot {
  const SaveStatusSnapshot._(this.status, this.errorCode, this.restoredDraft);

  /// 从当前工作区提取状态，保存层错误优先于控制器的一般错误。
  factory SaveStatusSnapshot.of(WorkspaceController controller) {
    final state = controller.editing.saveState;
    return SaveStatusSnapshot._(
      state?.status,
      state?.errorCode ?? controller.errorCode,
      state != null && state.baseHead != state.head,
    );
  }

  /// 实际保存状态；无活动章时可能为空。
  final SaveStatus? status;

  /// 可显示的稳定错误码，不含正文或私人路径。
  final String? errorCode;

  /// 当前草稿基线是否与正式 head 不同。
  final bool restoredDraft;

  /// 是否需要显示恢复动作；冲突也保留完整恢复出口。
  bool get hasError =>
      errorCode != null ||
      status == SaveStatus.error ||
      status == SaveStatus.conflict;

  /// 是否没有可展示的保存事实。
  bool get isEmpty => status == null && errorCode == null && !restoredDraft;

  /// 按当前界面语言描述状态，正常空状态返回空串。
  String statusText(WorkbenchLabels labels) {
    final s = labels.strings;
    return labels(switch (status) {
      SaveStatus.dirty => s.saveDirty,
      SaveStatus.saving => s.saveSaving,
      SaveStatus.saved => s.saveSaved,
      SaveStatus.conflict => s.saveConflict,
      SaveStatus.error => s.saveError,
      null => hasError ? s.saveError : '',
    });
  }

  /// 为紧凑入口提供完整状态、恢复基线与错误说明。
  String description(WorkbenchLabels labels) => [
    statusText(labels),
    if (restoredDraft) labels(labels.strings.draftRestoredBase),
    if (errorCode != null)
      labels(labels.strings.errorCode('\u2068$errorCode\u2069')),
  ].where((part) => part.isNotEmpty).join('；');
}
