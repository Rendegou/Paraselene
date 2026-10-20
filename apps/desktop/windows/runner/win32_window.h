// 通用 Win32 顶层窗口抽象：窗口类注册、DPI 缩放、深色主题、子内容布局与生命周期。
//
// 线程模型：全部方法必须在创建窗口的 UI 线程调用，没有跨线程同步。
// 所有权：window_handle_ 由本类 DestroyWindow；child_content_ 是外部传入的借用句柄，
// 本类只负责放置与缩放，绝不销毁它。
// 失败策略：CreateWindow 失败返回 false；未处理的消息统一交给 DefWindowProc。

#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>

#include <functional>
#include <memory>
#include <string>

// A class abstraction for a high DPI-aware Win32 Window. Intended to be
// inherited from by classes that wish to specialize with custom
// rendering and input handling
// 顶层窗口基类：子类通过覆写 OnCreate/OnDestroy/MessageHandler 定制行为，
// 句柄生命周期由本类统一管理，子类不得自行调用 DestroyWindow。
class Win32Window {
 public:
  // 逻辑坐标点；Create 时按目标显示器 DPI 折算为物理像素。
  struct Point {
    unsigned int x;
    unsigned int y;
    Point(unsigned int x, unsigned int y) : x(x), y(y) {}
  };

  // 逻辑尺寸；Create 时按目标显示器 DPI 折算为物理像素。
  struct Size {
    unsigned int width;
    unsigned int height;
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
  };

  // 构造只登记活动窗口计数，不创建 HWND。
  Win32Window();
  // 兜底调用 Destroy，确保未显式销毁的窗口句柄被释放。
  virtual ~Win32Window();

  // Creates a win32 window with |title| that is positioned and sized using
  // |origin| and |size|. New windows are created on the default monitor. Window
  // sizes are specified to the OS in physical pixels, hence to ensure a
  // consistent size this function will scale the inputted width and height as
  // as appropriate for the default monitor. The window is invisible until
  // |Show| is called. Returns true if the window was created successfully.
  // 先销毁旧窗口，再创建隐藏窗口并按 DPI 缩放；成功后立即回调 OnCreate。
  bool Create(const std::wstring& title, const Point& origin, const Size& size);

  // Show the current window. Returns true if the window was successfully shown.
  // 显示并激活窗口；返回值表示窗口此前是否可见，而不是创建是否成功。
  bool Show();

  // Release OS resources associated with window.
  // 释放 OS 资源：先回调 OnDestroy，再销毁 HWND；重复调用是安全的。
  void Destroy();

  // Inserts |content| into the window tree.
  // 把内容设为子窗口并铺满客户区；句柄所有权仍归调用方。
  void SetChildContent(HWND content);

  // Returns the backing Window handle to enable clients to set icon and other
  // window properties. Returns nullptr if the window has been destroyed.
  // 返回借用的顶层 HWND；未创建或已销毁时为空。
  HWND GetHandle();

  // If true, closing this window will quit the application.
  // 置位后 WM_DESTROY 会投递 WM_QUIT，结束主消息循环。
  void SetQuitOnClose(bool quit_on_close);

  // Return a RECT representing the bounds of the current client area.
  // 返回客户区像素矩形；调用方必须保证窗口句柄有效。
  RECT GetClientArea();

 protected:
  // Processes and route salient window messages for mouse handling,
  // size change and DPI. Delegates handling of these to member overloads that
  // inheriting classes can handle.
  // 处理 WM_DESTROY、DPI 变化、尺寸、焦点与主题变更；其余交给 DefWindowProc。
  virtual LRESULT MessageHandler(HWND window,
                                 UINT const message,
                                 WPARAM const wparam,
                                 LPARAM const lparam) noexcept;

  // 实际由 Create 在 HWND 建立后调用（旧注释提到的 CreateAndShow 已不存在），
  // 供子类完成窗口相关初始化；返回 false 会让 Create 整体失败。
  virtual bool OnCreate();

  // Called when Destroy is called.
  // 窗口销毁前调用；子类在此释放自己的资源，本类默认无操作。
  virtual void OnDestroy();

 private:
  friend class WindowClassRegistrar;

  // OS callback called by message pump. Handles the WM_NCCREATE message which
  // is passed when the non-client area is being created and enables automatic
  // non-client DPI scaling so that the non-client area automatically
  // responds to changes in DPI. All other messages are handled by
  // MessageHandler.
  // 静态窗口过程：WM_NCCREATE 时绑定 this 并启用 DPI 缩放，其余消息转交实例方法。
  static LRESULT CALLBACK WndProc(HWND const window,
                                  UINT const message,
                                  WPARAM const wparam,
                                  LPARAM const lparam) noexcept;

  // Retrieves a class instance pointer for |window|
  // 从 GWLP_USERDATA 取回实例指针；窗口尚未创建完成时为空。
  static Win32Window* GetThisFromHandle(HWND const window) noexcept;

  // Update the window frame's theme to match the system theme.
  // 按注册表 AppsUseLightTheme 偏好切换深色标题栏；读取失败时保持默认外观。
  static void UpdateTheme(HWND const window);

  // 为 true 时关闭窗口即退出应用。
  bool quit_on_close_ = false;

  // window handle for top level window.
  // 借出的顶层窗口句柄；WM_DESTROY 时置空，之后不得使用。
  HWND window_handle_ = nullptr;

  // window handle for hosted content.
  // 托管内容（Flutter 视图）的借用句柄，只用于布局，不负责销毁。
  HWND child_content_ = nullptr;
};

#endif  // RUNNER_WIN32_WINDOW_H_
