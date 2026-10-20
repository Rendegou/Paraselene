cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "native_close_guard.cpp"
  "companion_window.cpp"
  "companion_paint.cpp"
  "companion_quiet.cpp"
  "learning_window.cpp"
  "learning_security.cpp"
  "learning_profile.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# 源文件（含中文注释）为 UTF-8 无 BOM；MSVC 在 GBK 代码页下会按 ANSI 解析，
# 触发 C4819 并导致语法错误。显式按 UTF-8 读取源文件，保证注释编码不影响构建。
if(MSVC)
  target_compile_options(${BINARY_NAME} PRIVATE "/utf-8")
endif()

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "gdiplus.lib" "shell32.lib" "windowsapp.lib")
get_filename_component(LEARNING_SDK "${CMAKE_CURRENT_SOURCE_DIR}/../../../../build/vendor/webview2-1.0.2903.40/package/build/native" ABSOLUTE)
if(NOT EXISTS "${LEARNING_SDK}/include/WebView2.h")
  message(FATAL_ERROR "Run scripts/prepare-learning-sdk.ps1 before building the isolated learning window")
endif()
target_include_directories(${BINARY_NAME} PRIVATE "${LEARNING_SDK}/include")
target_link_libraries(${BINARY_NAME} PRIVATE "${LEARNING_SDK}/x64/WebView2LoaderStatic.lib" "shlwapi.lib" "version.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
