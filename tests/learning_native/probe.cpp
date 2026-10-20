#include "learning_window.h"
#include <WebView2EnvironmentOptions.h>
#include <flutter/method_result_functions.h>
#include <functional>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>

using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;
namespace {
std::string Utf8(const std::wstring& value) {
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
  std::string result(size, 0);
  WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), result.data(), size, nullptr, nullptr);
  return result;
}
void Require(bool ok, const char* label) {
  if (!ok) throw std::runtime_error(label);
  std::cout << "PASS " << label << std::endl;
}
bool PumpUntil(const std::function<bool()>& done, DWORD timeout = 15000) {
  const auto start = GetTickCount64();
  while (!done() && GetTickCount64() - start < timeout) {
    MSG message;
    while (PeekMessage(&message, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&message); DispatchMessage(&message);
    }
    MsgWaitForMultipleObjects(0, nullptr, FALSE, 20, QS_ALLINPUT);
  }
  return done();
}
class ProbeMessenger : public flutter::BinaryMessenger {
 public:
  mutable int faults = 0;
  void Send(const std::string&, const uint8_t*, size_t, flutter::BinaryReply reply) const override {
    ++faults; if (reply) reply(nullptr, 0);
  }
  void SetMessageHandler(const std::string&, flutter::BinaryMessageHandler) override {}
};
}

