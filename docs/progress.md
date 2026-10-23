> 2026-10-22 前端规范细节接续：补F15几何/命中/焦点验收、菜单状态AST规则和默认本地化生成物freshness，修复工具栏标题挤压、出处Enter误改正文、设置释放竞态及版本读取/回滚失败反馈。最终所选门禁PASS：AST141/0、工具22、ARB336×3、普通676、owned2、文本9、format/analyze、Release与独立复制包；680px/200%截图复看通过。golden未重批，原生物理项NOT_RUN。详细结果见 `docs/evidence/frontend-standards-20261021/detail-followup-20261022.md`；未提交或推送。

> 2026-10-21 前端规范落地与结构整改收尾：按 `docs/engineering/frontend-standards.md` 把工作台/编辑器/讨论/资料/legacy 巨型文件按职责拆成可测试组件，统一令牌/控件/选择器/组件主题入口（`theme/workbench_*`、`workspace/presentation/toolbar_*` 等），新增 AST 结构与 ARB 检查工具及统一入口 `scripts/check-frontend.ps1`，并同步 DESIGN/AGENTS/README。收尾修复上一会话遗留的版式菜单真实点击命中与测试格式问题。同一工作树统一门禁所选项全 PASS：AST 139 文件 0 违规、负向 21、ARB 336×3、format/analyze 无问题、普通回归 640、owned 2、Windows Release、独立复制包（probe 0/缺 DLL 1/path 移除 SDK）；golden 比较 SKIPPED（8 张历史差异未重批），真实 IME/DPI/屏幕阅读器/净机安装 NOT_RUN。证据见 `docs/evidence/frontend-standards-20261021/README.md`，历史 UI 交互与页面覆盖见 `docs/evidence/ui-interaction-20261021/`、`docs/evidence/ui-completion-20261021/`。

> 2026-10-20 整改复核 F1–F4 修复：补正文 composing 快捷键守卫，将生成运行态移至 Registry 以保留收起/重开后的取消能力，资料引用冻结当前作品/章节/讨论，移除 bundle 验证的历史目录自动删除。新增 12 项永久回归；定向 79、普通全量 583、owned 2 项通过，format/analyze、Release、独立复制包与历史目录保留检查通过。新客户端已打开（PID 37404）。真实物理 IME/DPI 等既有 NOT_RUN 边界保留，golden 未重批，未提交工作树。证据见 `docs/evidence/review-fixes-20261020/README.md`。

