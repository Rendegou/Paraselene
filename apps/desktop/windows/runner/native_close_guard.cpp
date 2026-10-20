// 原生关闭守卫实现：WM_CLOSE 先询问 Dart，批准后在独立消息里销毁窗口。
//
// 线程模型：通道调用与窗口消息都在 UI 线程执行，没有跨线程共享。
// 失败策略：Dart 返回失败或投递批准消息失败时清除 approved，窗口保持不关闭。
// 安全边界：只做关闭确认，不读写正文或持久化数据。

#include "native_close_guard.h"
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>

namespace {
  // 自定义消息：把真正的 DestroyWindow 挪出引擎回调，避免重入。
constexpr UINT kApprovedClose = WM_APP + 42;
}

// 注册 enable 方法；其它方法一律 NotImplemented，不额外暴露能力。
NativeCloseGuard::NativeCloseGuard(flutter::BinaryMessenger* messenger)
    : channel_(messenger, "paraselene/native_close",
               &flutter::StandardMethodCodec::GetInstance()) {
  channel_.SetMethodCallHandler([state = state_](const auto& call, auto result) {
    if (call.method_name() == "enable") {
      state->enabled = true;
      result->Success(flutter::EncodableValue(true));
    } else {
      result->NotImplemented();
    }
  });
}

// 先标记状态失效再解除回调，晚到的引擎结果会被忽略。
NativeCloseGuard::~NativeCloseGuard() {
  state_->alive = false;
  channel_.SetMethodCallHandler(nullptr);
}

// 已批准时销毁窗口；否则在启用状态下拦截 WM_CLOSE 并只发起一次确认。
bool NativeCloseGuard::HandleMessage(HWND window, UINT message) {
  if (message == kApprovedClose && state_->approved) {
    state_->approved = false;
    DestroyWindow(window);
    return true;
  }
  if (message != WM_CLOSE || !state_->enabled) return false;
  // pending 期间重复的 WM_CLOSE 直接吞掉，避免叠加确认请求。
  if (state_->pending) return true;
  state_->pending = true;
  auto state = state_;
  channel_.InvokeMethod("requestClose", nullptr,
      std::make_unique<flutter::MethodResultFunctions<flutter::EncodableValue>>(
          [state, window](const auto* value) {
            if (!state->alive) return;
            state->pending = false;
            const auto* approved = value ? std::get_if<bool>(value) : nullptr;
            if (approved && *approved) {
              state->approved = true;
              // Destroy outside the engine response callback to avoid reentrancy.
              // 投递失败时撤回批准，窗口保持打开，不留下不一致状态。
              if (!PostMessage(window, kApprovedClose, 0, 0)) state->approved = false;
            }
          },
          [state](const auto&, const auto&, const auto*) { state->pending = false; },
          [state]() { state->pending = false; }));
  return true;
}
