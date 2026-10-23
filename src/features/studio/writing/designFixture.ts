import { sampleProject } from "../sample";
import type { StudioProject } from "../types";
/** 设计演示专用章节标题池（纯虚构）。 */
const titles = [
  "潮汐以外",
  "不存在的航线",
  "雾中的灯塔",
  "归潮",
  "沿着旧地图",
  "迟到的回信",
  "未完成的航海日志",
  "夜航的人",
  "铜钥匙与一盏灯",
  "父亲没有说完的话",
  "回声",
  "北岸的修表铺",
  "海雾背后的城",
  "重返白塔港",
  "第十二次钟响",
  "在潮水退去之前",
  "另一封信",
  "被擦去的名字",
  "当所有航标都熄灭之后，我们仍然记得归途",
  "潮汐以外，仍有归途",
];
/** 设计演示专用观察段落池（纯虚构，章数超过标题时循环取用）。 */
const observations = [
  "潮水拍着石阶，留下细细的盐痕。林雾记得，父亲总在这里停住脚步，等水面重新平静，才带她往前走。",
  "沈砚把钥匙放在窗台上。铜已经被磨得很薄，只有柄上的裂纹清晰。他说，那不是一把用来开门的钥匙。",
  "白塔港的船夫不在夜里数钟声。他们只看岸边的灯，一盏接着一盏灭下去，就知道潮水正在转向。",
  "她从旧航海日志中抽出一张纸，纸边写着日期，正文却只有一行。有人在后来补过字，墨色比其它地方更深。",
  "风从北岸吹来，带着陌生木材的气味。港口没有那样的树，修表铺也没有。她把这个细节记在信封背面。",
  "没有人承认见过归潮号。可码头边的绳结还很新，掌管泊位的老人将那一页账本翻了过去，没有抬头。",
  "林雾没有再追问。她将表链收回衣袋，指尖碰到一粒铜屑，像一个尚未准备好说出口的名字。",
  "海图的北边有一块空白。父亲曾说，空白不表示那里什么也没有，有时只是画图的人没能回来。",
];
/** 构造设计演示工程：22 章标题 + 示例正文/观察段落，第三章追加长文验证滚动。 */
export function designProject(): StudioProject {
  const project = structuredClone(sampleProject);
  project.chapters = titles.map((title, index) => ({
    id: `ch-${index + 1}`,
    title: `第${index + 1}章 · ${title}`,
    body:
      sampleProject.chapters[index]?.body ??
      observations[index % observations.length],
  }));
  project.chapters[2].body +=
    "\n\n" +
    Array.from(
      { length: 64 },
      (_, index) =>
        `夜航记录 · 第${index + 1}页\n${observations[index % observations.length]}`,
    ).join("\n\n");
  return project;
}
