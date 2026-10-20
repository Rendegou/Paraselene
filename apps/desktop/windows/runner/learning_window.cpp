// 学习窗口实现：方法通道请求、窗口创建、WebView2 环境/控制器创建、资源拦截与关闭清理。
//
// 线程模型：方法通道回调与 WebView2 异步回调都在 UI 线程；
// 用 weak_ptr 与代际号丢弃晚到回调，避免访问已释放对象。
// 所有权：窗口 HWND 由 Shutdown 销毁；WebView2 COM 对象由 ComPtr 持有；
// profile_pins_ 通过回调捕获延长到清理完成。
// 关闭顺序：取消挂起结果 -> 隐藏窗口 -> Navigate(about:blank) -> ClearBrowsingDataAll ->
// Shutdown（关控制器、重置 COM、销毁 HWND）；15 秒定时器兜底。
// 失败策略：所有失败都以 E_FAIL 或 learning_unavailable/learning_cleanup_failed 上报，不降级放行。

#include "learning_window.h"
#include <flutter/standard_method_codec.h>
#include <WebView2EnvironmentOptions.h>
#include <vector>

using Microsoft::WRL::Callback;
namespace {
// 从 EncodableMap 读取可选字符串字段；缺失或类型不符返回空串。
std::string Field(const flutter::EncodableMap& map, const char* key) {
  const auto item = map.find(flutter::EncodableValue(key));
  if (item == map.end()) return "";
  const auto* value = std::get_if<std::string>(&item->second);
  return value ? *value : "";
}
// UTF-8 到 UTF-16 转换；长度非法或超过 80 个字符时返回空串。
std::wstring Wide(const std::string& input) {
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, input.data(), static_cast<int>(input.size()), nullptr, 0);
  if (length <= 0 || length > 80) return L"";
  std::wstring result(length, 0);
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, input.data(), static_cast<int>(input.size()), result.data(), length);
  return result;
}
}
// 注册 open 方法；locale 只接受 en/zh-Hans，其它请求返回 invalid_learning_request。
LearningWindow::LearningWindow(flutter::BinaryMessenger* messenger)
    : channel_(messenger, "paraselene/learning/v1", &flutter::StandardMethodCodec::GetInstance()) {
  channel_.SetMethodCallHandler([this](const auto& call, auto result) {
    const auto* map = call.arguments() ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
    if (call.method_name() != "open" || !map) { result->Error("invalid_learning_request"); return; }
    const auto locale = Field(*map, "locale");
    const auto title = Wide(Field(*map, "title"));
    if ((locale != "en" && locale != "zh-Hans") || title.empty()) { result->Error("invalid_learning_request"); return; }
    Open(locale, title, std::move(result));
  });
}
// 解除回调后执行 Close 与 Shutdown，确保析构不遗留 WebView2 与 HWND。
LearningWindow::~LearningWindow() { channel_.SetMethodCallHandler(nullptr); Close(); Shutdown(); }
// 注册并创建学习窗口；窗口类已存在时复用，创建失败返回 false。
bool LearningWindow::Create(const std::wstring& title) {
  WNDCLASSW type{}; type.lpfnWndProc = Proc; type.hInstance = GetModuleHandle(nullptr);
  type.lpszClassName = L"ParaseleneLearningV1"; type.hCursor = LoadCursor(nullptr, IDC_ARROW);
  if (!RegisterClassW(&type) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) return false;
  window_ = CreateWindowExW(0, type.lpszClassName, title.c_str(), WS_OVERLAPPEDWINDOW,
      CW_USEDEFAULT, CW_USEDEFAULT, 800, 680, nullptr, nullptr, type.hInstance, this);
  return window_ != nullptr;
}
// 处理忙与清理失败等前置条件，创建窗口与专用 profile，再异步创建 WebView2 环境；
// 15 秒定时器保证初始化不会无限挂起。
void LearningWindow::Open(const std::string& locale, const std::wstring& title,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (pending_ || cleaning_) { result->Error("learning_busy"); return; }
  if (cleanup_failed_) { result->Error("learning_cleanup_failed"); return; }
  if (controller_) { ShowWindow(window_, SW_RESTORE); SetForegroundWindow(window_); result->Success(); return; }
  if (!Create(title)) { result->Error("learning_unavailable"); return; }
  pending_ = std::move(result);
  if (!SetTimer(window_, 75, 15000, nullptr)) { Complete(E_FAIL); return; }
  page_ = locale == "en" ? L"https://learning-sandbox.invalid/index-en.html" : L"https://learning-sandbox.invalid/index.html";
  std::vector<wchar_t> path(32768);
  const DWORD size = GetModuleFileNameW(nullptr, path.data(), static_cast<DWORD>(path.size()));
  if (!size || size >= path.size()) { Complete(E_FAIL); return; }
  const std::wstring executable(path.data(), size);
  assets_ = executable.substr(0, executable.find_last_of(L"\\")) + L"\\data\\flutter_assets\\assets\\learning\\";
  if (!PrepareProfile()) { Complete(E_FAIL); return; }
  // No custom browser flags, external arguments, shared author profile or IPC bridge.
  const auto weak = weak_from_this();
  const auto pins = profile_pins_;
  const auto generation = ++generation_;
  auto options = Microsoft::WRL::Make<CoreWebView2EnvironmentOptions>();
  if (FAILED(options->put_ExclusiveUserDataFolderAccess(TRUE))) { Complete(E_FAIL); return; }
  const HRESULT status = CreateCoreWebView2EnvironmentWithOptions(nullptr, profile_.c_str(), options.Get(),
    Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>([weak, generation, pins](HRESULT error, ICoreWebView2Environment* environment) {
      (void)pins;  // Keep profile identity pinned through a late completion.
      const auto self = weak.lock(); if (!self) return S_OK;
      if (self->generation_ != generation) return S_OK;
      if (FAILED(error) || !environment || !self->window_) { self->Complete(E_FAIL); return S_OK; }
      const auto created = self->CreateController(environment, generation);
      if (FAILED(created)) self->Complete(created);
      return S_OK;
    }).Get());
  if (FAILED(status)) Complete(status);
}
// 用 InPrivate 与 IsolatedLearning profile 创建控制器，成功后加固安全设置并导航到沙箱页。
HRESULT LearningWindow::CreateController(ICoreWebView2Environment* environment, uint64_t generation) {
  environment_ = environment;
  Microsoft::WRL::ComPtr<ICoreWebView2Environment10> private_environment;
  HRESULT status = environment_.As(&private_environment);
  Microsoft::WRL::ComPtr<ICoreWebView2ControllerOptions> options;
  if (SUCCEEDED(status)) status = private_environment->CreateCoreWebView2ControllerOptions(&options);
  if (SUCCEEDED(status)) status = options->put_ProfileName(L"IsolatedLearning");
  if (SUCCEEDED(status)) status = options->put_IsInPrivateModeEnabled(TRUE);
  if (FAILED(status)) return status;
  const auto weak = weak_from_this();
  const auto pins = profile_pins_;
  return private_environment->CreateCoreWebView2ControllerWithOptions(window_, options.Get(),
    Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>([weak, generation, pins](HRESULT failure, ICoreWebView2Controller* controller) {
      (void)pins;
      const auto current = weak.lock(); if (!current) return S_OK;
      if (current->generation_ != generation) { if (controller) controller->Close(); return S_OK; }
      if (FAILED(failure) || !controller || !current->window_) { current->Complete(E_FAIL); return S_OK; }
      current->controller_ = controller;
      HRESULT configured = controller->get_CoreWebView2(&current->webview_);
      if (SUCCEEDED(configured)) configured = current->Secure();
      if (SUCCEEDED(configured)) configured = current->webview_->Navigate(current->page_.c_str());
      if (FAILED(configured)) current->Complete(configured);
      return S_OK;
    }).Get());
}
// 有挂起请求时按失败返回；否则关闭窗口并通过通道上报 learning_unavailable。
void LearningWindow::Fault() {
  if (pending_) { Complete(E_FAIL); return; }
  Close();
  channel_.InvokeMethod("fault", std::make_unique<flutter::EncodableValue>("learning_unavailable"));
}
// 兑现挂起请求：失败先关闭窗口；成功时同步控制器边界并显示窗口。
void LearningWindow::Complete(HRESULT status) {
  if (!pending_) return;
  if (window_) KillTimer(window_, 75);
  auto result = std::move(pending_);
  if (FAILED(status)) { Close(); result->Error("learning_unavailable"); return; }
  RECT bounds{}; GetClientRect(window_, &bounds); controller_->put_Bounds(bounds);
  ShowWindow(window_, SW_SHOW); result->Success();
}
// 幂等关闭：有 WebView2 时先异步清空浏览数据与 Workers，再由 Shutdown 收尾；
// 缺少 Profile2 接口视为清理失败，绝不静默复用 profile。
void LearningWindow::Close() {
  if (cleaning_) return;
  const auto generation = ++generation_;
  if (pending_) { auto result = std::move(pending_); result->Error("learning_closed"); }
  if (webview_) {
    Microsoft::WRL::ComPtr<ICoreWebView2_13> with_profile;
    Microsoft::WRL::ComPtr<ICoreWebView2Profile> profile;
    Microsoft::WRL::ComPtr<ICoreWebView2Profile2> clearing;
    if (SUCCEEDED(webview_.As(&with_profile)) && SUCCEEDED(with_profile->get_Profile(&profile)) && SUCCEEDED(profile.As(&clearing))) {
      cleaning_ = true;
      ShowWindow(window_, SW_HIDE);
      KillTimer(window_, 75);
      if (!SetTimer(window_, 76, 15000, nullptr)) { FinishCleanup(generation, E_FAIL); return; }
      // The InPrivate profile becomes invalid when its last controller closes.
      // Keep it alive until clearing finishes; Shutdown closes it on success,
      // failure or the bounded cleanup timer.
      // Blank the document to end its workers. Resource callbacks continue to
      // return local 403s while this asynchronous navigation/cleanup completes.
      if (FAILED(webview_->Navigate(L"about:blank"))) { FinishCleanup(generation, E_FAIL); return; }
      const auto weak = weak_from_this();
      const auto pins = profile_pins_;
      const HRESULT started = clearing->ClearBrowsingDataAll(Callback<ICoreWebView2ClearBrowsingDataCompletedHandler>(
        [weak, clearing, generation, pins](HRESULT status) {
          (void)pins;
          if (const auto self = weak.lock()) self->FinishCleanup(generation, status);
          return S_OK;
        }).Get());
      if (FAILED(started)) FinishCleanup(generation, started);
      return;
    }
    cleanup_failed_ = true;
    channel_.InvokeMethod("fault", std::make_unique<flutter::EncodableValue>("learning_cleanup_failed"));
  }
  Shutdown();
}
// 只有同一代清理才生效；按清理结果标记 cleanup_failed_，再统一 Shutdown。
void LearningWindow::FinishCleanup(uint64_t generation, HRESULT status) {
  if (!cleaning_ || generation_ != generation) return;
  cleanup_failed_ = FAILED(status);
  Shutdown();
  if (FAILED(status)) channel_.InvokeMethod("fault", std::make_unique<flutter::EncodableValue>("learning_cleanup_failed"));
}
// 统一释放顺序：控制器 -> COM 接口 -> 目录钉 -> HWND；
// InPrivate 数据随控制器关闭失效，专用缓存目录保留复用。
void LearningWindow::Shutdown() {
  ++generation_;
  cleaning_ = false;
  if (controller_) controller_->Close();
  webview_.Reset(); controller_.Reset(); environment_.Reset();
  profile_pins_.reset();
  if (window_) { const HWND window = window_; window_ = nullptr; DestroyWindow(window); }
  // InPrivate browser storage ends with its controller; the single marked cache
  // directory is reused. No per-open directory accumulation or recursive delete.
}
// 学习窗口过程：WM_CLOSE 走受控清理，75/76 定时器分别处理初始化与清理超时。
LRESULT CALLBACK LearningWindow::Proc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  auto* self = reinterpret_cast<LearningWindow*>(GetWindowLongPtr(window, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    self = static_cast<LearningWindow*>(reinterpret_cast<CREATESTRUCT*>(lparam)->lpCreateParams);
    SetWindowLongPtr(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
  }
  if (!self) return DefWindowProc(window, message, wparam, lparam);
  if (message == WM_CLOSE) { self->Close(); return 0; }
  if (message == WM_TIMER && wparam == 75) { self->Fault(); return 0; }
  if (message == WM_TIMER && wparam == 76) { self->FinishCleanup(self->generation_, E_FAIL); return 0; }
  if (message == WM_SIZE && self->controller_) {
    RECT bounds{}; GetClientRect(window, &bounds); self->controller_->put_Bounds(bounds); return 0;
  }
  return DefWindowProc(window, message, wparam, lparam);
}
