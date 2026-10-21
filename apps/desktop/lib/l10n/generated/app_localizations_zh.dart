// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '幻月';

  @override
  String get workspaceTitle => '写作工作台';

  @override
  String get chooseWork => '选择作品';

  @override
  String get works => '作品';

  @override
  String get chapters => '目录';

  @override
  String get noWorksTitle => '为下一段故事，留一页安静的纸';

  @override
  String get noWorksBody => '临时资料库还是空的。可以打开作品选择器，或创建示例材料体验工作台。';

  @override
  String get createDemo => '创建示例材料';

  @override
  String get loading => '正在读取工作台…';

  @override
  String get retry => '重新读取';

  @override
  String get errorTitle => '暂时无法读取工作台';

  @override
  String get errorBody => '材料没有被更改。可以重新读取后再试。';

  @override
  String get emptyChapters => '这部作品还没有章节。';

  @override
  String get chooseChapter => '从目录选择一章开始阅读。';

  @override
  String get readOnlyHint => '只读预览 · 正文编辑将在下一阶段接入';

  @override
  String get focusOn => '专注模式';

  @override
  String get focusOff => '退出专注';

  @override
  String get wideOn => '宽稿模式';

  @override
  String get wideOff => '舒适宽度';

  @override
  String get languageLabel => '界面语言';

  @override
  String get chineseLabel => '简体中文';

  @override
  String get englishLabel => 'English';

  @override
  String get realMode => 'REAL · Rust 桥接';

  @override
  String get syntheticMode => 'SYNTHETIC · 内存替身';

  @override
  String get syntheticNotice => '临时示例库 · 未接入作者数据 · 云能力关闭';

  @override
  String get workLanguage => '作品语言';

  @override
  String get documentLanguage => '章节语言';

  @override
  String get outputLanguage => '模型输出语言';

  @override
  String get mixedLanguage => '混合语言';

  @override
  String get undeterminedLanguage => '未指定';

  @override
  String get languageIndependence => '切换界面语言不会翻译或改写正文。';

  @override
  String get openDirectory => '打开章节目录';

  @override
  String get discussionCollapse => '收起讨论';

  @override
  String get closeDialog => '关闭';

  @override
  String chapterCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 章',
      one: '1 章',
      zero: '暂无章节',
    );
    return '$_temp0';
  }

  @override
  String get diagnosticsLabel => 'M1 验收';

  @override
  String get diagnosticTitle => '原生桥接验收';

  @override
  String get diagnosticIdle => '尚未运行原生验收。';

  @override
  String get diagnosticRunning => '正在验证真实 Rust / SQLite 合同…';

  @override
  String get diagnosticRun => '运行原生验收';

  @override
  String get diagnosticPass => '原生验收通过。';

  @override
  String diagnosticFail(String type) {
    return '原生验收失败。错误类型：$type';
  }

  @override
  String get backToWorkspace => '返回工作台';

  @override
  String get startupError => '原生工作台未能启动。';

  @override
  String get realDataLabel => '示例数据';

  @override
  String get languageFallback => '该语言尚未翻译，当前使用英文。';

  @override
  String get untitledWork => '未命名作品';

  @override
  String errorCode(String code) {
    return '错误代码：$code';
  }

  @override
  String get saveDirty => '有未保存更改';

  @override
  String get saveSaving => '保存中…';

  @override
  String get saveSaved => '已保存';

  @override
  String get saveConflict => '保存冲突——草稿已保留';

  @override
  String get saveError => '保存失败——草稿已保留';

  @override
  String get retrySave => '重试保存';

  @override
  String get editorTemporaryHint => '临时编辑区：长文编辑器性能验收尚未完成。';

  @override
  String get draftRestored => '已恢复本机编辑稿';

  @override
  String get draftRestoredBase => '已恢复本机编辑稿（基于旧确认版本）';

  @override
  String get durableSaveFailed => '更改未能持久化。请导出草稿后再重新打开。';

  @override
  String get newChapter => '新建章节';

  @override
  String get newWork => '新建作品';

  @override
  String get renameChapter => '重命名章节';

  @override
  String get archiveChapter => '归档章节';

  @override
  String get restoreChapter => '恢复章节';

  @override
  String get archivedChapters => '已归档';

  @override
  String get confirmChapter => '确认本章';

  @override
  String get confirmTitle => '确认以下正文？';

  @override
  String get confirmNotice => 'Ctrl+S 与自动保存只写编辑稿；确认后创建新的正式版本，编辑稿保留并以新版本为基准。';

  @override
  String get confirmAction => '确认';

  @override
  String get versionsTitle => '确认版本';

  @override
  String get emptyVersions => '还没有确认版本。';

  @override
  String get versionCurrent => '当前';

  @override
  String get rollbackAction => '回退到此版本';

  @override
  String get rollbackTitle => '回退到此版本？';

  @override
  String get rollbackNotice => '正稿将回退到该版本，当前编辑稿将被丢弃。';

  @override
  String get titleRequired => '标题不能为空';

  @override
  String get createAction => '创建';

  @override
  String get saveAction => '保存';

  @override
  String get cancelAction => '取消';

  @override
  String get chapterTitleLabel => '章节标题';

  @override
  String get workTitleLabel => '作品标题';

  @override
  String get exportDraft => '导出草稿';

  @override
  String get exportDone => '草稿已导出';

  @override
  String get exportFailed => '导出失败';

  @override
  String get exportPathLabel => '位置';

  @override
  String exportOmitted(int count) {
    return '$count 个章节未能读取，已略过';
  }

  @override
  String exportChapters(int count) {
    return '已导出 $count 个章节';
  }

  @override
  String get closeFailedTitle => '更改未能保存';

  @override
  String get closeFailedBody => '可以重试、导出草稿或继续编辑，窗口保持打开。';

  @override
  String get retryClose => '重试';

  @override
  String get keepEditing => '继续编辑';

  @override
  String get exitAnyway => '仍然退出';

  @override
  String get exitAnywayHint => '草稿已导出。现在不再保存并退出？';

  @override
  String get recoveryFilenameSuffix => '可读章节恢复稿';

  @override
  String get windowMinimize => '最小化';

  @override
  String get windowMaximize => '最大化';

  @override
  String get windowRestore => '还原';

  @override
  String get windowClose => '关闭窗口';

  @override
  String get windowActionFailed => '窗口操作未完成，请重试或使用系统窗口菜单。';

  @override
  String get discussSelection => '讨论这段';

  @override
  String get discussions => '讨论';

  @override
  String get discussionDraft => '未发草稿';

  @override
  String get discussionInvalid => '选段已变化，原始引用仍保留。';

  @override
  String get discussionSaveFailed => '讨论保存失败，草稿已保留；离开前请重试。';

  @override
  String get discussionEmpty => '尚无讨论';

  @override
  String get candidateCompare => '对比';

  @override
  String get candidateApply => '采纳候选';

  @override
  String get candidateReject => '拒绝候选';

  @override
  String get candidateOriginal => '原选段';

  @override
  String get candidateReplacement => '候选正文';

  @override
  String get candidateApplyNotice => '采纳只把候选写入编辑稿，可用一次撤销撤回；不会创建正式版本。';

  @override
  String get candidateApplyFailed => '候选未写入：正文或原目标已变化，请重新预览后再采纳。';

  @override
  String get discussionHistory => '历史记录';

  @override
  String get editorOperationFailed => '编辑或剪贴板操作未能完成，正文已保留。';

  @override
  String get editorRenderingUnsupported => '当前排版无法显示这段文本。正文已保留，可撤销或导出草稿。';

  @override
  String get editorAccessibleLabel => '正文编辑器';

  @override
  String get discussionSaved => '讨论已保存';

  @override
  String get referenceMaterials => '引用资料';

  @override
  String get referenceEmpty => '暂无出处';

  @override
  String get historicalSource => '历史出处';

  @override
  String get loreTitle => '资料库';

  @override
  String get mapPreview => '地图预览（位置仅在本次会话保留）';

  @override
  String get close => '关闭';

  @override
  String get cancel => '取消';

  @override
  String get deepseekSettings => 'DeepSeek 设置';

  @override
  String get deepseekKey => '新 API Key（仅存 Windows 凭据管理器）';

  @override
  String get deepseekEnable => '为此合成工作区启用官方 DeepSeek';

  @override
  String get deepseekDeleteKey => '删除 Key 并关闭云调用';

  @override
  String get deepseekSaveSettings => '保存设置';

  @override
  String get deepseekFeeNotice =>
      '向官方 DeepSeek 发送以下完整消息可能产生费用。请核对全部内容再确认；取消可能无法避免服务方计费，应用不会自动重试。';

  @override
  String get generationPreview => '预览完整外发消息';

  @override
  String get generationCancel => '取消生成';

  @override
  String get generationApprove => '确认这些材料并仅发送一次';

  @override
  String get generationFailed => '请求未能完成。正文与草稿已保留；再次请求前需重新核对材料。';

  @override
  String backupRehearsed(int count) {
    return '恢复验证通过：$count 部作品。临时库已关闭。';
  }

  @override
  String get bindSource => '将选段绑定为出处';

  @override
  String get referenceUse => '使用所选资料';

  @override
  String get backupRehearse => '独立恢复演练';

  @override
  String get fullBackup => '完整合成备份';

  @override
  String get sourceBindingFailed => '出处绑定失败。请先保存并确认与当前正文完全一致的正式版本。';

  @override
  String get backupFailed => '备份或恢复验证失败，当前库仍保持打开。';

  @override
  String get backupDisclosure =>
      '包含正文、版本、讨论与设置，不含 API Key；仅当前 Windows 用户可解密。恢复演练会使用独立临时库，保留当前库。';

  @override
  String get backupSaved => '备份已写入并验证可恢复';

  @override
  String get characterPlayful => '轻快';

  @override
  String get characterStar => '星星';

  @override
  String get characterConcise => '简洁';

  @override
  String get legacyPatches => '历史候选修改';

  @override
  String get legacyDrafts => '历史试写';

  @override
  String get characterCloud => '云朵';

  @override
  String get novelMemory => '小说记忆';

  @override
  String get saveMemory => '保存';

  @override
  String get addMemory => '增加记忆';

  @override
  String get characterName => '本地私有显示名称';

  @override
  String get novelHistory => '小说审阅历史';

  @override
  String get characterGentle => '温和';

  @override
  String get correctMemory => '编辑记忆';

  @override
  String get characterPack => '声明式角色包';

  @override
  String get openQuestions => '确认稿待决议题';

  @override
  String get learningMemory => '学习记忆';

  @override
  String get memoryTitle => '标题';

  @override
  String get memoryLibrary => '记忆库';

  @override
  String get historyInvalid => '无法读取这条历史记录。';

  @override
  String get chapterSummary => '章节摘要';

  @override
  String get importCharacter => '导入角色包';

  @override
  String get exportCharacter => '导出角色包';

  @override
  String get memoryBody => '内容';

  @override
  String get characterPackDisclosure => '角色包只包含外观与语气，私有名称保留在本地；脚本、路径及额外字段会被拒绝。';

  @override
  String get personalMemory => '个人记忆';

  @override
  String get applyBlock => '采纳此块';

  @override
  String get characterSettings => '角色设置';

  @override
  String get characterMoon => '月亮';

  @override
  String get memoryEmpty => '此空间还没有确认的记忆。';

  @override
  String get oldIdeas => '旧想法';

  @override
  String get preserveTextLanguage => '保持正文语言';

  @override
  String get workspaceTools => '工作区工具';

  @override
  String get companionOpen => '打开工作区';

  @override
  String get nextIdea => '下一个想法';

  @override
  String get importConfirm => '确认导入';

  @override
  String get companionDisclosure => '仅本次运行启用。全屏及专注时隐藏；无法确认勿扰状态时保持隐藏。';

  @override
  String get noIdea => '已导入的用户消息中没有更多想法候选。';

  @override
  String get searchImported => '搜索已导入消息';

  @override
  String get importPartial => '预览有省略或解析告警，请核对所选原文后再确认。';

  @override
  String get importedLibrary => '已导入对话';

  @override
  String get companionHide => '显示／隐藏伙伴';

  @override
  String get importDisclosure =>
      '选择不超过 16 MiB 的 UTF-8 JSON、JSONL 或 Markdown 文件。只读取所选文件。预览每段对话最多显示 10 条消息、每条 1500 字；确认后保存完整解析内容。不发送网络请求。';

  @override
  String get sourceOriginal => '完整所选源文件';

  @override
  String get importDone => '导入已提交，可在下方搜索消息。';

  @override
  String get importSelectedFile => '选择对话文件';

  @override
  String get desktopCompanion => '桌面伙伴';

  @override
  String get companionQuit => '保存并退出';

  @override
  String get confirmIdea => '保存这个想法';

  @override
  String get companionFailed => '桌面伙伴已停止，可在角色设置中重新启用。';

  @override
  String get learningExercise => '五分钟练习';

  @override
  String get learningUnavailable =>
      '无法打开隔离练习窗口，需要较新的 Microsoft Edge WebView2 运行时及完整学习资源。';

  @override
  String get parsedImportedMessage => '导入消息（解析文本）';

  @override
  String get convertNovel => '转为小说项目';

  @override
  String get ideaWrong => '不再认可';

  @override
  String get ideaDone => '已经完成';

  @override
  String get memoryActions => '记忆操作';

  @override
  String get memoryMutationNotice =>
      '确认更新这条想法？状态更新会复核当前状态；转换会创建目标并保留出处，不能重复转换。';

  @override
  String get deleteMemory => '删除这条记忆';

  @override
  String get ideaLiked => '仍然喜欢';

  @override
  String get ideaStarted => '已经开始';

  @override
  String get deleteMemoryNotice => '将隐藏这条记忆。原始导入会话保留；本操作不会删除源文件。';

  @override
  String get convertPersonal => '转为个人记忆';

  @override
  String get convertLearning => '转为学习目标';

  @override
  String get ideaShelved => '暂时搁置';

  @override
  String get exportMemory => '导出这条记忆';

  @override
  String get historicalAi => '模型试写';

  @override
  String get loadHistoricalDraft => '载入为编辑稿';

  @override
  String get discardHistoricalDraft => '丢弃这份试写';

  @override
  String get historicalDiscarded => '已丢弃';

  @override
  String get historicalAuthor => '作者文本';

  @override
  String get loadHistoricalNotice =>
      '将用这份历史文本替换当前编辑稿，保留编辑器撤销历史。它仍未成为确认稿；确认章节前请重新核对，历史试写的待决状态不变。';

  @override
  String get historicalUnknown => '未知状态';

  @override
  String get historicalPending => '待决';

  @override
  String get historicalAccepted => '已采纳';

  @override
  String get discardHistoricalNotice => '仅将这份待决试写标为已丢弃，历史文本仍可阅读。当前编辑稿和确认版本保留。';

  @override
  String get rpgNewScene => '新的场景';

  @override
  String get summaryTaskNotice =>
      '只使用本章已确认版本，忽略未确认工作副本。摘要是可丢弃派生材料；来源变化时拒绝发布。每次重建均需预览并确认。';

  @override
  String get rpgReply => '主角回复（1–300 字）';

  @override
  String get rebuildSummary => '重建章节摘要';

  @override
  String get rpgTitle => '跑团试写';

  @override
  String get rpgTaskNotice => '场景提案不会进入正稿。选择或填写主角回复后，重新预览材料并确认发送，结果仅保存为待确认试写。';

  @override
  String get rpgDirection => '场景方向（1–500 字）';

  @override
  String get summaryTaskDone => '摘要重建完成，正文未被更改。';

  @override
  String get rpgDraftDone => '已保存为待确认试写。可在章节历史中审阅、载入或丢弃。';

  @override
  String get loreAliases => '别名（每行一个）';

  @override
  String get openSourceChapter => '定位到来源章节';

  @override
  String get mapRelation => '关系';

  @override
  String get mapRelationsHelp =>
      '布局和关系仅在本次资料窗口预览，不会保存。拖动地点卡片，滚轮缩放；依次点两个地点的“关系”可添加或移除连线。';

  @override
  String get loreScopeRetrospective => '回溯更改既有设定';

  @override
  String get loreScopeFromChapter => '自本章起：';

  @override
  String get loreScopeWhole => '全程有效';

  @override
  String get summaryReady => '摘要有效';

  @override
  String get rebuildRunning => '正在重建';

  @override
  String get rebuildDone => '重建完成';

  @override
  String get rebuildQueued => '等待重新预览和批准';

  @override
  String get rebuildFailed => '重建未完成，可重新预览后尝试';

  @override
  String get summaryStale => '摘要已过期，不能当作当前确认内容，请重新预览并重建。';

  @override
  String get refreshSources => '刷新出处';

  @override
  String get manuscriptSources => '正文出处';

  @override
  String get sourceMarksHint => '按住 Ctrl 点击下划线，可打开关联资料。';

  @override
  String get sourceMarksFailed => '出处未能加载，请刷新后重试。';

  @override
  String get sourceMarksLoading => '出处加载中…';

  @override
  String get sourceMarksEmpty => '本章暂无出处';

  @override
  String get sourceOpenFailed => '关联资料未能打开，请重试。';

  @override
  String get sourceOpenRetry => '重试打开';

  @override
  String get findInChapter => '查找正文';

  @override
  String get findPrompt => '查找当前章';

  @override
  String get findNext => '下一处';

  @override
  String get findNoMatch => '本章没有匹配文字。';

  @override
  String findPosition(String position) {
    return '已定位第 $position 字';
  }

  @override
  String chapterCharacters(int count) {
    return '本章 $count 字';
  }

  @override
  String get chapterEnd => '本章结束';

  @override
  String get undo => '撤销';

  @override
  String get redo => '重做';

  @override
  String get chapterDiscussion => '章节讨论';

  @override
  String discussionIndex(int count) {
    return '讨论记录 · $count';
  }

  @override
  String get discussionWholeChapter => '全章讨论';

  @override
  String get discussionSelection => '选段';

  @override
  String get discussionValid => '可继续讨论';

  @override
  String get discussionHasDraft => '有未发草稿';

  @override
  String get discussionGenerationUnavailable =>
      '整章讨论或原目标已变化的线程只能保留草稿与查看历史；生成预览需要有效选段。';

  @override
  String get searchChapters => '搜索章节';

  @override
  String get noMatchingChapters => '没有匹配的章节。';

  @override
  String get searchResources => '搜索资料';

  @override
  String get noMatchingResources => '没有匹配的资料。';

  @override
  String get exportWork => '导出正文与资料';

  @override
  String get exportWorkDone => '正文与资料已导出';

  @override
  String exportLoreCount(int count) {
    return '已导出 $count 条资料';
  }

  @override
  String get exportManuscriptSuffix => '正文与资料';

  @override
  String get ideaTarget => '转换目标';

  @override
  String get ideaTargetOpen => '查看/编辑目标';

  @override
  String get ideaTargetTitleLabel => '目标标题';

  @override
  String get ideaTargetSummaryLabel => '目标笔记';

  @override
  String get ideaTargetSave => '保存目标';

  @override
  String get ideaTargetSaved => '目标已保存。';

  @override
  String get ideaTargetFailed => '目标未能保存，请刷新后重试。';

  @override
  String get ideaTargetMissing => '这条旧想法没有可打开的目标。';

  @override
  String get ideaTargetSource => '来源出处';

  @override
  String get ideaTargetNovelSync => '编辑小说目标会同步修改作品名。';

  @override
  String get sideChapters => '章节';

  @override
  String get sideResources => '资料';

  @override
  String get searchWorks => '搜索作品';

  @override
  String get noMatchingWorks => '没有匹配的作品。';

  @override
  String get switchWork => '切换作品';

  @override
  String get sidebarReal => '本机作品 · SQLite';

  @override
  String get sidebarSynthetic => '示例作品 · 本机预览';

  @override
  String get resourcesEmpty => '暂无故事资料。';

  @override
  String get loreReadFailed => '资料读取失败，请重试。';

  @override
  String get newEntity => '新建设定';

  @override
  String get chapterAndVersions => '章节与版本';

  @override
  String get layoutMenu => '版式';

  @override
  String get layoutComfort => '舒适 · 760 px';

  @override
  String get layoutWide => '宽稿 · 920 px';

  @override
  String get modelSettings => '模型设置';

  @override
  String get moreTools => '更多';

  @override
  String get exportMenu => '导出';

  @override
  String chapterMeta(String work, int count) {
    return '$work · $count 字';
  }

  @override
  String selectionCount(int count) {
    return '已选 $count 字';
  }

  @override
  String get loreGroupCharacters => '人物';

  @override
  String get loreGroupWorld => '世界规则';

  @override
  String get loreGroupLocations => '地点';

  @override
  String get loreGroupTimeline => '时间线';

  @override
  String get loreGroupTaboo => '禁忌';

  @override
  String get loreGroupStyle => '文风';

  @override
  String get attachToDiscussion => '带入讨论';

  @override
  String get removeReference => '移除引用';

  @override
  String get expandLoreEdit => '展开编辑';

  @override
  String get lorePreviewHint => '仅预览：不会带入讨论，也不会发送给模型。';

  @override
  String get loreAttachedBoundary => '已带入当前讨论；生成前请核对完整外发预览。';

  @override
  String get loreAttachUnavailable => '当前没有可带入的讨论：请先打开作品与章节。';

  @override
  String get loreAttachLimit => '最多带入 32 项资料。';

  @override
  String get loreEntryMissing => '资料条目已不存在，请刷新后重试。';

  @override
  String get historyReferences => '历史请求中的引用（提交时快照）';

  @override
  String get viewCurrentLore => '查看当前资料';

  @override
  String get currentLoreContent => '当前内容';

  @override
  String get chapterDirectory => '章节目录';

  @override
  String get resourceDirectory => '故事资料';

  @override
  String get clearSearch => '清空搜索';

  @override
  String get loreUnconfirmed => '请先在资料库确认此条目，再选择引用。';

  @override
  String get referenceLimit => '最多可选择 32 项资料。';

  @override
  String get loreAdd => '新增资料';

  @override
  String get loreEdit => '编辑资料';

  @override
  String get characterAppearance => '外观';

  @override
  String get characterVoice => '语音';

  @override
  String get loreKind => '类型';

  @override
  String get loreName => '名称';

  @override
  String get loreBody => '内容';

  @override
  String get loreTimeline => '时间线';

  @override
  String get loreTaboo => '禁忌与约束';

  @override
  String get loreStyle => '文风';

  @override
  String get loreEmpty => '还没有资料，可从“新增资料”开始建立。';

  @override
  String get historyEmpty => '本章暂无审阅历史。';

  @override
  String get importEmpty => '选择对话文件以预览导入，或搜索已有导入消息。';

  @override
  String get loreScope => '生效范围';
}

