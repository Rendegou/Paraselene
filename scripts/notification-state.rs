//! 只读查看 Windows 当前通知状态，排查桌宠因 BUSY/全屏/演示而隐藏的情况。

#[link(name = "shell32")]
unsafe extern "system" {
    fn SHQueryUserNotificationState(state: *mut i32) -> i32;
}

fn main() {
    let mut state = -1;
    let result = unsafe { SHQueryUserNotificationState(&mut state) };
    println!("query_result={result} notification_state={state}");
}
