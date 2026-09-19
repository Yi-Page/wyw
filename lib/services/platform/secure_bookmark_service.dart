import 'dart:io';

import 'package:macos_secure_bookmarks/macos_secure_bookmarks.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/services/storage/storage.dart';

/// Keeps the user-picked download directory writable across app restarts on
/// sandboxed macOS via security-scoped bookmarks. No-op on other platforms.
class SecureBookmarkService {
  SecureBookmarkService._();

  static final _bookmarks = SecureBookmarks();
  static String _accessedPath = '';

  /// Persist a bookmark for [path] just picked by the user. Returns false if
  /// the bookmark cannot be created, in which case the path must not be used.
  static Future<bool> persist(String path) async {
    if (!Platform.isMacOS) return true;
    try {
      final bookmark = await _bookmarks.bookmark(Directory(path));
      await GStorage.putSetting(
          SettingsKeys.downloadDirectoryBookmark, bookmark);
      // The picker grant already covers this session.
      _accessedPath = path;
      return true;
    } catch (e, s) {
      WywLogger().e('${LogTag.platform} 创建 macOS 安全书签失败 path=$path',
          error: e, stackTrace: s);
      return false;
    }
  }

  /// Restore write access to the custom directory [path]. Returns the usable
  /// path (which may differ from [path] if the directory was moved), or null
  /// when access cannot be restored.
  static Future<String?> restore(String path) async {
    if (!Platform.isMacOS) return path;
    if (_accessedPath == path) return path;
    final String bookmark =
        GStorage.getSetting(SettingsKeys.downloadDirectoryBookmark);
    if (bookmark.isEmpty) return null;
    try {
      final entity = await _bookmarks.resolveBookmark(bookmark);
      await _bookmarks.startAccessingSecurityScopedResource(entity);
      _accessedPath = entity.path;
      return entity.path;
    } catch (e, s) {
      WywLogger().e('${LogTag.platform} 恢复 macOS 安全书签访问权限失败 path=$path',
          error: e, stackTrace: s);
      return null;
    }
  }

  static Future<void> clear() async {
    if (!Platform.isMacOS) return;
    await GStorage.putSetting(SettingsKeys.downloadDirectoryBookmark, '');
    _accessedPath = '';
  }
}
