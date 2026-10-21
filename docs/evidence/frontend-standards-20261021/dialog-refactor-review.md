# 讨论、资料与辅助对话框整改及独立复核

日期：2026-10-21。仅修改当前 Flutter 工程，保留原未提交成果；未改生成代码、历史 golden、Rust 或作者数据。

## 实施范围

- cowrite：稳定 State 保留草稿控制器与焦点；把展示快照、操作、候选、历史拆成有职责的 Widget。资料往返冻结 work/chapter/thread，采纳失败不污染已切换的线程；后台去抖保存有明确错误归宿，脏稿与重试出口保留。
- lore/legacy：拆分资料编辑、选择、地图、记忆、人物、导入和小说历史的长 build；保留原 CAS、一次性票据、确认链和异步状态所有者。工具输入/差异/出处使用主题角色；初始化 Future 与订阅释放错误有明确处理。地图关系按钮保留至少48px命中，文字缩放时节点和画布同步增高。
- 追加工作台范围：lore_preview 拆展示数据/历史解析和命名 Widget，以 export 保留旧导入API；动作可换行，减少动态效果时直接定位。workbench_screen 保留原 State 与动作注册表，布局组合改为命名 Widget。

## 本 agent 的实际验证

- 五组 AST 扫描均退出0：cowrite17、lore9、legacy20、lore_preview前缀3、workbench_screen1，共50个自有生产文件，0违规。汇总见 dialog-scope-metrics.json，各组报告在同目录。
- `dart format` 覆盖上述源文件和两个修改的测试文件，最终成功。
- `dart analyze --fatal-infos` 分别检查 cowrite、lore、legacy，均退出0；追加工作台文件在全lib静态截面发现的2个unused import已修正。全库最终分析由root统一执行。
- 新增测试：后台讨论写入失败保留脏稿并可重试；地图200%字号和48px命中。地图打开回调改为异步后，原两处测试fake同步改为async，原断言保留。未单独启动Flutter，统一行为回归交root运行。
- 扫描曾遇单个 analyzer pub缓存文件拒绝访问，重试同一只读扫描后成功；未放宽或豁免检查。

## 对 root 改动的独立只读复核

检查 theme/*、editor_status/save_*、editor_tools/workspace_tool_dialog、work_picker/work_picker_content 与相关异步测试调整。确认主题为职责拆分、状态投影不复制正文或写入；未发现可确认的P1。

发现同型P2：恢复重试/创建作品忽略bool结果并无条件退出当前路由。root已改为成功且发起路由仍current时关闭，并增加负向回归；这两处及rollbackChapter同类修复已静态复核。ConfirmChapterDialog._confirm存在同型退出路径，已向root报告，最终修复与验证由root记录。

真实IME、物理DPI/多屏、屏幕阅读器及原生完整状态矩阵不属于上述AST/组件证据，保持各自实际状态。
