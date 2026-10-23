import type { StudioProject } from "./types";

/**
 * Entirely fictional fixture; never imports private writing or the native database.
 * 完全虚构的示例工程：仅供预览/演示使用，不导入任何真实写作内容或本机数据库。
 */
export const sampleProject: StudioProject = {
  schema: 1, revision: 0, title: "雾海来信",
  chapters: [
    { id: "ch-1", title: "第一章 · 潮汐以外", body: "白塔港没有春天。\n\n每到三月，海雾便沿着石阶爬上来，把港口的钟声裹成一团湿冷的棉絮。林雾在修表铺里住了十七年，却从未听清过午夜的第十三声钟响。\n\n父亲留下的旧航图挂在墙上。图的边缘有一行小字：潮汐以外，仍有归途。\n\n她一直以为，那只是一个水手写给女儿的安慰。" },
    { id: "ch-2", title: "第二章 · 不存在的航线", body: "沈砚把那封信放在柜台上时，袖口还在滴水。\n\n“有人在北岸见过你父亲。”\n\n林雾没有伸手。三年来，带着同样消息走进修表铺的人已经够多了。他们或是讨一顿饭，或是想卖给她一张画满谎言的地图。\n\n可这封信的封蜡上，有一道她认识的裂纹。\n\n“归潮号。”沈砚说，“他在一条不存在的航线上。”" },
    { id: "ch-3", title: "第三章 · 雾中的灯塔", body: "雾是在傍晚漫上来的。\n\n起初只是水面上很薄的一层，像有人把一封没有写完的信，轻轻铺在了海上。等林雾走到白塔港尽头，整座灯塔只剩下一点模糊的轮廓。\n\n她把那封信又读了一遍。\n\n纸上的字迹已经洇开，唯独最后一句还清晰得像刚刚写下：不要相信第十三声钟响。\n\n“你还是来了。”\n\n沈砚站在灯塔的阴影里，肩头落着细密的水珠。他没有撑伞，右手握着一枚旧铜钥匙。林雾注意到，钥匙柄上的纹路，与信封封蜡上的裂纹一模一样。\n\n她没有问他为什么在这里。\n\n有些问题，一旦问出口，就再也无法假装自己不知道答案。\n\n远处，归潮号缓缓离开了码头。船尾的灯在雾中摇晃了两下，然后熄灭了。\n\n第一声钟响，从看不见的地方传来。" },
    { id: "ch-4", title: "第四章 · 归潮", body: "船上的人都不肯提起灯塔。\n\n林雾在甲板边找到一枚与沈砚手中相同的铜钥匙。钥匙没有锁，只有一个朝北的缺口。\n\n她抬头时，白塔港已经消失在雾里。" },
  ],
  entities: [
    { id: "lin", kind: "character", name: "林雾", subtitle: "修表师 · 寻找失踪的父亲", body: "十七岁的修表师，在白塔港长大。习惯先观察细节，再决定是否相信一个人。\n\n外在目标：找到父亲。\n内在矛盾：害怕答案证明，父亲是主动离开的。\n\n写作约束：不轻易倾诉；紧张时会摩挲表链。她不知道第十三声钟响的真实含义。", related: ["shen", "harbor", "bell"], sources: [{ chapterId: "ch-1", quote: "林雾在修表铺里住了十七年" }, { chapterId: "ch-3", quote: "她没有问他为什么在这里。" }] },
    { id: "shen", kind: "character", name: "沈砚", subtitle: "引航员 · 知道一些没有说出的事", body: "归潮号的前任引航员，熟悉雾海的暗礁。\n\n与林雾的关系：带来父亲的线索，但暂时未获信任。\n秘密：铜钥匙来自一次失败的返航。\n\n写作约束：少解释，以动作透露立场；当前章节不能直接揭露他的秘密。", related: ["lin", "lighthouse", "bell"], sources: [{ chapterId: "ch-2", quote: "沈砚把那封信放在柜台上时，袖口还在滴水。" }, { chapterId: "ch-3", quote: "右手握着一枚旧铜钥匙" }] },
    { id: "bell", kind: "world", name: "第十三声钟响", subtitle: "雾海规则 · 尚未揭示的真相", body: "白塔港的钟只应敲响十二次。第十三声不属于正常的时间。\n\n已知：信中警告不要相信它。\n未知：声音的来源与代价。\n\n叙事边界：第三章只呈现警告，不解释规则的真相。", related: ["lighthouse", "lin"], sources: [{ chapterId: "ch-3", quote: "不要相信第十三声钟响。" }] },
    { id: "sea", kind: "world", name: "雾海与航线", subtitle: "世界观 · 潮汐之外的归途", body: "浓雾会改变可见航标，却不会改变潮汐方向。地图上的航线与真实的返航路线并不总是一致。\n\n故事的核心意象：信、钟、钥匙与归途。\n地理边界：白塔港位于雾海南岸；灯塔在港口东侧。", related: ["harbor", "lighthouse", "north"], sources: [{ chapterId: "ch-1", quote: "潮汐以外，仍有归途。" }] },
    { id: "harbor", kind: "location", name: "白塔港", subtitle: "南岸 · 故事的起点", body: "终年潮湿的港城。修表铺位于沿海石阶尽头，旧码头面向雾海。\n\n到灯塔：沿东侧防波堤步行。\n到北岸：乘船，普通航图没有完整航线。", related: ["lin", "lighthouse", "north"], position: { x: 29, y: 69 }, sources: [{ chapterId: "ch-1", quote: "白塔港没有春天。" }] },
    { id: "lighthouse", kind: "location", name: "旧灯塔", subtitle: "东侧防波堤 · 第三章场景", body: "白塔港尽头的旧灯塔。海雾到来时，轮廓比灯光更先消失。\n\n场景作用：林雾与沈砚第二次会面；铜钥匙第一次出现。\n\n空间约束：可以看见离港的归潮号，但看不见钟声的来源。", related: ["harbor", "shen", "bell"], position: { x: 66, y: 58 }, sources: [{ chapterId: "ch-3", quote: "沈砚站在灯塔的阴影里" }] },
    { id: "north", kind: "location", name: "北岸", subtitle: "雾海彼端 · 尚未抵达", body: "父亲最后被目击的地方。当前只存在于沈砚提供的线索中，尚未被主角亲眼证实。\n\n叙事约束：不把传闻写成已确认的事实。", related: ["harbor", "sea"], position: { x: 48, y: 24 }, sources: [{ chapterId: "ch-2", quote: "有人在北岸见过你父亲。" }] },
  ],
};
