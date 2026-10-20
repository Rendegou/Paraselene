// 幻月 Windows runner 进程入口：初始化 COM、创建 FlutterWindow 并运行 Win32 消息循环。
//
// 线程模型：启动、窗口创建与消息分发都在主 UI 线程（STA 单元）上执行。
// 关闭顺序：消息循环结束后反初始化 COM，主窗口对象随函数作用域退出而析构。
// 失败策略：主窗口创建失败时直接返回 EXIT_FAILURE，不进入消息循环。
// 安全边界：只使用本进程命令行参数，不读取凭据、作者数据或远端内容。

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

// 进程入口：注册 Dart 工程与参数，创建主窗口后进入阻塞式消息循环。
int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"paraselene_flutter", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  // 消息循环结束后反初始化 COM；主窗口对象随函数返回析构。
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
