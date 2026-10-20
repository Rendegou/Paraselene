// 伴侣窗口的“安静”判定实现：综合 Windows 通知状态与专注会话决定是否隐藏桌宠。
//
// 线程模型：在伴侣窗口的定时器回调（UI 线程）中调用，COM/WinRT 调用属于当前单元。
// 失败策略：单个来源失败返回 nullopt，调用方沿用上一次判定，绝不把未知当成“不安静”。
// 安全边界：只读取系统状态，不访问用户文档、凭据或网络。

#include "companion_quiet.h"
#include <windows.h>
#include <shellapi.h>
#include <winrt/Windows.UI.Shell.h>

// 通知状态命中演示/全屏/忙碌，或专注会话开启时返回 true；
// 两个来源都明确为 false 才返回 false；其余返回 nullopt 表示未知。
std::optional<bool> CompanionQuiet() {
  QUERY_USER_NOTIFICATION_STATE state;
  std::optional<bool> shell;
  if (SUCCEEDED(SHQueryUserNotificationState(&state))) {
    shell = state == QUNS_NOT_PRESENT || state == QUNS_BUSY ||
            state == QUNS_RUNNING_D3D_FULL_SCREEN || state == QUNS_PRESENTATION_MODE;
  }
  std::optional<bool> focus;
  try {
    using winrt::Windows::UI::Shell::FocusSessionManager;
    focus = FocusSessionManager::IsSupported()
                ? FocusSessionManager::GetDefault().IsFocusActive() : false;
  } catch (const winrt::hresult_error&) {
    // Retry next poll, retaining the previous decision on transient failures.
  }
  if (shell == true || focus == true) return true;
  if (shell == false && focus == false) return false;
  return std::nullopt;
}
