# ADR-0001：Windows 构建工具链基线（windows-gnu + 便携 MinGW binutils）

- 状态：已接受（2026-09-26，T00 实测后锁定）
- 决策者：kimi（依据本机实测事实），用户知情（ AGENTS.md 同步更新）

## 背景

AGENTS.md 初版写的是"Rust stable MSVC 为正式打包路径"。T00 实测发现本机**没有安装 Visual Studio / Build Tools**（`C:\Program Files\Microsoft Visual Studio\2022` 是空目录，vswhere 检测不到任何产品），MSVC 链接器不存在；同时 rustup 已装 `stable-x86_64-pc-windows-gnu` 工具链。

## 决定

1. **默认工具链改为 `stable-x86_64-pc-windows-gnu`**（`rustup default` 已切换）。依据：用户自己的 local-ai-chat-manager 已用 MinGW-w64 在 Windows 验证过打包（MSI+NSIS），有成功先例。
2. **便携 MinGW 工具链放在 `C:\tools\paraselene-build\mingw64\`**（仓库外，不入库）：从 MSYS2 镜像（TUNA）提取 gcc / binutils(windres,dlltool,as,ld,ar) / gcc-libs 15.2.0 / libwinpthread / gmp / mpfr / mpc / isl / zstd / crt-git 等包。构建前需 `export PATH="/c/tools/paraselene-build/mingw64/bin:$PATH"`。
3. **`mingw64/bin` 下的 `x86_64-w64-mingw32-gcc*.exe` 等带前缀别名移到 `mingw64/_hidden/`**：rustc 只认带前缀的链接器驱动，找不到才回退 rustup 自包含模式（自带 lld + 自包含 CRT 导入库，链接可靠）；windres 预处理又需要无前缀的 `gcc`，两者共存于 PATH 即可。
4. **src-tauri 的 lib crate-type 只保留 `rlib`**：rustup 自包含模式的 lld 链接 cdylib 时报 `export ordinal too large: 90895`（超过 65535 上限）。幻月是 Windows-only 桌宠，不需要移动端的 staticlib/cdylib；如未来做移动端需重估（届时应改用完整 MSVC 或完整 MSYS2 环境）。
5. 未来若用户安装 VS Build Tools，可切回 MSVC 并废弃本方案（tauri-winres 同样支持 rc.exe）。

## 后果

- 好处：零系统级安装（不动注册表/系统目录），整个工具链一个文件夹可整体删除；构建链路已验证：`cargo check/test/build --workspace` 全绿。
- 代价：多一个 PATH 前置步骤；`pnpm tauri dev/build` 前必须先设置 PATH（已写入 AGENTS.md §2 与 evidence/T00）。打包安装包（T08）时 NSIS/MSI 在 gnu 下的表现需重新实测。
- 已知坑（记录在案）：Git Bash 的 `link.exe`（GNU coreutils）会抢 PATH 导致 MSVC 式报错，排查时先 `where link`；MSYS2 的 gcc-libs 16.2.0-4 是 2353 字节的空元包，运行库 DLL 要用 15.2.0-14 提取。
- 已知坑（2026-09-26 T01 补记）：T00 只验证了 windres + lld 链接，**便携工具链当时不能编译 C**——缺 mingw-w64 CRT 头文件（headers-git），首次编译 libsqlite3-sys 报 `stdarg.h: No such file or directory`；且 `cc1.exe` 不在 `bin/` 下，PATH 未前置 `mingw64/bin` 时会因找不到 `libgmp-10.dll` 等 DLL 而**静默失败**（无任何输出）。修复：从 TUNA 补提取 `mingw-w64-x86_64-headers-git` + `mingw-w64-x86_64-crt-git`（13.0.0.r380，装入 `mingw64/include` 与 `mingw64/lib`）、`mingw-w64-x86_64-windows-default-manifest-20260815-1`（`default-manifest.o`）、`mingw-w64-x86_64-winpthreads-14.0.0.r426`（`libpthread.a` 等导入库）。重装工具链时这四个包缺一不可。

## 验证

- `cargo check --workspace` / `cargo test --workspace` / `cargo build --workspace` 退出码 0（详见 docs/evidence/T00-20260926.md）。
