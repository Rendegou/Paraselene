cmake_minimum_required(VERSION 3.20)
project(learning_native_probe LANGUAGES CXX)
get_filename_component(ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
set(RUNNER "${ROOT}/apps/desktop/windows/runner")
set(WRAPPER "${ROOT}/apps/desktop/windows/flutter/ephemeral/cpp_client_wrapper")
set(SDK "${ROOT}/build/vendor/webview2-1.0.2903.40/package/build/native")
set(PRODUCTION_SOURCES
  "${RUNNER}/learning_window.cpp" "${RUNNER}/learning_profile.cpp"
  "${RUNNER}/learning_security.cpp" "${WRAPPER}/standard_codec.cc"
  "${WRAPPER}/core_implementations.cc")
add_executable(learning_native_probe probe.cpp ${PRODUCTION_SOURCES})
add_executable(learning_channel_probe channel_probe.cpp ${PRODUCTION_SOURCES})
foreach(PROBE IN ITEMS learning_native_probe learning_channel_probe)
target_compile_features(${PROBE} PRIVATE cxx_std_17)
target_compile_definitions(${PROBE} PRIVATE
  UNICODE _UNICODE NOMINMAX PARASELENE_LEARNING_PROBE)
target_compile_options(${PROBE} PRIVATE /W4 /WX /utf-8 /EHsc)
target_include_directories(${PROBE} PRIVATE "${RUNNER}"
  "${WRAPPER}/include" "${SDK}/include"
  "${ROOT}/apps/desktop/windows/flutter/ephemeral")
target_link_libraries(${PROBE} PRIVATE
  "${SDK}/x64/WebView2LoaderStatic.lib" shlwapi version ole32 user32 advapi32
  "${ROOT}/apps/desktop/windows/flutter/ephemeral/flutter_windows.dll.lib")
add_custom_command(TARGET ${PROBE} POST_BUILD COMMAND ${CMAKE_COMMAND} -E copy_if_different
  "${ROOT}/apps/desktop/windows/flutter/ephemeral/flutter_windows.dll"
  "$<TARGET_FILE_DIR:${PROBE}>")
endforeach()
add_custom_command(TARGET learning_channel_probe POST_BUILD COMMAND ${CMAKE_COMMAND} -E copy_directory
  "${ROOT}/apps/desktop/build/windows/x64/runner/Release/data/flutter_assets/assets/learning"
  "$<TARGET_FILE_DIR:learning_channel_probe>/data/flutter_assets/assets/learning")
