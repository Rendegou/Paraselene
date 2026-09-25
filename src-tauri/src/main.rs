// 发布构建下不弹出控制台窗口（Windows 子系统设为 GUI）。
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    paraselene_lib::run();
}
