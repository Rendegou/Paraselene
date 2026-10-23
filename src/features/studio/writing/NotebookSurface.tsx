import { EntityDetail } from "../EntityDetail";
import { WorldMap } from "../WorldMap";
import { ProjectFramework } from "../ProjectFramework";
import { NotebookManuscript } from "./NotebookManuscript";
import type { Notebook } from "./useNotebook";
/** 资料类视图（人物/世界观/地图条目、框架）的渲染分发与空态处理。 */
function ResourceSurface({ notebook }: { notebook: Notebook }) {
  // 浏览器预览模式下 map 视图渲染可交互世界地图；原生模式由侧栏承担地图职责，不重复挂载。
  if (notebook.surface === "map" && !notebook.native) return <WorldMap studio={notebook} />;
  if (notebook.surface === "framework") return <ProjectFramework />;
  // surface 是复数（characters/world），实体 kind 是单数，这里做显式映射。
  const kind = notebook.surface === "characters" ? "character" : notebook.surface === "map" ? "location" : "world";
  // 当前选中的实体类别不符时，回退到该类别下第一个实体；一个都没有则展示创建入口。
  const entity =
    notebook.entity?.kind === kind
      ? notebook.entity
      : notebook.project.entities.find((item) => item.kind === kind);
  return entity ? (
    <EntityDetail studio={notebook} entity={entity} />
  ) : (
    <div className="writing-empty">
      <h1>创建故事资料</h1>
      <button
        type="button"
        className="writing-primary"
        onClick={() => notebook.addEntity(kind)}
      >
        新建设定
      </button>
    </div>
  );
}

/** Keep the current chapter's EditorState alive while consulting local resources. */
// 工作区主面：正稿视图与资料视图互斥切换。
// 正稿始终用 hidden 而非卸载挂载——查阅资料时保住编辑器 EditorState，避免回来丢光标/撤销栈。
export function NotebookSurface({ notebook }: { notebook: Notebook }) {
  return <>
    <div hidden={notebook.surface !== "manuscript"}>
      <NotebookManuscript notebook={notebook} />
    </div>
    {notebook.surface !== "manuscript" && <>
      <button type="button" className="writing-return" onClick={() => {
        notebook.setSurface("manuscript");
      }}>返回正文</button>
      <ResourceSurface notebook={notebook} />
    </>}
  </>;
}
