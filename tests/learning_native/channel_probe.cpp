#include "learning_window.h"
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <map>
#include <stdexcept>

namespace {
void Require(bool ok, const char* label) {
  if (!ok) throw std::runtime_error(label);
  std::cout << "PASS " << label << std::endl;
}
bool PumpUntil(const std::function<bool()>& done, DWORD timeout = 20000) {
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
struct Outcome { int replies = 0; bool success = false; std::string error; };
class ChannelMessenger : public flutter::BinaryMessenger {
 public:
  mutable int faults = 0;
  std::map<std::string, flutter::BinaryMessageHandler> handlers;
  void Send(const std::string&, const uint8_t* data, size_t size, flutter::BinaryReply reply) const override {
    const auto call = flutter::StandardMethodCodec::GetInstance().DecodeMethodCall(data, size);
    if (call && call->method_name() == "fault") ++faults;
    if (reply) reply(nullptr, 0);
  }
  void SetMessageHandler(const std::string& channel, flutter::BinaryMessageHandler handler) override {
    if (handler) handlers[channel] = std::move(handler); else handlers.erase(channel);
  }
  std::shared_ptr<Outcome> Invoke(const std::string& method, flutter::EncodableValue value) {
    const auto& codec = flutter::StandardMethodCodec::GetInstance();
    const auto bytes = codec.EncodeMethodCall(flutter::MethodCall<flutter::EncodableValue>(method,
      std::make_unique<flutter::EncodableValue>(std::move(value))));
    auto outcome = std::make_shared<Outcome>();
    handlers.at("paraselene/learning/v1")(bytes->data(), bytes->size(),
      [outcome](const uint8_t* reply, size_t size) {
        ++outcome->replies;
        flutter::MethodResultFunctions<flutter::EncodableValue> result(
          [outcome](const auto*) { outcome->success = true; },
          [outcome](const std::string& code, const auto&, const auto*) { outcome->error = code; },
          [outcome] { outcome->error = "unexpected_not_implemented"; });
        if (!flutter::StandardMethodCodec::GetInstance().DecodeAndProcessResponseEnvelope(reply, size, &result))
          outcome->error = "invalid_envelope";
      });
    return outcome;
  }
};
flutter::EncodableValue Arguments(const std::string& locale, const std::string& title = "Synthetic learning") {
  return flutter::EncodableValue(flutter::EncodableMap{
    {flutter::EncodableValue("locale"), flutter::EncodableValue(locale)},
    {flutter::EncodableValue("title"), flutter::EncodableValue(title)}});
}
void Error(const std::shared_ptr<Outcome>& result, const char* code) {
  Require(result->replies == 1 && !result->success && result->error == code, code);
}
std::wstring DesktopName(HANDLE desktop) {
  wchar_t name[256]; DWORD length = 0;
  Require(GetUserObjectInformationW(desktop, UOI_NAME, name, sizeof(name), &length), "desktop name available");
  return name;
}
}

// Uses the unmodified production method-channel handler, profile and open path.
// Its visible HWND lives only on a private desktop, never the user's desktop.
class LearningChannelProbe {
 public:
  LearningChannelProbe() : window_(std::make_shared<LearningWindow>(&messenger_)) {}
  ~LearningChannelProbe() { window_->Close(); PumpUntil([&] { return !window_->cleaning_; }); }
  void Requests() {
    Error(messenger_.Invoke("unknown", Arguments("en")), "invalid_learning_request");
    Error(messenger_.Invoke("open", flutter::EncodableValue("wrong_type")), "invalid_learning_request");
    Error(messenger_.Invoke("open", Arguments("fr")), "invalid_learning_request");
    Error(messenger_.Invoke("open", Arguments("en", "")), "invalid_learning_request");
    Error(messenger_.Invoke("open", Arguments("en", std::string(81, 'x'))), "invalid_learning_request");
    Error(messenger_.Invoke("open", Arguments("en", std::string("\xC3\x28", 2))), "invalid_learning_request");
    Require(!window_->window_ && !window_->pending_, "invalid requests create no native window");
    const auto cancelled = messenger_.Invoke("open", Arguments("en"));
    Require(window_->pending_ != nullptr && !IsWindowVisible(window_->window_), "open starts hidden and pending");
    Error(messenger_.Invoke("open", Arguments("zh-Hans")), "learning_busy");
    SendMessageW(window_->window_, WM_CLOSE, 0, 0);
    Error(cancelled, "learning_closed");
    const auto until = GetTickCount64() + 1500;
    PumpUntil([&] { return GetTickCount64() >= until; }, 2000);
    Require(cancelled->replies == 1 && !window_->window_ && !window_->controller_ && !window_->pending_,
      "late creation cannot resurrect cancelled channel open");
  }
  void Open(const std::string& locale, const wchar_t* expected_page) {
    const auto result = messenger_.Invoke("open", Arguments(locale, locale == "zh-Hans" ? u8"合成学习窗口" : "Synthetic learning"));
    const bool replied = PumpUntil([&] { return result->replies != 0; });
    std::cout << "CHANNEL_OPEN replied=" << replied << " count=" << result->replies << " success=" << result->success
      << " error=" << result->error << " cleaning=" << window_->cleaning_ << " cleanup_failed=" << window_->cleanup_failed_
      << " asset_exists=" << std::filesystem::exists(std::filesystem::path(window_->assets_) / expected_page) << std::endl;
    Require(replied && result->replies == 1 && result->success,
      "encoded channel open returns real native success");
    Require(window_->window_ && IsWindowVisible(window_->window_) && window_->controller_ && window_->webview_,
      "production open creates shown HWND on private desktop");
    const HDESK input = OpenInputDesktop(0, FALSE, DESKTOP_READOBJECTS);
    Require(input != nullptr, "opened channel can inspect input desktop identity");
    const bool private_window = DesktopName(input) != DesktopName(GetThreadDesktop(GetCurrentThreadId()));
    CloseDesktop(input);
    Require(private_window, "shown channel window remains outside input desktop");
    Require(window_->page_ == std::wstring(L"https://learning-sandbox.invalid/") + expected_page,
      "channel locale selects expected fixed page");
    const HWND original = window_->window_;
    const auto again = messenger_.Invoke("open", Arguments(locale));
    Require(again->replies == 1 && again->success && window_->window_ == original,
      "second completed open reuses production window");
    Eval(L"document.getElementById('code').value='def double(x):\\n    return x * 2'; document.getElementById('run').click(); true");
    const auto started = GetTickCount64();
    bool passed = false;
    while (!passed && GetTickCount64() - started < 20000) {
      passed = Eval(L"document.getElementById('status').textContent.startsWith('3 / 3')") == L"true";
      const auto until = GetTickCount64() + 100;
      PumpUntil([&] { return GetTickCount64() >= until; }, 200);
    }
    Require(passed, "channel-opened real Pyodide returns expected numbers");
    Require(messenger_.faults == 0, "channel open emitted no native fault");
    Close();
  }
  void Close() {
    SendMessageW(window_->window_, WM_CLOSE, 0, 0);
    Require(PumpUntil([&] { return !window_->cleaning_; }) && !window_->cleanup_failed_ &&
      !window_->window_ && !window_->controller_ && !window_->webview_, "channel native close and cleanup");
  }
 private:
  std::wstring Eval(const wchar_t* script) {
    struct Result { bool done = false; HRESULT status = E_PENDING; std::wstring value; };
    auto result = std::make_shared<Result>();
    const HRESULT scheduled = window_->webview_->ExecuteScript(script,
      Microsoft::WRL::Callback<ICoreWebView2ExecuteScriptCompletedHandler>(
        [result](HRESULT status, LPCWSTR value) {
          result->done = true; result->status = status; result->value = value ? value : L"null"; return S_OK;
        }).Get());
    if (FAILED(scheduled)) throw std::runtime_error("channel page script scheduled");
    if (!PumpUntil([&] { return result->done; }) || FAILED(result->status)) throw std::runtime_error("channel page script completes");
    return result->value;
  }
  ChannelMessenger messenger_;
  std::shared_ptr<LearningWindow> window_;
};

int RunPrivateDesktop(wchar_t** argv) {
  const auto name = L"ParaseleneSynthetic-" + std::to_wstring(GetCurrentProcessId());
  const HDESK isolated = CreateDesktopW(name.c_str(), nullptr, nullptr, 0,
    GENERIC_ALL, nullptr);
  if (!isolated) { std::cerr << "FAIL create private desktop " << GetLastError() << std::endl; return 1; }
  wchar_t executable[32768];
  if (!GetModuleFileNameW(nullptr, executable, 32768)) { CloseDesktop(isolated); return 1; }
  auto command = L"\"" + std::wstring(executable) + L"\" \"" + argv[1] + L"\" \"" + argv[2] + L"\" --private-child";
  auto desktop = L"winsta0\\" + name;
  STARTUPINFOW startup{sizeof(startup)};
  startup.lpDesktop = desktop.data();
  startup.dwFlags = STARTF_USESTDHANDLES;
  startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
  startup.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
  startup.hStdError = GetStdHandle(STD_ERROR_HANDLE);
  PROCESS_INFORMATION process{};
  const BOOL created = CreateProcessW(executable, command.data(), nullptr, nullptr, TRUE,
    CREATE_NO_WINDOW, nullptr, nullptr, &startup, &process);
  DWORD exit = 1;
  if (created) {
    CloseHandle(process.hThread);
    if (WaitForSingleObject(process.hProcess, 150000) == WAIT_OBJECT_0) GetExitCodeProcess(process.hProcess, &exit);
    else { TerminateProcess(process.hProcess, 1); WaitForSingleObject(process.hProcess, 5000); }
    CloseHandle(process.hProcess);
  } else std::cerr << "FAIL create private desktop child " << GetLastError() << std::endl;
  if (!CloseDesktop(isolated)) { std::cerr << "FAIL release private desktop " << GetLastError() << std::endl; return 1; }
  return static_cast<int>(exit);
}

int wmain(int argc, wchar_t** argv) {
  if (argc == 3) return RunPrivateDesktop(argv);
  if (argc != 4 || std::wstring(argv[3]) != L"--private-child") return 2;
  bool initialized = false;
  int code = 0;
  try {
    const HDESK isolated = GetThreadDesktop(GetCurrentThreadId());
    Require(DesktopName(isolated).find(L"ParaseleneSynthetic-") == 0, "process starts on dedicated private desktop");
    const HDESK input = OpenInputDesktop(0, FALSE, DESKTOP_READOBJECTS);
    Require(input != nullptr, "input desktop identity available");
    const bool different = DesktopName(input) != DesktopName(isolated);
    CloseDesktop(input);
    Require(different, "probe desktop differs from user input desktop");
    wchar_t temporary[MAX_PATH];
    Require(GetTempPathW(MAX_PATH, temporary) > 0 &&
      std::filesystem::path(temporary).lexically_normal() == (std::filesystem::path(argv[2]) / L"").lexically_normal(),
      "channel TEMP matches explicit synthetic root");
    std::ifstream marker(std::filesystem::path(argv[2]) / L"PARASELENE_NATIVE_PROBE_V1", std::ios::binary);
    const std::string identity((std::istreambuf_iterator<char>(marker)), std::istreambuf_iterator<char>());
    Require(identity == "owned-synthetic-native-probe", "channel synthetic marker required");
    Require(SUCCEEDED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED)), "channel COM initialized");
    initialized = true;
    {
      LearningChannelProbe probe;
      probe.Requests();
      probe.Open("en", L"index-en.html");
      probe.Open("zh-Hans", L"index.html");
    }
    std::cout << "PASS native channel suite (no Flutter engine)" << std::endl;
  } catch (const std::exception& error) {
    std::cerr << "FAIL " << error.what() << std::endl; code = 1;
  }
  if (initialized) CoUninitialize();
  return code;
}
