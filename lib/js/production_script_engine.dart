import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/js/base_js_engine.dart';
import 'package:wyw/js/js_extends/js_bridge.dart';
import 'package:wyw/repositories/history_repository.dart';
import 'package:wyw/repositories/plugin_history_repository.dart';
import 'package:wyw/services/history/history_progress_reporter.dart';
import 'package:wyw/services/storage/storage.dart';

/// 正式运行环境：与测试台加载相同的 init.js / log / http，
/// 但**不启用**测试专用状态（无日志缓冲、无 Promise 异步桥）。
///
/// 用途：App 主体（scrap 数据处理、规则计算等）执行 JS 脚本。
///
/// **不变量**：
///   - 与 [ScriptEngine] 各自持有独立 [FlutterQjs] 实例
///   - 测试台反复 evaluate 产生的全局变量不会污染正式环境
///   - 正式环境不收集 log() 到缓冲——如需日志，走 [BaseJsEngine.handleCommonMessage] → WywLogger
///
/// **插件系统**：
///   初始化时建立 `globalThis.__plugins__ = {}` 全局对象，作为插件实例的注册表。
///   配合 [PluginManager] 使用，从本地 JS 文件加载规则并实例化。
///
/// **pluginName 来源**：
///   插件实例在自己的方法中通过 `this.name` 拿到自己的 pluginName，
///   调用 PluginBrowse 时把 pluginName 作为消息字段传入（如 `pluginName: this.name`）。
///   不再用 JS 全局 mutable 状态（避免并发/异步上下文切换导致串扰）。
class ProductionScriptEngine extends BaseJsEngine {
  static final ProductionScriptEngine _instance = ProductionScriptEngine._();
  factory ProductionScriptEngine() => _instance;
  ProductionScriptEngine._();

  @override
  Future<void> init() async {
    await super.init();
    // 配置进度上报器（让 PlayerController 直接写应用历史，Dart 端）
    final repo = HistoryRepository(
      box: GStorage.histories,
    );
    HistoryProgressReporter().configure(() => repo);
    // 插件浏览历史（JSON 后端）
    final pluginRepo = inject<PluginHistoryRepository>();
    JSEngineCommonApi.pluginHistoryRepository = pluginRepo;
    // 初始化插件注册表
    evaluate('globalThis.__plugins__ = globalThis.__plugins__ || {};',
        name: '<plugins-init>');
    // PluginBrowse 已在 BaseJsEngine.init() 加载 init.js 时注入
  }

  /// 同步执行一段脚本并返回原始结果。
  ///
  /// 返回值由 flutter_qjs 序列化：
  ///   - 基本类型（num / String / bool）→ 直接返回
  ///   - null → null
  ///   - `Map` / `List`（纯 JSON 可序列化）→ 转成对应 Dart 类型
  ///   - 函数 / 对象 / 带循环引用的对象 → 可能返回 `Map<String, dynamic>` 或抛错
  Object? runScript(String code, {String? name = '<production>'}) {
    return evaluate(code, name: name);
  }
}
