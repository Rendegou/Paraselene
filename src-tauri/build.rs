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

    if let Err(error) = tauri_build::try_build(tauri_build::Attributes::new()) {
        eprintln!("tauri-build failed: {error:#}");
        std::process::exit(1);
    }
}
