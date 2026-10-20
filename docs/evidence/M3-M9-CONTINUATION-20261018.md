# 2026-10-18 M3–M9 连续实施与验收记录

授权范围：接续现有工作树实施至 M9。原工程只读；不接管作者库，不读取真实 Key，不运行真实模型，不发布。下述“已实现”不代表整个阶段验收完成；本记录替代本文件先前“全部尚未执行”的过期描述。

## 当前实现

| 阶段 | 当前工作树能力 | 未完成或未验证的边界 |
| --- | --- | --- |
| M3 | 输入冻结 epoch、迟到剪贴板拦截、精确 UTF-16 锚点及撤销恢复、多讨论槽位、有限历史容量 | 完整 IME/DPI/多屏与生产编辑器验收；焦点往返等 |
| M5 | Rust 真实线程 CAS、独立 operation、候选原子采纳/拒绝、引用版本复核、讨论草稿写入队列与关闭屏障、输出语言选择 | 统一端到端原生矩阵、更多故障恢复路径 |
| M6 | 六类资料、版本/CAS、按历史记录复核原文及 hash、确认版本引用选择、正文出处装饰/Ctrl点击定位、地图会话内拖动 | 系统对话框组合、地图位置和关系持久化等价实现 |
| M7 | 官方 DeepSeek-only、默认关闭、完整一次性预览与逐次批准、隔离凭据接口、取消/超时/迟到/drop 收尾 | 真实网络/Key 不在本次授权内；未以假测试宣称真实模型通过 |
| M8 | DPAPI 合成 SQLite 完整备份、hash/完整性/schema/FK 校验、新根恢复、强制云关闭、导出及恢复演练 UI；2026-10-19 Release/独立包复验通过 | 净机系统矩阵未执行 |
| M9 历史 | 作品/章节问题、历史草稿阅读/丢弃/载入编辑稿、逐块/全部 legacy patch、RPG两阶段与摘要worker经 Rust CAS/hash 原子采纳 | 原生交互矩阵与真实模型未执行 |
| M9 记忆/导入 | 四个明确记忆空间、创建/纠正/详情/来源/删除/可读导出；显式选择 UTF-8 文件、限额预览/一次确认或取消、事务导入、检索、完整所选源文件保留；想法候选、状态与转换 | 剩余原生验收待执行 |
| M9 角色/桌宠 | 本地私有名、枚举限定分享包、18帧公开素材、透明窗口/拖动/互动/托盘/quiet、运行失败回报 | 实际 Windows 交互、quiet/DPI/多屏矩阵未执行；默认不自动启用 |
| M9 学习 | 独立 InPrivate WebView2、固定本地资源与 worker-inclusive 白名单、禁原生桥接/下载/外部窗口、双语公开前端及 Pyodide、关闭清理串行化、目录句柄固定、超时与错误回报 | 原生学习执行及完整隔离攻击矩阵未执行，不能继承原工程证据 |

## 已执行证据

- FRB 2.11.1 重新生成成功；Windows 内部 shell 钩子禁用，格式化/检查由 pwsh 显式执行。`m5/frb-generation-source-preservation.txt`。
- Rust 应用层 18/18：备份/恢复/损坏、Unicode及非章节出处、legacy patch、记忆隔离、角色包、完整原文保留、导入回滚/取消、SSE失败/取消/drop/关闭云/超时、20万字四次操作及重开。`m5/rust-application-tests-m9-final.txt`。
- 真实 SQLite 讨论集成 1/1：`m5/rust-discussion-integration.txt`。
- 严格 Clippy 全目标通过：`m5/rust-clippy-continuation-final.txt`。
- 编辑器/共写/窗口/生命周期 102/102：`m5/flutter-focused-current.txt`。包含历史容量、原生 gateway 合同；mock 不证明实际桌宠/学习隔离通过。
- 静态检查通过：`m5/dart-analyze-current.txt`（最后标签改动前；需末次复验）。
- 审查修订前 Windows Release 构建通过：`m5/windows-build-learning-reviewed.txt`。最终 Release 已通过：`m5/windows-release-current.txt`；独立包 `m5/bundle-final.txt` PASS，无SDK路径退出0、缺DLL退出1。
- 初次受限 Rust 合成根失败及中间失败日志保留；修正合成 fixture、Windows socket 非阻塞继承后最终18/18通过。没有删除失败证据或更新 golden。

## 审查修订

只读审查指出并修正：主导航失败伪成功、配置目录累积、清理与重开竞态、必需脚本读取失败伪成功、profile 路径替换竞态。最后三项及迟到回调的共享RAII句柄修订已重建通过，末次只读复审无新增可行动缺陷。所有异步回调绑定 generation；清理未完禁止重开、清理失败后本进程禁用；缓存及祖先目录拒绝 reparse 并保持无 delete-share 句柄。源码审查不等于原生安全矩阵通过。

## 保留工作

M3/M5 的表列缺口、M6 的系统对话框组合、M9 的原生交互矩阵仍需继续验收。用户已明确要求做到 M9，不能将未验证的原生矩阵改为 DEFERRED 后宣称完成。最终还需当前源代码全回归、真实 FFI、正式独立包和必要人工系统矩阵；用户 Esc 停止的 Computer Use 未恢复。

## 末次统一回归（记忆操作与BOM修订后）

