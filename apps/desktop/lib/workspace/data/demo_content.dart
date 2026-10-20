// 合成演示正文常量：包含 CRLF、混合书写系统与组合字符，防止演示路径意外归一化。
// 只读常量，不写库、不触碰作者正文；只由显式演示入口引用。
/// Deliberately unnormalized synthetic text, including CRLF and mixed scripts.
///
/// 故意未归一化的演示文本，保留 CRLF、混合书写系统与组合字符。
const demoBody =
    '雨后的书店\r\n'
    '街灯映在水面上。The bookshop was still open.\r\n'
    'العربية · 👩‍💻 · e\u0301\r\n'
    '她推开门，听见熟悉的铃声。';