// Only this separately compiled executable has friend access. It uses the
// shipping profile, controller, resource firewall and lifecycle implementations.
// No native window is shown and no host-to-page test API ships in the app.
class LearningProbe {
 public:
  LearningProbe() : window_(std::make_shared<LearningWindow>(&messenger_)) {}
  ~LearningProbe() { window_->Close(); PumpUntil([&] { return !window_->cleaning_; }); }
  void Open(const std::wstring& assets, const wchar_t* page) {
    Require(window_->Create(L"Synthetic isolated learning probe"), "hidden HWND");
    window_->assets_ = assets + L"\\";
    std::cout << "ASSETS " << Utf8(window_->assets_) << std::endl;
    Require(GetFileAttributesW((window_->assets_ + page).c_str()) != INVALID_FILE_ATTRIBUTES, "entry asset exists");
    window_->page_ = std::wstring(L"https://learning-sandbox.invalid/") + page;
    Require(window_->PrepareProfile(), "dedicated pinned profile");
    const auto generation = ++window_->generation_;
    auto ready = std::make_shared<bool>(false);
    auto result = std::make_shared<HRESULT>(E_PENDING);
    auto options = Microsoft::WRL::Make<CoreWebView2EnvironmentOptions>();
    Require(SUCCEEDED(options->put_ExclusiveUserDataFolderAccess(TRUE)), "exclusive profile option");
    const auto weak = window_->weak_from_this();
    const auto pins = window_->profile_pins_;
    Require(SUCCEEDED(CreateCoreWebView2EnvironmentWithOptions(nullptr, window_->profile_.c_str(), options.Get(),
      Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
        [weak, pins, generation, ready, result](HRESULT status, ICoreWebView2Environment* environment) {
          (void)pins;
          const auto current = weak.lock();
          if (!current || current->generation_ != generation) return S_OK;
          *result = FAILED(status) || !environment ? E_FAIL : current->CreateController(environment, generation);
          *ready = true; return S_OK;
        }).Get())), "environment start");
    Require(PumpUntil([&] { return *ready; }) && SUCCEEDED(*result), "environment complete");
    LPWSTR version = nullptr;
    if (SUCCEEDED(window_->environment_->get_BrowserVersionString(&version))) {
      std::cout << "RUNTIME " << Utf8(version) << std::endl; CoTaskMemFree(version);
    }
    Require(PumpUntil([&] { return window_->webview_ != nullptr; }), "controller created");
    Require(SUCCEEDED(window_->controller_->put_IsVisible(FALSE)), "controller hidden");
    EventRegistrationToken diagnostic;
    window_->webview_->add_NavigationCompleted(Callback<ICoreWebView2NavigationCompletedEventHandler>(
      [](ICoreWebView2*, ICoreWebView2NavigationCompletedEventArgs* args) {
        BOOL ok = FALSE; COREWEBVIEW2_WEB_ERROR_STATUS error{};
        args->get_IsSuccess(&ok); args->get_WebErrorStatus(&error);
        std::cout << "NAV success=" << ok << " error=" << error << std::endl; return S_OK;
      }).Get(), &diagnostic);
    const auto worker_denied = worker_denied_;
    window_->webview_->add_WebResourceRequested(Callback<ICoreWebView2WebResourceRequestedEventHandler>(
      [worker_denied](ICoreWebView2*, ICoreWebView2WebResourceRequestedEventArgs* args) {
        ComPtr<ICoreWebView2WebResourceRequest> request;
        LPWSTR uri = nullptr;
        if (SUCCEEDED(args->get_Request(&request)) && SUCCEEDED(request->get_Uri(&uri))) {
          std::cout << "RESOURCE " << Utf8(uri) << std::endl;
          ComPtr<ICoreWebView2WebResourceResponse> response;
          int status = 0;
          if (std::wstring(uri) == L"https://learning-sandbox.invalid/worker-denied" &&
            SUCCEEDED(args->get_Response(&response)) && response &&
            SUCCEEDED(response->get_StatusCode(&status)) && status == 403) ++*worker_denied;
          CoTaskMemFree(uri);
        }
        return S_OK;
      }).Get(), &diagnostic);
    Require(Poll(L"document.readyState === 'complete' && !!document.getElementById('run')"), "real local page loaded");
    Require(!IsWindowVisible(window_->window_), "no visible native window");
    ComPtr<ICoreWebView2_13> view;
    ComPtr<ICoreWebView2Profile> profile;
    BOOL in_private = FALSE;
    Require(SUCCEEDED(window_->webview_.As(&view)) && SUCCEEDED(view->get_Profile(&profile)) &&
      SUCCEEDED(profile->get_IsInPrivateModeEnabled(&in_private)) && in_private, "InPrivate confirmed");
  }
  std::wstring Eval(const std::wstring& script) {
    struct Result { bool done = false; HRESULT status = E_PENDING; std::wstring json; };
    auto result = std::make_shared<Result>();
    const auto scheduled = window_->webview_ ? window_->webview_->ExecuteScript(script.c_str(),
      Callback<ICoreWebView2ExecuteScriptCompletedHandler>([result](HRESULT status, LPCWSTR value) {
        result->status = status; result->json = value ? value : L"null";
        result->done = true; return S_OK;
      }).Get()) : E_POINTER;
    if (FAILED(scheduled)) throw std::runtime_error("script scheduled");
    if (!PumpUntil([&] { return result->done; }) || FAILED(result->status)) throw std::runtime_error("script completion");
    return result->json;
  }
  bool Poll(const std::wstring& condition, DWORD timeout = 15000) {
    const auto start = GetTickCount64();
    while (GetTickCount64() - start < timeout) {
      if (Eval(condition) == L"true") return true;
      const auto until = GetTickCount64() + 100;
      PumpUntil([&] { return GetTickCount64() >= until; }, 200);
    }
    return false;
  }
  void Exercise(const std::wstring& escaped_code, bool success = true) {
    Eval(L"document.getElementById('code').value = " + escaped_code + L"; document.getElementById('run').click(); true");
    Require(Poll(L"!document.getElementById('run').disabled", 45000), "worker completes or timeout terminates");
    std::cout << "STATUS " << Utf8(Eval(L"document.getElementById('status').textContent"))
      << " DETAIL " << Utf8(Eval(L"document.getElementById('result').textContent")) << std::endl;
    Require(Eval(L"document.getElementById('status').textContent.startsWith('3 / 3')") ==
      (success ? L"true" : L"false"), success ? "Python expected values" : "non-success not forged");
  }
  void Boundaries();
  void InteractiveBoundaries();
  void Geolocation() {
    Require(SUCCEEDED(window_->controller_->put_IsVisible(TRUE)) && !IsWindowVisible(window_->window_),
      "geolocation controller active inside hidden native parent");
    Require(Poll(L"document.visibilityState === 'visible'"), "geolocation document visible to browser");
    auto requests = std::make_shared<int>(0);
    auto denied = std::make_shared<bool>(true);
    EventRegistrationToken token;
    Require(SUCCEEDED(window_->webview_->add_PermissionRequested(
      Callback<ICoreWebView2PermissionRequestedEventHandler>(
        [requests, denied](ICoreWebView2*, ICoreWebView2PermissionRequestedEventArgs* args) {
          COREWEBVIEW2_PERMISSION_KIND kind{};
          COREWEBVIEW2_PERMISSION_STATE state{};
          ++*requests;
          if (FAILED(args->get_PermissionKind(&kind)) || kind != COREWEBVIEW2_PERMISSION_KIND_GEOLOCATION ||
              FAILED(args->get_State(&state)) || state != COREWEBVIEW2_PERMISSION_STATE_DENY) *denied = false;
          return S_OK;
        }).Get(), &token)),
      "geolocation native observer");
    Eval(L"window.__geolocation = null; navigator.geolocation.getCurrentPosition(() => window.__geolocation = {escaped:true}, e => window.__geolocation = {code:e.code,message:e.message}); true");
    const bool completed = Poll(L"window.__geolocation !== null");
    std::cout << "GEOLOCATION native_requests=" << *requests << " result=" << Utf8(Eval(L"window.__geolocation")) << std::endl;
    Require(completed, "geolocation completed");
    Require(Eval(L"window.__geolocation.code === 1") == L"true" && *requests == 1 && *denied,
      "geolocation actual native permission denial (unavailable platform is not PASS)");
  }
  void ProfileAttacks();
  void ProfileJunctions();
  void BrowserCrash();
  void RendererCrash() {
    const int previous_faults = messenger_.faults;
    auto failures = std::make_shared<int>(0);
    EventRegistrationToken token;
    Require(SUCCEEDED(window_->webview_->add_ProcessFailed(
      Callback<ICoreWebView2ProcessFailedEventHandler>(
        [failures](ICoreWebView2*, ICoreWebView2ProcessFailedEventArgs* args) {
          COREWEBVIEW2_PROCESS_FAILED_KIND kind{};
          if (SUCCEEDED(args->get_ProcessFailedKind(&kind)) &&
              kind == COREWEBVIEW2_PROCESS_FAILED_KIND_RENDER_PROCESS_EXITED) ++*failures;
          return S_OK;
        }).Get(), &token)), "renderer crash observer");
    // Only this probe-owned renderer is targeted. No OS process enumeration or kill.
    Require(SUCCEEDED(window_->webview_->CallDevToolsProtocolMethod(L"Page.crash", L"{}",
      Callback<ICoreWebView2CallDevToolsProtocolMethodCompletedHandler>(
        [](HRESULT, LPCWSTR) { return S_OK; }).Get())), "owned renderer crash injected");
    Require(PumpUntil([&] { return *failures == 1 && !window_->window_ && !window_->cleaning_; }, 25000),
      "actual renderer crash closes native sandbox");
    Close(previous_faults + 1);
  }
  void NavigationAttack() {
    Eval(L"location.href='https://example.invalid/escape'; true");
    Require(PumpUntil([&] { return !window_->window_ && !window_->cleaning_; }), "forbidden navigation closes fail closed");
    Close(1);
  }
  void VerifyWorkerDenied() { Require(*worker_denied_ == 1, "worker request reached native firewall and received 403"); }
  void CloseRunningWorker() {
    auto requests = std::make_shared<int>(0);
    auto escaped = std::make_shared<int>(0);
    EventRegistrationToken token;
    Require(SUCCEEDED(window_->webview_->add_WebResourceRequested(Callback<ICoreWebView2WebResourceRequestedEventHandler>(
      [requests, escaped](ICoreWebView2*, ICoreWebView2WebResourceRequestedEventArgs* args) {
        ComPtr<ICoreWebView2WebResourceRequest> request;
        ComPtr<ICoreWebView2WebResourceResponse> response;
        LPWSTR uri = nullptr; int status = 0;
        if (SUCCEEDED(args->get_Request(&request)) && SUCCEEDED(request->get_Uri(&uri))) {
          if (std::wstring(uri) == L"https://learning-sandbox.invalid/worker-close") {
            ++*requests;
            if (FAILED(args->get_Response(&response)) || !response ||
                FAILED(response->get_StatusCode(&status)) || status != 403) ++*escaped;
          }
          CoTaskMemFree(uri);
        }
        return S_OK;
      }).Get(), &token)), "running worker observer");
    Eval(L"document.getElementById('code').value='from js import fetch\\nwhile True:\\n    await fetch(\"https://learning-sandbox.invalid/worker-close\")'; document.getElementById('run').click(); true");
    Require(PumpUntil([&] { return *requests >= 3; }, 15000), "worker actively requests before close");
    // Deterministically exercise the same stale callback fence set by Close,
    // before navigation can destroy the worker and hide a missing response.
    const auto before_fence = *requests;
    ++window_->generation_;
    Require(PumpUntil([&] { return *requests >= before_fence + 3; }, 15000), "stale worker requests observed");
    Require(*escaped == 0, "stale generation still returns local 403");
    Close();
    Require(*escaped == 0, "all observed live and closing worker requests locally denied");
  }
  void Close(int expected_faults = 0) {
    window_->Close();
    Require(PumpUntil([&] { return !window_->cleaning_; }) && !window_->cleanup_failed_ &&
      !window_->window_ && !window_->controller_ && !window_->webview_, "profile cleanup and native close");
    Require(messenger_.faults == expected_faults, "expected native fault callback count");
  }
 private:
  ProbeMessenger messenger_;
  std::shared_ptr<LearningWindow> window_;
  std::shared_ptr<int> worker_denied_ = std::make_shared<int>(0);
};