> 2026-10-20 中文注释补充（按用户要求保留，不回滚）：对生产代码补 Google 风格中文文件头/文档注释——Flutter lib 96 文件、Rust application/bridge 50 文件、Windows runner 19、text_contract 3（测试/集成测试/scripts 仅文件头）；独立新会话核对覆盖 220/220 在范围内文件（.py 工具脚本不在范围），受保护路径 93/93 哈希一致。修正 lore 文档尖括号、Rust 3 处注释缩进，并因中文注释引出 MSVC C4819 给 runner 加 `/utf-8` 后重新构建通过。最终门禁：Dart format/analyze、Rust fmt/check、Flutter 全量502+专项1+隔离2、Rust 292 + 严格 Clippy、Release 与独立复制包全部通过。详见 docs/evidence/COMMENT-PASS-20261020.md。
> 2026-10-20 真实点击测试：找到并采用 dsh-computer-use-win 0.5.0（独立 MCP 模式，UI Automation + 截图 + 点击/输入，兼容当前 DSH 0.1.0-rc.6），对最终 Release 合成示例库完成 10 项真实点击验证（创建示例、查找定位、字数、重命名、目录筛选、全章讨论、讨论索引、真实另存为对话框并取消、中英切换、关闭保存屏障退出），全部 PASS。发现 5 项 UX/自动化边界问题（对话框无关闭按钮、重命名按钮文案、SendKeys 下 Ctrl 组合键未生效待真实键盘复验等），未改代码。未触碰作者库/Key/真实模型。详见 docs/evidence/CLICK-TEST-20261020.md。
> 2026-10-20 小功能迁移补齐：章内查找（Ctrl+F）、Ctrl+S 立即保存、章节字数与内联重命名、章末撤销/重做/讨论本章、全章讨论与讨论索引、章节目录筛选、正文与资料 Markdown 导出、旧想法转换目标查看/编辑（复用既有 memoryDetail/memoryCorrect CAS，无新增 schema/FRB 接口）。普通 Flutter/生产 DLL 回归502项、真实 DLL 专项1项、隔离 owned 2项、Rust 工作区292项、格式/analyze/gen-l10n/严格 Clippy/Release 与独立包均通过。完整原生系统矩阵、真实模型、作者库接管与发布仍未执行；golden 未重写。详见 docs/evidence/SMALL-FEATURES-20261020.md。
> 2026-10-20 学习隔离审计接续：profile/祖先junction、更多popup/自动下载权限、严格GEOLOCATION+DENY、browser崩溃及失败禁重开、原生编码通道双语Open/Pyodide/WM_CLOSE专项均退出0。修复祖先junction校验晚于mkdir造成目标新增目录，修前失败和修后无新目录均有证据；最终Release通过。原生通道未启动Flutter引擎，版本及完整物理系统矩阵仍未完成，M5–M9不整体标完成。详见 docs/evidence/M9-LEARNING-AUDIT-20261020.md。
> 2026-10-20 学习隔离扩展：实际通知权限/同源popup/blob下载拒绝、未知/错误/hardlink profile标记拒绝、profile及祖先重命名固定、探针自有renderer崩溃关闭清理专项PASS（isolation-final退出0）。发现并修复仅FILE_READ_ATTRIBUTES未能阻止目录重命名，新增FILE_LIST_DIRECTORY后修前成功/修后error32/释放后成功均有证据。独立只读复审、正式Release和独立复制包PASS；junction替换/更多变体/browser崩溃/版本/方法通道真实open及物理系统矩阵仍未完成，M5–M9不整体标完成。详见 docs/evidence/M9-LEARNING-NATIVE-20261020.md。
> 2026-10-20 学习窗口原生接续：双语Pyodide、Worker本地403、CSP/宿主消息隔离、无限循环终止、活Worker/旧代次拦截、关闭清理和重开存储清除通过。真实探针发现并修复InPrivate提前释放导致0x8007139F无法重开的缺陷，关闭期防火墙也保持本地拒绝。最终Release/独立包通过；权限/下载/目录攻击等完整安全矩阵及桌宠/quiet、IME/DPI/多屏、净机仍未完成。详见 docs/evidence/M9-LEARNING-NATIVE-20261020.md。出处收尾的真实UI2项、加密库2项及最终静态检查亦通过。
> 2026-10-19 正文出处接续：已补下划线、Ctrl点击、重叠资料选择与键盘入口；当前确认稿/原文/hash由Rust校验，脏正文、旧版本及异步迟到不装饰新稿。482项普通Flutter/真实DLL回归及Rust专项3项通过，静态与严格Clippy通过。详情 docs/evidence/M6-SOURCE-MARKS-20261019.md。下方M6未实现的早期说明保留为历史，当前原生系统矩阵依旧未完成。
> 2026-10-19 M6 出处交互收尾：正文出处装饰、Ctrl 点击与出处定位已验证；修复测试控制器宽度更新在构建期通知导致的 EditorViewport setState 问题，并新增跨章节 Unicode 标量→UTF-16 定位及 stale/脏正文拒绝回归。Dart 格式/analyze、出处定向32项、Rust出处3项、排除既有golden的普通全量478项、Release和独立包均通过；golden未重写，原生系统矩阵仍NOT_RUN。证据见 `docs/evidence/M6-SOURCE-INTERACTION-20261019.md`。
> 本次最终产物：Release及独立复制包通过（移除SDK路径退出0、缺DLL退出1），专用加密持久库FFI 2/2通过；同时修正陈旧CMake缓存将打包指向Program Files的问题，固定仅在项目构建目录staging。未发布或操作作者库，原生系统矩阵仍NOT_RUN。
> 本次接续：补齐RPG两阶段、单章摘要重建及队列恢复、M5字符差异/采纳修订历史、M6别名/范围/候选否决/出处高亮定位和临时地图交互。最终471项普通Flutter/真实DLL回归、Rust专项10项与无问题静态检查通过；原生系统矩阵仍未验证，M5–M9未全部完成。详细证据见 docs/evidence/M9-CAPABILITY-MAP-20261018.md；较早状态保留为历史记录。
> 2026-10-18 历史草稿接续：已增加同章待决试写的显式丢弃，以及保留撤销的“载入为编辑稿”（之后仍需确认章节）。Rust迁移定向8/8、Flutter定向30/30、严格Clippy、无问题静态分析和最新Release通过；独立包结果见 docs/evidence/m5/bundle-historical.txt。只读复审无新增缺陷。RPG、摘要重建及原生隔离/系统矩阵未完成，不将M9标为完成。入口映射见 docs/evidence/M9-CAPABILITY-MAP-20261018.md。
> 2026-10-18 本批统一验证：459项普通Flutter/真实DLL回归、2项隔离加密库FFI、Rust工作区265项及后续7项迁移定向回归、严格Clippy、无问题静态分析、最终Release和独立包均通过。已补齐记忆删除/导出和想法状态/转换，并修复真实FFI发现的前导BOM丢失；学习窗口审查发现的清理/目录/异步句柄竞态已修订。M9仍有RPG、摘要重建、历史草稿操作与原生隔离等验收缺口，未标完成。详情见连续实施记录末节。
> 2026-10-18 接续更新：M8 合成备份/恢复、M9 历史 patch/记忆/导入/想法/角色/桌宠/学习窗口已实现；Rust 应用层18/18、真实讨论集成1/1、严格Clippy及102项定向Flutter测试通过。学习窗口最后三项审查修订正在重建。M9 的 RPG、摘要重建、历史草稿操作、记忆剩余操作及原生隔离/IME/DPI矩阵仍未完成；M3–M9不标整体完成。下方旧状态是历史记录，当前详情以 docs/evidence/M3-M9-CONTINUATION-20261018.md 为准。
> 2026-10-18 新会话连续实施：M3锚点/多槽位、M5持久讨论与候选事务接线、M6资料/历史出处/地图预览、M7官方DeepSeek显式预览/BYOK/取消接口已新增源码与部分合成测试用例，尚未统一验证，阶段均不标完成。M8/M9继续实施。完整记录见 docs/evidence/M3-M9-CONTINUATION-20261018.md。旧已验收与NOT_RUN状态分别保留。

