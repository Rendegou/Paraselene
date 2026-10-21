# 控件与页面覆盖矩阵 · 2026-10-21

在上一轮未提交成果上继续完成，未提交/合并/推送。本轮不重批历史golden，不清理任何分发，不访问作者库/凭据，不发送模型请求。原工程只读。

## 实际覆盖

| 角色 / 页面 | 本轮落实 |
| --- | --- |
| 按钮与导航 | 继续使用WorkbenchControls；侧栏文字操作/页签/章节/资料行改为共享TextButton；页签及章节selected语义；busy同时禁点击、右键与长按并减弱文字；清空IconButton带tooltip、48px命中；搜索壳允许字号增长，壳负责底色，字段仅绘制聚焦下划线 |
| 选择器 | 全库7个DropdownButton调用点全部迁移：人物2、记忆1、资料类型1、作用域1、讨论输出语言1、TaskOutputLanguage1（摘要/RPG复用）。WorkbenchSelect用共享按钮+原生showMenu/CheckedPopupMenuItem，当前值initialValue定位、勾选、Escape/焦点返回；原始值和历史未知scope不改写 |
| 复选框/开关 | CheckboxTheme/SwitchTheme显式保留48px命中、原生勾选/toggled语义、hover/pressed色层、局部焦点轮廓；禁用优先；不画成普通动作按钮 |
| 工具输入 | 所有TextField已显式指定工具字；14px表单用状态感知WorkbenchTokens.input，禁用颜色不覆盖回正常ink；既有搜索13px角色保留。作者正文CustomPainter/EditableText不变；表单统一边框/标签/错误边框；人物外观/语音、资料类型/名称/内容/作用域有标签；类型枚举本地化 |
| 弹窗层级 | 浏览型标题18px/600，任务型AlertDialog15px/500。资料库地图isSelected/selectedIcon；新增/编辑tooltip表意。设置/记忆编辑/备份支持滚动，主要保存为FilledButton；导入窗口按内容增长，长内容才滚动 |
| 讨论 | 去固定560px高；受视口和键盘内缩约束，短内容收缩、长内容滚动。去全章标题/状态重复；标题、草稿待保存状态、能力限制分工；预览为主要操作，但整章保持禁用与原因，不开放未具备能力，不省略完整预览和明确确认 |
| 非理想状态 | 空资料、空记忆、空历史收紧；空历史显示明确文案；历史读取失败不再无限spinner。导入空态给可执行下一步。引用说明32项上限，满额禁新增而允许取消；未确认条目说明先确认再引用 |

## 共享控件状态验证

PASS表示本轮widget实际运行；共享合同通过不代表每个页面均完成物理鼠标/屏幕阅读器验收。R/H/P/F/S/D分别为rest、hover、pressed、keyboard-focus、selected、disabled。

| 控件族 | R | H | P | F | S | D | 证据 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Text/Icon按钮底座 | PASS | PASS | PASS | PASS | N/A一次性动作；toggle页面见下 | PASS | ui_control_contract_test；32px可视/48px命中、Enter、几何稳定、200%长标签 |
| 工具选择器 | PASS | 继承底座；页面NOT_RUN | 继承底座；页面NOT_RUN | PASS | PASS当前值菜单勾选 | PASS | ui_completion_contract_test；1×/2×、未知scope、Escape返回焦点、Enter开启、选择回传、禁用不开菜单 |
| CheckboxListTile | PASS | PASS | PASS | PASS | PASS | PASS | ui_completion_contract_test；原生值变更、Space、全状态几何稳定 |
| SwitchListTile | PASS | PASS | PASS | PASS | PASS | PASS | 同上；无真实伴侣配置调用 |
| 工具输入 | PASS | 页面NOT_RUN | N/A | 截图PASS；各表单逐项Tab NOT_RUN | N/A | PASS字体/颜色/边框解析 | ui_completion_capture_test、ui_completion_contract_test、既有discussion capture |
| 侧栏导航行 | PASS | 继承底座；逐行NOT_RUN | 继承底座；逐行NOT_RUN | 共享底座PASS；逐行NOT_RUN | 章节/页签PASS既有操作回归 | 代码覆盖；逐行运行态NOT_RUN | writing_features_test、operation_parity；不把import当验收 |

## 页面与尺寸验证

常规1440×900、窄窗680×900、200%为680×900的2×字号；均加载本地真实字体，非Ahem。以下PASS为rest布局/字段字体/无溢出与截图，不代表该页所有业务状态已测。

