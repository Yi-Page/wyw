// ignore_for_file: library_private_types_in_public_api

import 'package:mobx/mobx.dart';
import 'package:wyw/js/script_engine.dart';

part 'js_dev_controller.g.dart';

/// JS 脚本测试台控制器。
///
/// 路由级 Store 单例（见 [jsDevModule] 的 `provide`），持有脚本引擎、
/// 运行日志与运行状态；页面只负责编辑输入与渲染日志。
class JsDevController = _JsDevController with _$JsDevController;

abstract class _JsDevController with Store {
  late final ScriptEngine engine;

  @observable
  ObservableList<JsLogLine> lines = ObservableList.of([]);

  @observable
  bool running = false;

  _JsDevController() {
    engine = ScriptEngine();
    engine.init();
  }

  Future<void> run(String script) async {
    if (running) return;
    running = true;
    try {
      final result = await engine.runTest(script);
      appendResult(result);
    } catch (e, s) {
      lines.add(JsLogLine.error('Run failed: $e\n$s'));
    } finally {
      running = false;
    }
  }

  void appendResult(RunResult r) {
    lines.add(JsLogLine.header('- run -'));
    for (final log in r.logs) {
      lines.add(JsLogLine.fromLog(log));
    }
    if (r.isSuccess) {
      if (r.returnValue != null) {
        lines.add(JsLogLine.returnValue(r.returnValue));
      }
    } else {
      lines.add(JsLogLine.error(r.error?.toString() ?? 'unknown error'));
      if (r.stackTrace != null && r.stackTrace!.isNotEmpty) {
        lines.add(JsLogLine.stack(r.stackTrace!));
      }
    }
  }

  void clear() => lines.clear();
}

enum JsLogKind { info, warn, error, header, returnValue, stack }

/// 一条测试台日志记录（不可变值对象）。
class JsLogLine {
  JsLogLine(this.kind, this.text, {this.timestamp});

  factory JsLogLine.fromLog(LogEntry e) {
    final kind = switch (e.level) {
      LogLevel.info => JsLogKind.info,
      LogLevel.warn => JsLogKind.warn,
      LogLevel.error => JsLogKind.error,
    };
    return JsLogLine(kind, e.message, timestamp: DateTime.now());
  }

  factory JsLogLine.header(String s) => JsLogLine(JsLogKind.header, s);
  factory JsLogLine.error(String s) => JsLogLine(JsLogKind.error, s);
  factory JsLogLine.stack(String s) => JsLogLine(JsLogKind.stack, s);
  factory JsLogLine.returnValue(dynamic v) =>
      JsLogLine(JsLogKind.returnValue, v);

  final JsLogKind kind;
  final dynamic text;
  final DateTime? timestamp;
}
