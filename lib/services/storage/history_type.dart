import 'package:hive_ce/hive.dart';

part 'history_type.g.dart';

/// 通用历史记录类型枚举
///
/// - video / novel / comic 走类型化 JS API（强类型进度类）
/// - custom 走自由 K/V，差异由 progress Map 内容承担
///
/// 适配器手写在 history_type.g.dart（绕开 hive_ce_generator 1.11.2
/// 与 analyzer 12 不兼容导致的 enum 解析失败）。
enum HistoryType {
  video,
  novel,
  comic,
  custom;

  String get value => switch (this) {
        HistoryType.video => 'video',
        HistoryType.novel => 'novel',
        HistoryType.comic => 'comic',
        HistoryType.custom => 'custom',
      };

  static HistoryType fromValue(String v) => switch (v) {
        'video' => HistoryType.video,
        'novel' => HistoryType.novel,
        'comic' => HistoryType.comic,
        _ => HistoryType.custom,
      };
}
