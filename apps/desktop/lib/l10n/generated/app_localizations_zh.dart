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
  String get confirmNotice => '将创建新的确认版本，编辑稿保留并以新版本为基准。';

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
  String get confirmNotice => '将创建新的确认版本，编辑稿保留并以新版本为基准。';

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
}
