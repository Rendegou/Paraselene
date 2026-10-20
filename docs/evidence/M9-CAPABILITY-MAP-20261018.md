# M9 迁移入口与证据（2026-10-18 当前工作树）

本表用于追踪实际迁移和剩余工作，不能替代实现或将 NOT_RUN 改成完成。原工程只读、作者库/真实凭据/模型请求/发布均未执行。

| 原能力 | Flutter / Rust 接入 | 当前证据与边界 |
| --- | --- | --- |
| 逐块patch | 历史面板 LegacyPatchCard → apply_legacy_patch → core原子提交 | Rust部分采纳/过期拒绝通过；operation-owned候选仅走M5引用复核入口 |
| open questions | 历史面板按确认文本列出问题并选章 | 源码接入；原生交互矩阵未执行 |
| 历史试写 | LegacyDraftCard：完整可读、状态/来源本地化、显式丢弃、载入编辑稿 | 丢弃范围/重复/保留正文Rust通过；载入经保存屏障、CAS和保留撤销；仍需确认章节，不标原历史draft accepted |
| RPG两阶段 | 工具菜单 → ReviewedTaskDialog → 原core两阶段准备/场景校验 → 一次性固定端点发送 | 场景临时保存，回复只写pending试写；每阶段独立完整材料预览与明确批准，输出语言独立；回环SSE与真实DLL的无网络守卫通过。真实模型 NOT_RUN |
| 摘要/重建 | 工具菜单手动批准的单章worker；持久队列、claim/head CAS；历史面板显示有效性/队列状态 | 只发送确认稿；预览不建任务，批准后事务认领；取消/超时失败、来源变化拒绝发布；重启/备份恢复只回queued，禁止自动外发。真实模型 NOT_RUN |
| 记忆四空间 | MemoryDialog及MemoryActions，scope/work/CAS由Rust复核 | 创建/纠正/来源/删除/可读导出通过源码接入与真实FFI；导出是可读视图，不冒称恢复备份 |
| 想法来源/状态/转换 | 显式确认导入候选、合法状态菜单、三目标转换 | 真实FFI：来源保留、旧状态拒绝、重复转换拒绝、已转换源保护、过期删除拒绝；小说转换后的目录刷新保留当前编辑器 |
| 导入/检索 | 系统显式选文件→限额预览→一次确认或取消，完整所选原文另行保存 | UTF-8 BOM/CRLF/Unicode、事务重复回滚、备份重开、取消容量释放通过；不扫描磁盘 |
| 角色分享包 | CharacterDialog + core枚举限定包 | 私有名不导出、未知脚本字段拒绝、备份恢复通过 |
| 桌宠/托盘/quiet | 注入服务+独立原生透明窗口、固定公开素材、quiet检测、错误回报 | gateway测试/构建/审查通过；实际交互、系统quiet、DPI/多屏 NOT_RUN |
| Python学习窗口 | 独立InPrivate WebView2、固定资源白名单、无宿主桥、双语页面、Pyodide | 2026-10-20双语真实Python、Worker403、CSP/消息、超时、关闭清理重开专项PASS；权限/下载/popup/崩溃/目录攻击等完整矩阵仍未完成 |

## 当前验证

- 普通Flutter/真实生产范围DLL：459项通过（历史操作前统一回归），随后历史接口/保存屏障/关闭/外部撤销30项定向通过。
- 加密owned-synthetic专用DLL真实FFI：2项通过（历史新接口前；原持久接口未改变）。
- Rust工作区265项通过；后续历史/记忆等迁移定向8项通过。严格Clippy通过；Dart静态检查无问题。
- 绑定生成已固化前导U+FEFF保留：原生成SSE解码器会吞BOM，真实双BOM正文及完整导入原文回归已通过。重新生成后补丁持续生效。
- 旧失败输出、golden失败图片和既有合成证据均保留；未重写golden基线。
- 2026-10-19 M6出处交互收尾：出处定向/编辑器32项、Rust出处3项、排除既有golden的普通全量478项、格式/analyze、Release与独立包均通过；详见 `M6-SOURCE-INTERACTION-20261019.md`。
- 2026-10-19当前代码Release与独立包见 `m5/m6-windows-release-20261019.txt`、`m5/bundle-20261019/copied-bundle-status.json`；`m5/windows-release-historical.txt`、`m5/bundle-historical.txt`仅保留历史记录。

