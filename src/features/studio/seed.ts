import type { SourceReference, StudioProject } from "./model";

/**
 * Invented story for the clearly labelled experience workspace; no private material.
 * 纯虚构的种子故事，服务于明确标注的"体验工作台"；不得夹带任何私人素材。
 */
/** 预置引用条目：与下方章节正文对应，供引用面板与跳转演示使用。 */
export const references: SourceReference[] = [
  { id: "key", chapterId: "chapter-2", title: "钥匙的来历", quote: "她把铜钥匙放进外套的内袋，没告诉闻舟。", note: "林汐保留了自己的行动选择，而不是无条件信任闻舟。" },
  { id: "light", chapterId: "chapter-1", title: "灯塔的规则", quote: "雾港的灯塔从不在午夜熄灭。", note: "世界规则：灯塔异常需要有原因，不能当作寻常景象。" },
  { id: "letter", chapterId: "chapter-3", title: "未寄出的信", quote: "信封上没有邮票，只有父亲的名字。", note: "信的来源尚未揭晓，是后续可以发展的伏笔。" },
];

/** 种子工程：四章正文 + 知识库（角色/世界/地点/伏笔），首次进入或无存档时使用。 */
export const seedProject: StudioProject = {
  title: "雾港来信",
  chapters: [
    { id: "chapter-1", title: "雾中的港口", body: "雾港的灯塔从不在午夜熄灭。\n\n林汐到达码头时，钟楼刚敲过十一下。运鱼的人拖着最后一只木箱，箱底在石板上划出一道湿痕。她站在候船亭下，手里的地址被雨洇得只剩半行。\n\n父亲失踪后的第七天，她收到了这张纸。没有落款，也没有解释。纸上只写着：来雾港，别走大路。\n\n对岸灯塔的光扫过水面，短暂地照亮一艘没有名字的船。有人在船上举了一下手。\n\n她没有回应。父亲从前教过她，夜里不要替陌生人认出自己。" },
    { id: "chapter-2", title: "雨中的钥匙", body: "闻舟在修船铺的屋檐下等她，鞋边沾着黑色的海泥。\n\n“你父亲让我把这个交给你。”他摊开手，一枚铜钥匙躺在掌心。钥匙齿磨损得厉害，柄上刻着一个很小的月牙。\n\n她把铜钥匙放进外套的内袋，没告诉闻舟。\n\n闻舟没有问她为什么。雨声盖过屋里收音机的噪音，他将一杯热水推到她面前，说灯塔那边的人已经等了很久。\n\n“等的是我，还是这把钥匙？”\n\n他低头擦掉桌上的水渍。\n\n“明天你可以自己问。”" },
    { id: "chapter-3", title: "灯塔来信", body: "海雾是在凌晨退去的。\n\n林汐沿着防波堤往前走，潮水在石缝里留下细碎的白沫。灯塔比她想象中更旧，门口的铁链已经锈成了暗红色。她从外套内袋取出钥匙。\n\n门没有锁。\n\n里面没有人，只有一张靠窗的木桌。桌角压着一封信。信封上没有邮票，只有父亲的名字。\n\n她没有立刻拆开。窗外传来船笛声，短促的一声，像是谁在确认她已经到了。\n\n“你比我想的来得早。”\n\n闻舟站在门口，手里拿着两杯还冒热气的咖啡。他的目光落在那封信上，又很快移开。\n\n“我父亲来过这里？”她问。\n\n“很多人都来过。”\n\n林汐把信翻过来。背面有一道很浅的折痕，像有人反复捏住同一个地方。她把它放进外套，没让闻舟看见信封上的字。\n\n“那就从他开始说。”\n\n窗外的雾又漫了上来，灯塔的光穿过玻璃，落在两人之间。" },
    { id: "chapter-4", title: "潮声以外", body: "她把那封信带回了旅馆。\n\n窗户正对着码头，退潮之后，石阶露出了她昨天没有看见的一行字。林汐打开笔记本，把那几个字逐个抄下来。\n\n这一次，她决定先自己找答案。" },
  ],
  knowledge: [
    { id: "lin", kind: "character", title: "林汐", subtitle: "寻找父亲的修复师", description: "二十六岁。习惯先观察，再作决定。她来到雾港寻找失踪的父亲，也在重新判断自己曾经相信的事。", details: [{ label: "当前目标", value: "弄清父亲为何离开，以及谁在引导她来到雾港。" }, { label: "行为边界", value: "不会轻易交出关键线索。对闻舟保持有限信任。" }, { label: "说话方式", value: "简短、具体；提问直接，不用对白解释自己的情绪。" }], references: ["key", "letter"] },
    { id: "wen", kind: "character", title: "闻舟", subtitle: "知道更多的引路人", description: "三十一岁。修船铺的主人，认识林汐的父亲。他提供帮助，却总是在最关键的地方停下来。", details: [{ label: "表面目标", value: "把林汐带到灯塔。" }, { label: "未决动机", value: "他保护的是林汐，还是父亲留下的秘密？暂不定论。" }, { label: "行为边界", value: "会回避直接问题；不替林汐作决定。" }], references: ["key", "letter"] },
    { id: "rules", kind: "world", title: "雾港与灯塔", subtitle: "世界规则 · 近现代沿海小城", description: "雾港靠航运维生。灯塔既是航标，也是居民判断海况的依据。故事中的异常应建立在稳定的日常规则上。", details: [{ label: "灯塔", value: "午夜持续亮灯。熄灭意味着有人主动改变了规则。" }, { label: "潮汐", value: "退潮显露旧石阶；高潮时防波堤尽头不可通行。" }, { label: "信息边界", value: "林汐初来乍到，不知道港口居民之间的旧约定。" }], references: ["light"] },
    { id: "harbor", kind: "place", title: "旧码头", subtitle: "雾港南岸 · 林汐的抵达地", description: "客船与渔船共用的老码头。钟楼、候船亭和旅馆都在步行范围内。", details: [{ label: "关联场景", value: "第一章抵达；第四章退潮后发现石阶文字。" }], references: ["light"] },
    { id: "tower", kind: "place", title: "北岸灯塔", subtitle: "防波堤尽头 · 当前场景", description: "沿旧码头向北绕过潮汐湾，顺防波堤走到尽头。退潮时约二十分钟，涨潮时需要乘船。", details: [{ label: "空间约束", value: "门口能看到木桌，但从码头看不到塔内。" }], references: ["light", "letter"] },
    { id: "letter-thread", kind: "foreshadow", title: "父亲的信", subtitle: "已埋设 · 尚未回收", description: "是谁把没有邮票的信留在灯塔？折痕说明信曾被反复握住，来源和寄送方式都未揭晓。", details: [{ label: "埋设位置", value: "第三章：木桌上的信、闻舟移开的目光、背面的折痕。" }, { label: "后续方向", value: "让线索来自一次具体行动，而不是人物主动解释一切。" }], references: ["letter"] },
  ],
};
