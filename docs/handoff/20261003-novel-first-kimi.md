# KIMI 交接：小说优先

日期：2026-10-03。研究快照2026-10-02；本文件是提示词快照，执行时先核对最新看板。规划已完成，T05A–T05H实现尚未开始。

## 可直接复制的完整提示词

你在 Windows 项目“幻月 / Paraselene”中继续开发。当前用户要求先把小说共写做成适合长篇的工作台，Python任务延期。请真正执行代码、验证并更新证据，不只再写计划。

工作目录：`D:\MyAgent\paraselene-work`。正式仓库：`D:\paraselene`，当前未经用户授权不向它同步。先执行 `git status --short` 核对现有未提交成果，不reset、不清库、不覆盖其它任务改动。所有命令使用PowerShell7 `pwsh`，禁止powershell.exe/Bash/Docker。

首先设置具体工程会话标题，格式 `YYMMDD | [幻月小说] 动作 + 具体任务`；日期取执行当天。诊断不明用排查，确认缺陷才用修复。

必须依次阅读：

1. `AGENTS.md`、`README.md`、`docs/development-direction.md`、`docs/progress-checkpoint.md`。
2. `docs/engineering/project-map.md`、`docs/engineering/code-standards.md`。
3. `docs/novel/README.md`、`docs/novel/open-source-research.md`、`docs/novel/product-spec.md`。
4. `docs/novel/context-and-storage.md`、`docs/novel/implementation-plan.md`、`docs/adr/0003-longform-novel-workbench.md`。
5. `windows-companion-agent-brief.md`、`幻月-Agent执行Goal.md`和与你修改范围有关的现有T05证据。

现状必须牢记：

- 已有确认稿版本树、试写隔离、局部改写、跑团共写、一次性外发预览及字面设定冲突。历史测试不等于当前原生验收通过。
- 生成目前拼接整作品确认稿，超过30,000字拒绝；目录API带全文。不要只调大常量。
- NovelEditor.tsx、novel-core/lib.rs、memory-core/novel.rs是拆分入口；现有数据库与历史版本必须兼容。
- 长篇工作台、设定集结构化、版本出处、预算上下文、伏笔/动机链、恢复队列全部是PLANNED，不能当成已经有了。
- T06/G12–G14仍PARTIAL且延期，不继续扩展Python；保持隔离窗口/CSP/IPC和轨迹成果有效。

执行顺序：从T05A开始认领并实现，按T05A→B→C→D→E→F→G→H继续。每阶段保持可运行，达标后更新看板与证据再进入下一阶段；不要一次大改全仓，不能以“规划完成”结束实现任务。

第一阶段的具体要求：先复跑相关小说/存储基线，建立长度/复杂度债务清单与质量检查入口，把小说UI/领域逻辑拆成地图中的清晰职责。保持已有行为/接口/资料兼容，暂不顺便更换所有依赖和编辑器。工具不可用要报告，不输出假PASS。T05B才以真实WebView2 spike锁CodeMirror6候选及恢复方案。

最终产品要求：

- 左侧卷章/设定目录，中间当前章节正文，右侧Agent/修改diff/引用三个tab；保留夜空手帐视觉，正文是中心。
- AI输出候选，用户看diff后可逐块/全部应用到编辑稿、拒绝和撤销；用户另行确认才进正稿。
- patch绑定不可变输入、确认头版本、working_revision和原文hash；过期/重复/多块偏移/Unicode都在后端检查。
- 设定集支持人物/关系/世界/时间线/禁忌/文风，作者确认和AI候选分离；所有引用可回到确认版本。
- 伏笔有埋设/发展/回收证据；动机链区分角色认知、世界事实与AI解释。未来计划不自动泄漏到历史章节/POV。
- 上下文分层、有token预算、来源manifest与实际外发预览；硬约束超限阻止发送，摘要/索引依赖变更必须失效重建。
- 按章加载、目录不带全文、编辑缓存有限；本机编辑稿自动保存、可恢复，取消/断网/重启不把不完整候选当正稿。

工程规则：普通函数≤60有效行、React组件≤150、生产模块≤400，按规范的例外与增量债务策略执行；不要继续把所有业务塞到一个组件。纯Rust核心不依赖Tauri，SQL在memory-core，原生API只通过src/lib/ipc.ts。公开API说明契约，注释说明边界和原因。

第三方项目只参考机制，本轮不得粘贴GPL/AGPL源码。首版本机SQLite/FTS/trigram，不引入外部图/向量服务、多Agent军团、一键整本生成或云协作。模型走DeepSeek官方BYOK，不读.env/Key/auth/token文件；合成数据测试，日志/仓库无私人正文。保留云开关、四空间隔离和一次性外发确认。

验证要求：按实施计划N01–N12记录命令、退出码、关键结果、限制和证据。特别测过期patch、重复采纳、多块偏移、中文IME/emoji、未来信息隔离、摘要dirty/恢复、百万字/200章以及强制退出后恢复。浏览器/mock通过不能冒充原生WebView2通过。

已有基线（历史信息，执行时复跑）：2026-10-01过滤一个系统Keyring环境用例后138项Rust测试通过；未过滤仍有NoStorageAccess(1312)。不能说全量已经绿。typecheck/build历史通过。先看`docs/evidence/T06-20261001.md`了解过滤范围，不通过读取凭据规避问题。

可用命令（在pwsh中逐条运行并检查退出码）：

```powershell
$env:PATH='C:\tools\paraselene-build\mingw64\bin;' + $env:PATH
pnpm typecheck
pnpm build
cargo test -p paraselene-novel-core -p paraselene-memory-core --target-dir 'D:\MyAgent\.cargo-target' --offline
cargo check -p paraselene --target-dir 'D:\MyAgent\.cargo-target' --offline
```

每阶段交付：本次任务及可用行为、修改文件、实际验证、失败/未测项、证据链接、下一动作；同步看板/必要spec与ADR。PLANNED/代码已写/合成通过/原生通过分别说明，全部N项当期有证据才宣布小说里程碑完成。不要上传作品、发布或未经授权同步正式仓库。只有必要凭据/权限/付费依赖、不可兼容破坏或实质需求冲突才停并明确说明。

现在先核对最新看板，认领T05A，开始执行。

## 接续提示词（新会话时）

继续幻月小说模块。先读AGENTS和最新进度看板，再读本交接提示词与实施计划。以看板的事实和任务负责人为准，复查上阶段证据与代码，接着第一个依赖满足的未完成T05子任务；不要重复已完成重构或把历史PASS当本次验证。
