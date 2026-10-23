import { useEffect, useRef, useState } from "react";
/**
 * 笔记本布局状态：聚焦态、分栏（可持久化到原生偏好）、侧栏与移动端断点。
 * 窗口变窄到 900px 以下时强制收起侧栏；persist 经 ref 透传避免闭包过期。
 */
export function useNotebookLayout(initialWide = false, persist?: (wide: boolean) => void) {
  const [focus, setFocus] = useState(false);
  const [wide, setWide] = useState(initialWide);
  const latestPersist = useRef(persist);
  latestPersist.current = persist;
  useEffect(() => { latestPersist.current?.(wide); }, [wide]);
  const [sidebar, setSidebar] = useState(
    () => matchMedia("(min-width: 901px)").matches,
  );
  const [mobile, setMobile] = useState(
    () => matchMedia("(max-width: 760px)").matches,
  );
  useEffect(() => {
    const compact = matchMedia("(max-width: 900px)");
    const small = matchMedia("(max-width: 760px)");
    const collapse = (event: MediaQueryListEvent) => {
      if (event.matches) setSidebar(false);
    };
    const resize = (event: MediaQueryListEvent) => setMobile(event.matches);
    compact.addEventListener("change", collapse);
    small.addEventListener("change", resize);
    return () => {
      compact.removeEventListener("change", collapse);
      small.removeEventListener("change", resize);
    };
  }, []);
  return {
    focus,
    setFocus,
    wide,
    setWide,
    sidebar,
    setSidebar,
    mobile,
    /** 导航后收起侧栏（仅窄屏需要；宽屏侧栏常显）。 */
  closeNavigation: () => {
      if (matchMedia("(max-width: 900px)").matches) setSidebar(false);
    },
  };
}
