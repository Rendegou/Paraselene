// 学习窗口的 WebView2 安全加固与资源白名单实现。
//
// 线程模型：全部在 UI 线程的 WebView2 回调中执行，回调捕获 weak_ptr 并校验 generation。
// 失败策略：加固任一步失败返回 HRESULT；资源或导航异常走 Fault，关闭会话而不是降级放行。
// 安全边界：禁用主机对象、Web 消息、DevTools、右键、脚本对话框、权限、下载与新窗口；
// 只允许 https://learning-sandbox.invalid 下的本地白名单资源，并下发严格 CSP。

#include "learning_window.h"
#include <shlwapi.h>
#include <array>
#include <utility>

using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;
// 宏：逐步检查 HRESULT，并在首个失败处返回错误码。
#define LEARNING_CHECK(call) do { const HRESULT checked = (call); if (FAILED(checked)) return checked; } while (false)
// 关闭所有非必要 WebView2 能力，注册资源、导航、新窗口、权限与下载拦截，
// 最后转交 WatchLifecycle 监听导航完成与进程失败。
HRESULT LearningWindow::Secure() {
  ComPtr<ICoreWebView2_13> with_profile;
  ComPtr<ICoreWebView2Profile> profile;
  ComPtr<ICoreWebView2Profile2> clearing;
  LEARNING_CHECK(webview_.As(&with_profile));
  LEARNING_CHECK(with_profile->get_Profile(&profile));
  LEARNING_CHECK(profile.As(&clearing));
  ComPtr<ICoreWebView2Settings> settings;
  LEARNING_CHECK(webview_->get_Settings(&settings));
  LEARNING_CHECK(settings->put_IsWebMessageEnabled(FALSE));
  LEARNING_CHECK(settings->put_AreHostObjectsAllowed(FALSE));
  LEARNING_CHECK(settings->put_AreDevToolsEnabled(FALSE));
  LEARNING_CHECK(settings->put_AreDefaultContextMenusEnabled(FALSE));
  LEARNING_CHECK(settings->put_AreDefaultScriptDialogsEnabled(FALSE));
  ComPtr<ICoreWebView2_22> filtering;
  // Older runtimes without worker-inclusive filtering cannot run learner code.
  LEARNING_CHECK(webview_.As(&filtering));
  LEARNING_CHECK(filtering->AddWebResourceRequestedFilterWithRequestSourceKinds(
      L"*", COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL, COREWEBVIEW2_WEB_RESOURCE_REQUEST_SOURCE_KINDS_ALL));
  const auto weak = weak_from_this();
  const auto generation = generation_;
  EventRegistrationToken token;
  LEARNING_CHECK(webview_->add_WebResourceRequested(Callback<ICoreWebView2WebResourceRequestedEventHandler>(
    [weak, generation](ICoreWebView2*, ICoreWebView2WebResourceRequestedEventArgs* args) {
      const auto self = weak.lock();
      if (!self) return E_ABORT;
      const bool active = self->generation_ == generation && !self->cleaning_;
      if (FAILED(self->Resource(args, active))) self->Fault();
      return S_OK;
    }).Get(), &token));
  LEARNING_CHECK(webview_->add_NavigationStarting(Callback<ICoreWebView2NavigationStartingEventHandler>(
    [weak, generation](ICoreWebView2*, ICoreWebView2NavigationStartingEventArgs* args) {
      LPWSTR uri = nullptr; const HRESULT status = args->get_Uri(&uri);
      const auto self = weak.lock();
      const bool allowed = SUCCEEDED(status) && self && uri &&
          ((self->generation_ == generation && self->page_ == uri) ||
           (self->cleaning_ && std::wstring(uri) == L"about:blank"));
      CoTaskMemFree(uri); return args->put_Cancel(!allowed);
    }).Get(), &token));
  // 拒绝新窗口、权限授予、下载与外部导航，避免沙箱页面获得宿主能力。
  LEARNING_CHECK(webview_->add_NewWindowRequested(Callback<ICoreWebView2NewWindowRequestedEventHandler>(
    [](ICoreWebView2*, ICoreWebView2NewWindowRequestedEventArgs* args) { return args->put_Handled(TRUE); }).Get(), &token));
  LEARNING_CHECK(webview_->add_PermissionRequested(Callback<ICoreWebView2PermissionRequestedEventHandler>(
    [](ICoreWebView2*, ICoreWebView2PermissionRequestedEventArgs* args) { return args->put_State(COREWEBVIEW2_PERMISSION_STATE_DENY); }).Get(), &token));
  ComPtr<ICoreWebView2_4> downloads;
  LEARNING_CHECK(webview_.As(&downloads));
  LEARNING_CHECK(downloads->add_DownloadStarting(Callback<ICoreWebView2DownloadStartingEventHandler>(
    [](ICoreWebView2*, ICoreWebView2DownloadStartingEventArgs* args) { return args->put_Cancel(TRUE); }).Get(), &token));
  return WatchLifecycle();
}
// 只在同一会话代际内响应；导航成功且 HTTP 200 才 Complete，其余情况 Fault。
HRESULT LearningWindow::WatchLifecycle() {
  const auto weak = weak_from_this();
  const auto generation = generation_;
  EventRegistrationToken token;
  LEARNING_CHECK(webview_->add_NavigationCompleted(Callback<ICoreWebView2NavigationCompletedEventHandler>(
    [weak, generation](ICoreWebView2*, ICoreWebView2NavigationCompletedEventArgs* args) {
      const auto self = weak.lock(); if (!self || self->generation_ != generation) return S_OK;
      BOOL success = FALSE;
      ComPtr<ICoreWebView2NavigationCompletedEventArgs2> response;
      int http_status = 0;
      const bool loaded = SUCCEEDED(args->get_IsSuccess(&success)) && success &&
          SUCCEEDED(args->QueryInterface(IID_PPV_ARGS(&response))) &&
          SUCCEEDED(response->get_HttpStatusCode(&http_status)) && http_status == 200;
      if (loaded) self->Complete(S_OK); else self->Fault();
      return S_OK;
    }).Get(), &token));
  LEARNING_CHECK(webview_->add_ProcessFailed(Callback<ICoreWebView2ProcessFailedEventHandler>(
    [weak, generation](ICoreWebView2*, ICoreWebView2ProcessFailedEventArgs*) {
      if (const auto self = weak.lock(); self && self->generation_ == generation) self->Fault(); return S_OK;
    }).Get(), &token));
  return S_OK;
}