## 本次 RPG / 摘要 / M5–M6 接续

- 最终普通Flutter与生产DLL：471/471 PASS，`m5/flutter-regression-reviewed-complete.txt`；包含新RPG逐阶段批准、迟到取消显示已提交结果、空引用历史、20万字差异有界显示、出处Unicode标量高亮、地图拖动/二倍缩放/越界/71地点等回归。
- Rust整工作区273项 PASS（`m5/rust-workspace-reviewed.txt`），随后最终reviewed专项10/10 PASS（`m5/rust-reviewed-complete.txt`）；后者包含事务回滚不得读取Key、重启和恢复备份隔离。当前严格Clippy和Rust格式通过；Dart无问题分析及格式通过。
- M5历史从持久operation的applied终态投影采纳修订，作者snapshot不混入服务端candidate。字符差异按完整grapheme比较，超过有界窗口显示整段改动，保留逐字往返；相邻span合并。
- M6别名/作用范围选章/候选否决已接入，否决复核work/head/status；跨作品或归档章节不能成为from范围。出处按记录版本高亮，只在当前head及工作文本一致时定位编辑器，旧版不会套用新正文坐标。
- 地图明确选择“等价保留临时预览”：只显示地点，窗口内拖动、缩放、临时关系开关可用；动态画布及边界限制防止卡片丢失。原native未保存related/position，本次不新增数据库schema或冒称持久地图。
- 只读审查三项P2（空target、迟到取消隐藏结果、地图越界）均已修正并有回归；末次复审无新增确定缺陷。首轮失败日志保留，未删除断言或改golden。
- 实际学习Python执行/隔离攻击、桌宠/托盘/quiet、IME/DPI/多屏、净机安装和作者数据接管依旧未验证；用户停止的Computer Use未恢复。M5–M9不统一标为完成。正文出处装饰/Ctrl点击已于2026-10-19补齐并验证，M6剩余系统对话框组合与原生矩阵。
- 构建门禁额外发现并修正：旧CMake cache的安装前缀为Program Files，导致已编译目标在打包阶段失败。系统对应目录不存在；现固定为当前target旁的本地bundle staging，缓存不能将打包导向系统目录。缺失的固定WebView2编译SDK按已锁SHA256恢复，无系统运行时安装。失败日志保留在 `m5/windows-release-reviewed.txt`、`m5/windows-release-reviewed-final.txt`，后续结果单列。
- 新增设定别名/范围/候选否决的Rust回归1/1 PASS：`m5/rust-lore-reviewed.txt`，覆盖跨作品范围、过期head和重复否决。

最终构建与独立包：`m5/windows-release-reviewed-staging-fixed.txt` Release PASS（19.6秒增量重建）；`m5/bundle-reviewed.txt` PASS，独立包 `build/m1-distribution-80451878655546a6bc66c2ef566aec04` 移除SDK PATH后诊断退出0，复制包缺DLL退出1。专用test-support持久库真实FFI 2/2 PASS：`m5/flutter-owned-reviewed.txt`。CMake staging修订只读复审无确定问题。上述包未发布、未安装到系统、未接管作者库，不代表真实模型或原生系统矩阵已通过。

## 2026-10-19 正文出处接续

M6正文出处装饰/Ctrl点击缺口已补齐：Rust按当前head及精确原文校验范围/hash，Flutter按同一帧矩形绘制/命中，提供重叠选择与键盘入口，编辑和异步过期隐藏旧标记。回跳前再核对来源head及正文；历史资料仍可读。482项普通Flutter/真实DLL回归、Rust专项3项与严格检查通过，末次只读复审无新增确定缺陷。详见 `M6-SOURCE-MARKS-20261019.md`；此前“正文出处尚未补齐”的说明是历史状态。原生系统/隔离/净机矩阵不因此标完成。

## 2026-10-20 学习窗口原生接续

双语Pyodide、Worker明确403及原生拦截观察、CSP/宿主消息、超时后继续运行、活Worker/旧代次防火墙、关闭重开存储清除和禁止导航收拢已通过专项真实原生测试。修复InPrivate controller提前释放导致清理失败的0x8007139F；最终Release和独立包通过。此前全部NOT_RUN已被本次部分替代，完整权限/下载/popup/崩溃/profile攻击/版本矩阵仍待补齐。详情 M9-LEARNING-NATIVE-20261020.md；M5–M9不整体标完成。
