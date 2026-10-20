// FlutterWindow 声明：主窗口承载 Flutter 视图，并持有原生关闭守卫、伴侣窗口与学习窗口。
//
// 线程模型：所有成员只在 UI 线程创建、使用和销毁，构造与析构都不跨线程。
// 所有权：flutter_controller_、close_guard_、companion_ 由本类独占；learning_ 以 shared_ptr
// 管理，使 WebView2 异步回调可以通过 weak_ptr 观察其生命周期，关闭时先 Close 再 reset。
// 关闭顺序：学习窗口 -> 伴侣窗口 -> 关闭守卫 -> Flutter 控制器，最后交给基类销毁 HWND。
// 失败策略：OnCreate 任一步失败返回 false，主窗口创建整体失败。

#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "win32_window.h"
#include "native_close_guard.h"
#include "companion_window.h"
#include "learning_window.h"

// 主窗口：把 Flutter 视图嵌入 Win32 子窗口，并在其之上处理关闭确认、伴侣托盘与学习窗口。
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  // 只保存 Dart 工程引用；HWND、引擎与子窗口都在 OnCreate 中创建。
  explicit FlutterWindow(const flutter::DartProject& project);
  // 析构前必须已执行 OnDestroy；此处不重复释放引擎或 HWND 资源。
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  // 创建 Flutter 控制器与视图、注册插件，并建立关闭守卫、伴侣窗口和学习窗口。
  bool OnCreate() override;
  // 按固定顺序释放各子对象，再交给基类销毁窗口；子对象释放顺序不可调换。
  void OnDestroy() override;
  // 先于 Flutter 插件拦截关闭守卫与伴侣消息；返回 0 表示消息已被消费。
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  // Dart 入口与参数；构造后不再修改。
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  // Flutter 引擎与视图的唯一持有者，必须早于 HWND 销毁释放。
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  // 关闭确认守卫；先于 Flutter 生命周期插件处理 WM_CLOSE。
  std::unique_ptr<NativeCloseGuard> close_guard_;
  // 本地伴侣窗口；随主窗口销毁释放，不访问网络或作者数据。
  std::unique_ptr<CompanionWindow> companion_;
  // 学习窗口共享指针；关闭时先 Close 再释放，避免 WebView2 回调悬空。
  std::shared_ptr<LearningWindow> learning_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
