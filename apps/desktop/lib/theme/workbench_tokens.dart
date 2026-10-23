// 工作台语义令牌：定义纸面、工具、状态及排版角色，供界面与绘制共享。
// 仅保存 Flutter 值，不读写库或正文；尺寸为 logical px，字号随系统文字缩放。
import 'package:flutter/material.dart';

/// 当前设计系统的颜色、尺寸与文字角色；业务不得复制裸色或字体声明。
abstract final class WorkbenchTokens {
  /// 正文纸面底色。
  static const paper = Color(0xfffaf9f5);

  /// 外框与目录底色。
  static const frame = Color(0xfff3f4f6);

  /// 顶部工具栏底色。
  static const toolbar = Color(0xfff8f8f9);

  /// 主要文字颜色。
  static const ink = Color(0xff292d34);

  /// 次要文字颜色；在纸面、框架和浮层上保持可读对比度。
  static const muted = Color(0xff616976);

  /// 装饰分隔线；不作为识别必要控件或焦点的唯一线索。
  static const stroke = Color(0xffdfe2e7);

  /// 主要动作、选中项文字和键盘焦点颜色。
  static const accent = Color(0xff49659c);

  /// 选中项底色；同时保留文字、勾选或语义状态。
  static const selected = Color(0xffe8edf5);

  /// 普通悬停底色。
  static const hover = Color(0xffe9ecf1);

  /// 作者正文选区底色。
  static const selection = Color(0xffdce5f4);

  /// 错误和需要作者处理的警告文字。
  static const warning = Color(0xff955127);

  /// 保存成功状态点；同时有状态文字。
  static const saved = Color(0xff647f70);

  /// 不绘制表面时的透明色。
  static const transparent = Colors.transparent;

  /// 菜单、对话框与资料浮层表面。
  static const floating = Colors.white;

  /// 临时浮层的轻量阴影；不得绘制到正文嵌入区域。
  static const shadow = Color(0x1f000000);

  /// 搜索外壳和待载入内容的中性底色。
  static const placeholder = Color(0xffeaecf0);

  /// 正文出处标记颜色。
  static const source = Color(0xff2c5c83);

  /// Tooltip 与错误通知的深色表面。
  static const inverseSurface = Color(0xff2f3640);

  /// 控件悬停叠色；不改变几何与命中范围。
  static const hoverOverlay = Color(0x1249659c);

  /// 控件按下叠色。
  static const pressedOverlay = Color(0x2449659c);

  /// 原生选择控件的局部焦点叠色。
  static const focusOverlay = Color(0x3349659c);

  /// 目录栏宽度。
  static const directoryWidth = 240.0;

  /// 舒适阅读外容器宽度，包含左右各 48px 留白。
  static const comfortableWidth = 856.0;

  /// 宽稿外容器宽度，包含左右各 48px 留白。
  static const wideWidth = 1016.0;

  /// 顶栏最小高度。
  static const toolbarHeight = 56.0;

  /// 按钮和输入框圆角。
  static const radius = 6.0;

  /// 讨论表面与浮层圆角。
  static const overlayRadius = 8.0;

  /// 工具、导航及标题的本地无衬线字体。
  static const uiFont = 'Notebook Sans';

  /// 作者正文的本地衬线字体。
  static const serifFont = 'Notebook Serif';

  /// 阿拉伯文离线回退字体。
  static const fallbackFont = 'Noto Arabic';

  /// 工具文字默认 14px/1.6；调用方仅按 DESIGN 角色选尺寸与字重。
  static TextStyle ui({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    double height = 1.6,
    Color color = ink,
    double? letterSpacing,
    List<FontFeature>? fontFeatures,
  }) => TextStyle(
    fontFamily: uiFont,
    fontFamilyFallback: const [fallbackFont],
    fontSize: size,
    fontWeight: weight,
    height: height,
    color: color,
    letterSpacing: letterSpacing,
    fontFeatures: fontFeatures,
  );

  /// 作者正文样式：20px/1.85，不对原文做缩进或归一化。
  static const body = TextStyle(
    fontFamily: serifFont,
    fontFamilyFallback: [uiFont, fallbackFont],
    fontSize: 20,
    height: 1.85,
    color: ink,
  );

  /// 常规章节标题：32px/1.55、600 字重；中文标题不用负字距，避免相邻笔画相撞。
  static final title = ui(size: 32, weight: FontWeight.w600, height: 1.55);

  /// 紧凑章节标题：27px/1.55，保留大字号自然增高。
  static final titleCompact = ui(
    size: 27,
    weight: FontWeight.w600,
    height: 1.55,
  );

  /// 工具输入字体；禁用态独立减弱，不能继承作者正文样式。
  static final input = WidgetStateTextStyle.resolveWith(
    (states) => ui(
      color: states.contains(WidgetState.disabled)
          ? muted.withValues(alpha: 0.5)
          : ink,
    ),
  );

  /// 差异片段仅增加底色和线型，继承父级字体与前景，不改原文。
  static TextStyle diff({
    required bool removed,
    required ColorScheme colors,
  }) => TextStyle(
    backgroundColor: removed ? colors.errorContainer : colors.tertiaryContainer,
    decoration: removed ? TextDecoration.lineThrough : TextDecoration.underline,
  );

  /// 历史出处高亮继承文字角色，以底色和下划线同时标记来源区间。
  static TextStyle sourceHighlight(ColorScheme colors) => TextStyle(
    backgroundColor: colors.secondaryContainer,
    decoration: TextDecoration.underline,
  );
}
