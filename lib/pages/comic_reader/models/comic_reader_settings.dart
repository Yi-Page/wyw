import 'package:wyw/services/storage/storage.dart';

/// 阅读器设置读写封装。
///
/// 采用字符串键 + 默认值映射（与 venera 的 `appdata.settings` 对齐），
/// 实际持久化复用主项目的 GStorage（Hive `setting` box）。
class ComicReaderSettings {
  ComicReaderSettings._();

  /// 阅读器设置默认值（与 venera 保持一致）。
  static final Map<String, dynamic> _defaults = {
    'readerMode': 'galleryLeftToRight',
    'readerScreenPicNumberForPortrait': 1,
    'readerScreenPicNumberForLandscape': 1,
    'showSingleImageOnFirstPage': false,
    'enableTapToTurnPages': true,
    'reverseTapToTurnPages': false,
    'enablePageAnimation': true,
    'enableDoubleTapToZoom': true,
    'enableLongPressToZoom': true,
    'longPressZoomPosition': 'press',
    'limitImageWidth': true,
    'enableTurnPageByVolumeKey': true,
    'enableClockAndBatteryInfoInReader': true,
    'showSystemStatusBar': false,
    'showPageNumberInReader': true,
    'preloadImageCount': 4,
    'autoPageTurningInterval': 5,
    'readerScrollSpeed': 1.0,
    'quickCollectImage': 'No',
    'continuousChapterSwitchThreshold': 80.0,
  };

  /// 读取设置；未持久化时返回默认值。
  static dynamic get(String key) {
    final value = GStorage.getSettingByName(key);
    if (value != null) {
      return value;
    }
    return _defaults[key];
  }

  /// 读取类型化设置；类型不匹配或未持久化时返回默认值。
  static T getT<T>(String key) {
    final value = get(key);
    if (value is T) {
      return value;
    }
    return _defaults[key] as T;
  }

  static int getInt(String key) => getT<int>(key);

  static bool getBool(String key) => getT<bool>(key);

  static String getString(String key) => getT<String>(key);

  static double getDouble(String key) => getT<double>(key);

  /// 写入设置。
  static Future<void> set(String key, dynamic value) =>
      GStorage.putSettingByName(key, value);

  /// 恢复默认设置：删除全部已持久化的值，使 [get] 回落到 [_defaults]。
  static Future<void> resetAll() async {
    for (final key in _defaults.keys) {
      await GStorage.deleteSettingByName(key);
    }
  }
}
