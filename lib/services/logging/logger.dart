// ignore_for_file: avoid_print

/// wyw 日志基础设施。使用规范见 `docs/logging.md`（消息格式 / 级别语义 /
/// 静默吞异常治理 / 全局兜底）；模块 Tag 常量见 `log_tags.dart`。
///
/// 本文件内的裸 `print` 是全项目唯一被允许的位置：日志输出自身失败时只能
/// 走控制台兜底，避免递归写日志。
library;

import 'dart:async';
import 'dart:io';

import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:synchronized/synchronized.dart';

const Symbol _forceLogKey = #_forceLog;

class WywLogFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    final forceLog = Zone.current[_forceLogKey] as bool? ?? false;
    if (forceLog) {
      return true;
    }
    return event.level.index >= Logger.level.index;
  }
}

class WywLogPrinter extends PrettyPrinter {
  WywLogPrinter()
      : super(
          methodCount: 0,
          errorMethodCount: 8,
          lineLength: 120,
          colors: true,
          // Disable emojis for better compatibility
          printEmojis: false,
          dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
        );

  @override
  List<String> log(LogEvent event) {
    // For trace, debug, info - never show stack trace
    if (event.level == Level.trace ||
        event.level == Level.debug ||
        event.level == Level.info) {
      final messageStr = stringifyMessage(event.message);
      final time = getTime(event.time);
      final prefix = _getPrefix(event.level);
      final levelName = _getLevelName(event.level);

      return [
        '$prefix $time $levelName $messageStr',
      ];
    }

    // For warning, error, fatal - use default behavior which shows stack if provided
    return super.log(event);
  }

  /// Colored prefix for log level
  String _getPrefix(Level level) {
    if (!colors) return _getLevelTag(level);

    const reset = '\x1B[0m';
    String colorCode;

    switch (level) {
      case Level.trace:
        colorCode = '\x1B[90m'; // Bright Black
      case Level.debug:
        colorCode = '\x1B[36m'; // Cyan
      case Level.info:
        colorCode = '\x1B[32m'; // Green
      case Level.warning:
        colorCode = '\x1B[33m'; // Yellow
      case Level.error:
        colorCode = '\x1B[31m'; // Red
      case Level.fatal:
        colorCode = '\x1B[35m'; // Magenta
      default:
        colorCode = '';
    }

    return '$colorCode${_getLevelTag(level)}$reset';
  }

  /// Tag symbol for log level
  String _getLevelTag(Level level) {
    switch (level) {
      case Level.trace:
        return '[·]';
      case Level.debug:
        return '[*]';
      case Level.info:
        return '[i]';
      case Level.warning:
        return '[!]';
      case Level.error:
        return '[×]';
      case Level.fatal:
        return '[‼]';
      default:
        return '[-]';
    }
  }

  String _getLevelName(Level level) {
    return level.name.toUpperCase().padRight(7);
  }
}

class WywLogOutput extends LogOutput {
  static final Lock _logLock = Lock();
  static String? _logFilePath;

  static Future<String> _getLogFilePath() async {
    if (_logFilePath != null) return _logFilePath!;

    final dir = (await getApplicationSupportDirectory()).path;
    final logDir = p.join(dir, 'logs');
    final directory = Directory(logDir);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    _logFilePath = p.join(logDir, 'wyw_logs.log');
    return _logFilePath!;
  }

  @override
  void output(OutputEvent event) {
    // 控制台兜底输出全部级别；落盘见 _writeToFile（仅 w/e/f 或 forceLog）。
    for (var line in event.lines) {
      print(line);
    }

    // Write to file if: warning/error/fatal OR forceLog is enabled
    final forceLog = Zone.current[_forceLogKey] as bool? ?? false;
    if (event.level.index >= Level.warning.index || forceLog) {
      _writeToFile(event);
    }
  }

