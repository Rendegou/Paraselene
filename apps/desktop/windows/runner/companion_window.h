// 本地伴侣窗口声明：可选的桌面宠物与托盘入口，只在本机合成绘制。
//
// 线程模型：窗口、托盘、方法通道与定时器全部在 UI 线程，没有后台线程。
// 所有权：pet_ 的 HWND 在 Disable 中销毁；托盘图标由 Shell_NotifyIcon 成对增删；
// GDI+ 启动令牌在 Disable 中关闭。
// 安全边界：只接受 Dart 传入的名称、文案与外观枚举，不读取素材以外的用户数据，不联网。

#ifndef RUNNER_COMPANION_WINDOW_H_
#define RUNNER_COMPANION_WINDOW_H_
#include <windows.h>
#include <shellapi.h>
#include <gdiplus.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <array>
#include <memory>
#include <string>

// Explicitly enabled local-only desktop surface. No credentials or model access.
// 伴侣窗口：按 Dart 配置创建透明分层窗口与托盘图标，定时轮询安静状态并绘制动画；
// 绘制或托盘失败统一走 Fault，先释放全部原生资源再通知 Dart。
class CompanionWindow {
 public:
  // 注册 paraselene/companion/v1；只接受带 version=1、外观枚举与文案的 configure 请求。
  CompanionWindow(HWND owner, flutter::BinaryMessenger* messenger);
  // 先解除通道回调再 Disable，确保引擎不会回调到已释放的对象。
  ~CompanionWindow();
  // 处理托盘回调与 TaskbarCreated；返回 true 表示消息已消费。
  bool HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);
 private:
  // 启动 GDI+、加载六帧素材、创建分层窗口与托盘并启动定时器；任一步失败返回 false。
  bool Enable(const std::string& appearance);
  // 逆序释放托盘、定时器与窗口、素材、GDI+；可重复调用。
  void Disable();
  // 原生失败时释放资源并向 Dart 报告 companion_unavailable。
  void Fault();
  // 绘制指定动画帧到分层窗口；实现见 companion_paint.cpp。
  bool Paint(size_t frame);
  // 添加托盘图标并升级到 NOTIFYICON_VERSION_4；失败返回 false。
  bool AddTray();
  // 弹出托盘菜单：恢复主窗口、切换桌宠显隐或请求关闭主窗口。
  void Menu();
  // 250ms 节拍：周期性刷新安静状态与动画帧，失败即 Fault。
  void Tick();
  // 把伴侣窗口限制在当前显示器工作区内。
  void Clamp();
  // 伴侣窗口过程：处理拖动、右键菜单、定时器与 DPI/显示器变化。
  static LRESULT CALLBACK Proc(HWND, UINT, WPARAM, LPARAM);
  // 主窗口借用句柄；只用于回传托盘消息与恢复窗口，不销毁。
  HWND owner_;
  // 伴侣分层窗口；由 Disable 销毁。
  HWND pet_ = nullptr;
  // GDI+ 启动令牌；非零时才调用 GdiplusShutdown。
  ULONG_PTR gdiplus_ = 0;
  // 托盘图标是否已添加，保证 NIM_ADD 与 NIM_DELETE 成对。
  bool tray_ = false;
  // 当前安静状态；未知时沿用上一次结果。
  bool quiet_ = true;
  // 用户通过托盘手动隐藏的标记，优先于自动安静判定。
  bool manually_hidden_ = false;
  // 250ms 节拍计数，驱动动画与安静状态轮询。
  unsigned ticks_ = 0;
  // 点击触发 poke 帧的结束节拍。
  unsigned poke_until_ = 0;
  // 六帧预解码位图（idle/blink/curious/poke/sleep/beast），随 Disable 释放。
  std::array<std::unique_ptr<Gdiplus::Bitmap>, 6> images_;
  // Dart 传入的本地化文案，只用于窗口标题与托盘菜单。
  std::wstring name_, open_, hide_, quit_;
  // paraselene/companion/v1 方法通道；析构时解除回调。
  flutter::MethodChannel<flutter::EncodableValue> channel_;
};
#endif
