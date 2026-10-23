# FE-001 · 菜单选择合同与实现同步

状态：**PLANNED**。关联需求：W02、W06。当前未认领实施；从[当前队列](../progress.md)接手并登记负责人后开始。用户本轮先统一规范，不能把本任务文档当作修复已经完成。

## 已确认基线

源码基点为 `046530f3149e8e4abdb4342a818503119832c5ee`。2026-10-23 [审计验证](../evidence/agent-frontend-assessment-20261023/verification.json)的普通回归 673 通过、3 失败；其余所选自动检查通过。三项失败分别是宽稿布局，以及选择器 1×/2× 字号合同。

[选择器](../../apps/desktop/lib/theme/workbench_select.dart)使用 `WorkbenchCheckedMenuItem`，其基类为 `PopupMenuItem`；[工作台测试](../../apps/desktop/test/m2_workbench_test.dart)和[控件合同测试](../../apps/desktop/test/ui_completion_contract_test.dart)仍按旧 `CheckedPopupMenuItem` 查找。已复现的是测试与实现失配，不据此宣称真实菜单操作已坏。

## 目标与范围

作者通过真实菜单切换舒适/宽稿与选择器值后，得到正确选中状态；键盘可打开、选择、取消并回到触发器，作者正文逐字不变。覆盖相关中英、适用窄窗及 1×/2× 字号组合。

允许修改菜单共享控件、相关调用点、行为测试与对应文档。沿用当前主题/状态管理/数据权威，不改作者库、Rust schema、模型请求或既有正文合同。

复用 [DESIGN](../../DESIGN.md) 中控件几何/状态与[前端规范](../engineering/frontend-standards.md)。先检查共享控件已有能力；不把机械替换 finder 类型当作完整验收。

## 行为与验收

- 菜单通过稳定值、selected 语义和真实命中验收；宽稿切换后阅读宽度确实变化，原文保持精确一致。
- Enter 打开/选择，Escape 取消；关闭后焦点回到原触发器，状态切换不改变命中区域或抢正文按键。
- 禁用控件不能打开菜单；禁用断言不能因继续查旧类型而空洞通过。
- 三项已知失败恢复；受影响控件、工具栏、键盘/焦点合同通过。发生新的异常或计时器/命中警告时定位原因，不能吞掉警告换绿。

在 `apps/desktop` 中、使用正确的生产能力 DLL 环境运行受影响测试；切片完成后在仓库根运行 `pwsh -NoProfile -File scripts/check-frontend.ps1 -Test` 并记录实际源码/工作树。新增几何或视觉改动时按工作流补实际渲染/比较；本任务不自动重批 golden，也不将系统 IME/DPI 标为通过。

## 交付

尚未实施，验证结果保持上述基线 FAIL。实施后记录文件范围、源码指纹、实际命令/退出码、复核与剩余未测项，再更新当前状态；不覆盖原审计失败记录。