> 2026-10-18 代码优先接续：修复编辑器冻结未拦截原生/异步剪贴板修改、会话锁定到Widget重建间的输入窗口，并初始化Adapter contentEpoch以保留首次编辑历史。用户已要求后续统一测试，收取既有10项批次后停止新测试/分析/构建，最终代码尚未统一验证。当前正式产物仍为上一轮字体修复版。见 docs/evidence/m3/INPUT_FREEZE_FOLLOWUP.md。

> 2026-10-18 最新验证：用户确认原生 caption 正反向 Tab 正常，正式 Release 与独立包复验通过。随后定位并修复既有 M3 编辑器遗漏离线字体回退导致阿拉伯文不可见，真实栅格测试修前失败/修后通过，83项编辑器/窗口/关闭回归、analyze、最新正式构建及独立包通过。golden 未更新，完整 M3/IME 与 M2-W 物理矩阵仍待验收，M5未提升。再次Esc停止桌面操作，合成探针PID24116仍保留。详见 docs/evidence/m3/EDITOR_FONT_FOLLOWUP.md。

> 2026-10-18 最新接续：人工确认标题区拖动与右边框缩放正常，探针原生 move/resize 事件支持该结果。定位并修复 Navigator 外层焦点闭环导致的 caption Tab 不可达；双向遍历、Enter 关闭、模态隔离及生命周期26项通过。用户 Esc 停止 Computer Use，原生键盘复验及最新正式包重建待续；当前 Release 输出为合成 trace 探针，PID19168 未由代理关闭。M2-W 保持 IN_PROGRESS。详见 docs/evidence/m2-window/WINDOW_SHELL_REPORT.md。

