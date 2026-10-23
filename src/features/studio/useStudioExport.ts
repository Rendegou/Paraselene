import { useRef, useState } from "react";
import { isNativeRuntime, studioExport } from "../../lib/ipc";
import { downloadPreview } from "./projectActions";
import { projectMarkdown } from "./previewModel";
import type { StudioProject } from "./types";

/**
 * Native dialog writes the visible draft as backup, even when preview persistence is blocked.
 * 工程导出：原生运行时走系统保存对话框（内容仍在前端组装，对话框只是落盘通道）；
 * 浏览器预览退化为触发下载。失败时记录失败格式供 retryExport 重试。
 */
export function useStudioExport(project: StudioProject, notify: (text: string) => void) {
  const [exportError, setExportError] = useState("");
  const [exporting, setExporting] = useState(false);
  const busy = useRef(false);
  // 记录失败时的格式，供 retryExport 原样重试；成功后不需要清空（重试幂等，重导出同格式无害）
  const failedFormat = useRef<"markdown" | "json" | null>(null);
  async function exportFile(format: "markdown" | "json") {
    if (busy.current) return; // 防止连击产生并发导出
    busy.current = true;
    setExporting(true);
    setExportError("");
    const fileName = `${project.title}.${format === "markdown" ? "md" : "json"}`;
    const content = format === "markdown" ? projectMarkdown(project) : JSON.stringify(project, null, 2);
    try {
      if (isNativeRuntime()) {
        const result = await studioExport({ fileName, content, format });
        notify(result.status === "saved" ? "导出文件已写入。" : "已取消导出。");
      } else {
        downloadPreview(fileName, content, format === "markdown" ? "text/markdown;charset=utf-8" : "application/json");
        notify("已请求浏览器下载，请检查下载结果。");
      }
    } catch {
      failedFormat.current = format;
      setExportError("导出失败，当前内容仍保留。请重新导出并选择可写位置。");
    } finally {
      busy.current = false;
      setExporting(false);
    }
  }
  return { exportError, exporting,
    retryExport: () => failedFormat.current ? exportFile(failedFormat.current) : Promise.resolve(),
    exportProject: () => exportFile("json"), exportText: () => exportFile("markdown") };
}
