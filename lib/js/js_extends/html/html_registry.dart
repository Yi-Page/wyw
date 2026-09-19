import 'package:wyw/js/js_extends/html/document_wrapper.dart';
import 'package:wyw/js/js_extends/html/extract_handler.dart';
import 'package:wyw/js/js_extends/html/parse_handler.dart';
import 'package:wyw/js/js_extends/html/query_handler.dart';
import 'package:wyw/js/js_extends/html/serialize_handler.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';

/// HTML 文档注册表：管理 [DocumentWrapper] 实例，按四大类分发 JS 端 `html.*` 调用。
///
/// **职责**：
///   - 持有 `key → DocumentWrapper` 的 Map（每个 JS 引擎实例独立）
///   - 接收 `{method: 'html', function: '<function_name>'}` 消息
///   - 按四大类（解析 / 查询导航 / 数据提取 / 序列化）路由到对应 handler
///
/// **设计要点**：
///   - **派发表**：本类的 [handleHtmlCallback] 用 `switch` 显式列出全部 22 个 function 及其所属 handler，
///     形成自解释的"目录"。改派发逻辑时无需翻阅各 handler 文件。
///   - **handler 类**：每个 handler 是无状态的纯静态方法集合，只负责调用 [DocumentWrapper] 的对应方法。
///     任何 handler 都可以直接修改 [documents]（实际只有解析层会这样做）。
///   - **DOM 解析依赖**：`package:html`，封装在 [DocumentWrapper] 中。
///   - **XPath 依赖**：`xpath_selector_html_parser`（扩展方法），同样封装在 [DocumentWrapper] 中。
class HtmlRegistry {
  /// key → [DocumentWrapper] 的 Map。
  ///
  /// **当前实现**：简单 Map，无 LRU 淘汰。注释中曾提到"最多 8 个"但未实现，
  /// 后续如需限制可改为 `LinkedHashMap` + 超出时移除最早 key。
  ///
  /// **访问权限**：设为 public 是为了让 handler 类能直接访问，
  /// 避免在 registry 和 handler 之间传 getter 造成的样板代码。
  final documents = <int, DocumentWrapper>{};

  /// JS 端 `sendMessage({method: 'html', function: ..., ...})` 的统一入口。
  ///
  /// **派发表**（22 个 function，按四大类分组）：
  ///
  /// *解析层*：[ParseHandler]
  ///   - `parse`, `dispose`, `node_to_element`
  ///
  /// *查询/导航层*：[QueryHandler]
  ///   - 文档级：`querySelector`, `querySelectorAll`, `xpathQueryAll`, `getElementById`
  ///   - 元素级：`dom_querySelector`, `dom_querySelectorAll`, `xpathQuery`
  ///   - 导航：`getParent`, `getChildren`, `getNodes`, `getPreviousSibling`, `getNextSibling`
  ///
  /// *数据提取层*：[ExtractHandler]
  ///   - 文本：`getText`, `node_text`
  ///   - 属性：`getAttributes`
  ///   - 元数据：`getClassNames`, `getId`, `getLocalName`
  ///   - 节点类型：`node_type`
  ///
  /// *序列化层*：[SerializeHandler]
  ///   - `getInnerHTML`
  Object? handleHtmlCallback(Map<String, dynamic> data) {
    final function = data['function'] as String?;
    if (function == null) return null;

    return switch (function) {
      // ===== 解析层 =====
      'parse' => ParseHandler.parse(this, data),
      'dispose' => ParseHandler.dispose(this, data),

      // ===== 查询/导航层 — 文档级 =====
      'xpathQuery' => QueryHandler.documentXpathQuery(this, data),
      'querySelector' => QueryHandler.documentQuerySelector(this, data),
      'querySelectorAll' => QueryHandler.documentQuerySelectorAll(this, data),
      'xpathQueryAll' => QueryHandler.documentXpathQueryAll(this, data),
      'getElementById' => QueryHandler.documentGetElementById(this, data),

      // ===== 查询/导航层 — 元素级 =====
      'dom_xpathQuery' => QueryHandler.elementXpathQuery(this, data),
      'dom_querySelector' => QueryHandler.elementQuerySelector(this, data),
      'dom_xpathQueryAll' => QueryHandler.elementXpathQueryAll(this, data),
      'dom_querySelectorAll' =>
        QueryHandler.elementQuerySelectorAll(this, data),

      // ===== 查询/导航层 — 树形导航 =====
      'getParent' => QueryHandler.elementGetParent(this, data),
      'getChildren' => QueryHandler.elementGetChildren(this, data),
      'getChildrenInfo' => QueryHandler.elementGetChildrenInfo(this, data),
      'getPreviousSibling' =>
        QueryHandler.elementGetPreviousSibling(this, data),
      'getNextSibling' => QueryHandler.elementGetNextSibling(this, data),

      // ===== 数据提取层 — 文本 =====
      'getText' => ExtractHandler.elementGetText(this, data),

      // ===== 数据提取层 — 属性 =====
      'getAttributes' => ExtractHandler.elementGetAttributes(this, data),

      // ===== 数据提取层 — 元数据 =====
      'getClassNames' => ExtractHandler.elementGetClassNames(this, data),
      'getId' => ExtractHandler.elementGetId(this, data),
      'getLocalName' => ExtractHandler.elementGetLocalName(this, data),

      // ===== 序列化层 =====
      'getInnerHTML' => SerializeHandler.elementGetInnerHTML(this, data),

      // ===== 未知 function =====
      _ => _unknown(function),
    };
  }

  Object? _unknown(String? function) {
    WywLogger().w('${LogTag.js} 未知的 html function: $function');
    return null;
  }
}