# Flutter 迁移进度

## 当前状态（2026-10-22）

| 范围 | 状态 | 证据 |
| --- | --- | --- |
| M0 Text/Locale 合同 | IMPLEMENTED | `docs/evidence/M0-20261015.md` |
| M1 Windows runner/FRB/存储 | IMPLEMENTED | `docs/evidence/M1-20261015.md` |
| M2 多语言与视觉工作台 | IMPLEMENTED（历史基线） | `docs/evidence/M2-20261015.md` |
| M2-W 自绘窗口/导航栏 | IN_PROGRESS（默认启用导航栏，`--system-title-bar` 回退） | `docs/evidence/m2-window/` |
| M3 生产编辑器 | IMPLEMENTED（C 方案生产化；spike 历史见 ADR-003） | `docs/M3-PRODUCTION-EDITOR-PLAN.md`、`docs/evidence/m3/` |
| M4 关闭屏障/恢复导出 | IN_PROGRESS（真实系统矩阵部分 NOT_RUN） | `docs/evidence/M4-20261015.md`、`docs/evidence/m4/` |
| M5–M9 共写/资料/学习等 | 部分完成（完整原生安全矩阵/净机 NOT_RUN，不标整体完成） | `docs/evidence/m5/`…`m9/` |
| 视觉方案对齐原 TS 版 | IMPLEMENTED（代码+回归，真实窗口截图待人工复核） | `docs/evidence/UI-PARITY-20261020.md` |
| 中文注释补充 | PASS（覆盖 220/220 在范围文件；保留不回滚） | `docs/evidence/COMMENT-PASS-20261020.md` |
| 操作一致性整改 R01–R16（批次 A–F） | PASS（R16 清理后重建：571+2 tests、format/analyze 0、Release/bundle/m1/m2/m4 集成通过；真实 IME/DPI/净机 NOT_RUN） | `docs/evidence/operation-parity-20261020/README.md` |
| R15 文档入口整理 / R16 清理重建（批次 F） | 完成（清理 19,960 文件/11.58 GiB；V28 重建 PASS） | `docs/evidence/operation-parity-20261020/batch-F.md`、`cleanup-manifest.md` |
| 最终统一门禁（真实 FFI/Release/bundle/Windows integration/golden 报告） | PASS（golden 单独报告 2 失败：既有视觉基线未重批，未 update） | `docs/evidence/operation-parity-20261020/` 的 `final-*.log`、`bundle-probe/` |
| 原生交互外观合同与控件/页面覆盖（2026-10-21） | IMPLEMENTED（共享 32px 控件底板/48px 命中、DiscussionSurface、控件状态合同；627+owned2 回归、Release/bundle PASS；物理状态矩阵 NOT_RUN） | `docs/evidence/ui-interaction-20261021/README.md`、`ui-completion-20261021/README.md` |
| 前端规范与结构整改（F01–F14，2026-10-21） | PASS（AST 139/0、负向21、ARB 336×3、普通回归640、owned2、format/analyze、Release/bundle；golden SKIPPED、物理项 NOT_RUN） | `docs/evidence/frontend-standards-20261021/README.md` |
| 前端规范细节接续（F01–F15，2026-10-22） | 所选自动检查 PASS（AST141/0、工具22、freshness及9样本、ARB336×3、普通676、owned2、文本9、format/analyze、Release/bundle；golden SKIPPED、物理项 NOT_RUN） | `docs/evidence/frontend-standards-20261021/detail-followup-20261022.md` |

