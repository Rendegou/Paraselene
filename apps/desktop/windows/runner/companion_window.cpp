// 伴侣窗口实现：方法通道配置、GDI+ 素材加载、分层窗口/托盘创建、定时动画与失败回收。
//
// 线程模型：全部逻辑在 UI 线程；托盘回调与定时器由本进程消息循环分发。
// 所有权：HWND、托盘图标、GDI+ 令牌与位图都成对创建/释放，Disable 可重复调用。
// 失败策略：配置非法返回 invalid_companion_request；原生失败返回 companion_unavailable，
// 并先释放资源再通知 Dart，避免留下半初始化对象。
// 安全边界：只使用打包的本地 PNG 素材与系统状态查询，不联网、不读取作者数据。

#include "companion_window.h"
#include "companion_quiet.h"
#include "resource.h"
#include <flutter/standard_method_codec.h>
#include <algorithm>
#include <vector>

// 文件内辅助：托盘/定时器消息常量、UTF-8 到 UTF-16 转换与 EncodableMap 字段读取。
namespace {
constexpr UINT kTray = WM_APP + 74;
constexpr UINT_PTR kTimer = 74;
const UINT kTaskbarCreated = RegisterWindowMessageW(L"TaskbarCreated");
std::wstring Wide(const std::string& value) {
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()), nullptr, 0);
  if (size <= 0) return L"";
  std::wstring text(size, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()), text.data(), size);
  return text;
}
std::string Text(const flutter::EncodableMap& map, const char* key) {
  const auto item = map.find(flutter::EncodableValue(key));
  if (item == map.end()) return "";
  const auto* value = std::get_if<std::string>(&item->second);
  return value ? *value : "";
}
}

// 注册 configure 方法：校验 version=1、外观枚举、名称长度与必填文案后才应用配置。
CompanionWindow::CompanionWindow(HWND owner, flutter::BinaryMessenger* messenger)
    : owner_(owner), channel_(messenger, "paraselene/companion/v1", &flutter::StandardMethodCodec::GetInstance()) {
  channel_.SetMethodCallHandler([this](const auto& call, auto result) {
    const auto* map = call.arguments() ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
    if (call.method_name() != "configure" || !map) { result->Error("invalid_companion_request"); return; }
    const auto version = map->find(flutter::EncodableValue("version"));
    const auto enabled = map->find(flutter::EncodableValue("enabled"));
    const auto* v = version == map->end() ? nullptr : std::get_if<int32_t>(&version->second);
    const auto* on = enabled == map->end() ? nullptr : std::get_if<bool>(&enabled->second);
    const auto appearance = Text(*map, "appearance");
    if (!v || *v != 1 || !on || (appearance != "moon" && appearance != "star" && appearance != "cloud")) {
      result->Error("invalid_companion_request"); return;
    }
    name_ = Wide(Text(*map, "name")); open_ = Wide(Text(*map, "openLabel"));
    hide_ = Wide(Text(*map, "hideLabel")); quit_ = Wide(Text(*map, "quitLabel"));
    if (name_.empty() || name_.size() > 80 || open_.empty() || hide_.empty() || quit_.empty()) {
      result->Error("invalid_companion_request"); return;
    }
    Disable();
    if (*on && !Enable(appearance)) { Disable(); result->Error("companion_unavailable"); return; }
    result->Success(flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("version"), flutter::EncodableValue(1)},
      {flutter::EncodableValue("visible"), flutter::EncodableValue(pet_ && IsWindowVisible(pet_))},
      {flutter::EncodableValue("quiet"), flutter::EncodableValue(quiet_)}}));
  });
}
// 先解除通道回调再释放原生资源，防止引擎回调到析构中的对象。
CompanionWindow::~CompanionWindow() { channel_.SetMethodCallHandler(nullptr); Disable(); }

