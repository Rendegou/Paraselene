//! Isolated stage-A window: packaged product UI, synthetic fixture, no database or credentials.
use tauri::{WebviewUrl, WebviewWindowBuilder};

#[tauri::command]
fn app_ready() -> bool {
    true
}

#[tauri::command]
fn probe_event(metadata: String) {
    // Synthetic-only interaction categories and coordinates; no text, keys or content.
    println!("PROBE_EVENT:{metadata}");
}

const INPUT_OBSERVER: &str = r#"
document.addEventListener('DOMContentLoaded', () => {
  const report = (kind, composing = false) => {
    const active = document.activeElement;
    const selection = document.getSelection();
    const range = selection?.rangeCount ? selection.getRangeAt(0).getBoundingClientRect() : null;
    window.__TAURI_INTERNALS__.invoke('probe_event', {metadata: JSON.stringify({
      kind, tag: active?.tagName || '', role: active?.getAttribute('role') || '',
      editable: Boolean(active?.isContentEditable || ['INPUT','TEXTAREA'].includes(active?.tagName)),
      className: typeof active?.className === 'string' ? active.className : '',
      composing, selection: selection ? {anchor: selection.anchorOffset, focus: selection.focusOffset, collapsed: selection.isCollapsed} : null,
      inputSelection: active?.selectionStart == null ? null : [active.selectionStart, active.selectionEnd],
      rect: range ? [range.x, range.y, range.width, range.height] : null,
      ratio: devicePixelRatio, viewport: [innerWidth, innerHeight],
      visibleCarets: [...document.querySelectorAll('.cm-cursor')].map(x=>{const r=x.getBoundingClientRect();return [r.x,r.y,r.width,r.height]}),
    })});
  };
  for (const kind of ['focusin','compositionstart','compositionend','keydown','pointerup','selectionchange']) {
    document.addEventListener(kind, event => {
      if (kind === 'keydown' && !['Escape','Enter','F7'].includes(event.key)) return;
      requestAnimationFrame(() => report(kind, Boolean(event.isComposing || kind === 'compositionstart')));
    });
  }
  report('ready');
});
"#;

fn main() {
    let mut context = tauri::generate_context!();
    context.config_mut().app.windows.clear();
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![
            app_ready,
            probe_event,
            paraselene_lib::commands::studio_export::studio_export
        ])
        .setup(|app| {
            let window = WebviewWindowBuilder::new(
                app,
                "studio",
                WebviewUrl::App("index.html?design=paragraph".into()),
            )
            .title("幻月 · A阶段合成验收")
            .inner_size(1280.0, 800.0)
            .min_inner_size(760.0, 560.0)
            .initialization_script(INPUT_OBSERVER)
            .build()?;
            println!(
                "PROBE_NATIVE:scale={:?}:size={:?}:position={:?}",
                window.scale_factor(),
                window.inner_size(),
                window.outer_position()
            );
            Ok(())
        })
        .run(context)
        .expect("isolated notebook probe failed");
}
