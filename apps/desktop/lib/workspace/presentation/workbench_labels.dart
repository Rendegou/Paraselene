// 工作台本地化文案适配，只扩展界面字符串，不改变作者内容。
import '../../l10n/generated/app_localizations.dart';

/// Transforms translated chrome only for the optional expansion harness.
///
/// 界面文案包装：伪本地化只作用于 UI 文案，不翻译也不改写作品、章节与作者正文。
class WorkbenchLabels {
  const WorkbenchLabels(this.strings, this.pseudo);

  /// 当前界面语言的完整标签集合。
  final AppLocalizations strings;

  /// 是否扩展界面标签进行布局验证，不改作者内容。
  final bool pseudo;

  /// 返回本地化文案；伪本地化时复制并加方括号，仅用于扩展性验证。
  String call(String value) => pseudo ? '[$value · $value]' : value;
}
