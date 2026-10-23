// 左侧目录页签。契约见下方 ShelfTabs 的文档注释。

/** 左侧目录页签：章节 / 设定集切换。`value` 为受控选中项，`onChange` 由父层更新。 */
export function ShelfTabs(props: { value: "docs" | "lore"; onChange: (tab: "docs" | "lore") => void }) {
  return <div className="novel-shelf-tabs" role="tablist" aria-label="目录切换">
    <button type="button" role="tab" aria-selected={props.value === "docs"}
      className={props.value === "docs" ? "selected" : ""} onClick={() => props.onChange("docs")}>章节</button>
    <button type="button" role="tab" aria-selected={props.value === "lore"}
      className={props.value === "lore" ? "selected" : ""} onClick={() => props.onChange("lore")}>设定集</button>
  </div>;
}