说明：下表与后续段落为历史记录，保留当时的 NOT_RUN 与结论，不因后续批次改写。

> 2026-10-20 操作一致性整改收尾（R01–R16）：按 `docs/engineering/FLUTTER-OPERATION-REMEDIATION-20261020.md` 完成批次 A–F，覆盖保存状态/错误恢复、纸面连续滚动与阅读位置、讨论线程单槽与索引、选区落点与焦点、资料查阅/带入、快捷键层级、出处四态、工具栏折叠、能力提示与候选采纳、文档入口与文件清理。R16 清理 19,960 文件/12,431,014,076 字节，保留并归档唯一验证 PASS 的 M1 发布包于 `build/release-archive/m1-20261020-1445/`；清理后离线重建，`flutter build windows --release` 与独立 bundle 探针 PASS。最终门禁：format 168 文件 0 变化、analyze No issues、生产能力 DLL 全量 571 tests PASS、owned 2 tests PASS、Windows integration m1 1 + m2 1 + m4 2 PASS；golden 单独报告 2 失败（既有视觉基线未重批，未执行 `--update-goldens`）；Rust 源码未改故按 §7.4 NOT_RUN，桥接已重建。净机安装、作者数据库接管、真实 IME/物理 DPI/系统剪贴板仍 NOT_RUN，不宣称通过。工作树未提交。详见 `docs/evidence/operation-parity-20261020/batch-F.md` 与同目录 `README.md`。

> 2026-10-18 M2-W 实施接续：已接入可注入窗口服务、本地化 caption 与共享关窗守卫；修正原生探针发现的 Tooltip Overlay、完整工作台语义屏蔽，以及独立审查发现的释放竞态/焦点语义。23项窗口+生命周期、435项普通Dart回归通过；最终 analyze、正式 Release 和独立分发诊断通过。真实最大化/双击还原/最小化恢复、系统菜单、自定义关闭失败留窗/重复关闭/组合输入恢复导出/明确退出已有证据。M2-W **IN_PROGRESS**：拖动及右边缩放尚未观察到位移，Snap/DPI/多屏/其余缩放/完整原生矩阵未验；默认系统标题栏，`--window-shell` 显式开启。M4 补齐真实系统写入失败、导出后继续编辑、UI版本回退、真实FFI保存失败导出与明确退出，仍不提升 golden/完整IME/M3生产化状态。详见 `docs/evidence/m2-window/WINDOW_SHELL_REPORT.md` 与 M4 NATIVE_FOLLOWUP_REPORT。下方保留历史记录。

> 2026-10-18 本轮实施复验：M4 原生存储审查阻断项已修正；pending 认证、最终密文容量上限、staging 四边界强杀、owned hardlink/reparse、test-support DLL/fixture 隔离均有新证据。真实系统 SaveAs 取消后 Alt+F4 绕过关闭监听的问题已复现并增加 runner 守卫，同路径复验通过；真实系统导出成功/明确退出、真实 Rust 库正常关窗与独立重开正文/hash 通过。220 Rust、420 普通 Dart、2 owned FFI、2 Windows M4 集成、8 生命周期测试通过，Release 独立包通过。未跑 golden，真实系统写入失败/导出后继续编辑组合仍有未验项，M4 不宣称全矩阵完成；M3 生产化、M2-W、M5–M9 状态不提升。详见 `docs/evidence/m4/NATIVE_FOLLOWUP_REPORT.md`。下方保留接续前与历史记录。

> 2026-10-18 接续核对：M0–M2 的通过状态来自历史证据；M3 生产编辑器已有未提交接线，尚无本次复验，旧测试／golden 不覆盖当前工作树。M4 除真实关窗／系统对话框未测，还保留原生持久化审查的 2 项 P1、2 项 P2／证据缺口，不能标完成。自定义标题栏 M2-W 已加入独立迁移计划第 13 节（PLANNED）。详见 `docs/evidence/PROGRESS-REVIEW-20261018.md`；本次未运行测试或构建。

