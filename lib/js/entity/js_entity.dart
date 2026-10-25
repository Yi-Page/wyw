import 'dart:convert';

import 'package:wyw/js/base_js_engine.dart';

/// JS 实体：**引擎里的一份代码 + 由它创建的一个实例**（挂在全局注册表的某个槽位）。
///
/// 它是**插件的组成部分，但不必是「插件本身」的实例** —— 谁都可以用它包一份 JS 代码：
/// 插件类、基类、测试台里的任意类。所以这里只放**与业务语义无关**的机制：
/// 建实例 / 调方法 / 探活 / 卸载，以及类名与槽位这两个独立身份。
/// 「这个插件有没有实现某个能力」属于插件语义，在 `Plugin.implementsMethod` 上。
///
/// 成员就这些：**JS 类名**、实例**挂在哪**（`entityPath` + `entityName`）、
/// **代码**、承载它的**引擎**。
///
/// **`className` 与 `entityName` 刻意是两个独立字段**：命名链现在要求它们逐字符相同
/// （`PluginSourceRule` 校验类名 = 插件名，槽位也用插件名），但那是**插件侧的约束**，
/// 不是这个类的假设 —— 它描述的是两件不同的事：
///   - [className]：`new` 谁；
///   - [entityName]：实例挂到全局注册表的哪个槽位、之后按什么名字寻址。
/// 将来若要把同一个类挂到别的槽位（测试台、多实例、别名），这里不必改。
///
/// ## 实例是怎么"持有"的
///
/// QuickJS 的实例活在引擎堆里，`evaluate` 会把对象**深拷贝成 Dart `Map`**
/// （flutter_qjs 的 `_jsToDart` 只对函数 / Promise 返回可长期持有的 `JSRef`），
/// 所以 Dart 侧唯一能长期持有实例的办法就是记住它在全局的**挂载路径**
/// `entityPath.entityName`（见 [entityFullPath]），探活用 `path !== undefined`。
///
/// ## 生命周期
///
///   1. `register()` —— 执行源码，建实例挂到 [entityFullPath]
///   2. `invoke()` —— 调实例方法，async/Promise 自动等待
///   3. `unload()` —— 从全局删掉实例
///
/// 重载不在这里：换代码要换一份 [content]，由 `Plugin.reload` 新建实体完成。
class JsEntity {
  JsEntity({
    required this.className,
    required this.entityPath,
    required this.entityName,
    required this.engine,
    required this.content,
  });

  /// JS 类名 —— `new <className>()` 用它，错误信息也用它。
  ///
  /// 由 `PluginSourceRule` 校验为「= 插件名」，但本类不假设它与 [entityName] 相同。
  final String className;

  /// 实例挂载的全局对象路径（如 `__plugins__`）
  final String entityPath;

  /// 实例名：挂到 `entityPath.entityName`，之后也按这个名字寻址
  final String entityName;

  /// 承载实例的 JS 引擎
  final BaseJsEngine engine;

  /// 插件代码（`{插件名}.js` 的内容，由调用方读盘后传进来）
  final String content;

  /// 实例在 JS 全局的完整访问路径 —— Dart 侧的「实例句柄」
  String get entityFullPath => '$entityPath.$entityName';

  /// 检查实例是否仍存在于 JS 引擎中。
  bool get isLoaded => engine.evaluate('$entityFullPath !== undefined') == true;

  /// 注册：执行 [content] 并创建实例挂载到 [entityFullPath]。
  ///
  /// **不注入任何字段**：宿主需要的元数据全在 `index.json` 的记录上，实例上不存在
  /// 这类字段。存储命名空间由 `PluginSource` 的 `get key()` 从**类名**派生，因此
  /// 构造期读 `this.key` 就已经正确 —— 现存 20/37 个插件正是在构造函数里调 `init()`。
  Future<void> register() async {
    final wrapped = '''
      (function() {
        $content
        if (typeof $className !== 'function') {
          throw new Error('Class $className not found in content');
        }
        $entityFullPath = new $className();
      })()
    ''';

    engine.evaluate(wrapped, name: '<register:$entityFullPath>');
  }

  /// 调用插件实例的方法。
  ///
  /// **Promise 处理**：检测返回值是否有 `.then`，有则等待 resolve —— async 方法会
  /// 自动等待，调用方无需处理。
  ///
  /// [method] 方法名；[args] 参数（JSON 序列化后传入）。
  /// 返回值尝试 JSON 还原；插件内抛错时抛 [EntityInvokeException]。
  Future<dynamic> invoke(
    String method, [
    List<dynamic> args = const [],
  ]) async {
    final argsLiteral = args.isEmpty ? '[]' : jsonEncode(args);

    final code = '''
      (function() {
        try {
          var __p = $entityFullPath;
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

  /// 卸载：从 JS 全局删掉实例。
  ///
  /// 调用后 [isLoaded] 返回 `false`，但本对象仍可用（`content` 还在）。
  void unload() {
    engine.evaluate('delete $entityFullPath;');
  }
}

/// 插件方法调用异常
class EntityInvokeException implements Exception {
  EntityInvokeException({
    required this.className,
    required this.entityPath,
    required this.entityName,
    required this.method,
    required this.message,
  });

  /// JS 类名
  final String className;

  /// 实例挂载的全局对象路径
  final String entityPath;

  /// 实例名
  final String entityName;

  /// 调用的方法名
  final String method;

  /// 异常信息（来自 JS 侧）
  final String message;

  @override
  String toString() => 'EntityInvokeException($className.$method): '
      '$entityPath.$entityName\n$message';
}