// 只为白名单内的 GET 资源提供本地文件与 MIME；其它请求返回 403 与严格 CSP 头。
HRESULT LearningWindow::Resource(ICoreWebView2WebResourceRequestedEventArgs* args, bool allow_assets) {
  static const std::array<std::pair<const wchar_t*, const wchar_t*>, 12> assets = {{
    {L"index.html", L"text/html; charset=utf-8"}, {L"index-en.html", L"text/html; charset=utf-8"},
    {L"learning.js", L"text/javascript"}, {L"learning-en.js", L"text/javascript"},
    {L"learning.css", L"text/css"}, {L"worker.js", L"text/javascript"}, {L"worker-en.js", L"text/javascript"},
    {L"pyodide/pyodide.mjs", L"text/javascript"}, {L"pyodide/pyodide.asm.mjs", L"text/javascript"},
    {L"pyodide/pyodide.asm.wasm", L"application/wasm"}, {L"pyodide/pyodide-lock.json", L"application/json"},
    {L"pyodide/python_stdlib.zip", L"application/zip"}
  }};
  ComPtr<ICoreWebView2WebResourceRequest> request;
  LEARNING_CHECK(args->get_Request(&request));
  LPWSTR raw_uri = nullptr, raw_method = nullptr;
  LEARNING_CHECK(request->get_Uri(&raw_uri));
  const std::wstring uri = raw_uri ? raw_uri : L""; CoTaskMemFree(raw_uri);
  LEARNING_CHECK(request->get_Method(&raw_method));
  const bool get = raw_method && std::wstring(raw_method) == L"GET"; CoTaskMemFree(raw_method);
  ComPtr<IStream> stream;
  std::wstring mime;
  for (const auto& asset : assets) {
    // 清理阶段 allow_assets 为 false，所有请求直接 403，阻断残留 Worker。
    if (!allow_assets) break;
    if (!get || uri != std::wstring(L"https://learning-sandbox.invalid/") + asset.first) continue;
    const auto path = assets_ + asset.first;
    LEARNING_CHECK(SHCreateStreamOnFileEx(path.c_str(), STGM_READ | STGM_SHARE_DENY_WRITE,
          FILE_ATTRIBUTE_NORMAL, FALSE, nullptr, &stream));
    mime = asset.second;
    break;
  }
  const std::wstring headers = L"Content-Security-Policy: default-src 'none'; script-src 'self' 'wasm-unsafe-eval'; worker-src blob:; connect-src https://learning-sandbox.invalid; style-src 'self'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-store\r\nContent-Type: " + mime;
  ComPtr<ICoreWebView2WebResourceResponse> response;
  LEARNING_CHECK(environment_->CreateWebResourceResponse(stream.Get(), stream ? 200 : 403,
      stream ? L"OK" : L"Blocked", headers.c_str(), &response));
  return args->put_Response(response.Get());
}
#undef LEARNING_CHECK
