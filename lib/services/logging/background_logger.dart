import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';

/// 后台 isolate 专用文件日志（纯 `dart:io`，无 Flutter 插件依赖）。
///
/// 背景：后台任务 isolate（前台服务 TaskHandler 回调）中 path_provider 的
/// MethodChannel 不可用，无法直接使用 WywLogger（其文件落盘依赖
/// path_provider）。因此主 isolate 在服务启动后通过
/// `FlutterForegroundTask.sendDataToTask` 下发日志文件绝对路径（见
/// `BackgroundDownloadService._sendLogPathToTask`），任务侧收到后落盘；
/// 路径未到达前先缓冲，路径到达后一次性补写，保证不丢日志。
///
/// 写入格式与 `WywLogOutput` 的文件格式风格一致：
/// `[时间] [级别tag] [Tag] 消息`；级别 tag 与 `WywLogPrinter` 相同
/// （i=[i]、w=[!]、e=[×]）。
///
/// 跨 isolate 并发写同一文件：双方都使用 `FileMode.writeOnlyAppend`
/// （POSIX O_APPEND 单次 write 原子），按行追加不会交错损坏。
class BackgroundFileLogger {
  BackgroundFileLogger._();

  static final Lock _lock = Lock();
  static String? _path;
  static final List<String> _pending = [];

  /// 主 isolate 下发日志文件绝对路径。
  static void setPath(String path) {
    if (_path == path) return;
    _path = path;
    if (_pending.isNotEmpty) {
      final buffered = List<String>.of(_pending);
      _pending.clear();
      _writeAll(buffered);
    }
  }

  /// 信息级日志（后台 isolate 的日志只有任务生命周期事件，量极小，一律落盘）。
  static void i(String tag, String message) => _log('[i]', tag, message);

  /// 警告级日志。
  static void w(String tag, String message) => _log('[!]', tag, message);

  /// 错误级日志。
  static void e(String tag, String message) => _log('[×]', tag, message);

  static void _log(String levelTag, String tag, String message) {
    final line = '[${DateTime.now()}] $levelTag $tag $message';
    if (_path == null) {
      _pending.add(line);
    } else {
      _writeAll([line]);
    }
  }

  static void _writeAll(List<String> lines) {
    final path = _path;
    if (path == null) return;
    _lock.synchronized(() async {
      try {
        final file = File(path);
        final dir = file.parent;
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        final buffer = StringBuffer();
        for (final line in lines) {
          buffer
            ..writeln(line)
            ..writeln();
        }
        await file.writeAsString(
          buffer.toString(),
          mode: FileMode.writeOnlyAppend,
        );
      } catch (err) {
        // 静默可接受：后台 isolate 中无法走 WywLogger（平台通道不可用，
        // 再套一层也会失败），退回 debugPrint 保证 adb logcat 至少可见。
        debugPrint('写后台日志到文件失败: $err');
      }
    });
  }
}
