# Build the owned bridge with an explicit toolchain; never change rustup default.
find_program(PARASELENE_CARGO cargo REQUIRED)
get_filename_component(PARASELENE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../.." ABSOLUTE)
set(PARASELENE_RUST_TARGET "${PARASELENE_ROOT}/build/rust-m1-msvc")
set(PARASELENE_BRIDGE_DLL "${PARASELENE_RUST_TARGET}/release/paraselene_bridge.dll")
file(GLOB_RECURSE PARASELENE_RUST_INPUTS CONFIGURE_DEPENDS
  "${PARASELENE_ROOT}/rust/application/src/*.rs"
  "${PARASELENE_ROOT}/rust/bridge/src/*.rs"
  "${PARASELENE_ROOT}/rust/core/*/src/*.rs"
  "${PARASELENE_ROOT}/rust/core/*/src/*.sql"
  "${PARASELENE_ROOT}/rust/*/Cargo.toml"
  "${PARASELENE_ROOT}/rust/core/*/Cargo.toml")
add_custom_command(OUTPUT "${PARASELENE_BRIDGE_DLL}"
  COMMAND "${PARASELENE_CARGO}" +stable-x86_64-pc-windows-msvc build
    --manifest-path "${PARASELENE_ROOT}/rust/Cargo.toml"
    --package paraselene-bridge --target-dir "${PARASELENE_RUST_TARGET}"
    --release --locked --offline
  DEPENDS ${PARASELENE_RUST_INPUTS} "${PARASELENE_ROOT}/rust/Cargo.lock"
  COMMENT "Building Paraselene synthetic-only Rust bridge (MSVC)"
  VERBATIM)
add_custom_target(paraselene_rust_bridge ALL DEPENDS "${PARASELENE_BRIDGE_DLL}")
add_dependencies(${BINARY_NAME} paraselene_rust_bridge)
install(FILES "${PARASELENE_BRIDGE_DLL}" DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

# Bundle the compiler's redistributable release CRT beside both native DLLs.
set(CMAKE_INSTALL_SYSTEM_RUNTIME_DESTINATION "${CMAKE_INSTALL_PREFIX}")
set(CMAKE_INSTALL_SYSTEM_RUNTIME_COMPONENT Runtime)
include(InstallRequiredSystemLibraries)
if(NOT CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS)
  message(FATAL_ERROR "MSVC redistributable runtime libraries were not found")
endif()
