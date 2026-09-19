import 'package:wyw/js/js_extends/html/html_registry.dart';

/// 查询/导航层 handler。
///
/// **职责**：从一个文档或元素出发，按选择器（CSS / XPath）或树形结构关系，
/// 找到其它元素或节点。
///
/// **注册的 JS function**（按类别细分）：
///
/// *文档级 — 选择器查询*：
///   - `querySelector` — 单元素查询（CSS 优先，query 以 `//` 开头时转 XPath）
///   - `querySelectorAll` — 多元素查询（同上）
///   - `xpathQueryAll` — 强制 XPath 多元素查询
///   - `getElementById` — 按 ID 查询
///
/// *元素级 — 选择器查询*：
///   - `dom_querySelector` — CSS 单查询
///   - `dom_querySelectorAll` — CSS 多查询
///   - `xpathQuery` — XPath 单查询
///
/// *导航 — 树形结构*：
///   - `getParent` — 父元素
///   - `getChildren` — 直接子元素列表（不含文本节点）
///   - `getChildrenInfo` — 直接子节点列表（结构化数据：type + text + 可选 elementKey）
///   - `getPreviousSibling` — 前兄弟元素
///   - `getNextSibling` — 后兄弟元素
class QueryHandler {
  // ============================================================
  // 文档级 — 选择器查询
  // ============================================================

  /// 单元素查询（CSS 优先；query 以 `//` 开头时自动转 XPath）。
  static int? documentXpathQuery(
      HtmlRegistry registry, Map<String, dynamic> data) {
    final key = data['key'];
    final query = data['query'] as String?;
    if (query == null || query.isEmpty) return null;
    final wrapper = registry.documents[key]!;
    return wrapper.xpathQuery(query);
  }

  /// 单元素查询（CSS 优先；query 以 `//` 开头时自动转 XPath）。
  static int? documentQuerySelector(
      HtmlRegistry registry, Map<String, dynamic> data) {
    final key = data['key'];
    final query = data['query'] as String?;
    if (query == null || query.isEmpty) return null;
    final wrapper = registry.documents[key]!;
    return wrapper.querySelector(query);
  }

  /// 多元素查询（同上）。
  static List<int> documentQuerySelectorAll(
      HtmlRegistry registry, Map<String, dynamic> data) {
    final key = data['key'];
    final query = data['query'] as String?;
    if (query == null || query.isEmpty) return <int>[];
    final wrapper = registry.documents[key]!;
    if (query.startsWith('//')) {
      return wrapper.xpathQueryAll(query);
    }
    return wrapper.querySelectorAll(query);
  }

  /// 强制 XPath 多元素查询。
  static List<int> documentXpathQueryAll(
      HtmlRegistry registry, Map<String, dynamic> data) {
    final wrapper = registry.documents[data['key']]!;
    return wrapper.xpathQueryAll(data['query']);
  }

  /// 按 ID 查询。
  static int? documentGetElementById(
      HtmlRegistry registry, Map<String, dynamic> data) {
    return registry.documents[data['key']]!.getElementById(data['id']);
  }

  // ============================================================
  // 元素级 — 选择器查询
  // ============================================================

  /// CSS 单查询（XPath 自动识别由 JS 端处理，本方法不重复判断）。
  static int? elementQuerySelector(
      HtmlRegistry registry, Map<String, dynamic> data) {
    final wrapper = registry.documents[data['doc']]!;
    final query = data['query'] as String?;
    if (query == null || query.isEmpty) return null;
    return wrapper.elementQuerySelector(data['key'], query);
  }

  /// XPATH 多查询。
  static List<int> elementXpathQueryAll(
      HtmlRegistry registry, Map<String, dynamic> data) {
    final wrapper = registry.documents[data['doc']]!;
    return wrapper.elementXpathQueryAll(data['key'], data['query']);
  }

  /// CSS 多查询。
  static List<int> elementQuerySelectorAll(
      HtmlRegistry registry, Map<String, dynamic> data) {
    final wrapper = registry.documents[data['doc']]!;
    return wrapper.elementQuerySelectorAll(data['key'], data['query']);
  }

  /// XPath 单查询。
  static int? elementXpathQuery(
      HtmlRegistry registry, Map<String, dynamic> data) {
    final wrapper = registry.documents[data['doc']]!;
    return wrapper.elementXpathQuery(data['key'], data['query']);
  }

  // ============================================================
  // 导航 — 树形结构
  // ============================================================

  /// 父元素。
  static int? elementGetParent(
      HtmlRegistry registry, Map<String, dynamic> data) {
    return registry.documents[data['doc']]!.elementGetParent(data['key']);
  }

  /// 直接子元素列表（不含文本节点）。
  static List<int> elementGetChildren(
      HtmlRegistry registry, Map<String, dynamic> data) {
    return registry.documents[data['doc']]!.elementGetChildren(data['key']);
  }

  /// 直接子节点列表（含文本/注释节点）。
  ///
  /// 替代旧版 `elementGetNodes` 的设计：
  /// Text/Comment **不持久化**（它们无法进行节点操作），改为一次性返回结构化数据。
  /// 仅 Element 子节点分配 [elements] 池的 key 用于后续操作。
  static List<Map<String, dynamic>> elementGetChildrenInfo(
      HtmlRegistry registry, Map<String, dynamic> data) {
    return registry.documents[data['doc']]!.elementGetChildrenInfo(data['key']);
  }

  /// 前一个兄弟元素。
  static int? elementGetPreviousSibling(
      HtmlRegistry registry, Map<String, dynamic> data) {
    return registry.documents[data['doc']]!.getPreviousSibling(data['key']);
  }

  /// 后一个兄弟元素。
  static int? elementGetNextSibling(
      HtmlRegistry registry, Map<String, dynamic> data) {
    return registry.documents[data['doc']]!.getNextSibling(data['key']);
  }
}