void LearningProbe::Boundaries() {
  ComPtr<ICoreWebView2Settings> settings;
  BOOL messages = TRUE, hosts = TRUE;
  Require(SUCCEEDED(window_->webview_->get_Settings(&settings)) &&
    SUCCEEDED(settings->get_IsWebMessageEnabled(&messages)) &&
    SUCCEEDED(settings->get_AreHostObjectsAllowed(&hosts)) && !messages && !hosts,
    "host objects and web messaging disabled");
  auto received = std::make_shared<int>(0);
  EventRegistrationToken message_token;
  Require(SUCCEEDED(window_->webview_->add_WebMessageReceived(Callback<ICoreWebView2WebMessageReceivedEventHandler>(
    [received](ICoreWebView2*, ICoreWebView2WebMessageReceivedEventArgs*) { ++*received; return S_OK; }).Get(),
    &message_token)), "native message observer");
  Eval(L"try { chrome.webview.postMessage('synthetic-denied'); } catch {} true");
  Eval(LR"JS(window.__blocked = null; window.__violations = [];
  document.addEventListener('securitypolicyviolation', e => window.__violations.push(e.blockedURI));
  (async () => {
    const checks = [];
    try { checks.push((await fetch('/not-allowlisted')).status === 403); } catch { checks.push(false); }
    try { await fetch('http://127.0.0.1:9/synthetic-only'); checks.push(false); } catch { checks.push(true); }
    try { await fetch('file:///C:/synthetic-no-such-file'); checks.push(false); } catch { checks.push(true); }
    try { await import('https://example.invalid/forbidden.js'); checks.push(false); } catch { checks.push(true); }
    window.__blocked = checks;
  })(); true)JS");
  Require(Poll(L"Array.isArray(window.__blocked) && window.__blocked.length === 4"), "resource attacks finish");
  Require(Eval(L"window.__blocked.every(Boolean)") == L"true", "page attack requests rejected");
  Require(Poll(L"window.__violations.length >= 3"), "CSP reports actual blocked requests");
  std::cout << "CSP " << Utf8(Eval(L"window.__violations")) << std::endl;
  Require(Eval(L"['http://127.0.0.1:9', 'file', 'https://example.invalid'].every(prefix => window.__violations.some(uri => uri.startsWith(prefix)))") == L"true",
    "CSP blocked loopback file and external module before transport");
  Require(*received == 0, "page cannot deliver native message");
  Eval(L"localStorage.setItem('synthetic-probe','must-not-survive'); true");
}

