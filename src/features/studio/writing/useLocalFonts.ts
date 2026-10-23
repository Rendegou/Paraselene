import { useEffect, useState } from "react";

/**
 * Expose loading proof in DOM attributes without relying on a fallback font-family string.
 * 本地字体加载探针：用 Font Loading API 实际加载四档字重，
 * 返回 loading/ready/fallback 三态供界面挂 DOM 属性（不依赖 fallback 字体名推断）。
 */
export function useLocalFonts() {
  const [status, setStatus] = useState("loading");
  useEffect(() => {
    let mounted = true;
    const faces = [
      '400 20px "Notebook Serif"',
      '400 14px "Notebook Sans"',
      '500 14px "Notebook Sans"',
      '600 32px "Notebook Sans"',
    ];
    Promise.all(
      faces.map((face) => document.fonts.load(face, "幻月小说雾海来信")),
    )
      .then((results) => {
        if (mounted)
          setStatus(
            results.every(
              (result) =>
                result.length > 0 &&
                result.every((font) => font.status === "loaded"),
            )
              ? "ready"
              : "fallback",
          );
      })
      .catch(() => {
        if (mounted) setStatus("fallback");
      });
    return () => {
      mounted = false;
    };
  }, []);
  return status;
}
