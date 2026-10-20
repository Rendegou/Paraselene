// 原生关闭守卫声明：在 Flutter 插件处理 WM_CLOSE 之前拦截关闭请求。
//
// 线程模型：方法由 UI 线程的窗口过程调用；方法通道回调也由引擎在 UI 线程分发。
// 状态：enabled 由 Dart 侧显式启用；pending/approved 防止重复确认与重入。
// 关闭顺序：Dart 批准后投递自定义消息，在消息循环里销毁窗口，而不是在引擎回调内销毁。

#ifndef RUNNER_NATIVE_CLOSE_GUARD_H_
#define RUNNER_NATIVE_CLOSE_GUARD_H_
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>
#include <memory>

// Own WM_CLOSE before engine/plugin handlers, including after modal file dialogs.
// 接管 WM_CLOSE：启用后先向 Dart 请求确认，批准后才真正 DestroyWindow；
// 未启用或非 WM_CLOSE 消息返回 false，交回窗口过程。
class NativeCloseGuard {
 public:
  // 绑定 paraselene/native_close 通道；只有 Dart 调用 enable 后才开始拦截。
  explicit NativeCloseGuard(flutter::BinaryMessenger* messenger);
  // 置状态失效并解除通道回调，晚到的引擎结果会被丢弃。
  ~NativeCloseGuard();
  // 处理已批准关闭与 WM_CLOSE；返回 true 表示消息已被消费。
  bool HandleMessage(HWND window, UINT message);

 private:
  // 与异步结果共享的状态；alive 防止回调访问已析构的守卫。
  struct State {
    bool enabled = false;
    bool pending = false;
    bool approved = false;
    bool alive = true;
  };
  // shared_ptr 让引擎回调安全地观察守卫生命周期。
  std::shared_ptr<State> state_ = std::make_shared<State>();
  // 与 Dart 的关闭确认通道；析构时移除回调。
  flutter::MethodChannel<flutter::EncodableValue> channel_;
};
#endif
