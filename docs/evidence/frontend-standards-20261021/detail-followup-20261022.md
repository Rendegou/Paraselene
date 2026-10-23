# 前端规范与细节验收接续 · 2026-10-22

本轮在 `b1f9c43` 之后继续修改。上一次已提交的 F01–F14 与 640 项结果保留在本目录 README；它们不自动证明本轮工作树通过。未提交、未推送，未读取作者库/凭据或发模型请求；8 张既有 golden 差异图保留。

## 规范补强

- F03 明确有职责的既有 part 命名空间和禁止碎片拆分规避长度的界限。
- F05 要求菜单真正消费共享状态；固定 SDK 的 `PopupMenuButton.child` 不消费完整 ButtonStyle，所以相关入口迁到原生按钮分支，AST 增加 `menu-state-style` 和正反例。
- F08 明确编辑器只处理自身 primaryFocus 的正文键，嵌入控件的按键交还原生 Actions。
- F09 要求弹窗内操作失败在当前弹窗反馈原因，不能由被遮挡的工作台错误条承担。
- F10 明确同步 setState、await 后控制器与原 route 生命周期、身份校验。
- F13 默认门禁新增官方 gen-l10n 输出 freshness，隔离生成并逐路径/原始字节比较，不写真实输入和生成物。
- F14 仅沿用历史注释文档的风格与契约说明，不把旧“只改注释”任务边界带到一般功能修正。
- F15 增加文字真实几何、命中边缘、焦点与关闭恢复验收；区分共享合同、逐页观察、golden 和物理系统证据。

入口仍是 `docs/engineering/frontend-standards.md`、`DESIGN.md`、`scripts/check-frontend.ps1`，没有增加互相竞争的规范。

## 已修路径与复现

1. 工具栏按当前译文、文字缩放、选区/讨论能力及保存状态测量宽度，预留标题与状态，正常标题保持单行；长作者标题有完整可访问文字和 tooltip。修前 `toolbar-before-test.txt` 实测标题需要 76.25px、仅得到 20.30px。移除挤占空间的 Spacer，文字放大时顶栏可增高。
2. 出处菜单与重试使用共享 48px 命中及 2px 局部键盘焦点。`sources-before-test.txt` 保留常规/200% 命中不足的失败；新回归检查底缘命中、Material 实际焦点边框和恢复。
3. 出处按钮已获 primaryFocus 时，外层 EditorViewport 仍先消费 Enter，在正文开头插入换行。`sources-editor-focus-before.txt` 精确原文断言修前失败；`_key` 的 primaryFocus 守卫修正按键归属。原生 IME 验收没有由这个合成按键测试替代。
4. 设置保存/删除先冻结参数，迟到结果不再访问已经释放的输入控制器；成功只关闭原 route。18 项 gated fake 覆盖四个等待阶段、成功/失败、Escape/外点及保留弹窗后的恢复。
5. 版本列表区分加载/失败/空/内容，缓存查询并显式重试；冻结作品/章节，回滚继续检查成功值、mounted 与原 route。10 项合成测试覆盖同步/异步读取失败、查询重用、身份切换和迟到回滚。复核又发现回滚 false 只让弹窗保持打开、没有局部错误；补 liveRegion 稳定错误码，保留版本列表与重试，成功后才关闭；有覆盖路由时只记录本弹窗的失败，不关闭新路由。
6. 版式测试点击真实 CheckedPopupMenuItem 行，启用命中警告失败守卫，不再点击 IgnorePointer 中的文字换取虚假操作通过。

英文长保存冲突/失败还增加 1040/1060 窗口边界回归，已有选区与讨论索引同时存在；恢复入口可实际点击、重试/导出可达，正文保持精确不变。更多菜单有真实键盘焦点轮廓，Enter 打开、Escape 关闭并归还焦点。5/5 PASS，见 `toolbar-state-regressions.txt`；首轮把触摸焦点当键盘焦点的测试配置失败另保留。

## 验证记录

