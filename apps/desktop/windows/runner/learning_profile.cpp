// 学习窗口的专用 profile 准备实现：在 TEMP 下建立并钉住缓存目录，拒绝重解析点。
//
// 线程模型：在 UI 线程的 Open 流程中同步执行，不跨线程。
// 所有权：打开的目录句柄存入 profile_pins_，由 shared_ptr 生命周期统一关闭。
// 安全策略：父目录先钉住再创建；只复用带精确标记的专用目录，未知目录绝不接管或删除。

#include "learning_window.h"
#include <array>
#include <cstring>

namespace {
// Pin every component without delete sharing. A checked directory cannot be
// renamed into a junction while WebView asynchronously opens its profile.
// 从盘符根起逐级打开目录且不跟随重解析点，并校验最终路径与属性；
// 任一组件是 junction/符号链接或路径不符即失败。
bool PinDirectories(const std::wstring& path, std::vector<HANDLE>& pins) {
  if (path.size() < 3 || path[1] != L':' || path[2] != L'\\') return false;
  for (size_t end = 3; ; ) {
    const auto component = path.substr(0, end);
    // Attribute-only handles do not enforce sharing constraints on Windows.
    // Request directory read access so omitting FILE_SHARE_DELETE pins identity.
    const HANDLE directory = CreateFileW(component.c_str(), FILE_READ_ATTRIBUTES | FILE_LIST_DIRECTORY,
        FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING,
        FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_BACKUP_SEMANTICS, nullptr);
    if (directory == INVALID_HANDLE_VALUE) return false;
    pins.push_back(directory);
    BY_HANDLE_FILE_INFORMATION info{};
    std::array<wchar_t, 32768> final_path{};
    const DWORD length = GetFinalPathNameByHandleW(directory, final_path.data(),
        static_cast<DWORD>(final_path.size()), FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
    auto expected = L"\\\\?\\" + component;
    if (expected.size() > 7 && expected.back() == L'\\') expected.pop_back();
    if (!GetFileInformationByHandle(directory, &info) ||
        !(info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) ||
        (info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) ||
        !length || length >= final_path.size() || _wcsicmp(expected.c_str(), final_path.data()) != 0) return false;
    if (end == path.size()) return true;
    end = path.find(L'\\', end + 1);
    if (end == std::wstring::npos) end = path.size();
  }
}
}

// 先钉住 TEMP 父目录，再创建或复用专用缓存目录并写读标记；
// 标记内容或硬链接数不符时失败，不把未知目录当作 WebView2 profile。
bool LearningWindow::PrepareProfile() {
  wchar_t temporary[MAX_PATH];
  const DWORD count = GetTempPathW(MAX_PATH, temporary);
  if (!count || count >= MAX_PATH) return false;
  std::wstring parent(temporary, count);
  while (parent.size() > 3 && parent.back() == L'\\') parent.pop_back();
  profile_pins_ = std::make_shared<ProfilePins>();
  // Validate and pin the parent before any filesystem mutation. Otherwise a
  // junction in TEMP could receive a new directory even though startup fails.
  if (!PinDirectories(parent, profile_pins_->handles)) return false;
  profile_ = parent + (parent.back() == L'\\' ? L"" : L"\\") + L"paraselene-flutter-learning-cache-v1";
  const bool created = CreateDirectoryW(profile_.c_str(), nullptr) != FALSE;
  if (!created && GetLastError() != ERROR_ALREADY_EXISTS) return false;
  if (!PinDirectories(profile_, profile_pins_->handles)) return false;
  const DWORD attributes = GetFileAttributesW(profile_.c_str());
  if (attributes == INVALID_FILE_ATTRIBUTES || !(attributes & FILE_ATTRIBUTE_DIRECTORY) ||
      (attributes & FILE_ATTRIBUTE_REPARSE_POINT)) return false;
  // Claim only a new dedicated directory, or reuse our exact marker. An unknown
  // existing directory never becomes a WebView profile and is never removed.
  const auto marker = profile_ + L"\\PARASELENE_LEARNING_CACHE_V1";
  constexpr char expected[] = "paraselene-flutter-learning-cache-v1\n";
  const HANDLE file = CreateFileW(marker.c_str(), created ? GENERIC_WRITE : GENERIC_READ,
      FILE_SHARE_READ, nullptr, created ? CREATE_NEW : OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  BY_HANDLE_FILE_INFORMATION info{};
  bool valid = GetFileInformationByHandle(file, &info) && !(info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) && info.nNumberOfLinks == 1;
  DWORD length = 0;
  if (created) valid = valid && WriteFile(file, expected, sizeof(expected) - 1, &length, nullptr) && length == sizeof(expected) - 1;
  else {
    std::array<char, sizeof(expected)> bytes{};
    valid = valid && ReadFile(file, bytes.data(), static_cast<DWORD>(bytes.size()), &length, nullptr) &&
        length == sizeof(expected) - 1 && std::memcmp(bytes.data(), expected, length) == 0;
  }
  CloseHandle(file);
  return valid;
}