- Flutter 普通回归与生产范围真实DLL：459/459 PASS，`m5/flutter-regression-bom-final.txt`；隔离 test-support 加密持久库真实FFI：2/2 PASS，`m5/flutter-owned-ffi-current.txt`。未跑或重写golden。
- Rust 工作区265项 PASS，`m5/rust-workspace-current.txt`；后续转换源保护与小说标题同步等迁移定向7项 PASS，`m5/rust-migration-actions-final.txt`。严格Clippy PASS，`m5/rust-clippy-actions-final.txt`。
- Dart无问题：`m5/dart-analyze-final-current.txt`；Dart全目录格式检查、Rust app/bridge格式检查通过。最初未格式化的bridge文件已显式格式化；保留首轮失败输出。
- 真实FFI暴露FRB SSE String解码器吞掉前导BOM，已在固定生成流程中确定性修订，连续两个BOM正文及完整导入原文往返通过：`m5/flutter-m9-real-ffi-final.txt`。生成器升级时若匹配不再唯一直接报错，不能静默失去此合同。
- 原工程和目标core的79份快照共158次SHA256复核一致：`m5/core-source-integrity-current.json`。
- 最新Release和独立包均通过；这只证明构建、桥接与基础合成合同，不证明学习执行隔离、桌宠交互、IME/DPI/多屏通过。
- 首轮普通回归因新增基类声明遗漏编译失败；补正后真实FFI再发现BOM丢失；以上失败日志均保留，没有以删除断言通过。

## 历史草稿后续（同日）

历史面板补齐显式丢弃和“载入为编辑稿”。丢弃只处理同作品同章pending记录、保留历史文本，不触碰正文/确认稿；载入是作者复制操作，经保存屏障与最新revision CAS后保留同章撤销，仍需确认章节，历史draft状态不会冒充accepted。身份/并发/关闭专项只读审查无新增可行动缺陷。Rust迁移定向8/8与Flutter定向30/30通过，严格Clippy及Dart无问题检查通过。该时点RPG/摘要重建仍未完成；随后已补齐，见下节与 M9-CAPABILITY-MAP-20261018.md。

## RPG / 摘要与 M5–M6 最新接续

已完成工具菜单的RPG两阶段与单章摘要手动批准worker，每次发送使用完整预览及一次性票据；取消、上下文变化、超时、Future丢弃或事务失败不会发布迟到结果。摘要仅取确认章，claim/source-head CAS发布，重启及恢复备份只恢复queued，禁止自动网络。RPG不更改工作稿或正稿，只保存pending试写。

M5新增grapheme字符差异和从持久applied操作派生的采纳修订历史，作者快照仍独立。M6新增别名/作用范围选章/精确head候选否决；历史出处高亮并在head/正文一致时定位编辑器。地图等价保留临时预览，地点/拖动/缩放/关系均可达，明确不持久化，并补动态画布和越界保护。正文出处装饰/Ctrl点击已于2026-10-19补齐并验证。

最终普通Flutter/真实DLL471项、Rust最终专项10项、之前工作区273项、严格Clippy、Dart无问题及格式通过。158次原/目标core文件哈希复核一致。末次只读复审无新增确定缺陷。完整入口与日志索引更新在 M9-CAPABILITY-MAP-20261018.md；不是将既有部分结果重命名为完成。原生学习执行/安全攻击矩阵、桌宠/quiet/DPI/多屏、IME及净机安装仍NOT_RUN，未恢复Computer Use、未读取作者数据/凭据、未调用真实模型或发布。

最终构建与独立包：`m5/windows-release-reviewed-staging-fixed.txt` Release PASS（19.6秒增量重建）；`m5/bundle-reviewed.txt` PASS，独立包 `build/m1-distribution-80451878655546a6bc66c2ef566aec04` 移除SDK PATH后诊断退出0，复制包缺DLL退出1。专用test-support持久库真实FFI 2/2 PASS：`m5/flutter-owned-reviewed.txt`。CMake staging修订只读复审无确定问题。上述包未发布、未安装到系统、未接管作者库，不代表真实模型或原生系统矩阵已通过。

## M6 正文出处交互收尾（2026-10-19）

核对发现正文出处装饰与 Ctrl 点击已在当前工作树实现，原“未补齐”记录滞后。首轮定向测试暴露测试用 `BasicEditorController.width()` 在构建期通知、触发 `EditorViewport` 构建期 `setState`；已修正为与生产 `EditorInputClient.width()` 一致。新增出处定位回归覆盖跨章节重载、Unicode 标量 anchor 到 UTF-16 选区、旧 head 与脏正文拒绝定位。

验证结果：Dart 格式与 `flutter analyze --fatal-infos` 通过；出处/编辑器定向32项通过；Rust出处3项通过；排除两个既有 golden 基线差异的普通全量478项通过；Release 与独立复制包通过（无 SDK PATH probe 退出0、缺 bridge DLL 退出1）。完整命令和产物索引见 `M6-SOURCE-INTERACTION-20261019.md`。两个 golden 未重写；真实模型、作者数据接管和原生系统矩阵仍未执行。

## 2026-10-20 继续实施

出处收尾：482项普通回归之后补充真实工作台UI2项、隔离加密库2项及最终无问题静态分析通过，详见M6-SOURCE-MARKS-20261019.md。学习窗口新增独立隐藏原生探针，发现并修复InPrivate清理顺序故障，补齐双语Python执行、Worker/CSP/消息隔离、超时、活Worker与旧代次403、关闭重开；最终Release和独立包通过。完整安全矩阵和其他系统验收仍未完成，详见M9-LEARNING-NATIVE-20261020.md。未恢复Computer Use、未接触作者数据/凭据、未调用真实模型或发布。
