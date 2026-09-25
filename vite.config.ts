import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Tauri 2 期望 dev server 固定端口且环境变量前缀放行 TAURI_ENV_*（tauri.conf.json devUrl 指向此处）。
export default defineConfig({
  plugins: [react()],
  clearScreen: false,
  server: {
    port: 1420,
    strictPort: true,
  },
  envPrefix: ["VITE_", "TAURI_ENV_*"],
  build: {
    target: "es2021",
    // Vite 8 默认使用 rolldown 内置压缩器；esbuild 压缩需另行安装 esbuild 包，不引入。
    sourcemap: false,
  },
});
