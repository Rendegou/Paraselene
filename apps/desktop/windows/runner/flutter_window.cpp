// FlutterWindow 实现：创建 Flutter 视图与各原生子窗口，并按固定顺序处理消息与关闭。
//
// 线程模型：所有窗口消息、引擎回调与方法通道都在 UI 线程执行。
// 所有权：控制器、关闭守卫、伴侣窗口由本类释放；Flutter 子窗口 HWND 交给 Win32Window 管理。
// 关闭顺序：学习窗口 -> 伴侣窗口 -> 关闭守卫 -> Flutter 控制器 -> 基类 DestroyWindow。
// 失败策略：OnCreate 任一步失败返回 false，由 Win32Window::Create 整体判败。

#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

// 只保存 Dart 工程引用；窗口与引擎在 Create/OnCreate 阶段建立。
FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

// 资源已在 OnDestroy 中释放；析构保持为空，避免重复释放。
FlutterWindow::~FlutterWindow() {}

// 创建 Flutter 控制器并注册插件，再创建关闭守卫、伴侣窗口与学习窗口，
// 最后把 Flutter 视图挂进窗口树；控制器缺少引擎或视图时立即失败。
bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  close_guard_ = std::make_unique<NativeCloseGuard>(
      flutter_controller_->engine()->messenger());
  companion_ = std::make_unique<CompanionWindow>(GetHandle(), flutter_controller_->engine()->messenger());
  learning_ = std::make_shared<LearningWindow>(flutter_controller_->engine()->messenger());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

// 按学习窗口 -> 伴侣窗口 -> 关闭守卫 -> Flutter 控制器的顺序释放，最后交给基类。
// 先启动 WebView2 清理，再释放 Flutter 引擎，避免原生回调晚于引擎销毁。
void FlutterWindow::OnDestroy() {
  // 先关闭学习窗口并释放共享引用，确保其 WebView2 清理不晚于引擎销毁。
  if (learning_) learning_->Close();
  learning_.reset();
  companion_.reset();
  close_guard_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
// 关闭守卫优先于 Flutter 插件处理 WM_CLOSE；伴侣窗口只消费托盘与任务栏重建消息。
// 其余消息交给 Flutter 引擎，最后回落到 Win32Window 的默认处理。
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Always intercept before Flutter's lifecycle manager and modal-dialog plugins.
  // 关闭确认必须在 Flutter 生命周期插件之前，避免原生关闭绕过未保存确认。
  if (close_guard_ && close_guard_->HandleMessage(hwnd, message)) return 0;
  // 伴侣窗口只消费自己的托盘与任务栏消息，其余返回 false 继续分发。
  if (companion_ && companion_->HandleMessage(message, wparam, lparam)) return 0;
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    // 系统字体变化时让引擎重新加载字体，保持排版与原生字体一致。
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