2026-10-15；Owner：当前迁移会话。原工程只读，独立分支 `codex/flutter-migration-20261015`。

- M0 Text/Locale Contract：IMPLEMENTED，9项Dart测试/2项Rust测试、静态检查、5组跨语言向量通过；独立审查已修正质量入口失败证据记录，最终交付验证见 `docs/evidence/M0-20261015.md`。
- M1 Windows runner/FRB/storage：IMPLEMENTED。Build Tools安装退出0；Windows doctor、Release构建、182项Rust测试、严格Clippy、真实FFI/CLI与Windows集成通过。独立复制包移除SDK PATH后验收通过，缺DLL退出1。FRB2.11.1生成绑定重跑无变化；5个core crate的79份快照及原工程559份文件不变。最终独立审查与证据见 `docs/evidence/M1-20261015.md`。
- M2 多语言与视觉工作台：IMPLEMENTED。中英47条ARB、脚本感知fallback、离线字体、目录/作品选择/专注/宽稿/错误区已实现；301项非golden检查（含288组双语布局矩阵）、2项真实字体golden、真实Windows缩放/语言切换、M1诊断回归与Release构建通过。九项统一检查均退出0，独立整体审查批准。详见 `docs/evidence/M2-20261015.md`。
- M3：C_FEASIBILITY_PASS。用户已接受C隔离验证3–5有效人日粗估，并按"优化代价大就通过"规则裁决通过。第二轮增量布局51测试、analyze、profile构建通过，同机profile exit 0：7/7样本输入P95≤29.24ms、装载≤71ms、普通滚动全部通过；首轮真实IME重复字符已修复并经同一物理按键序列复测通过（raw51/`ni`/composing10:12，trace与截图存档）。第三轮单次排版优化（页高取自探针行测，取消双重排版）后51测试/analyze/build/profile仍全过，编辑P95进一步改善（单行25.4→19.8、非重复29.2→22.6），但stress全幅滚动（连续118/120帧超33ms）与无换行长文档中段冷跳（2319ms）确认为懒测量架构固有代价，消除需动验收契约或架构，故按规则接受为已记录限制。此前A/B字体打包错误已更正，重采A/B200k编辑P95约85/214ms；`m3/flutter-profile.json`在19:11被一次误构建重写，A/B对照以`m3/ab-font-validated-profile.json`为准。M3 截止时正式工作台保持只读；后续已获授权进入 M4，作者数据接管仍未授权；C生产化（ADR-003另估12–20人日）未授权。当前见 `docs/evidence/M3-C-20261015.md`，实现细节见 `docs/evidence/m3/c-incremental-implementation.md`，原A/B历史见 `docs/evidence/M3-20261015.md`，投入边界见 `docs/ADR-003-editor-spike.md`。
- M4：IN_PROGRESS（2026-10-16 代码修复已提交 `77e8498`：关闭监听器注册、导出结果门控、目录可见性提前、屏障内 restoreSession/seedDemo、inputLocked 冻结、跨作品内存稿过滤。367 项 Dart 测试 + 211 项 Rust 测试 + analyze/fmt/clippy 全过。真实 WM_CLOSE 与系统保存对话框原生验收仍 NOT_RUN）。切片计划、出口映射与逐片记录见 `docs/evidence/M4-20261015.md`。M4-1 Rust 硬化、M4-2 桥接/repository、M4-3 保存协调器均经独立复审通过；owned-synthetic 冷启动持久化（ADR-004）跨进程/强杀/篡改/毒化验证齐全（`docs/evidence/m4/OWNED_PERSISTENCE_REPORT.md`）；M4-4 工作台接线与 M4-5 关闭屏障/恢复导出完成（`docs/evidence/m4/UI_INTEGRATION_REPORT.md`）。整体独立审查可交付，5 项低危发现：2 项已修并补回归，3 项记录为已知问题（REVIEWS.md）。完整性：原工程 559 源码哈希、core 79 快照一致。范围边界：M4 使用明示的临时简易编辑面（不宣称长文性能），M3 生产编辑器、作者数据接管、真实模型仍未授权。
- M5：讨论/候选/撤销/历史与字符差异已接入，合成与真实DLL回归通过；原生全矩阵未验。
- M6：资料/版本/别名/范围/否决/出处高亮及定位/正文出处装饰/Ctrl点击/临时地图预览已接入；系统对话框组合仍有缺口。
- M7：官方DeepSeek合成层已验证，真实模型未授权/NOT_RUN。
- M8：本地bundle与合成备份恢复已实现；净机安装、IME/DPI/多屏及作者库接管未完成。
- M9：历史小说含RPG和摘要worker、记忆/导入/想法/角色/桌宠/学习均有迁移入口；学习双语Python及原生隔离专项已通过，完整安全矩阵待补齐，桌宠系统矩阵仍NOT_RUN，不能标全产品替代完成。

