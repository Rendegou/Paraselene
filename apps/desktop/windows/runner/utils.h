// runner 通用工具声明：控制台重定向与 UTF-16/UTF-8 命令行参数转换。
//
// 线程模型：只在进程启动阶段由主线程调用，不涉及后台线程。
// 失败策略：控制台创建失败时静默继续；编码转换失败返回空字符串或空向量。
// 安全边界：只处理本进程命令行，不做 Unicode 归一化，不读取文件或网络。

#ifndef RUNNER_UTILS_H_
#define RUNNER_UTILS_H_

#include <string>
#include <vector>

// Creates a console for the process, and redirects stdout and stderr to
// it for both the runner and the Flutter library.
// 分配新控制台并把 stdout/stderr 指向 CONOUT$，仅用于诊断输出。
void CreateAndAttachConsole();

// Takes a null-terminated wchar_t* encoded in UTF-16 and returns a std::string
// encoded in UTF-8. Returns an empty std::string on failure.
// 非法代理对或转换失败返回空串；不进行 Unicode 归一化。
std::string Utf8FromUtf16(const wchar_t* utf16_string);

// Gets the command line arguments passed in as a std::vector<std::string>,
// encoded in UTF-8. Returns an empty std::vector<std::string> on failure.
// 通过 CommandLineToArgvW 解析并跳过可执行文件名；内存由 LocalFree 释放。
std::vector<std::string> GetCommandLineArguments();

#endif  // RUNNER_UTILS_H_
