import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_qjs/flutter_qjs.dart';

import 'js_extends/js_bridge.dart';

/// JS 引擎抽象基类：封装「测试台/正式」两份运行时共用的初始化逻辑。
///
/// **初始环境**（与 [init] 中顺序保持一致）：
///   1. `sendMessage` 桥（指向 [handleMessage]）
///   2. `assets/js/init.js`（公共 API 库：Convert / Network / log / http / console / UI / setTimeout 等）
///
/// 子类负责：
///   - 选择是否实现 `runTest` / `runScript` 等业务入口
///   - 重写 [handleMessage] 以扩展消息处理（如捕获 `__asyncResolve`、收集 log）
///
/// **不变量**：每个实例持有独立的 [FlutterQjs]，互不污染全局对象。
abstract class BaseJsEngine with JSEngineCommonApi {
  FlutterQjs? _engine;
  bool _initialized = false;

  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;
    _engine = FlutterQjs();
    _engine!.dispatch();

    // 1. sendMessage 桥
    final setGlobal = _engine!.evaluate(
      '(k, v) => { this[k] = v; }',
    ) as JSInvokable;
    setGlobal(['sendMessage', _bridge]);
    setGlobal.free();

    // 2. 加载 init.js（公共 API 库：Convert / Network / log / http / console / UI / setTimeout 等）
    final buffer = await rootBundle.load('assets/js/init.js');
    _engine!.evaluate(
      utf8.decode(buffer.buffer.asUint8List()),
      name: '<init>',
    );

    _initialized = true;
  }

  /// 暴露给 JS 的 `sendMessage` 全局函数。
  /// 必须是稳定引用，因此绑定到实例方法而不是每次 new 闭包。
  Object? _bridge(dynamic msg) => handleMessage(msg);

  /// 子类可重写：处理来自 JS 的消息。
  /// 默认实现：委托给 [JSEngineCommonApi.handleCommonMessage]（html/convert/log 等）。
  @protected
  Object? handleMessage(dynamic msg) => handleCommonMessage(msg);

  /// 通用 JS 执行入口。
  /// 返回值由 flutter_qjs 序列化（基本类型 / Map / List / null）。
  Object? evaluate(String code, {String? name}) =>
      _engine!.evaluate(code, name: name);

  void dispose() {
    disposeCommon();
    _engine?.close();
    _engine?.port.close();
    _engine = null;
    _initialized = false;
  }
}