void LearningProbe::InteractiveBoundaries() {
  auto popups = std::make_shared<int>(0);
  auto permissions = std::make_shared<int>(0);
  auto downloads = std::make_shared<int>(0);
  auto escaped = std::make_shared<int>(0);
  auto automatic_downloads = std::make_shared<int>(0);
  EventRegistrationToken token;
  Require(SUCCEEDED(window_->webview_->add_NewWindowRequested(
    Callback<ICoreWebView2NewWindowRequestedEventHandler>(
      [popups, escaped](ICoreWebView2*, ICoreWebView2NewWindowRequestedEventArgs* args) {
        BOOL handled = FALSE;
        ++*popups;
        if (FAILED(args->get_Handled(&handled)) || !handled) ++*escaped;
        return S_OK;
      }).Get(), &token)), "popup outcome observer");
  Require(SUCCEEDED(window_->webview_->add_PermissionRequested(
    Callback<ICoreWebView2PermissionRequestedEventHandler>(
      [permissions, escaped, automatic_downloads](ICoreWebView2*, ICoreWebView2PermissionRequestedEventArgs* args) {
        COREWEBVIEW2_PERMISSION_STATE state{};
        COREWEBVIEW2_PERMISSION_KIND kind{};
        ++*permissions;
        if (SUCCEEDED(args->get_PermissionKind(&kind))) std::cout << "PERMISSION kind=" << kind << std::endl;
        if (kind == COREWEBVIEW2_PERMISSION_KIND_MULTIPLE_AUTOMATIC_DOWNLOADS) ++*automatic_downloads;
        if (FAILED(args->get_State(&state)) || state != COREWEBVIEW2_PERMISSION_STATE_DENY) ++*escaped;
        return S_OK;
      }).Get(), &token)), "permission outcome observer");
  ComPtr<ICoreWebView2_4> view;
  Require(SUCCEEDED(window_->webview_.As(&view)) && SUCCEEDED(view->add_DownloadStarting(
    Callback<ICoreWebView2DownloadStartingEventHandler>(
      [downloads, escaped](ICoreWebView2*, ICoreWebView2DownloadStartingEventArgs* args) {
        BOOL cancel = FALSE;
        ++*downloads;
        if (FAILED(args->get_Cancel(&cancel)) || !cancel) ++*escaped;
        return S_OK;
      }).Get(), &token)), "download outcome observer");
  Eval(L"window.open('https://learning-sandbox.invalid/index.html','_blank'); true");
  Require(PumpUntil([&] { return *popups == 1; }), "popup reached native handler");
  Eval(L"window.open('https://example.invalid/escape','_blank'); true");
  Require(PumpUntil([&] { return *popups == 2; }), "external popup handled before navigation");
  Eval(L"window.open('about:blank','_blank'); true");
  Require(PumpUntil([&] { return *popups == 3; }), "blank popup handled by native guard");
  Eval(L"window.__permission = null; Notification.requestPermission().then(v => window.__permission = v); true");
  Require(Poll(L"window.__permission === 'denied'"), "notification permission denied to page");
  Require(*permissions == 1, "permission reached native handler");
  Eval(L"const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob(['synthetic-only'])); a.download = 'synthetic-denied.txt'; a.click(); true");
  Require(PumpUntil([&] { return *downloads == 1; }), "blob download reached native handler");
  Eval(L"const d = document.createElement('a'); d.href = 'data:text/plain,synthetic-only'; d.download = 'synthetic-data-denied.txt'; d.click(); true");
  Require(PumpUntil([&] { return *automatic_downloads == 1; }), "repeated data download reached native automatic-download permission gate");
  Require(*downloads == 1, "denied automatic-download permission prevents second DownloadStarting");
  Require(*escaped == 0, "native popup permission and download outcomes fail closed");
  Require(!IsWindowVisible(window_->window_), "interactive attacks keep native window hidden");
}