本轮实施授权已获得。之前规划中的“本轮不实施”仅约束规划交付，不限制本次用户明确要求执行。

M0放在 `packages/text_contract` 而非根Flutter依赖中，保证纯Dart/无UI测试边界；M1未来app引用该包。原计划目录职责不变。

> 2026-10-20 操作一致性整改批次 C（R06/R07/R08）完成：R06 讨论线程改为单活动槽——活动线程按实测高度展开、其余只保留段末 24px 标记且 `height: 0` 不占排版空间，收起保留草稿/标记/引用，卡片有界滚动、切章自动收起；R07 完整索引——顶栏宽窄窗同一入口打开“讨论记录 · N”对话框，列出本章全部线程（失效/整章/未发草稿），按真实 ID 重开不新建，失效线程临时面板保留冻结引文/历史且禁用生成与采纳，线程保存失败在卡片内提示并可重试，未落盘草稿在入口显示角标；R08 选区落点——顶栏抢焦点时用冻结的 UTF-16 区间创建线程，创建后选中锚点、滚动露出卡片并自动聚焦草稿，收起回正文锚点末尾，只读/屏障期间不创建且解锁后折叠临时选区，同时修复编辑器失焦时 `TextInputConnection` 的 attached 断言。新增 `thread_host_test`（3）、`selection_focus_test`（5）、`discussion_index_test`（3），扩展线程布局测试；批次 C 回归 409 tests 通过，dart format 0、`flutter analyze --fatal-infos` 0。真实 IME/桌面矩阵与批次 D–F 未测。详见 `docs/evidence/operation-parity-20261020/batch-C.md`。

> 2026-10-20 操作一致性整改批次 D 完成：R10（快捷键按焦点/层级）——窗口级 Ctrl+F/Ctrl+S 先检查可见路由与 `primaryFocus` 是否在可编辑输入框内，组字期间交还 IME；Escape 每次只退最内层（查找→已展开讨论→专注），重命名/资料/讨论草稿/查找输入框内不再越过最内层操作正文；更多菜单打开时计算最新能力。R09（资料查阅/带入/编辑分离）——侧栏资料行按 ID 打开只读预览卡，明确“带入讨论/展开编辑/关闭”，预览不改引用与模型上下文，保留 32 项引用上限与整章规则，提交时请求快照与当前内容分开展示，长章中部返回不丢滚动/选区/undo。R11（出处四态）——出处接缝区分加载中/空/失败/内容，失败可显式刷新重试、旧响应不装饰新正文，关联资料打不开时保留入口可重试。R13（工具栏按空间折叠）——按实际宽度与文字缩放分层，窄窗保留查找/讨论/索引/更多，章节与版本、模型、版式、专注、导出、语言收进更多菜单；顶栏按钮增加语义名、键盘焦点与 40px 目标高度。新增 `focus_shortcuts_test`（4）、`source_state_test`（5）、`toolbar_fold_test`（4），扩展 `source_marks_test` 四态断言。批次回归 447 tests、dart format 0、`flutter analyze --fatal-infos` 0。真实 IME/桌面矩阵、批次 E–F 未测。详见 `docs/evidence/operation-parity-20261020/batch-D.md`。