/// The translations for Chinese, using the Han script (`zh_Hans`).
class AppLocalizationsZhHans extends AppLocalizationsZh {
  AppLocalizationsZhHans() : super('zh_Hans');

  @override
  String get appTitle => '幻月';

  @override
  String get workspaceTitle => '写作工作台';

  @override
  String get chooseWork => '选择作品';

  @override
  String get works => '作品';

  @override
  String get chapters => '目录';

  @override
  String get noWorksTitle => '为下一段故事，留一页安静的纸';

  @override
  String get noWorksBody => '临时资料库还是空的。可以打开作品选择器，或创建示例材料体验工作台。';

  @override
  String get createDemo => '创建示例材料';

  @override
  String get loading => '正在读取工作台…';

  @override
  String get retry => '重新读取';

  @override
  String get errorTitle => '暂时无法读取工作台';

  @override
  String get errorBody => '材料没有被更改。可以重新读取后再试。';

  @override
  String get emptyChapters => '这部作品还没有章节。';

  @override
  String get chooseChapter => '从目录选择一章开始阅读。';

  @override
  String get readOnlyHint => '只读预览 · 正文编辑将在下一阶段接入';

  @override
  String get focusOn => '专注模式';

  @override
  String get focusOff => '退出专注';

  @override
  String get wideOn => '宽稿模式';

