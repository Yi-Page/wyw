import 'package:flutter/material.dart';

/// JS 控制台（dev 工具）配色。
///
/// 终端语义豁免：控制台固定深色底、编辑器固定浅色底，不随应用主题切换
/// （与 IDE 终端一致）。定义于本白名单文件由
/// test/no_hardcoded_colors_test.dart 允许；规范见
/// docs/ui-routing-design-spec.md 第 8C 节。
abstract final class JsConsoleColors {
  /// 代码编辑区底色（浅色纸面，配 monospace 字体）
  static const Color editorBg = Color(0xFFF7F7F7);

  /// 控制台底
  static const Color consoleBg = Colors.black;

  /// 控制台空态/次要文字
  static const Color consoleText = Colors.white54;

  /// 时间戳等弱化文字（配合 withValues(alpha:) 使用）
  static const Color faintText = Colors.white;

  static const Color info = Color(0xFF8BC34A);
  static const Color warn = Color(0xFFFFB74D);
  static const Color error = Color(0xFFEF5350);
  static const Color returnValue = Color(0xFF4FC3F7);
  static const Color header = Colors.white70;
  static const Color stack = Color(0xFFFF8A80);
}