> 2026-10-20 操作一致性整改批次 E 完成（R14，§7 矩阵映射）：整章/失效线程明确“只能保留草稿与查看历史，生成需要有效选段”，不伪装整章模型；候选区说明“采纳只写编辑稿、可一次撤销、不创建正式版本”，采纳失败（正文/原目标变化、revision 冲突）显示原因并保留草稿；确认章节提示改为“自动保存/Ctrl+S 只写编辑稿，确认才创建正式版本”。新增 `capability_notice_test`（5，含 20 万字四操作冷启动）；三份 ARB 各 319 键；批次回归 453 tests、dart format 0、`flutter analyze --fatal-infos` 0。§7 的 V01–V28 已在 `batch-E.md` 建立证据映射，真实 Windows/IME/FFI/外网项集中标 NOT_RUN，留最终统一门禁。详见 `docs/evidence/operation-parity-20261020/batch-E.md`。

> 2026-10-20 操作一致性整改（进行中）：按 `docs/engineering/FLUTTER-OPERATION-REMEDIATION-20261020.md` 执行 R01–R16。批次 A（R01 保存状态订阅 EditingSession、R02 全宽度保存失败恢复、R04 资料加载 workId+epoch、R12 搜索作用域/重命名文案）与批次 B（R03 宽稿唯一持久状态、R05 纸面标题/正文/章末单一滚动坐标与阅读位置恢复）已完成：新增 operation_parity 目标测试 317 项、批次 B 回归 419 项全部通过；dart format/analyze 0。真实 FFI/Windows IME/窗口矩阵与批次 C–F 未执行。详见 `docs/evidence/operation-parity-20261020/batch-A-B.md`。

> 2026-10-20 视觉方案对齐接续：按原 TS 版 CSS 重写工作台视觉层（主题令牌、60/48/32 纸面排版、240px 目录、56px 扁平顶栏、章节/资料页签、保存状态点、版式/语言/更多菜单），并把 M2-W 自绘导航栏并入默认界面（--system-title-bar 保留回退）。新增 workbench_sidebar.dart、editor_action_registry.dart，工具入口上移到顶栏“更多”，未删除查找/讨论/导出/模型/备份等功能。format、analyze、502 项 Flutter 回归、2 项 owned 真实 FFI、Release 构建与独立 bundle 探针通过；golden 未重批，Rust 源码未改。真实窗口截图复看待用户确认（已停止 Computer Use）。详见 docs/evidence/UI-PARITY-20261020.md。


> 2026-10-21 原生交互外观合同完成：复现48px按钮底板、默认冷灰Card及编辑器灰绿槽底，统一ThemeData/WorkbenchControls的32px可视底板与48px透明命中、局部焦点和禁用态；段下DiscussionSurface独占暖纸面，Dialog不叠Card，草稿用工具字体；顶栏、章末、菜单与弹窗同类状态已迁移。588普通回归、84定向、4顶栏语义、2 owned、analyze/format、Release与独立bundle通过，680px/200%字号组件截图通过；新版独立客户端已打开并观察展开讨论。历史golden未重批，已有差异和文档保留；真实IME/DPI/原生完整状态矩阵仍NOT_RUN。未提交或推送。详见 docs/evidence/ui-interaction-20261021/README.md。

- 2026-10-21 控件/辅助页收尾：统一7处选择器、状态感知工具输入、Checkbox/Switch、侧栏导航焦点/禁用、浏览/任务弹窗标题角色；整章讨论自适应并去重复状态，补空态和操作层级。普通627+owned2通过，33页尺寸截图，Windows Release及独立bundle通过；未提交/推送，原生完整状态与严格ARB基线元数据缺口见docs/evidence/ui-completion-20261021/README.md。
