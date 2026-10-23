import { useEffect, useMemo, useRef } from "react";

/** Stored source ranges count Unicode characters, so emoji must remain whole when highlighted. */
// 按存储的字符区间（Unicode 码位计）在正文版本里高亮引用片段，并滚动到高亮处。
// 区间非法（非整数/负数/空区间/越界）时整体降级：提示并展示全文，不硬切字符串。
export function SourceVersionText({ body, startChar, endChar }: { body: string; startChar: number; endChar: number }) {
  const mark = useRef<HTMLElement>(null);
  const parts = useMemo(() => {
    // Array.from 按码点拆分，保证 emoji 等代理对不会被切半。
    const characters = Array.from(body);
    if (!Number.isInteger(startChar) || !Number.isInteger(endChar) || startChar < 0 || endChar <= startChar || endChar > characters.length) return null;
    return [characters.slice(0, startChar).join(""), characters.slice(startChar, endChar).join(""), characters.slice(endChar).join("")];
  }, [body, startChar, endChar]);
  useEffect(() => { mark.current?.scrollIntoView({ block: "center" }); }, [parts]);
  return parts ? <pre>{parts[0]}<mark ref={mark}>{parts[1]}</mark>{parts[2]}</pre>
    : <><p role="alert">出处范围无效，下面仅显示绑定版本。</p><pre>{body}</pre></>;
}
