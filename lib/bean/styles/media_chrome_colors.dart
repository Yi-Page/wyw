import 'package:flutter/material.dart';

/// 媒体铬层最小固定色集（叠加在任意视频帧/漫画图/照片上的控件）。
///
/// 这部分颜色刻意脱离 Material ColorScheme：背景内容不可知，白字 + 深色
/// scrim 是保证对比度的功能需求（M3 对媒体应用的官方立场）。除此之外的
/// UI 一律走 `Theme.of(context).colorScheme`（规范见
/// docs/ui-routing-design-spec.md 第 8 节；test/no_hardcoded_colors_test.dart 强制）。
///
/// 主题色仍可介入的"强调位"（进度条活跃段、高亮按钮、状态指示）直接用
/// `colorScheme.primary` / `error`，不要加进这里。
abstract final class MediaChromeColors {
  /// 图标 / 主文字
  static const Color foreground = Colors.white;

  /// 次要文字
  static const Color foregroundDim = Colors.white70;

  /// 弱化文字
  static const Color foregroundFaint = Colors.white54;

  /// 禁用态文字/图标（图片查看器翻页箭头等）
  static const Color foregroundDisabled = Colors.white38;

  /// 视频面底 / 图片查看器底（加载中、无内容的画布）
  static const Color surface = Colors.black;

  /// 遮罩基色：配合 `withValues(alpha:)` 做半透明 scrim。alpha 保持行内——
  /// 各遮罩的透明度（0.18~0.5）是独立调优值，不在此抽象
  static const Color scrim = Colors.black;

  /// 面板投影 / 渐变端点
  static const Color barrier = Colors.black45;

  /// 播放器字幕样式：媒体样式（粉字白描边是刻意选择，与主题无关），
  /// 收拢于此便于未来做成用户设置。（Paint 级联无法参与 const，故用 final）
  static final TextStyle subtitleStyle = TextStyle(
    color: Colors.pink,
    fontSize: 48.0,
    background: Paint()..color = Colors.transparent,
    decoration: TextDecoration.none,
    fontWeight: FontWeight.bold,
    shadows: [
      Shadow(
        offset: Offset(1.0, 1.0),
        blurRadius: 3.0,
        color: Color.fromARGB(255, 255, 255, 255),
      ),
      Shadow(
        offset: Offset(-1.0, -1.0),
        blurRadius: 3.0,
        color: Color.fromARGB(125, 255, 255, 255),
      ),
    ],
  );
}
