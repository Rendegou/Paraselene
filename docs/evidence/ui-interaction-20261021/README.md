# 原生交互外观实施 · 2026-10-21

仓库分支 `codex/flutter-migration-20261015`，基线 `19d12c98ee8d333da8391c22f01ef82d25b491a7`。本轮保持未提交，未合并、未推送。前置八张 golden failure 差异图与两份未提交文档均保留，历史分发未清理。

## 复现与根因

先使用真实 WorkbenchScreen / DiscussionPanel 和内存合成仓库生成修改前四态截图，没有访问作者库或认证。实际文字按钮矩形48×48；全局minimumSize把命中尺寸直接变成可视底板，固定overlay不区分disabled/focus。默认Card没有显式主题，使用surfaceContainerLow冷灰；草稿TextField继承bodyLarge，误用正文20px衬线字。EditorScene另把整个讨论槽画为#e4e8df，卡片周围露出灰绿底。段下没有全屏ModalBarrier。

本机Flutter源码核对：card.dart默认color取surfaceContainerLow；button_style_button.dart的_InputPadding在32px可视Material外独立提供48px命中。Context7已按要求resolve并两次查询，均无匹配，API行为以安装SDK源码与真实widget回归核对。

参考只读本机dsh-claude-style 0.17.0 STYLE.md，以及交接固定提交484ece039400ab45a97e935abb5bc47245845a96的shared/popover.css、theme/tokens.json、shared/motion.css。借鉴共享表面与状态机制，未复制品牌色、未执行或修改插件。Impeccable 4.7 context已执行并读craft-floor；这是既有界面的局部细化，没有新建品牌或产品设定。

## 实现

- WorkbenchControls统一32px最小可视底板、48px透明命中、标准密度、6px圆角、8px图文距离、12px面板内距。文字随缩放自然增高；hover/pressed只改变本控件色层，focus以预留的2px轮廓显示，disabled优先。
- ThemeData统一Text/Filled/Outlined/IconButton；Card显式暖纸面、无tint、无默认阴影，菜单4px内距/轻阴影/下置，对话框统一32%灰幕。通用输入聚焦用局部蓝灰下划线，讨论草稿用独立细边框。
- DiscussionSurface是段下唯一表面责任方；移除ScenePainter灰绿槽底，保留scene.slots、测量回调、布局与滚动算法。Dialog宿主显式inDialog，不再嵌套Card；收起/关闭图标与本地化区分。
- 草稿恢复工具字体14px，操作行独立8px间距。对比/历史补方向箭头和expanded/selected语义。
- 顶栏与章末迁移至同一原生TextButton样式；顶栏保留tooltip并显式暴露语义tap，禁用导出入口本身；版式字体说明纠正。
- 既有40px菜单触发区与正文24px锚点标记保留尺寸，未缩小；例外与原因在DESIGN.md记录。菜单行保留原生48px最小高度，避免大字号截断。未机械改变正文排版与纸面留白。

## 验证结果

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| format | PASS，13文件零变化 | format.log |
| analyze --no-pub | PASS，No issues found | analyze.log |
| 普通全量回归 | PASS，588项；含生产DLL合成FFI | regression-tests.log |
| 最后焦点/语义调整后定向回归 | PASS，84项 | focused-tests.log |
| 新增顶栏语义tap/48px断言 | PASS，4项 | toolbar-semantics.log |
| owned独占合成目录 / test-support DLL | PASS，2项 | owned-tests.log |
| 680×900 / 200%字号 | PASS，输入、hover、pressed、收起重开、菜单Escape | narrow.log |
| Windows Release | PASS | release-build.log |
| 独立复制bundle | PASS；正常0、缺DLL1；SDK已从PATH移除 | bundle/copied-bundle-status.json |
| 独立静态审查 | 未发现可确认P1/P2；未独立运行测试 | 本会话review_ui审查 |
| 新版可见窗口 | PASS，独立bundle窗口658878，已观察实际段下讨论 | 本会话Computer Use画面 |

ui_control_contract_test实际验证32px可视Material与至少48px外部命中；点击透明顶边可触发；hover/pressed/focus矩形不变；键盘Enter可触发；disabled无tap；200%长标签自然增高无溢出。ui_interaction_capture_test实际打开线程、输入合成草稿、收起重开保留草稿，以及整章Dialog/菜单Escape。保留并复跑原IME composing守卫、生成收起重开仍可取消、资料冻结目标相关回归。

全量与定向运行仍有原有wide_layout_test点击CheckedPopupMenuItem内部Text的命中警告；同类警告在上轮regression-tests.log已存在。本机Flutter的CheckedPopupMenuItem用IgnorePointer包裹内部ListTile，事件由菜单行接收；版式切换与宽度断言仍通过。未屏蔽警告或关闭命中检查。

## 图像与原生观察边界

截图在仓库忽略的 `build/ui-interaction-20261021/`：before-empty/focus/draft/hover；after-empty/focus/draft/hover/pressed/reopen/dialog/menu；after-narrow相同段下状态及menu。均加载打包真实字体，非Ahem；没有重批既有golden。最终截图包裹整个路由树，菜单与Dialog包含在截图中；开启真实阴影渲染并在测试结束前恢复debug变量。修改前截图仍保留最初测试环境的阴影轮廓，不把测试专用黑边当作产品边线。

原生旧窗口置前后观察到相同冷灰Card与灰绿槽底；新版实际展开后暖纸面连续，草稿局部边线与操作行已可见。自动化曾发生截图捕获遮挡、索引失效、坐标点击后状态延迟，未把这些操作推断为缺陷或已通过的状态。原生输入/hover/pressed/focus完整矩阵、真实物理IME、DPI/多屏和净机安装仍NOT_RUN；组件矩阵不能替代这些验收。未输入真实模型指令、未点击发送、未读Key/认证或作者数据库。

运行中的新版来自：`D:\MyAgent\paraselene-flutter\build\m1-distribution-bf5500bb4ede42049a0421d1d5e9c520\paraselene_flutter.exe`。SHA256见client-artifacts.json；此前两个独立分发与retention哨兵目录仍在。保留所有副本。
