import { useEffect, useState } from "react";
import { ping } from "./lib/ipc";

// 幻月占位原型（T00）：一个可拖动的圆形「幻月」。
// 拖动通过 Tauri 2 的 data-tauri-drag-region 实现（需 core:window:allow-start-dragging 权限）。
// 交互刻意保持最简：左键点击切换表情，右键显示提示气泡。不做任何模型调用。
const MOODS = ["(￣▽￣)", "(～﹃～)", "(¬‿¬)", "(つ✧ω✧)つ"] as const;

export default function App() {
  const [mood, setMood] = useState(0);
  const [hint, setHint] = useState<string | null>(null);
  const [ipcOk, setIpcOk] = useState<string>("…");

  useEffect(() => {
    // 挂载时验证前端 ↔ Rust IPC 链路（唯一封装层 lib/ipc.ts）。
    ping()
      .then((r) => setIpcOk(r))
      .catch(() => setIpcOk("offline"));
  }, []);

  return (
    <div
      data-tauri-drag-region
      onClick={() => setMood((m) => (m + 1) % MOODS.length)}
      onContextMenu={(e) => {
        e.preventDefault();
        setHint((h) => (h ? null : "退出请用托盘菜单"));
      }}
      style={{
        width: 120,
        height: 120,
        borderRadius: "50%",
        background: "radial-gradient(circle at 35% 35%, #fdf6d8, #e8d98a 60%, #c9b45f)",
        boxShadow: "0 0 24px rgba(240, 220, 130, 0.55)",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        cursor: "grab",
        fontSize: 20,
        color: "#5a4d1e",
        fontFamily: "system-ui, sans-serif",
      }}
      title={`IPC: ${ipcOk}`}
    >
      <span>{MOODS[mood]}</span>
      {hint && (
        <div
          style={{
            position: "absolute",
            top: 128,
            left: 0,
            whiteSpace: "nowrap",
            background: "rgba(20, 20, 30, 0.85)",
            color: "#eee",
            padding: "4px 8px",
            borderRadius: 6,
            fontSize: 12,
          }}
        >
          {hint}
        </div>
      )}
    </div>
  );
}
