import 'dart:convert';

import 'package:wyw/js/base_js_engine.dart';

/// JS 实体：封装一个 JS 类实例的加载、调用、卸载操作。
///
/// **核心概念**：
///   - `entityPath` = JS 全局对象的路径
///   - `entityName` = 实例名（如 `greeting`）
///   - JS 实例访问路径为 [entityFullPath]（点号语法）
///
/// **生命周期**：
///   1. `JsEntity.register()` — 执行 JS 源码并创建实例挂载到全局
///   2. `invoke()` — 调用实例方法，支持 async/Promise 自动等待
///   3. `unload()` — 从 JS 全局注册表移除实例
///   4. `reload()` — 热重载：先 unload 再重新 register
///
/// **使用示例**：
/// ```dart
/// final entity = await JsEntity.register(
///   name: 'greeting',
///   className: 'Greeting',
///   entityName: 'greeting',
///   entityPath: '__plugins__',
///   content: 'class Greeting { greet(n) { return "Hello, " + n; } }',
///   engine: engine,
/// );
///
/// final result = await entity.invoke('greet', ['World']);
/// // result = 'Hello, World!'
/// ```
class JsEntity {
  /// JS 类名（PascalCase），用于错误信息和调试。
  final String className;

  /// JS 全局对象路径
  final String entityPath;

  /// 用于访问 `__plugins__.entityName`。
  final String entityName;

  /// 承载此插件的 JS 引擎实例。
  final BaseJsEngine engine;

  /// 插件 JS 源码内容（用于热重载）。
  final String content;

  /// JS 实例的完整访问路径，用于调试输出。
  /// 格式：`__plugins__.greeting`
  String get entityFullPath => '$entityPath.$entityName';

  /// 检查插件实例是否仍存在于 JS 引擎中。
  ///
  /// 通过在 JS 引擎中执行 `__plugins__.greeting !== undefined` 判断。
  bool get isLoaded {
    final result = engine.evaluate(
      '$entityPath.$entityName !== undefined',
      name: '<plugin-isLoaded:$entityFullPath>',
    );
    return result == true;
  }

  JsEntity({
    required this.className,
    required this.entityPath,
    required this.entityName,
    required this.engine,
    required this.content,
  });

  /// 注册插件：执行 JS 源码并创建实例挂载到 全局对象。
  ///
  /// **执行流程**：
  ///   1. 将 [content] 包裹在 IIFE 中执行（类声明留在函数作用域）
  ///   2. 检查类是否存在，不存在则抛错
  ///   3. 创建 `new className()` 实例并挂载到 `entityPath.entityName`
  ///
  /// [name] — 插件名，用于错误信息和日志
  /// [className] — JS 类名（PascalCase），用于实例化
  /// [entityName] — 插件实例名，用于挂载路径
  /// [entityPath] — 全局对象路径
  /// [content] — JS 源码内容
  /// [engine] — JS 引擎实例
  Future<void> register() async {
    final wrapped = '''
      (function() {
        $content
        if (typeof $className !== 'function') {
          throw new Error('Class $className not found in content');
        }
        __plugins__.$entityName = new $className();
      })()
    ''';

    engine.evaluate(wrapped, name: '<register:$entityPath.$entityName>');
  }

  /// 调用插件实例的方法。
  ///
  /// **Promise 处理**：
  ///   检测返回值是否有 `.then` 方法，若有则等待 Promise resolve。
  ///   async 方法会自动等待，无需调用方处理。
  ///
  /// [method] — 方法名
  /// [args] — 参数列表（JSON 序列化后传递）
  ///
  /// 返回值会尝试 JSON.parse 还原。
  /// 抛错时抛出 [EntityInvokeException]。
  Future<dynamic> invoke(
    String method, [
    List<dynamic> args = const [],
  ]) async {
    final argsLiteral = args.isEmpty ? '[]' : jsonEncode(args);

    final code = '''
      (function() {
        try {
          var __p = $entityPath.$entityName;
          if (!__p) {
            return JSON.stringify({ ok: false, error: 'Plugin not loaded: $entityName' });
          }
          var __m = __p['$method'];
          if (typeof __m !== 'function') {
            return JSON.stringify({ ok: false, error: 'Method not found: $className.$method' });
          }
          var __args = $argsLiteral;
          var __r = __m.apply(__p, __args);
          if (__r && typeof __r.then === 'function') {
            return new Promise(function(resolve) {
              __r.then(function(val) {
                resolve(JSON.stringify({ ok: true, value: JSON.stringify(val) }));
              }).catch(function(e) {
                resolve(JSON.stringify({ ok: false, error: String(e && e.message || e) }));
              });
            });
          }
          return JSON.stringify({ ok: true, value: JSON.stringify(__r) });
        } catch (e) {
          return JSON.stringify({ ok: false, error: String(e && e.message || e) });
        } 
      })()
    ''';

    final raw =
        engine.evaluate(code, name: '<plugin-invoke:$className.$method>');
    // async 插件方法返回 JS Promise，QuickJS 同步 evaluate 会返回 Dart Future 包装
    // 必须 await 让 Promise resolve，否则 rawStr 会是 "Instance of 'Future<dynamic>'"
    final actual = raw is Future ? await raw : raw;
    final rawStr = actual?.toString() ?? '';
    final outer = json.decode(rawStr) as Map<String, dynamic>;

    if (outer['ok'] == true) {
      final value = outer['value'];
      if (value == null) return null;
      if (value == 'null') return null;
      return json.decode(value as String);
    } else {
      throw EntityInvokeException(
        className: className,
        entityPath: entityPath,
        entityName: entityName,
        method: method,
        message: outer['error']?.toString() ?? 'Unknown error',
      );
    }
  }

  /// 热重载：从 [content] 重新执行，完成实例重建。
  ///
  /// 先调用 [unload] 移除旧实例，再重新 [register]。
  /// 适用于修改 JS 源码后无需重启应用即可生效的场景。
  void reload({String? content}) async {
    content = content ?? this.content;
    unload();
    await register();
  }

  /// 卸载插件：从 JS 全局注册表删除实例。
  ///
  /// 执行 `delete __plugins__.entityName`。
  /// 调用后 [isLoaded] 会返回 `false`，但 [JsEntity] 对象本身仍可用。
  void unload() {
    engine.evaluate('delete $entityPath.$entityName;');
  }
}

/// 插件方法调用异常
class EntityInvokeException implements Exception {
  /// 插件类名
  final String className;

  /// 全局对象路径
  final String entityPath;

  /// 插件实例名
  final String entityName;

  /// 调用的方法名
  final String method;

  /// 异常信息
  final String message;

  EntityInvokeException({
    required this.className,
    required this.entityPath,
    required this.entityName,
    required this.method,
    required this.message,
  });

  @override
  String toString() =>
      'EntityInvokeException($className.$method): $entityPath.$entityName\n$message';
}