void LearningProbe::ProfileAttacks() {
  wchar_t temporary[MAX_PATH];
  Require(GetTempPathW(MAX_PATH, temporary) > 0, "synthetic temporary path");
  struct Restore {
    std::wstring tmp, temp;
    ~Restore() { SetEnvironmentVariableW(L"TMP", tmp.c_str()); SetEnvironmentVariableW(L"TEMP", temp.c_str()); }
  } restore;
  wchar_t value[32768];
  GetEnvironmentVariableW(L"TMP", value, 32768); restore.tmp = value;
  GetEnvironmentVariableW(L"TEMP", value, 32768); restore.temp = value;
  const auto base = std::filesystem::path(temporary) / L"profile-attacks";
  const auto select = [&](const wchar_t* scenario) {
    const auto root = base / scenario;
    std::filesystem::create_directories(root);
    Require(SetEnvironmentVariableW(L"TMP", root.c_str()) &&
      SetEnvironmentVariableW(L"TEMP", root.c_str()), "select owned synthetic TEMP");
    return root / L"paraselene-flutter-learning-cache-v1";
  };
  auto profile = select(L"unknown");
  std::filesystem::create_directory(profile);
  Require(!window_->PrepareProfile(), "unknown existing profile rejected");
  window_->Close();
  Require(std::filesystem::exists(profile), "unknown directory preserved");
  profile = select(L"wrong-marker");
  std::filesystem::create_directory(profile);
  { std::ofstream marker(profile / L"PARASELENE_LEARNING_CACHE_V1"); marker << "synthetic-wrong-marker"; }
  Require(!window_->PrepareProfile(), "wrong profile marker rejected");
  window_->Close();
  profile = select(L"hardlink-marker");
  std::filesystem::create_directory(profile);
  const auto source = profile.parent_path() / L"synthetic-marker-source";
  { std::ofstream marker(source, std::ios::binary); marker << "paraselene-flutter-learning-cache-v1\n"; }
  Require(CreateHardLinkW((profile / L"PARASELENE_LEARNING_CACHE_V1").c_str(), source.c_str(), nullptr), "synthetic marker hardlink created");
  Require(!window_->PrepareProfile(), "hardlinked marker rejected");
  window_->Close();
  profile = select(L"pinned");
  Require(window_->PrepareProfile(), "new owned profile accepted");
  std::cout << "PIN_PATH actual=" << Utf8(window_->profile_) << " expected=" << Utf8(profile.wstring())
    << " handles=" << window_->profile_pins_->handles.size() << std::endl;
  const auto renamed = profile.parent_path() / L"renamed";
  const BOOL moved = MoveFileExW(profile.c_str(), renamed.c_str(), 0);
  const DWORD move_error = GetLastError();
  std::cout << "PIN_RENAME moved=" << moved << " error=" << move_error << std::endl;
  Require(!moved && move_error == ERROR_SHARING_VIOLATION,
    "pinned profile cannot be renamed");
  Require(!MoveFileExW(profile.parent_path().c_str(), (base / L"renamed-parent").c_str(), 0) &&
    GetLastError() == ERROR_SHARING_VIOLATION, "pinned ancestor cannot be renamed");
  window_->Close();
  Require(MoveFileExW(profile.c_str(), renamed.c_str(), 0), "owned profile pin released after close");
}

