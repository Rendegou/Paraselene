// 学习窗口声明：独立的 InPrivate WebView2 浏览器，用于本地离线学习沙箱。
//
// 线程模型：窗口、WebView2 回调与方法通道都在 UI 线程，没有后台线程。
// 所有权：window_ 由 Shutdown 销毁；COM 接口由 ComPtr 持有并在 Shutdown 重置；
// profile_pins_ 用目录句柄把 WebView2 数据目录钉在确定的合成路径上。
// 关闭顺序：取消挂起请求并隐藏窗口，清空浏览数据与 Workers，再关控制器与 HWND；
// 15 秒定时器为初始化与清理兜底。
// 安全边界：独立 profile、禁用主机对象/消息/DevTools/下载/权限，只放行本机打包素材。

#ifndef RUNNER_LEARNING_WINDOW_H_
#define RUNNER_LEARNING_WINDOW_H_
#include <windows.h>
#include <WebView2.h>
#include <wrl.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <memory>
#include <string>
#include <vector>

// Separate browser/profile. No host objects, web messaging or user-code IPC.
// 学习窗口：按 Dart 请求创建 InPrivate WebView2，加载本地沙箱页面并只放行白名单资源；
// 打开与关闭都通过方法通道返回稳定错误码，失败不降级为放行。
class LearningWindow : public std::enable_shared_from_this<LearningWindow> {
 public:
  // 注册 paraselene/learning/v1；只接受 locale 为 en/zh-Hans 的 open 请求。
  explicit LearningWindow(flutter::BinaryMessenger* messenger);
  // 解除通道回调，关闭挂起请求并释放 WebView2 与 HWND。
  ~LearningWindow();
  // 幂等关闭：取消挂起结果、清空浏览数据与 Workers，超时兜底强制清理。
  void Close();
 private:
#ifdef PARASELENE_LEARNING_PROBE
  friend class LearningProbe;
  friend class LearningChannelProbe;
#endif
  // 注册窗口类并创建普通窗口；失败返回 false。
  bool Create(const std::wstring& title);
  // 启动一次学习会话：校验并发与清理状态，创建窗口与专用 profile 后异步建 WebView2。
  void Open(const std::string& locale, const std::wstring& title,
            std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  // 收紧 WebView2 设置并注册资源、导航、权限与下载拦截；失败返回 HRESULT。
  HRESULT Secure();
  // 监听导航完成与进程失败；只有 HTTP 200 的成功导航才 Complete。
  HRESULT WatchLifecycle();
  // 在 TEMP 下校验并钉住目录，只创建或复用带标记的专用缓存目录。
  bool PrepareProfile();
  // 使用 InPrivate 与 IsolatedLearning profile 创建控制器并绑定窗口。
  HRESULT CreateController(ICoreWebView2Environment* environment, uint64_t generation);
  // 有挂起请求时先失败返回；否则关闭窗口并通过通道上报 learning_unavailable。
  void Fault();
  // 只对白名单 GET 资源返回本地内容，其余一律 403；同时下发严格 CSP。
  HRESULT Resource(ICoreWebView2WebResourceRequestedEventArgs* args, bool allow_assets);
  // 兑现挂起请求：失败先关闭窗口；成功时同步边界、显示窗口并返回成功。
  void Complete(HRESULT status);
  // 统一释放：关控制器、重置 COM 与目录钉、销毁窗口；可重复调用。
  void Shutdown();
  // 清理完成回调：只有同一代清理才生效，失败标记 cleanup_failed_ 并上报。
  void FinishCleanup(uint64_t generation, HRESULT status);
  // 窗口过程：关闭走受控清理，75/76 定时器分别处理初始化与清理超时。
  static LRESULT CALLBACK Proc(HWND, UINT, WPARAM, LPARAM);
  // 学习窗口 HWND；由 Shutdown 销毁，异步回调中先判空。
  HWND window_ = nullptr;
  // 会话代际：打开与关闭都递增，晚到的 WebView2 回调按代际丢弃。
  uint64_t generation_ = 0;
  // 是否处于异步清理流程，期间拒绝新的打开请求。
  bool cleaning_ = false;
  // 清理失败后置位，后续打开返回 learning_cleanup_failed，避免复用残留 profile。
  bool cleanup_failed_ = false;
  // 目录句柄集合：析构时关闭全部句柄；共享指针把钉住状态延长到清理回调之后。
  struct ProfilePins {
    std::vector<HANDLE> handles;
    ~ProfilePins() { for (const auto handle : handles) CloseHandle(handle); }
  };
  // 清理回调捕获共享指针，确保 WebView2 关闭前目录身份持续被钉住。
  std::shared_ptr<ProfilePins> profile_pins_;
  // 本地素材目录、专用用户数据目录与当前沙箱入口 URL。
  std::wstring assets_, profile_, page_;
  // WebView2 COM 对象；Shutdown 中按 webview、controller、environment 顺序重置。
  Microsoft::WRL::ComPtr<ICoreWebView2Environment> environment_;
  Microsoft::WRL::ComPtr<ICoreWebView2Controller> controller_;
  Microsoft::WRL::ComPtr<ICoreWebView2> webview_;
  // 尚未完成的 open 请求；同一时间至多一个。
  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> pending_;
  // paraselene/learning/v1 方法通道；析构时解除回调。
  flutter::MethodChannel<flutter::EncodableValue> channel_;
};
#endif