| 页面 | 常规 | 窄窗 | 200% | 其他状态边界 |
| --- | --- | --- | --- | --- |
| 工作台顶栏/章末/侧栏 | PASS | PASS | PASS | toolbar布局矩阵、搜索清空/切换与语义回归；原生全状态NOT_RUN |
| 段下讨论 | PASS | PASS | PASS | 空/聚焦/草稿/hover/pressed/收起重开截图；本轮窄窗复跑见narrow-final.log |
| 整章讨论 | PASS | PASS | PASS | 原生窗口观察PASS；长历史/键盘软遮挡NOT_RUN |
| 资料库/编辑/引用 | PASS | PASS | PASS | 空态及字段布局；实际地图选中、满32项/未确认/加载错误逐页截图NOT_RUN，共享checkbox合同PASS |
| 人物/记忆编辑/记忆浏览 | PASS | PASS | PASS | 合成临时会话读取；不启动伴侣，不导入角色包；busy/错误截图NOT_RUN |
| 历史/导入 | PASS | PASS | PASS | 空态；导入修正后三档重跑PASS；真实文件导入/业务错误截图NOT_RUN |
| 备份/模型设置 | PASS | PASS | PASS | 只检查界面；不写云/凭据设置，不导出备份 |
| 完整外发预览 | 既有行为回归PASS | NOT_RUN单独截图 | NOT_RUN单独截图 | 使用假生成仓库，保留确认链，不发送真实模型请求 |
| 原生菜单/段末标记 | PASS组件回归 | PASS组件回归 | PASS组件回归 | 40px菜单布局、24px正文锚点有意保留；物理完整状态矩阵NOT_RUN |

## 执行结果与边界

- 普通全量：627 PASS，regression.log；包含新增33个辅助页面截图场景和6个控件合同，保留IME composing、生成收起重开仍可取消、资料冻结目标回归。原有wide_layout_test对CheckedPopupMenuItem内部Text的命中警告仍存在，未屏蔽。
- 之后导入自适应修正：3 PASS，import-final.log；最后搜索重复边线修正：定向回归见final-targeted.log。
- owned：2 PASS，owned.log；使用test-support DLL及独占随机目录。
- format：PASS，format.log；analyze：PASS，analyze-final.log。Impeccable detector为空数组（Flutter原生适用范围有限），不替代看图。
- ARB键集合：336键/3文件PASS，本轮17新增键均有description。原check-m2-l10n.ps1仍FAIL于基线addMemory，已确认HEAD有197个既有键缺description，见arb-key-parity.json；未把此项描述成全绿。
- Windows Release、独立复制bundle：PASS；bundle正常探针0、缺DLL失败闭合1、PATH移除SDK、保留历史副本。详见release-final.log和bundle/copied-bundle-status.json。
- 两次独立只读审查：首次盘点侧栏与辅助窗缺口；第二次发现禁用输入颜色/圆角、当前选择定位、上限说明、字段标签；已全部修正。审查代理未独立跑测试。

截图：build/ui-completion-20261021/*覆盖11页×3档；build/ui-interaction-20261021/completion-final-*与completion-narrow-*保留讨论/菜单状态；上轮before-*仍保留。首次截图测试失败（debug阴影恢复时机、路由尺寸测量、草稿debounce计时器）已修正；失败日志也保留，不当作产品失败或通过证据。八张历史golden failure差异图未触碰。

有意差异：浏览弹窗18px与任务弹窗15px；正文20px衬线与工具14px/搜索13px；开关/复选框原生选择形状；正文24px标记不扩大透明命中侵入邻近文字；40px既有菜单触发器保留。原生物理IME、屏幕阅读器、完整鼠标/键盘矩阵、DPI/多屏、净机安装仍NOT_RUN，需人工验收。不能宣称100%原生全场景统一。

## 最终构建

最后搜索边线修正后定向15项PASS；窄窗/200%讨论1项PASS；最终analyze无问题，Release增量构建PASS。最终独立bundle为 `D:\MyAgent\paraselene-flutter\build\m1-distribution-29c5b263d36244b68b20457504e12572`，证据在bundle-final（前次bundle证据与副本亦保留）。首次新版原生窗口68716已观察到完整工作台及紧凑整章讨论，未输入正文或调用模型；切换最终bundle的窗口信息见client-window.json。

最终窗口切换边界：新版窗口68716已经打开并观察；最后搜索双边框修正后的最终bundle已完成构建/独立验证。Computer Use在切换时反复返回`user input was detected in this window`，刷新又提示minimized；按指导恢复/重试仍失败，因此停止干扰用户。未声称最终29c5包的可见窗口已验证。可直接运行最终包中的exe；先关闭现有实例以释放合成库写者。