void LearningProbe::ProfileJunctions() {
  wchar_t temporary[MAX_PATH];
  Require(GetTempPathW(MAX_PATH, temporary) > 0, "junction synthetic root");
  struct Restore {
    std::wstring root;
    ~Restore() { SetEnvironmentVariableW(L"TMP", root.c_str()); SetEnvironmentVariableW(L"TEMP", root.c_str()); }
  } restore{temporary};
  const auto base = std::filesystem::path(temporary) / L"junction-attacks";
  const auto check = [&](const std::filesystem::path& root, const std::filesystem::path& junction) {
    const DWORD attributes = GetFileAttributesW(junction.c_str());
    Require(attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_REPARSE_POINT), "actual junction fixture");
    Require(SetEnvironmentVariableW(L"TMP", root.c_str()) && SetEnvironmentVariableW(L"TEMP", root.c_str()), "select junction attack TEMP");
    Require(!window_->PrepareProfile(), "junction path rejected by production profile guard");
    window_->Close();
    std::ifstream input(base / L"owned-target" / L"sentinel.txt", std::ios::binary);
    const std::string sentinel((std::istreambuf_iterator<char>(input)), std::istreambuf_iterator<char>());
    Require(sentinel == "synthetic-target-must-survive", "junction target sentinel unchanged");
  };
  check(base / L"profile", base / L"profile" / L"paraselene-flutter-learning-cache-v1");
  check(base / L"ancestor" / L"linked" / L"child", base / L"ancestor" / L"linked");
  Require(!std::filesystem::exists(base / L"owned-target" / L"child" / L"paraselene-flutter-learning-cache-v1"),
    "ancestor junction rejected before creating profile in target");
}