// 启动 GDI+、加载六帧素材、创建分层窗口与托盘并启动定时器；任一步失败立即返回 false，
// 由调用方 Disable 回收已创建的部分。
bool CompanionWindow::Enable(const std::string& appearance) {
  Gdiplus::GdiplusStartupInput input;
  if (Gdiplus::GdiplusStartup(&gdiplus_, &input, nullptr) != Gdiplus::Ok) return false;
  std::vector<wchar_t> path(32768);
  const DWORD size = GetModuleFileNameW(nullptr, path.data(), static_cast<DWORD>(path.size()));
  if (!size || size >= path.size()) return false;
  const std::wstring executable(path.data(), size);
  const auto root = executable.substr(0, executable.find_last_of(L"\\")) + L"\\data\\flutter_assets\\assets\\companions\\";
  const std::array<const wchar_t*, 6> states = {L"idle", L"blink", L"curious", L"poke", L"sleep", L"beast"};
  for (size_t i = 0; i < states.size(); ++i) {
    const auto file = root + Wide(appearance) + L"-" + states[i] + L".png";
    images_[i] = std::make_unique<Gdiplus::Bitmap>(file.c_str());
    if (images_[i]->GetLastStatus() != Gdiplus::Ok) return false;
  }
  WNDCLASSW type{}; type.lpfnWndProc = Proc; type.hInstance = GetModuleHandle(nullptr);
  type.lpszClassName = L"ParaseleneFlutterCompanionV1"; type.hCursor = LoadCursor(nullptr, IDC_HAND);
  if (!RegisterClassW(&type) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) return false;
  pet_ = CreateWindowExW(WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TOPMOST,
      type.lpszClassName, name_.c_str(), WS_POPUP, 0, 0, 180, 180, nullptr, nullptr, type.hInstance, this);
  if (!pet_) return false;
  MONITORINFO monitor{sizeof(MONITORINFO)};
  if (!GetMonitorInfoW(MonitorFromWindow(owner_, MONITOR_DEFAULTTOPRIMARY), &monitor)) return false;
  SetWindowPos(pet_, HWND_TOPMOST, monitor.rcWork.right - 200, monitor.rcWork.bottom - 200, 180, 180, SWP_NOACTIVATE);
  // 首次未知时先按安静处理，之后由 Tick 轮询修正。
  quiet_ = CompanionQuiet().value_or(true); manually_hidden_ = false; ticks_ = 0;
  if (!Paint(0) || !AddTray() || !SetTimer(pet_, kTimer, 250, nullptr)) return false;
  if (!quiet_) ShowWindow(pet_, SW_SHOWNOACTIVATE);
  return true;
}
// 逆序释放托盘图标、定时器与窗口、帧位图与 GDI+；重复调用是安全的。
void CompanionWindow::Disable() {
  if (tray_) { NOTIFYICONDATAW icon{sizeof(icon)}; icon.hWnd = owner_; icon.uID = 74; Shell_NotifyIconW(NIM_DELETE, &icon); tray_ = false; }
  if (pet_) { KillTimer(pet_, kTimer); DestroyWindow(pet_); pet_ = nullptr; }
  for (auto& image : images_) image.reset();
  if (gdiplus_) { Gdiplus::GdiplusShutdown(gdiplus_); gdiplus_ = 0; }
}
// 添加托盘图标并升级到 NOTIFYICON_VERSION_4；失败时 tray_ 为 false。
bool CompanionWindow::AddTray() {
  NOTIFYICONDATAW icon{sizeof(icon)}; icon.hWnd = owner_; icon.uID = 74;
  icon.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP; icon.uCallbackMessage = kTray;
  icon.hIcon = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcsncpy_s(icon.szTip, name_.c_str(), _TRUNCATE);
  tray_ = Shell_NotifyIconW(NIM_ADD, &icon) != FALSE;
  icon.uVersion = NOTIFYICON_VERSION_4;
  if (tray_ && !Shell_NotifyIconW(NIM_SETVERSION, &icon)) return false;
  return tray_;
}
// 处理任务栏重建与托盘回调；其余消息返回 false，交回主窗口过程。
bool CompanionWindow::HandleMessage(UINT message, WPARAM, LPARAM lparam) {
  // 资源管理器重启后托盘图标会丢失，需要重新添加。
  if (message == kTaskbarCreated && pet_) { tray_ = false; if (!AddTray()) Fault(); return true; }
  if (message != kTray) return false;
  if (LOWORD(lparam) == WM_CONTEXTMENU) Menu();
  if (LOWORD(lparam) == NIN_SELECT || LOWORD(lparam) == NIN_KEYSELECT) { ShowWindow(owner_, SW_RESTORE); SetForegroundWindow(owner_); }
  return true;
}
// 弹出托盘菜单并处理选择；关闭主窗口走与系统关闭按钮相同的 WM_CLOSE 守卫。
void CompanionWindow::Menu() {
  const HMENU menu = CreatePopupMenu();
  if (!menu) return;
  AppendMenuW(menu, MF_STRING, 1, open_.c_str());
  AppendMenuW(menu, MF_STRING, 2, hide_.c_str());
  AppendMenuW(menu, MF_STRING, 3, quit_.c_str());
  POINT point{}; GetCursorPos(&point); SetForegroundWindow(owner_);
  const UINT choice = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_NONOTIFY, point.x, point.y, 0, owner_, nullptr);
  DestroyMenu(menu);
  if (choice == 1) { ShowWindow(owner_, SW_RESTORE); SetForegroundWindow(owner_); }
  if (choice == 2) { manually_hidden_ = !manually_hidden_; ShowWindow(pet_, manually_hidden_ || quiet_ ? SW_HIDE : SW_SHOWNOACTIVATE); }
  if (choice == 3) PostMessage(owner_, WM_CLOSE, 0, 0); // Same save/close guard as system X.
  PostMessage(owner_, WM_NULL, 0, 0);
}
// 每 20 拍（约 5 秒）刷新一次安静状态；可见时按节拍选择动画帧，绘制失败即 Fault。
void CompanionWindow::Tick() {
  ++ticks_;
  if (ticks_ % 20 == 0) {
    if (const auto quiet = CompanionQuiet()) quiet_ = *quiet;
    ShowWindow(pet_, quiet_ || manually_hidden_ ? SW_HIDE : SW_SHOWNOACTIVATE);
  }
  if (!IsWindowVisible(pet_)) return;
  const size_t frame = ticks_ < poke_until_ ? 3 : ticks_ % 40 == 0 ? 1 : ticks_ % 80 > 72 ? 2 : 0;
  if (!Paint(frame)) Fault();
}
// 释放全部原生资源后向 Dart 报告 companion_unavailable。
void CompanionWindow::Fault() {
  Disable();
  channel_.InvokeMethod("fault", std::make_unique<flutter::EncodableValue>("companion_unavailable"));
}
// 把伴侣窗口限制在当前显示器工作区内，避免拖出屏幕后无法找回。
void CompanionWindow::Clamp() {
  RECT rect{}; GetWindowRect(pet_, &rect);
  MONITORINFO monitor{sizeof(MONITORINFO)};
  if (!GetMonitorInfoW(MonitorFromWindow(pet_, MONITOR_DEFAULTTONEAREST), &monitor)) return;
  const int width = rect.right - rect.left, height = rect.bottom - rect.top;
  SetWindowPos(pet_, nullptr, std::clamp(rect.left, monitor.rcWork.left, std::max(monitor.rcWork.left, monitor.rcWork.right - width)),
      std::clamp(rect.top, monitor.rcWork.top, std::max(monitor.rcWork.top, monitor.rcWork.bottom - height)), 0, 0, SWP_NOZORDER | SWP_NOSIZE | SWP_NOACTIVATE);
}
// 伴侣窗口过程：绑定 this，处理鼠标拖动、右键菜单、定时器与 DPI/显示器变化。
LRESULT CALLBACK CompanionWindow::Proc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  auto* self = reinterpret_cast<CompanionWindow*>(GetWindowLongPtr(window, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    self = static_cast<CompanionWindow*>(reinterpret_cast<CREATESTRUCT*>(lparam)->lpCreateParams);
    SetWindowLongPtr(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
  }
  if (!self) return DefWindowProc(window, message, wparam, lparam);
  // 不在点击时抢焦点，保持主窗口的输入焦点不变。
  if (message == WM_MOUSEACTIVATE) return MA_NOACTIVATE;
  // 定时器只服务本窗口的动画与安静状态轮询。
  if (message == WM_TIMER) { self->Tick(); return 0; }
  if (message == WM_LBUTTONDOWN) { self->poke_until_ = self->ticks_ + 4; if (!self->Paint(3)) { self->Fault(); return 0; } ReleaseCapture(); SendMessage(window, WM_NCLBUTTONDOWN, HTCAPTION, lparam); self->Clamp(); return 0; }
  if (message == WM_RBUTTONUP || message == WM_CONTEXTMENU) { self->Menu(); return 0; }
  if (message == WM_DISPLAYCHANGE || message == WM_DPICHANGED) { self->Clamp(); if (!self->Paint(0)) self->Fault(); return 0; }
  return DefWindowProc(window, message, wparam, lparam);
}
