import 'package:wyw/js/js_extends/html/html_registry.dart';

/// 数据提取层 handler。
///
/// **职责**：从元素中读取数据（文本、属性、元数据），不修改 DOM。
///
/// **注册的 JS function**（按提取类别细分）：
///
/// *文本内容*：
///   - `getText` — 元素的文本（递归合并所有文本子节点）
///
/// *属性*：
///   - `getAttributes` — 元素的所有属性 Map（JS 端可据此实现 `getAttribute(name)`）
///
/// *元数据*：
///   - `getClassNames` — `class` 属性拆分为字符串数组
///   - `getId` — 元素的 `id` 属性
///   - `getLocalName` — 标签名（如 `div`）
///
/// **注意**：节点（Text/Comment）的 text/type 已合并到 [QueryHandler.elementGetChildrenInfo]
/// 的结构化返回值中，不再有独立的 `node_text` / `node_type` function。
class ExtractHandler {
  // ============================================================
  // 文本内容
  // ============================================================

  /// 元素的文本内容。
  static String? elementGetText(
      HtmlRegistry registry, Map<String, dynamic> data) {
    return registry.documents[data['doc']]!.elementGetText(data['key']);
  }

  // ============================================================
  // 属性
  // ============================================================

  /// 元素的所有属性 Map。
  ///
  /// 返回 `{name: value}`。JS 端的 `getAttribute(name)` 会先调用此方法再取值。
  static Map<String, String> elementGetAttributes(
      HtmlRegistry registry, Map<String, dynamic> data) {
    return registry.documents[data['doc']]!.elementGetAttributes(data['key']);
  }

  // ============================================================
  // 元数据
  // ============================================================

  /// 元素的 class 列表（拆分后的字符串数组）。
  static List<String> elementGetClassNames(
      HtmlRegistry registry, Map<String, dynamic> data) {
    return registry.documents[data['doc']]!.getClassNames(data['key']);
  }

  /// 元素的 id。
  static String? elementGetId(
      HtmlRegistry registry, Map<String, dynamic> data) {
    return registry.documents[data['doc']]!.getId(data['key']);
  }

  /// 元素的标签名。
  static String? elementGetLocalName(
      HtmlRegistry registry, Map<String, dynamic> data) {
    return registry.documents[data['doc']]!.getLocalName(data['key']);
  }
}