void LearningProbe::BrowserCrash() {
  const int previous_faults = messenger_.faults;
  auto failures = std::make_shared<int>(0);
  EventRegistrationToken token;
  Require(SUCCEEDED(window_->webview_->add_ProcessFailed(
    Callback<ICoreWebView2ProcessFailedEventHandler>(
      [failures](ICoreWebView2*, ICoreWebView2ProcessFailedEventArgs* args) {
        COREWEBVIEW2_PROCESS_FAILED_KIND kind{};
        if (SUCCEEDED(args->get_ProcessFailedKind(&kind)) &&
            kind == COREWEBVIEW2_PROCESS_FAILED_KIND_BROWSER_PROCESS_EXITED) ++*failures;
        return S_OK;
      }).Get(), &token)), "browser crash observer");
  Require(SUCCEEDED(window_->webview_->CallDevToolsProtocolMethod(L"Browser.crash", L"{}",
    Callback<ICoreWebView2CallDevToolsProtocolMethodCompletedHandler>(
      [](HRESULT, LPCWSTR) { return S_OK; }).Get())), "owned exclusive browser crash injected");
  Require(PumpUntil([&] { return *failures == 1 && !window_->window_ && !window_->cleaning_; }, 25000),
    "actual browser crash releases native sandbox");
  Require(!window_->controller_ && !window_->webview_ && !window_->environment_, "crashed browser COM ownership released");
  std::cout << "BROWSER_CRASH cleanup_failed=" << window_->cleanup_failed_ << std::endl;
  Require(messenger_.faults == previous_faults + (window_->cleanup_failed_ ? 2 : 1), "browser failure notifications match cleanup result");
  if (window_->cleanup_failed_) {
    auto outcome = std::make_shared<std::string>();
    window_->Open("en", L"Synthetic rejected reopen", std::make_unique<flutter::MethodResultFunctions<flutter::EncodableValue>>(
      [outcome](const auto*) { *outcome = "unexpected_success"; },
      [outcome](const std::string& code, const auto&, const auto*) { *outcome = code; },
      [outcome] { *outcome = "unexpected_not_implemented"; }));
    Require(*outcome == "learning_cleanup_failed" && !window_->window_, "failed cleanup blocks production reopen");
  }
}

int wmain(int argc, wchar_t** argv) {
  if (argc != 3 && (argc != 4 || std::wstring(argv[3]) != L"--geolocation")) return 2;
  const HRESULT initialized = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  if (FAILED(initialized)) return 3;
  int code = 0;
  try {
    wchar_t temporary[MAX_PATH];
    Require(GetTempPathW(MAX_PATH, temporary) > 0 &&
      std::filesystem::path(temporary).lexically_normal() == (std::filesystem::path(argv[2]) / L"").lexically_normal(),
      "TEMP matches explicit synthetic root");
    std::ifstream marker(std::filesystem::path(argv[2]) / L"PARASELENE_NATIVE_PROBE_V1", std::ios::binary);
    const std::string identity((std::istreambuf_iterator<char>(marker)), std::istreambuf_iterator<char>());
    Require(identity == "owned-synthetic-native-probe", "script-created synthetic marker required");
    LearningProbe probe;
    if (argc == 4) {
      probe.Open(argv[1], L"index-en.html"); probe.Geolocation(); probe.Close();
      std::cout << "PASS geolocation native suite" << std::endl;
    } else {
    probe.ProfileAttacks();
    probe.ProfileJunctions();
    probe.Open(argv[1], L"index-en.html");
    probe.Exercise(L"'def double(x):\\n    return x * 2'");
    probe.Boundaries();
    probe.InteractiveBoundaries();
    probe.Exercise(L"'from js import fetch\\nresponse = await fetch(\"https://learning-sandbox.invalid/worker-denied\")\\nassert response.status == 403\\ndef double(x):\\n    return x * 2'");
    probe.VerifyWorkerDenied();
    probe.Exercise(L"'while True:\\n    pass'", false);
    Require(probe.Poll(L"document.getElementById('status').textContent.includes('timed out')"), "infinite worker terminated by page timer");
    probe.Exercise(L"'def double(x):\\n    return x * 2'");
    probe.CloseRunningWorker();
    probe.Open(argv[1], L"index.html");
    Require(probe.Eval(L"localStorage.getItem('synthetic-probe') === null") == L"true", "storage cleared on reopen");
    probe.Exercise(L"'def double(x):\\n    return x * 2'");
    probe.NavigationAttack();
    probe.Open(argv[1], L"index-en.html");
    probe.RendererCrash();
    probe.Open(argv[1], L"index-en.html");
    probe.BrowserCrash();
    std::cout << "PASS learning native suite" << std::endl;
    }
  } catch (const std::exception& error) {
    std::cerr << "FAIL " << error.what() << std::endl; code = 1;
  }
  CoUninitialize(); return code;
}
