import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";

// 渲染入口：挂载点由 index.html 保证存在，故这里的非空断言是安全约定。
// StrictMode 在开发环境会故意双调用 effect；本项目的订阅/定时器 effect 均已带清理函数，
// 依赖 effect 幂等清理的设计，不要把"双调用导致请求两次"当作预期外行为来规避。
ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
