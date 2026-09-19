import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:wyw/js/base_js_engine.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';

/// 脚本测试台引擎。
///
/// 继承 [BaseJsEngine] 复用「init.js + log + http + sendMessage 桥」初始化，
/// 但额外实现 [runTest]：捕获 log 到缓冲区、桥接 Promise/async 异步结果。
///
/// 与 [ProductionScriptEngine] 各自持有独立 FlutterQjs 实例，
/// 测试脚本的全局变量不会污染正式环境。
class ScriptEngine extends BaseJsEngine {
  factory ScriptEngine() => _instance ??= ScriptEngine._();
  static ScriptEngine? _instance;
  ScriptEngine._();

  /// 测试 / 子类化入口：返回一个新的 ScriptEngine 实例，绕开单例
  @visibleForTesting
  ScriptEngine.testable();

  /// 当前 runTest 激活的日志缓冲；runTest 之外为 null
  List<LogEntry>? _activeBuffer;

  /// 等待异步脚本完成时的 Completer；非空表示有待完成的 Promise
  Completer<RunResult>? _pendingAsyncResult;

  @override
  Object? handleMessage(dynamic msg) {
    if (msg is Map) {
      // 检测异步脚本的 Promise 已 resolve
      if (_pendingAsyncResult != null && msg['method'] == '__asyncResolve') {
        final inner =
            json.decode(msg['value'] as String) as Map<String, dynamic>;
        _pendingAsyncResult!
            .complete(_handleAsyncResolve(inner, _activeBuffer ?? []));
        _pendingAsyncResult = null;
        return null;
      }
      // runTest 进行中时，额外捕获 log() 到活动缓冲
      if (_activeBuffer != null && msg['method'] == 'log') {
        final level = _parseLevel(msg['level']);
        final message = msg['message']?.toString() ?? '';
        _activeBuffer!.add(LogEntry(level: level, message: message));
      }
    }
    // 始终委托给基类（JSEngineCommonApi.handleCommonMessage：html/convert/等）
    return super.handleMessage(msg);
  }

  Future<RunResult> runTest(String userScript) async {
    if (!isInitialized) {
      WywLogger().e('${LogTag.js} 测试台未初始化就调用 runTest');
      throw StateError('ScriptEngine not initialized; call init() first.');
    }

    final logs = <LogEntry>[];
    final prevBuffer = _activeBuffer;
    _activeBuffer = logs;

    try {
      // 用户脚本必须定义 `class Test { run() { ... } }`。
      // 整个脚本包在 IIFE 内：
      //   - `class Test` 留在 IIFE 函数作用域，不污染全局
      //   - 每次 `runTest` 都 `new Test()` 创建全新实例，方法间无状态残留
      //   - 同步/异步/异常三种结果统一序列化为 JSON
      // 注意：若用户脚本有语法错误，flutter_qjs 在解析阶段就抛 JSException
      // （不进 IIFE 的 try-catch），需在 Dart 侧 catch 处理。
      final raw = evaluate('''
        (function() {
          try {
            $userScript

            if (typeof Test !== 'function') {
              return JSON.stringify({
                ok: false,
                error: 'Test class is not defined. Expected: class Test { run() { /* ... */ } }',
                stack: ''
              });
            }

            const __instance = new Test();
            var r = __instance.run();

            if (r && typeof r.then === 'function') {
              // 异步：等待 Promise 完成后再返回
              r.then(function(val) {
                sendMessage({ method: '__asyncResolve', value: JSON.stringify({ ok: true, value: JSON.stringify(val) }) });
              }).catch(function(e) {
                sendMessage({ method: '__asyncResolve', value: JSON.stringify({ ok: false, error: String(e && e.message || e), stack: String(e && e.stack || '') }) });
              });
              return JSON.stringify({ __async: true });
            }
            return JSON.stringify({ ok: true, value: JSON.stringify(r) });
          } catch (e) {
            return JSON.stringify({
              ok: false,
              error: String(e && e.message || e),
              stack: String(e && e.stack || '')
            });
          }
        })()
      ''', name: '<test>');

      final rawStr = raw?.toString() ?? '';
      final outer = json.decode(rawStr) as Map<String, dynamic>;

      if (outer['__async'] == true) {
        // 异步：等待 __asyncResolve 消息带回结果
        _pendingAsyncResult = Completer<RunResult>();

        // 设置超时，避免 Promise 永远不 resolve。
        // 必须大于 WebView 取页面的默认超时（50s），否则测试台会先于
        // webview 的真实结果（成功/明确错误）掐断，只剩笼统的 Async timeout。
        Future.delayed(const Duration(seconds: 90), () {
          if (!_pendingAsyncResult!.isCompleted) {
            _pendingAsyncResult!.complete(RunResult(
              returnValue: null,
              logs: logs,
              error: 'Async timeout after 90s',
              stackTrace: null,
            ));
            _pendingAsyncResult = null;
          }
        });

        return await _pendingAsyncResult!.future;
      }
      if (outer['ok'] == true) {
        final valueJson = outer['value'] as String? ?? 'null';
        final parsed = valueJson == 'null' ? null : json.decode(valueJson);
        return RunResult(returnValue: parsed, logs: logs);
      } else {
        return RunResult(
          returnValue: null,
          logs: logs,
          error: outer['error']?.toString(),
          stackTrace: outer['stack']?.toString(),
        );
      }
    } catch (e) {
      // 捕获 flutter_qjs 抛出的 JSException（语法错误、解析错误等）
      // IIFE 内部的运行期错误已被 IIFE 自己的 try-catch 捕获并转 JSON
      final errorStr = e.toString();
      return RunResult(
        returnValue: null,
        logs: logs,
        error: errorStr,
        stackTrace: errorStr,
      );
    } finally {
      _activeBuffer = prevBuffer;
    }
  }

  RunResult _handleAsyncResolve(
      Map<String, dynamic> outer, List<LogEntry> logs) {
    if (outer['ok'] == true) {
      final valueJson = outer['value'] as String? ?? 'null';
      final parsed = valueJson == 'null' ? null : json.decode(valueJson);
      return RunResult(returnValue: parsed, logs: logs);
    } else {
      return RunResult(
        returnValue: null,
        logs: logs,
        error: outer['error']?.toString(),
        stackTrace: outer['stack']?.toString(),
      );
    }
  }

  LogLevel _parseLevel(dynamic raw) {
    final s = raw?.toString();
    switch (s) {
      case 'warn':
        return LogLevel.warn;
      case 'error':
        return LogLevel.error;
      default:
        return LogLevel.info;
    }
  }

  @override
  void dispose() {
    _instance = null;
    super.dispose();
  }
}

class RunResult {
  final dynamic returnValue;
  final List<LogEntry> logs;
  final Object? error;
  final String? stackTrace;

  const RunResult({
    required this.returnValue,
    required this.logs,
    this.error,
    this.stackTrace,
  });

  bool get isSuccess => error == null;
}

enum LogLevel { info, warn, error }

class LogEntry {
  final LogLevel level;
  final String message;

  const LogEntry({required this.level, required this.message});
}
