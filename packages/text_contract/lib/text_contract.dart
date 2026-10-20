// 纯 Dart 文本合同包的公开出口，汇总编辑坐标与语言偏好两组值对象。
//
// 本包不依赖 Flutter、IO 或数据库，不触碰正文持久化；所有失败用稳定错误码表达。

/// Exact text and language metadata contracts without UI or native dependencies.
///
/// 中文契约：只定义不可变值对象与坐标换算，不做 IO、也不依赖 Flutter；错误码保持稳定。
library;

export 'domain/editing/text_coordinates.dart';
export 'domain/models/language_preferences.dart';