  void _writeToFile(OutputEvent event) {
    _logLock.synchronized(() async {
      try {
        final filePath = await _getLogFilePath();
        final file = File(filePath);

        final timestamp = DateTime.now().toString();

        final buffer = StringBuffer();
        buffer.writeln('[$timestamp]');
        for (var line in event.lines) {
          final cleanLine = _removeAnsiCodes(line);
          buffer.writeln(cleanLine);
        }
        buffer.writeln();

        await file.writeAsString(
          buffer.toString(),
          mode: FileMode.writeOnlyAppend,
        );
      } catch (e) {
        // 全项目唯一允许的裸 print（规范见 docs/logging.md）：
        // 写日志失败时不能再走 WywLogger，否则会递归。
        print('写日志到文件失败: $e');
      }
    });
  }

  /// Remove ANSI escape codes from string to ensure clean log files
  String _removeAnsiCodes(String text) {
    return text.replaceAll(RegExp(r'\x1B\[[0-9;]*m'), '');
  }
}

class WywLogger {
  WywLogger._internal() {
    _logger = Logger(
      filter: WywLogFilter(),
      printer: WywLogPrinter(),
      output: WywLogOutput(),
    );
  }

  static final WywLogger _instance = WywLogger._internal();
  factory WywLogger() {
    return _instance;
  }

  late final Logger _logger;
  void _log(void Function() logFn, bool forceLog) {
    if (forceLog) {
      runZoned(logFn, zoneValues: {_forceLogKey: true});
    } else {
      logFn();
    }
  }

  /// t：方法级追踪（生产禁用，仅开发诊断；不落盘）。
  void t(dynamic message,
      {Object? error, StackTrace? stackTrace, bool forceLog = false}) {
    _log(() => _logger.t(message, error: error, stackTrace: stackTrace),
        forceLog);
  }

  /// d：调试信息 / 可忽略的 best-effort 失败（不落盘，仅控制台）。
  void d(dynamic message,
      {Object? error, StackTrace? stackTrace, bool forceLog = false}) {
    _log(() => _logger.d(message, error: error, stackTrace: stackTrace),
        forceLog);
  }

  /// i：正常运行的重要节点与关键决策（不落盘，仅控制台）。
  void i(dynamic message,
      {Object? error, StackTrace? stackTrace, bool forceLog = false}) {
    _log(() => _logger.i(message, error: error, stackTrace: stackTrace),
        forceLog);
  }

  /// w：预期内失败但已兜底/降级/重试，功能未损（落盘）。
  void w(dynamic message,
      {Object? error, StackTrace? stackTrace, bool forceLog = false}) {
    _log(() => _logger.w(message, error: error, stackTrace: stackTrace),
        forceLog);
  }

  /// e：操作失败，功能受损、用户可感知（落盘）。
  void e(dynamic message,
      {Object? error, StackTrace? stackTrace, bool forceLog = false}) {
    _log(() => _logger.e(message, error: error, stackTrace: stackTrace),
        forceLog);
  }

  /// f：不可恢复 / 全局兜底（未捕获异常、框架异常、数据损坏）（落盘）。
  void f(dynamic message,
      {Object? error, StackTrace? stackTrace, bool forceLog = false}) {
    _log(() => _logger.f(message, error: error, stackTrace: stackTrace),
        forceLog);
  }
}

Future<File> getLogsPath() async {
  final dir = (await getApplicationSupportDirectory()).path;
  final logDir = p.join(dir, 'logs');
  final filename = p.join(logDir, 'wyw_logs.log');

  final directory = Directory(logDir);
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }

  final file = File(filename);
  if (!await file.exists()) {
    await WywLogOutput._logLock.synchronized(() async {
      if (!await file.exists()) {
        await file.create();
      }
    });
  }
  return file;
}

Future<bool> clearLogs() async {
  try {
    final file = await getLogsPath();
    await WywLogOutput._logLock.synchronized(() async {
      await file.writeAsString('');
    });
    return true;
  } catch (e) {
    // 全项目唯一允许裸 print 的位置之一（见 docs/logging.md）。
    print('清空日志文件失败: $e');
    return false;
  }
}
