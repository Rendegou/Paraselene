// 伴侣“安静”判定接口声明。
//
// 线程模型：必须在 UI 线程调用，内部访问 COM/WinRT 系统服务。
// 契约：true/false 分别是安静与不安静；nullopt 表示未知，调用方必须沿用上一次状态。

#ifndef RUNNER_COMPANION_QUIET_H_
#define RUNNER_COMPANION_QUIET_H_
#include <optional>
// Unknown must retain the last quiet decision; never invent an all-clear.
std::optional<bool> CompanionQuiet();
#endif
