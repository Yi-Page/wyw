import 'package:flutter/material.dart';
import 'package:wyw/services/storage/storage.dart';

/// 阅读画布 palette：`novelBackground` 设置的支撑数据，与主题刻意无关
/// （阅读底色是"内容"，浅色主题下也可用夜间画布，同微信读书）。
/// 定义于本白名单文件由 test/no_hardcoded_colors_test.dart 允许。
abstract final class NovelCanvasPalette {
  /// 米黄纸底 / 纸上墨色
  static const Color paperBg = Color(0xFFFDF6E3);
  static const Color paperInk = Color(0xFF333333);

  /// 夜间底 / 夜间字
  static const Color darkBg = Color(0xFF121212);
  static const Color darkInk = Color(0xFFCCCCCC);

  /// 画布上的次要文字（页脚等，两种底色通用）
  static const Color inkSecondary = Colors.grey;

  /// 按设置值解析 (背景色, 正文字色)；未知值回落纸色。
  static (Color bg, Color ink) resolve(String background) =>
      background == 'dark' ? (darkBg, darkInk) : (paperBg, paperInk);
}

/// 小说阅读器设置读写封装。
///
/// 与漫画的 [ComicReaderSettings] 对齐，实际持久化复用主项目的 GStorage
/// （Hive `setting` box）。
class NovelReaderSettings {
  NovelReaderSettings._();

  /// 小说阅读器设置默认值。
  static final Map<String, dynamic> _defaults = {
    'novelFontSize': 18.0,
    'novelLineHeight': 1.6,
    'novelBackground': 'light',
    'novelMode': 'scroll',
  };

  /// 读取设置；未持久化时返回默认值。
  static dynamic get(String key) {
    final value = GStorage.getSettingByName(key);
    if (value != null) {
      return value;
    }
    return _defaults[key];
  }

  static T getT<T>(String key) {
    final value = get(key);
    if (value is T) {
      return value;
    }
    return _defaults[key] as T;
  }

  static double getDouble(String key) => getT<double>(key);

  static Future<void> set(String key, dynamic value) =>
      GStorage.putSettingByName(key, value);
}
