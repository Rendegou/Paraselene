# CLIENT-MVP A：最终A资产原生验收续跑

任务日期：2026-10-12；记录续写于2026-10-13。工作副本 `D:\MyAgent\paraselene-work`。

状态：**NATIVE_A_PARTIAL**。本次仅确认最终A前端的原生启动、当前150%DPI和系统保存对话框；没有完成A交互出口，不能标A_PASS或CLIENT_MVP_PASS。

## 构建与隔离

只控制 `src-tauri/examples/notebook_window_probe.rs` 的合成窗口 `幻月 · A阶段合成验收`，未初始化NovelState、作者数据库或凭据；UI路由为 `index.html?design=paragraph`。使用Windows Computer Use技能，node_repl直接导入 `@oai/sky`。没有使用远程浏览器localhost入口，没有私人库或Key访问。

此续跑先通过唯一返回窗口对象关闭上轮窗口；当时AX显示上轮“已取消导出”，但这是旧A窗口状态，不能沿用为本次最终A取消通过。

最终A前端资产 `dist/assets/index-CeLYtN5m.js`，SHA256 `D7D5C29646C517FEBE7DD941637F99706ED5305BFE2A0168B5D5233D445282B6`。

本次编译成功时example SHA256 `F3AAAD3AFB1725D6162B54E122D2045307E70D73406916E942D0638973BFA30C`。这是开发example，不是安装包。

实际命令（PowerShell7）：

```powershell
$env:PATH='C:\tools\paraselene-build\mingw64\bin;' + $env:PATH
cargo build -p paraselene --example notebook_window_probe --target-dir 'D:\MyAgent\.cargo-target' --offline
```

第一次退出1：并行B修改注册threads/thread_snapshot而文件暂缺（E0583）；第二次退出1：delete_working_copy缺新增revision参数（E0061）。不覆盖其他Agent修改；文件与调用完成后第三次构建退出0，29.02s。

单文件rustfmt在sandbox先遇canonicalize权限拒绝；相同单文件命令沙箱外获准，退出0。编译采用既定GNU环境，未改工具链/CSP/IPC权限。运行PATH加入 `D:\MyAgent\.cargo-target\debug` 以找到WebView2Loader；此措施不是安装版分发验收。

example增加合成验收观察器：只记录event类别、元素tag/role/class、editable/composing、selection/inputSelection坐标、range/caret矩形、DPR/viewport；不记录输入文字、按键字母或正文。stdout见 `native-a-20261012/probe.log`，stderr见同目录 `probe-error.log`。

## 本次真实观测

1. 第三次构建后启动打包UI。Computer Use精确标题筛选得到唯一窗口（返回id720912），截图显示合成20章/7资料，章节标题为h1 `第3章 · 雾中的灯塔`，有主动“重命名”按钮。
2. 原生Tauri `scale_factor=1.5`；物理客户区1920×1200；DOM `devicePixelRatio=1.5`、CSS viewport1280×800。当前真实Windows缩放150%，没有使用网页zoom模拟DPI。启动布局截图能正常看到标题、正文和工具栏；这不等于所有150%交互已通过。
3. 点击“导出”→菜单“正文与资料 Markdown”，原生AX及截图出现“导出当前写作稿”Windows系统对话框，文件名 `雾海来信.md`，文件类型 `写作稿 (*.md)`，有保存/取消按钮。只验证打开对话框，没有写文件。
4. 尝试AX点击返回的取消索引254，工具报 `element 254 is not available in cached app state for notebook_window_probe.exe`。随后重新取得包含主窗和对话框的截图，准备坐标取消，但尚未执行坐标动作。因此取消/焦点回归仍NOT_RUN，不按这次AX失败推断产品取消故障。
5. 续写恢复时node_repl状态已丢失（sky undefined）；按技能重新初始化后，精确标题窗口匹配为0。未再发送UI输入。此次续跑没有收到“user stopped Computer Use”错误；窗口为何消失未确认，不能猜测用户停止或应用崩溃。

## 仍未完成

