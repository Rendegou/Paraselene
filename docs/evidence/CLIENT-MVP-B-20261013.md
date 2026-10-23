# CLIENT-MVP B：正式工作台与可靠保存接线

日期：2026-10-13。负责人：codex/client-mvp-20261012。状态：IMPLEMENTED / NATIVE_ACCEPTANCE_IN_PROGRESS；尚不宣称离线写作出口或 CLIENT_MVP_PASS。

本次继续接手 Kimi 的领域适配层与 B 薄命令，保留工作副本现有修改。只在 `D:\MyAgent\paraselene-work` 工作，未同步原仓库、未读私人作品或 Key、未调用模型。

## 实现范围

- 原生默认入口使用正式作品选择/新建，浏览器与独立设计预览仍显式使用预览数据；原生不初始化预览 localStorage，正式读取失败不降级示例。
- 目录读取摘要，正文按章加载。工作区拥有独立保存协调器；正文、资料、偏好与线程分别持久化。正文包含空稿，保存状态绑定 CAS revision。切章、切作品、归档、版本操作与关闭均先冻结编辑并等待保存；失败保留草稿并取消导航/退出，允许重试与导出。
- 最近作品、最近章节、版式和滚动位置复用 settings。损坏偏好不阻断正文；损坏最近作品记录不阻断作品列表，重建前保留原值备份。
- 章节新建/显式重命名/全集重排/可恢复归档、当前章查找；归档与非章节文档在重排中保留。旧入口统一请求 studio 保存屏障后的切换。
- 人物/地点/世界资料分别保存与明确确认。资料重试使用保存屏障，避免迟到读取覆盖新输入。出处绑定不可变版本和 Unicode 字符范围，校验选段，旧出处只读查看绑定版本，不猜测相似句。
- 资料批量重读先读取完整快照，全部成功后才安装正文与 CAS revision；单项读取失败不会在旧可见稿背后安装远端新 revision。迟到的旧批次不覆盖新批次。出处当前状态按最新目录 head 重新计算，确认/回退后不会沿用旧缓存标记。
- 查看出处时按储存的 Unicode 字符范围高亮并滚动到绑定版本中的原句；范围无效明确提示，仅显示绑定版本。版本弹层 Escape 只关闭当前层并恢复焦点。
- 作者确认当前稿与持久回退复用原子内核：head/revision/base/context 同事务检查；确认、编辑稿 rebasing、回退与弃稿失败整体回滚。确认稿仍须非空，自动保存不移动正稿。
- 段落讨论保存目标快照、草稿、引用、要求和记录。迟到线程读取按最新正文校验锚点，无法证明映射就失效；冲突保留本地草稿，不自动覆盖。正式候选按钮禁用示例，界面明确模型未连接。
- Markdown 系统导出逐章读取其他正文并包含当前内存稿，可用于保存失败时备份；讨论不混入正文。关闭命令失败会解除冻结并持续显示错误。
- 若其他章节读取失败，仍可导出当前内存稿、可读章节和可见资料；文件名标明恢复稿，成功后持续说明遗漏章节数量，不报完整作品导出成功。数据库不可读的回归测试覆盖此备份边界。
- 新增独立 `native_workspace_probe`：嵌入构建产物，显式合成 SQLite 路径，不打开 appdata，不注册凭据或模型命令。原生操作证据另行追加。
- probe 可显式传 `--fail-body-saves` 做测试专用正文写入错误注入；不传参数走真实 core 保存。此旗标不进入正式产品命令或修改数据库内容。

## 已执行检查

PowerShell 7 / Windows GNU Rust，target-dir `D:\MyAgent\.cargo-target`；Rust 构建 PATH 前置 `C:\tools\paraselene-build\mingw64\bin`。

1. `node node_modules/typescript/bin/tsc --noEmit`：退出 0。
2. `node scripts/quality/run-web-tests.mjs`：最终 81/81 PASS，0 skipped；含保存并发/屏障、线程 CAS/加载竞态、UTF-16/emoji 坐标、空基准、全集重排和跨作品重命名拒绝。
3. `node scripts/quality/code-metrics.mjs --verify docs/engineering/code-metrics-baseline.json --json`：baseline/current 7，added=[]，退出 0。
4. 同工具 `--ipc-boundary --json`：只有 `src/lib/ipc.ts` 为允许入口，offenders=[]，退出 0。
5. 最终 Vite build：退出 0，198 modules。主包约 547.78 kB，gzip 178.10 kB，存在 >500 kB 构建警告，未调整门槛隐藏警告。
6. `cargo build -p paraselene --example native_workspace_probe --target-dir D:\MyAgent\.cargo-target --offline`：退出 0。首次资源文件 os32 被占用，停止唯一合成 A 窗口后重试通过。
7. `cargo test -p paraselene --lib commands::studio_workspace::tests --target-dir D:\MyAgent\.cargo-target --offline`：1/1 PASS；损坏 recent 不阻断已有/新作品、原值备份、重建断言。14 其他测试 filtered，不宣称全量 Tauri tests PASS。存在旧 quiet dead-code 警告。
8. Rust AST：baseline/current 36，added=[]，退出 0。memory-core 119 测试、迁移故障/重开与原子故障测试详见 [存储证据](CLIENT-MVP-B-STORAGE-20261013.md)。
9. `cargo clippy -p paraselene-novel-core -p paraselene-memory-core --target-dir D:\MyAgent\.cargo-target --offline -- -D warnings`：退出 0，无警告；`cargo test -p paraselene-novel-core ... --offline`：34/34 PASS，0 filtered，存在历史测试 unused-variable 警告。

## 验收边界

最终隔离构建：`native_workspace_probe.exe` SHA256 `9D1F313271FDCD84D21817D6DB50CFBED668E461193009FD46027D60136AF809`；嵌入 `index-CYa-Mhep.js` SHA256 `ADAB26D045711373D49972B0BCB1DEFA915C2185E1379F3FF766CFFD3D25A337`。此构建已冻结交由原生验收；初版正文恢复证据与最终版分开记录，见 [B原生](CLIENT-MVP-B-NATIVE-20261013.md)。不是安装产物。

真实 Key、真实请求/取消/候选采纳为 C，尚未接线。安装包及安装后恢复为 D，尚未运行。原生 B 合成流程正在验证；A 完整 IME、DPI 与焦点出口仍 PARTIAL，见 [A 原生证据](CLIENT-MVP-A-NATIVE-20261012.md)。全仓 cargo-fmt 历史债务未消除，定向格式化不等于全仓 PASS。

下一步：完成同一嵌入构建的原生新建/立即切章/关闭重开/资料/线程/导出验证，修复实际失败后形成 B 出口；随后接最小安全 C 预览/发送/取消/采纳与安装后 D。
