fn main() {
    // TEMP DEBUG: capture panic message to a file (cargo swallows build-script stderr here)
    let default_hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        let payload = info
            .payload()
            .downcast_ref::<&str>()
            .copied()
            .or_else(|| info.payload().downcast_ref::<String>().map(|s| s.as_str()))
            .unwrap_or("<non-string payload>");
        let location = info
            .location()
            .map(|l| format!("{}:{}", l.file(), l.line()))
            .unwrap_or_default();
        std::fs::write(
            std::env::var("OUT_DIR").unwrap() + "/../../panic.log",
            format!("panic: {payload} @ {location}"),
        )
        .ok();
        default_hook(info);
    }));

    // tauri-build 只负责图标/版本资源，清单由 embed_manifest_for_all_targets 统一提供：
    // 它默认的清单经 embed-resource 发 `cargo:rustc-link-arg-bins`，只进 bin 目标，
    // 且与本函数下发的全目标清单会重复（RT_MANIFEST 同 ID 冲突）。
    let attrs = tauri_build::Attributes::new()
        .windows_attributes(tauri_build::WindowsAttributes::new_without_app_manifest());
    if let Err(error) = tauri_build::try_build(attrs) {
        eprintln!("tauri-build failed: {error:#}");
        std::process::exit(1);
    }

    embed_manifest_for_all_targets();
}

/// 把应用清单（comctl32 v6 依赖）链进**所有**目标（bin / lib 测试 / example）。
///
/// 背景（2026-09-26 实测踩坑）：tauri-build 默认经 embed-resource 发的是
/// `cargo:rustc-link-arg-bins`——清单只进 bin。lib 测试进程与 example 没有清单 →
/// 绑定 comctl32 v5 → 缺 `TaskDialogIndirect` → 进程以
/// STATUS_ENTRYPOINT_NOT_FOUND (0xC0000139) 启动即死，且无任何输出。
/// `cargo:rustc-link-arg-tests` 又只覆盖 tests/ 集成测试，管不到 lib 单元测试——
/// 所以清单改由本函数用 `cargo:rustc-link-arg=` 全目标下发（单一来源，bin 不再从
/// tauri-build 拿清单，避免同 ID 资源冲突）。
///
/// 清单内容与 tauri-build 默认 windows-app-manifest.xml 一致（comctl32 v6 依赖）。
fn embed_manifest_for_all_targets() {
    if !cfg!(windows) {
        return;
    }
    const MANIFEST: &str = r#"<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <dependency>
    <dependentAssembly>
      <assemblyIdentity
        type="win32"
        name="Microsoft.Windows.Common-Controls"
        version="6.0.0.0"
        processorArchitecture="*"
        publicKeyToken="6595b64144ccf1df"
        language="*"
      />
    </dependentAssembly>
  </dependency>
</assembly>
"#;
    let out = std::env::var("OUT_DIR").expect("OUT_DIR");
    let dir = std::path::Path::new(&out).join("app-manifest-res");
    std::fs::create_dir_all(&dir).expect("create app-manifest-res dir");
    let xml = dir.join("app.manifest");
    std::fs::write(&xml, MANIFEST).expect("write app.manifest");
    // rc 里用绝对路径（windres 以包根为 CWD 解析相对路径，不可靠）；
    // 正斜杠：windres 会把反斜杠当转义符（\t \b \a 全被吃掉，2026-09-26 实测）。
    // 类型必须写数字 24：本版 windres 不把 RT_MANIFEST 当预定义常量，
    // 会退化成字符串类型名（SxS 只认数字 24 → 清单被忽略 → comctl32 v5 →
    // TaskDialogIndirect 缺失 → 0xC0000139，2026-09-26 实测）。
    let rc = dir.join("resource.rc");
    std::fs::write(
        &rc,
        format!(
            "1 24 \"{}\"\n",
            xml.display().to_string().replace('\\', "/")
        ),
    )
    .expect("write resource.rc");
    let obj = dir.join("app-manifest-res.o");
    let status = std::process::Command::new("windres")
        .arg(&rc)
        .arg("-o")
        .arg(&obj)
        .status()
        .expect("run windres（构建前需 export PATH 含便携 MinGW，ADR-0001）");
    assert!(status.success(), "windres 编译应用清单失败");
    println!("cargo:rustc-link-arg={}", obj.display());
}