`detail-regressions.txt` 是首轮 38/41：两个出处键盘回归失败并定位上述正文按键归属；一个版本重试捕获新增 setState 回调返回 Future，已改同步 block。`detail-regressions-after.txt` 是 40/41：剩余失败来自测试中 setWide(false) 的350ms偏好防抖计时器未完成；测试补400ms时钟推进，最终状态由下列统一检查决定，旧失败日志不删。

本地化隔离生成、9 项真实 SDK 正反样本及真实应用8文件前后 SHA-256 不变见 [freshness/README.md](freshness/README.md)。工具依赖、作者数据、Rust 与 golden 基线未修改。

`detail-final/` 的首轮统一检查已通过普通675、owned2、工具22、文本9、格式/分析和Release；随后独立复核确认回滚局部失败反馈缺口，所以该轮不作为最后交付状态。`rollback-feedback-before.txt` 保留“当前弹窗找不到失败码”的精确负向复现；`rollback-feedback-after.txt` 版本9项通过，随后增加覆盖路由期间失败的第10项。过程中测试误断言尚未展开的当前版本正文应可见，保留在 `rollback-feedback-fixture-assertion.txt`，修为检查原文不变及已展开历史正文可见。

## 最终同一源码验证

在仓库根目录运行 `pwsh -NoProfile -File scripts/check-frontend.ps1 -Test -WindowsBuild -ReportDirectory docs/evidence/frontend-standards-20261021/detail-final-reviewed`，退出0。RunId为 `c0fa6dc4fa8047acb8fd21e47156a1ff`，所选检查 `PASS`；总体仍标 `PARTIAL`，不把未选/物理项合并成通过。

| 检查 | 实际结果 |
| --- | --- |
| 全部自有生产 Dart AST | 141文件、0违规 |
| 门禁工具正反样本 | 22/22 PASS，包括泛型类型参数带前缀的菜单反例 |
| ARB与官方生成物 | 336键×3文件；3生成文件逐字节一致，源输入/生成物不变 |
| format / analyze | 应用221文件、纯文本包4文件、工具7文件格式无变化；应用/文本/工具分析无问题 |
| 普通回归（生产能力DLL） | 676/676 PASS，含版本10项及新键盘/几何回归 |
| 专用owned FFI / text_contract | 2/2、9/9 PASS |
| Windows Release | PASS，退出0 |
| 独立复制包 | PASS，正常probe退出0、缺DLL退出1，PATH移除SDK；见 `detail-final-reviewed/bundle/copied-bundle-status.json` |
| golden | SKIPPED；既有8张差异图前后SHA-256一致，未重批基线 |
| 物理IME、DPI/多屏、屏幕阅读器、净机安装 | NOT_RUN |

独立包目录 `build/m1-distribution-a2f232fba00a4139933632c793240f8e`。使用复制件与合成数据，未清理历史副本、未安装/发布。上述结果日志都在 `detail-final-reviewed/`；根侧另核对Rust/FRB/l10n生成目录无Git变更，见 `protected-generated-rust-status.json`。

## 集中视觉复看

最终普通全量采集了 `standards-final-20261022-*` 常规1440×900状态截图；另以 `UI_CAPTURE_NARROW=1`、`UI_CAPTURE_PHASE=standards-narrow-final-20261022` 单跑 `ui_interaction_capture_test.dart`，退出0，采集680×900/200%状态，见 `narrow-visual-capture.txt`。固定使用离线真实字体，非Ahem。

已实际查看并保存常规/窄窗展开讨论场景：[修前工具栏](toolbar-before.png)、[修后常规](toolbar-after.png)、[窄窗200%](narrow-after-200.png)。标题和保存状态可读，窄窗动作折叠可达、讨论动作可换行、表面无额外遮罩。这是widget渲染观察，未替代golden比较、逐页完整六态或真实Windows系统验收。

独立审查的原发现、修复复核与证据核对保留在 [independent-final-review.md](independent-final-review.md)。