  @override
  String get wideOff => '舒适宽度';

  @override
  String get languageLabel => '界面语言';

  @override
  String get chineseLabel => '简体中文';

  @override
  String get englishLabel => 'English';

  @override
  String get realMode => 'REAL · Rust 桥接';

  @override
  String get syntheticMode => 'SYNTHETIC · 内存替身';

  @override
  String get syntheticNotice => '临时示例库 · 未接入作者数据 · 云能力关闭';

  @override
  String get workLanguage => '作品语言';

  @override
  String get documentLanguage => '章节语言';

  @override
  String get outputLanguage => '模型输出语言';

  @override
  String get mixedLanguage => '混合语言';

  @override
  String get undeterminedLanguage => '未指定';

  @override
  String get languageIndependence => '切换界面语言不会翻译或改写正文。';

  @override
  String get openDirectory => '打开章节目录';

  @override
  String get discussionCollapse => '收起讨论';

  @override
  String get closeDialog => '关闭';

  @override
  String chapterCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 章',
      one: '1 章',
      zero: '暂无章节',
    );
    return '$_temp0';
  }

  @override
  String get diagnosticsLabel => 'M1 验收';

  @override
  String get diagnosticTitle => '原生桥接验收';

  @override
  String get diagnosticIdle => '尚未运行原生验收。';

  @override
  String get diagnosticRunning => '正在验证真实 Rust / SQLite 合同…';

  @override
  String get diagnosticRun => '运行原生验收';

  @override
  String get diagnosticPass => '原生验收通过。';

  @override
  String diagnosticFail(String type) {
    return '原生验收失败。错误类型：$type';
  }

  @override
  String get backToWorkspace => '返回工作台';

  @override
  String get startupError => '原生工作台未能启动。';

  @override
  String get realDataLabel => '示例数据';

  @override
  String get languageFallback => '该语言尚未翻译，当前使用英文。';

  @override
  String get untitledWork => '未命名作品';

  @override
  String errorCode(String code) {
    return '错误代码：$code';
  }

  @override
  String get saveDirty => '有未保存更改';

  @override
  String get saveSaving => '保存中…';

  @override
  String get saveSaved => '已保存';

  @override
  String get saveConflict => '保存冲突——草稿已保留';

  @override
  String get saveError => '保存失败——草稿已保留';

  @override
  String get retrySave => '重试保存';

  @override
  String get editorTemporaryHint => '临时编辑区：长文编辑器性能验收尚未完成。';

  @override
  String get draftRestored => '已恢复本机编辑稿';

  @override
  String get draftRestoredBase => '已恢复本机编辑稿（基于旧确认版本）';

  @override
  String get durableSaveFailed => '更改未能持久化。请导出草稿后再重新打开。';

  @override
  String get newChapter => '新建章节';

  @override
  String get newWork => '新建作品';

  @override
  String get renameChapter => '重命名章节';

  @override
  String get archiveChapter => '归档章节';

  @override
  String get restoreChapter => '恢复章节';

  @override
  String get archivedChapters => '已归档';

  @override
  String get confirmChapter => '确认本章';

  @override
  String get confirmTitle => '确认以下正文？';

  @override
  String get confirmNotice => 'Ctrl+S 与自动保存只写编辑稿；确认后创建新的正式版本，编辑稿保留并以新版本为基准。';

  @override
  String get confirmAction => '确认';

  @override
  String get versionsTitle => '确认版本';

  @override
  String get emptyVersions => '还没有确认版本。';

  @override
  String get versionCurrent => '当前';

  @override
  String get rollbackAction => '回退到此版本';

  @override
  String get rollbackTitle => '回退到此版本？';

  @override
  String get rollbackNotice => '正稿将回退到该版本，当前编辑稿将被丢弃。';

  @override
  String get titleRequired => '标题不能为空';

  @override
  String get createAction => '创建';

  @override
  String get saveAction => '保存';

  @override
  String get cancelAction => '取消';

  @override
  String get chapterTitleLabel => '章节标题';

  @override
  String get workTitleLabel => '作品标题';

  @override
  String get exportDraft => '导出草稿';

  @override
  String get exportDone => '草稿已导出';

  @override
  String get exportFailed => '导出失败';

  @override
  String get exportPathLabel => '位置';

  @override
  String exportOmitted(int count) {
    return '$count 个章节未能读取，已略过';
  }

  @override
  String exportChapters(int count) {
    return '已导出 $count 个章节';
  }

  @override
  String get closeFailedTitle => '更改未能保存';

  @override
  String get closeFailedBody => '可以重试、导出草稿或继续编辑，窗口保持打开。';

  @override
  String get retryClose => '重试';

  @override
  String get keepEditing => '继续编辑';

  @override
  String get exitAnyway => '仍然退出';

  @override
  String get exitAnywayHint => '草稿已导出。现在不再保存并退出？';

  @override
  String get recoveryFilenameSuffix => '可读章节恢复稿';

  @override
  String get windowMinimize => '最小化';

  @override
  String get windowMaximize => '最大化';

  @override
  String get windowRestore => '还原';

  @override
  String get windowClose => '关闭窗口';

  @override
  String get windowActionFailed => '窗口操作未完成，请重试或使用系统窗口菜单。';

  @override
  String get discussSelection => '讨论这段';

  @override
  String get discussions => '讨论';

  @override
  String get discussionDraft => '未发草稿';

  @override
  String get discussionInvalid => '选段已变化，原始引用仍保留。';

  @override
  String get discussionSaveFailed => '讨论保存失败，草稿已保留；离开前请重试。';

  @override
  String get discussionEmpty => '尚无讨论';

  @override
  String get candidateCompare => '对比';

  @override
  String get candidateApply => '采纳候选';

  @override
  String get candidateReject => '拒绝候选';

  @override
  String get candidateOriginal => '原选段';

  @override
  String get candidateReplacement => '候选正文';

  @override
  String get candidateApplyNotice => '采纳只把候选写入编辑稿，可用一次撤销撤回；不会创建正式版本。';

  @override
  String get candidateApplyFailed => '候选未写入：正文或原目标已变化，请重新预览后再采纳。';

  @override
  String get discussionHistory => '历史记录';

  @override
  String get editorOperationFailed => '编辑或剪贴板操作未能完成，正文已保留。';

  @override
  String get editorRenderingUnsupported => '当前排版无法显示这段文本。正文已保留，可撤销或导出草稿。';

  @override
  String get editorAccessibleLabel => '正文编辑器';

  @override
  String get discussionSaved => '讨论已保存';

  @override
  String get referenceMaterials => '引用资料';

  @override
  String get referenceEmpty => '暂无出处';

  @override
  String get historicalSource => '历史出处';

  @override
  String get loreTitle => '资料库';

  @override
  String get mapPreview => '地图预览（位置仅在本次会话保留）';

  @override
  String get close => '关闭';

  @override
  String get cancel => '取消';

  @override
  String get deepseekSettings => 'DeepSeek 设置';

  @override
  String get deepseekKey => '新 API Key（仅存 Windows 凭据管理器）';

  @override
  String get deepseekEnable => '为此合成工作区启用官方 DeepSeek';

  @override
  String get deepseekDeleteKey => '删除 Key 并关闭云调用';

  @override
  String get deepseekSaveSettings => '保存设置';

  @override
  String get deepseekFeeNotice =>
      '向官方 DeepSeek 发送以下完整消息可能产生费用。请核对全部内容再确认；取消可能无法避免服务方计费，应用不会自动重试。';

  @override
  String get generationPreview => '预览完整外发消息';

  @override
  String get generationCancel => '取消生成';

  @override
  String get generationApprove => '确认这些材料并仅发送一次';

  @override
  String get generationFailed => '请求未能完成。正文与草稿已保留；再次请求前需重新核对材料。';

  @override
  String backupRehearsed(int count) {
    return '恢复验证通过：$count 部作品。临时库已关闭。';
  }

  @override
  String get bindSource => '将选段绑定为出处';

  @override
  String get referenceUse => '使用所选资料';

  @override
  String get backupRehearse => '独立恢复演练';

  @override
  String get fullBackup => '完整合成备份';

  @override
  String get sourceBindingFailed => '出处绑定失败。请先保存并确认与当前正文完全一致的正式版本。';

  @override
  String get backupFailed => '备份或恢复验证失败，当前库仍保持打开。';

  @override
  String get backupDisclosure =>
      '包含正文、版本、讨论与设置，不含 API Key；仅当前 Windows 用户可解密。恢复演练会使用独立临时库，保留当前库。';

  @override
  String get backupSaved => '备份已写入并验证可恢复';

  @override
  String get characterPlayful => '轻快';

  @override
  String get characterStar => '星星';

  @override
  String get characterConcise => '简洁';

  @override
  String get legacyPatches => '历史候选修改';

  @override
  String get legacyDrafts => '历史试写';

  @override
  String get characterCloud => '云朵';

  @override
  String get novelMemory => '小说记忆';

  @override
  String get saveMemory => '保存';

  @override
  String get addMemory => '增加记忆';

  @override
  String get characterName => '本地私有显示名称';

  @override
  String get novelHistory => '小说审阅历史';

  @override
  String get characterGentle => '温和';

  @override
  String get correctMemory => '编辑记忆';

  @override
  String get characterPack => '声明式角色包';

  @override
  String get openQuestions => '确认稿待决议题';

  @override
  String get learningMemory => '学习记忆';

  @override
  String get memoryTitle => '标题';

  @override
  String get memoryLibrary => '记忆库';

  @override
  String get historyInvalid => '无法读取这条历史记录。';

  @override
  String get chapterSummary => '章节摘要';

  @override
  String get importCharacter => '导入角色包';

  @override
  String get exportCharacter => '导出角色包';

  @override
  String get memoryBody => '内容';

  @override
  String get characterPackDisclosure => '角色包只包含外观与语气，私有名称保留在本地；脚本、路径及额外字段会被拒绝。';

  @override
  String get personalMemory => '个人记忆';

  @override
  String get applyBlock => '采纳此块';

  @override
  String get characterSettings => '角色设置';

  @override
  String get characterMoon => '月亮';

  @override
  String get memoryEmpty => '此空间还没有确认的记忆。';

  @override
  String get oldIdeas => '旧想法';

  @override
  String get preserveTextLanguage => '保持正文语言';

  @override
  String get workspaceTools => '工作区工具';

  @override
  String get companionOpen => '打开工作区';

  @override
  String get nextIdea => '下一个想法';

  @override
  String get importConfirm => '确认导入';

  @override
  String get companionDisclosure => '仅本次运行启用。全屏及专注时隐藏；无法确认勿扰状态时保持隐藏。';

  @override
  String get noIdea => '已导入的用户消息中没有更多想法候选。';

  @override
  String get searchImported => '搜索已导入消息';

  @override
  String get importPartial => '预览有省略或解析告警，请核对所选原文后再确认。';

  @override
  String get importedLibrary => '已导入对话';

  @override
  String get companionHide => '显示／隐藏伙伴';

  @override
  String get importDisclosure =>
      '选择不超过 16 MiB 的 UTF-8 JSON、JSONL 或 Markdown 文件。只读取所选文件。预览每段对话最多显示 10 条消息、每条 1500 字；确认后保存完整解析内容。不发送网络请求。';

  @override
  String get sourceOriginal => '完整所选源文件';

  @override
  String get importDone => '导入已提交，可在下方搜索消息。';

  @override
  String get importSelectedFile => '选择对话文件';

  @override
  String get desktopCompanion => '桌面伙伴';

  @override
  String get companionQuit => '保存并退出';

  @override
  String get confirmIdea => '保存这个想法';

  @override
  String get companionFailed => '桌面伙伴已停止，可在角色设置中重新启用。';

  @override
  String get learningExercise => '五分钟练习';

  @override
  String get learningUnavailable =>
      '无法打开隔离练习窗口，需要较新的 Microsoft Edge WebView2 运行时及完整学习资源。';

  @override
  String get parsedImportedMessage => '导入消息（解析文本）';

  @override
  String get convertNovel => '转为小说项目';

  @override
  String get ideaWrong => '不再认可';

  @override
  String get ideaDone => '已经完成';

  @override
  String get memoryActions => '记忆操作';

  @override
  String get memoryMutationNotice =>
      '确认更新这条想法？状态更新会复核当前状态；转换会创建目标并保留出处，不能重复转换。';

  @override
  String get deleteMemory => '删除这条记忆';

  @override
  String get ideaLiked => '仍然喜欢';

  @override
  String get ideaStarted => '已经开始';

  @override
  String get deleteMemoryNotice => '将隐藏这条记忆。原始导入会话保留；本操作不会删除源文件。';

  @override
  String get convertPersonal => '转为个人记忆';

  @override
  String get convertLearning => '转为学习目标';

  @override
  String get ideaShelved => '暂时搁置';

  @override
  String get exportMemory => '导出这条记忆';

  @override
  String get historicalAi => '模型试写';

  @override
  String get loadHistoricalDraft => '载入为编辑稿';

  @override
  String get discardHistoricalDraft => '丢弃这份试写';

  @override
  String get historicalDiscarded => '已丢弃';

  @override
  String get historicalAuthor => '作者文本';

  @override
  String get loadHistoricalNotice =>
      '将用这份历史文本替换当前编辑稿，保留编辑器撤销历史。它仍未成为确认稿；确认章节前请重新核对，历史试写的待决状态不变。';

  @override
  String get historicalUnknown => '未知状态';

  @override
  String get historicalPending => '待决';

  @override
  String get historicalAccepted => '已采纳';

  @override
  String get discardHistoricalNotice => '仅将这份待决试写标为已丢弃，历史文本仍可阅读。当前编辑稿和确认版本保留。';

  @override
  String get rpgNewScene => '新的场景';

  @override
  String get summaryTaskNotice =>
      '只使用本章已确认版本，忽略未确认工作副本。摘要是可丢弃派生材料；来源变化时拒绝发布。每次重建均需预览并确认。';

  @override
  String get rpgReply => '主角回复（1–300 字）';

  @override
  String get rebuildSummary => '重建章节摘要';

  @override
  String get rpgTitle => '跑团试写';

  @override
  String get rpgTaskNotice => '场景提案不会进入正稿。选择或填写主角回复后，重新预览材料并确认发送，结果仅保存为待确认试写。';

  @override
  String get rpgDirection => '场景方向（1–500 字）';

  @override
  String get summaryTaskDone => '摘要重建完成，正文未被更改。';

  @override
  String get rpgDraftDone => '已保存为待确认试写。可在章节历史中审阅、载入或丢弃。';

  @override
  String get loreAliases => '别名（每行一个）';

  @override
  String get openSourceChapter => '定位到来源章节';

  @override
  String get mapRelation => '关系';

  @override
  String get mapRelationsHelp =>
      '布局和关系仅在本次资料窗口预览，不会保存。拖动地点卡片，滚轮缩放；依次点两个地点的“关系”可添加或移除连线。';

  @override
  String get loreScopeRetrospective => '回溯更改既有设定';

  @override
  String get loreScopeFromChapter => '自本章起：';

  @override
  String get loreScopeWhole => '全程有效';

  @override
  String get summaryReady => '摘要有效';

  @override
  String get rebuildRunning => '正在重建';

  @override
  String get rebuildDone => '重建完成';

  @override
  String get rebuildQueued => '等待重新预览和批准';

  @override
  String get rebuildFailed => '重建未完成，可重新预览后尝试';

  @override
  String get summaryStale => '摘要已过期，不能当作当前确认内容，请重新预览并重建。';

  @override
  String get refreshSources => '刷新出处';

  @override
  String get manuscriptSources => '正文出处';

  @override
  String get sourceMarksHint => '按住 Ctrl 点击下划线，可打开关联资料。';

  @override
  String get sourceMarksFailed => '出处未能加载，请刷新后重试。';

  @override
  String get sourceMarksLoading => '出处加载中…';

  @override
  String get sourceMarksEmpty => '本章暂无出处';

  @override
  String get sourceOpenFailed => '关联资料未能打开，请重试。';

  @override
  String get sourceOpenRetry => '重试打开';

  @override
  String get findInChapter => '查找正文';

  @override
  String get findPrompt => '查找当前章';

  @override
  String get findNext => '下一处';

  @override
  String get findNoMatch => '本章没有匹配文字。';

  @override
  String findPosition(String position) {
    return '已定位第 $position 字';
  }

  @override
  String chapterCharacters(int count) {
    return '本章 $count 字';
  }

  @override
  String get chapterEnd => '本章结束';

  @override
  String get undo => '撤销';

  @override
  String get redo => '重做';

  @override
  String get chapterDiscussion => '章节讨论';

  @override
  String discussionIndex(int count) {
    return '讨论记录 · $count';
  }

  @override
  String get discussionWholeChapter => '全章讨论';

  @override
  String get discussionSelection => '选段';

  @override
  String get discussionValid => '可继续讨论';

  @override
  String get discussionHasDraft => '有未发草稿';

  @override
  String get discussionGenerationUnavailable =>
      '整章讨论或原目标已变化的线程只能保留草稿与查看历史；生成预览需要有效选段。';

  @override
  String get searchChapters => '搜索章节';

  @override
  String get noMatchingChapters => '没有匹配的章节。';

  @override
  String get searchResources => '搜索资料';

  @override
  String get noMatchingResources => '没有匹配的资料。';

  @override
  String get exportWork => '导出正文与资料';

  @override
  String get exportWorkDone => '正文与资料已导出';

  @override
  String exportLoreCount(int count) {
    return '已导出 $count 条资料';
  }

  @override
  String get exportManuscriptSuffix => '正文与资料';

  @override
  String get ideaTarget => '转换目标';

  @override
  String get ideaTargetOpen => '查看/编辑目标';

  @override
  String get ideaTargetTitleLabel => '目标标题';

  @override
  String get ideaTargetSummaryLabel => '目标笔记';

  @override
  String get ideaTargetSave => '保存目标';

  @override
  String get ideaTargetSaved => '目标已保存。';

  @override
  String get ideaTargetFailed => '目标未能保存，请刷新后重试。';

  @override
  String get ideaTargetMissing => '这条旧想法没有可打开的目标。';

  @override
  String get ideaTargetSource => '来源出处';

  @override
  String get ideaTargetNovelSync => '编辑小说目标会同步修改作品名。';

  @override
  String get sideChapters => '章节';

  @override
  String get sideResources => '资料';

  @override
  String get searchWorks => '搜索作品';

  @override
  String get noMatchingWorks => '没有匹配的作品。';

  @override
  String get switchWork => '切换作品';

  @override
  String get sidebarReal => '本机作品 · SQLite';

  @override
  String get sidebarSynthetic => '示例作品 · 本机预览';

  @override
  String get resourcesEmpty => '暂无故事资料。';

  @override
  String get loreReadFailed => '资料读取失败，请重试。';

  @override
  String get newEntity => '新建设定';

  @override
  String get chapterAndVersions => '章节与版本';

  @override
  String get layoutMenu => '版式';

  @override
  String get layoutComfort => '舒适 · 760 px';

  @override
  String get layoutWide => '宽稿 · 920 px';

  @override
  String get modelSettings => '模型设置';

  @override
  String get moreTools => '更多';

  @override
  String get exportMenu => '导出';

  @override
  String chapterMeta(String work, int count) {
    return '$work · $count 字';
  }

  @override
  String selectionCount(int count) {
    return '已选 $count 字';
  }

  @override
  String get loreGroupCharacters => '人物';

  @override
  String get loreGroupWorld => '世界规则';

  @override
  String get loreGroupLocations => '地点';

  @override
  String get loreGroupTimeline => '时间线';

  @override
  String get loreGroupTaboo => '禁忌';

  @override
  String get loreGroupStyle => '文风';

  @override
  String get attachToDiscussion => '带入讨论';

  @override
  String get removeReference => '移除引用';

  @override
  String get expandLoreEdit => '展开编辑';

  @override
  String get lorePreviewHint => '仅预览：不会带入讨论，也不会发送给模型。';

  @override
  String get loreAttachedBoundary => '已带入当前讨论；生成前请核对完整外发预览。';

  @override
  String get loreAttachUnavailable => '当前没有可带入的讨论：请先打开作品与章节。';

  @override
  String get loreAttachLimit => '最多带入 32 项资料。';

  @override
  String get loreEntryMissing => '资料条目已不存在，请刷新后重试。';

  @override
  String get historyReferences => '历史请求中的引用（提交时快照）';

  @override
  String get viewCurrentLore => '查看当前资料';

  @override
  String get currentLoreContent => '当前内容';

  @override
  String get chapterDirectory => '章节目录';

  @override
  String get resourceDirectory => '故事资料';

  @override
  String get clearSearch => '清空搜索';

  @override
  String get loreUnconfirmed => '请先在资料库确认此条目，再选择引用。';

  @override
  String get referenceLimit => '最多可选择 32 项资料。';

  @override
  String get loreAdd => '新增资料';

  @override
  String get loreEdit => '编辑资料';

  @override
  String get characterAppearance => '外观';

  @override
  String get characterVoice => '语音';

  @override
  String get loreKind => '类型';

  @override
  String get loreName => '名称';

  @override
  String get loreBody => '内容';

  @override
  String get loreTimeline => '时间线';

  @override
  String get loreTaboo => '禁忌与约束';

  @override
  String get loreStyle => '文风';

  @override
  String get loreEmpty => '还没有资料，可从“新增资料”开始建立。';

  @override
  String get historyEmpty => '本章暂无审阅历史。';

  @override
  String get importEmpty => '选择对话文件以预览导入，或搜索已有导入消息。';

  @override
  String get loreScope => '生效范围';
}
