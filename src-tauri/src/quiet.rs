//! Windows 通知状态适配：全屏、演示或锁屏时收起桌宠。

use std::time::Duration;
use tauri::Manager;
use windows::Win32::System::WinRT::{RoInitialize, RO_INIT_MULTITHREADED};
use windows::UI::Shell::FocusSessionManager;

#[link(name = "shell32")]
extern "system" {
    fn SHQueryUserNotificationState(state: *mut i32) -> i32;
}

fn should_quiet(state: i32) -> bool {
    // QUERY_USER_NOTIFICATION_STATE: NOT_PRESENT, BUSY, D3D_FULLSCREEN,
    // PRESENTATION_MODE。QUIET_TIME(6) 是首次登录后的缓冲期；APP(7)
    // 只表示 Windows Store 应用在运行，不代表应隐藏桌宠。
    matches!(state, 1 | 2 | 3 | 4)
}

fn query_shell() -> Option<bool> {
    let mut state = 0;
    // SAFETY: Windows Shell API 将枚举值写入有效的 i32 输出参数。
    let result = unsafe { SHQueryUserNotificationState(&mut state) };
    if result == 0 {
        Some(should_quiet(state))
    } else {
        None
    }
}

fn combine(shell: Option<bool>, focus: Option<bool>) -> Option<bool> {
    match (shell, focus) {
        (Some(true), _) | (_, Some(true)) => Some(true),
        (Some(false), Some(false)) => Some(false),
        _ => None,
    }
}

enum FocusSource {
    Unsupported,
    Reader(FocusSessionManager),
    Unavailable,
}

fn resolve_focus() -> FocusSource {
    match FocusSessionManager::IsSupported() {
        Ok(false) => FocusSource::Unsupported,
        Ok(true) => FocusSessionManager::GetDefault()
            .map(FocusSource::Reader)
            .unwrap_or(FocusSource::Unavailable),
        Err(_) => FocusSource::Unavailable,
    }
}

fn query_focus(source: &mut FocusSource) -> Option<bool> {
    if matches!(source, FocusSource::Unavailable) {
        *source = resolve_focus();
    }
    match source {
        FocusSource::Unsupported => Some(false),
        FocusSource::Reader(manager) => match manager.IsFocusActive() {
            Ok(active) => Some(active),
            Err(_) => {
                // 下次轮询重建 Reader；瞬时失败不能当作专注已结束。
                *source = FocusSource::Unavailable;
                None
            }
        },
        FocusSource::Unavailable => None,
    }
}

pub fn start(app: tauri::AppHandle) {
    std::thread::spawn(move || {
        // 新线程独立初始化 WinRT apartment；不支持与读取失败分开处理。
        // 读取失败会在下一轮重试，避免启动时的瞬时失败永久关闭专注检测。
        let winrt_ready = unsafe { RoInitialize(RO_INIT_MULTITHREADED) }.is_ok();
        let mut focus = FocusSource::Unavailable;
        let mut quiet_active = false;
        let mut hidden_by_quiet = false;
        loop {
            let quiet = combine(
                query_shell(),
                if winrt_ready {
                    query_focus(&mut focus)
                } else {
                    None
                },
            );
            match quiet {
                Some(true) if !quiet_active => {
                    quiet_active = true;
                    if let Some(card) = app.get_webview_window("card") {
                        let _ = card.hide();
                    }
                    if let Some(pet) = app.get_webview_window("pet") {
                        if pet.is_visible().unwrap_or(false) {
                            if pet.hide().is_ok() {
                                hidden_by_quiet = true;
                            }
                        }
                    }
                }
                Some(false) if quiet_active => {
                    quiet_active = false;
                    if hidden_by_quiet {
                        if let Some(pet) = app.get_webview_window("pet") {
                            if pet.show().is_ok() {
                                hidden_by_quiet = false;
                            }
                        }
                    }
                }
                _ => {}
            }
            std::thread::sleep(Duration::from_secs(5));
        }
    });
}

#[cfg(test)]
mod tests {
    use super::{combine, should_quiet};

    #[test]
    fn notification_states() {
        for state in [1, 2, 3, 4] {
            assert!(should_quiet(state));
        }
        for state in [0, 5, 6, 7, 8] {
            assert!(!should_quiet(state));
        }
    }

    #[test]
    fn focus_or_fullscreen_quiets_and_errors_do_not_invent_a_state() {
        assert_eq!(combine(Some(false), Some(true)), Some(true));
        assert_eq!(combine(Some(true), Some(false)), Some(true));
        assert_eq!(combine(Some(false), Some(false)), Some(false));
        assert_eq!(combine(Some(false), None), None);
        assert_eq!(combine(None, Some(false)), None);
        assert_eq!(combine(None, None), None);
    }
}