- 标题Enter/Escape和微软拼音真实组成输入：**NOT_RUN**。本次没用press_key字母形成候选，不拿旧Unicode set_value或观察器存在当IME通过。
- 正文拖选/双击/跨段选区/undo与复制：**NOT_RUN**。
- 段下/全章草稿资料往返、原焦点/选区/scroll与undo保留：**NOT_RUN**。
- 菜单键盘、叠层Escape逐层关闭：**NOT_RUN**。
- 非输入chrome/段下空白异常caret：**PARTIAL**。启动与导出按钮事件editable=false、visibleCarets=[]；没有执行完整逐组件复现。
- 系统导出取消、write、overwrite、不可写/占用失败、保留草稿与重试：**NOT_RUN**（仅对话框打开PASS）。
- 100%/125%DPI：**NOT_RUN**。150%DPI只启动布局/对话框观测，完整交互**PARTIAL**。
- 最小760×560与最大化、最近窗口恢复：**NOT_RUN**。
- 安装版、正式保存、真实DeepSeek：本证据范围**NOT_RUN**。

下一动作：重新选择唯一合成验收窗口并补系统取消/写入/覆盖失败，再进行IME、编辑器与资料返回。此A已嵌入资产与后续B构建需分别标识；不能把后续B源码状态写成此A运行结果。

## 恢复后补充（2026-10-13）

父Agent确认未关闭A窗口，授权继续后，重启原有已编译A binary（未重编译，因此仍为上述A资产），stdout另存 `native-a-20261012/probe-resume.log`。

- **系统取消 PASS（本次最终A资产）**：按截图坐标点击保存框取消；下一原生截图与AX明确出现“已取消导出。”，对话框关闭。
- **系统write PASS（合成Markdown）**：再次打开同一系统保存框；确认文件名输入后，输入workspace合成路径 `docs/evidence/native-a-20261012/synthetic-export.md`，点击保存；下一截图与AX出现“导出文件已写入。”。PowerShell7 UTF-8读回文件，断言含合成标题“雾中的灯塔”和正文锚句“雾是在傍晚漫上来的。”，退出0；文件16794字节。未把全文写到日志。该合成导出文件仅作为本机测试材料，不应提交为作品语料。
- **标题普通Enter/Escape PASS**：主动重命名后type_text追加合成“原生续验😀”，Return后h1与目录同步显示新标题、input退出；再次主动重命名追加“不应保存”，工具press_key Escape后h1及目录仍为上次提交值，不含该取消标记，input退出。此路径不是IME组成输入；IME仍NOT_RUN。
- 原生AX经常返回滞后输入Value/错误focused_element，截图显示实际更新；系统对话框AX索引不可用时改用刚刷新主窗截图坐标。首次恢复AX click还报 `coordinate input geometry is unavailable`，刷新含截图状态后正常。均为工具输入/观测限制，未判为产品缺陷。

上述补充覆盖原“取消/write NOT_RUN”和“标题Enter/Escape NOT_RUN”的普通输入部分。overwrite/failure、IME、编辑器选择/undo、资料往返、叠层、最小/最大化仍未完成；A出口仍PARTIAL。

- **IME组成Enter保护：PARTIAL证据**：标题编辑状态下使用真实 `press_key n`、`press_key i`；截图显示输入中ni与中文候选窗（1你、2尼等），日志含 `compositionstart`、INPUT editable=true composing=true。按Return后候选窗退出，标题仍处于input/完成/取消编辑态（未提前h1提交），ni按IME Enter行为作为拉丁文字进入。已验证真实组成输入事件与Enter保护，但未用Space/候选选择提交中文、未测组成Escape/正文IME或中文标点；不能据此标完整微软拼音PASS。候选窗视觉与当前输入法相符，但尚未查看系统输入法名称，身份仅待确认。

root随后准备B同UI临时DBprobe，要求释放tauri-build资源占用；我对精确唯一A窗口发送Alt+F4结束（只此合成窗口），不重编译共用target。A剩余原生项后续可在同UI的B隔离测试补，但必须保留构建身份。
