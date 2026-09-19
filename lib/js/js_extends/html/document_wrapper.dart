import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';

/// HTML 文档 + 元素索引容器。
///
/// **职责**：
///   - 持有解析后的 [dom.Document]（来自 `package:html`）
///   - 维护一个整数索引池：[elements]（仅持久化"后续还会操作的元素"）
///   - JS 端只拿到整数下标，Dart 端按下标访问真正的 DOM 元素
///
/// **设计原则**：
///   - **只持久化能进行节点操作的元素** —— 这是 [elements] 唯一的内容
///   - **不持久化节点（Text/Comment/Document）** —— 它们没有"节点操作"能力，
///     在 `elementGetChildrenInfo` 中以结构化数据（`type` + `text`）一次性返回，
///     JS 看后即丢，无需 key 引用
///
/// **四类操作的实现集中处**：
///   - 查询层：[querySelector] / [querySelectorAll] / [xpathQuery] / [xpathQueryAll] / [getElementById] /
///     [elementQuerySelector] / [elementQuerySelectorAll] / [elementXpathQuery] / [elementXpathQueryAll]
///   - 导航层：[elementGetParent] / [elementGetChildren] / [elementGetChildrenInfo] /
///     [getPreviousSibling] / [getNextSibling]
///   - 提取层：[elementGetText] / [elementGetAttributes] / [getClassNames] /
///     [getId] / [getLocalName]
///   - 序列化层：[elementGetInnerHTML]
class DocumentWrapper {
  final dom.Document doc;
  final elements = <dom.Element>[];

  DocumentWrapper.fromHtml(String htmlString) : doc = html.parse(htmlString);

  // ============================================================
  // 查询层 — 文档级
  // ============================================================

  int? querySelector(String query) {
    final element = doc.querySelector(query);
    if (element == null) return null;
    elements.add(element);
    return elements.length - 1;
  }

  List<int> querySelectorAll(String query) {
    final res = doc.querySelectorAll(query);
    return _collectElementKeys(res);
  }

  List<int> xpathQueryAll(String xpath) {
    try {
      final result = doc.documentElement!.queryXPath(xpath);
      return _collectXPathElementKeys(result.nodes);
    } catch (e) {
      WywLogger().w('${LogTag.js} XPath 查询失败 xpath=$xpath', error: e);
      return [];
    }
  }

  int? xpathQuery(String xpath) {
    try {
      final result = doc.documentElement!.queryXPath(xpath);
      if (result.nodes.isEmpty) return null;
      final node = result.nodes.first.node;
      if (node is! dom.Element) return null;
      elements.add(node);
      return elements.length - 1;
    } catch (e) {
      WywLogger().w('${LogTag.js} XPath 查询失败 xpath=$xpath', error: e);
      return null;
    }
  }

  int? getElementById(String id) {
    final element = doc.getElementById(id);
    if (element == null) return null;
    elements.add(element);
    return elements.length - 1;
  }

  // ============================================================
  // 查询层 — 元素级
  // ============================================================

  int? elementQuerySelector(int key, String query) {
    final res = elements[key].querySelector(query);
    if (res == null) return null;
    elements.add(res);
    return elements.length - 1;
  }

  List<int> elementQuerySelectorAll(int key, String query) {
    return _collectElementKeys(elements[key].querySelectorAll(query));
  }

  int? elementXpathQuery(int key, String xpath) {
    try {
      final result = elements[key].queryXPath(xpath);
      if (result.nodes.isEmpty) return null;
      final node = result.nodes.first.node;
      if (node is! dom.Element) return null;
      elements.add(node);
      return elements.length - 1;
    } catch (e) {
      WywLogger().w('${LogTag.js} XPath 查询失败 xpath=$xpath', error: e);
      return null;
    }
  }

  List<int> elementXpathQueryAll(int key, String xpath) {
    try {
      final result = elements[key].queryXPath(xpath);
      return _collectXPathElementKeys(result.nodes);
    } catch (e) {
      WywLogger().w('${LogTag.js} XPath 查询失败 xpath=$xpath', error: e);
      return [];
    }
  }

  // ============================================================
  // 导航层
  // ============================================================

  int? elementGetParent(int key) {
    final res = elements[key].parent;
    if (res == null) return null;
    elements.add(res);
    return elements.length - 1;
  }

  List<int> elementGetChildren(int key) {
    return _collectElementKeys(elements[key].children);
  }

  /// 一次性返回所有子节点的"分析数据"（结构化 JSON）。
  ///
  /// **设计原则**：Text/Comment/Document 没有"节点操作"能力，因此**不持久化**到任何池。
  /// 这里把它们的内容（type + text）一次性返回，JS 看后即丢。
  /// 仅当子节点是 Element 时，才分配一个 [elements] 池的 key 给 JS 用于后续操作。
  ///
  /// 返回结构示例：
  /// ```json
  /// [
  ///   {"type": "element", "text": "Title", "elementKey": 5},
  ///   {"type": "text", "text": "Hello"},
  ///   {"type": "comment", "text": "TODO"},
  /// ]
  /// ```
  List<Map<String, dynamic>> elementGetChildrenInfo(int key) {
    final res = elements[key].nodes;
    final result = <Map<String, dynamic>>[];
    for (final node in res) {
      if (node is dom.Element) {
        elements.add(node);
        result.add({
          'type': 'element',
          'text': node.text,
          'elementKey': elements.length - 1,
        });
      } else {
        // Text / Comment / Document / 其它
        result.add({
          'type': _nodeTypeString(node),
          'text': node.text ?? '',
        });
      }
    }
    return result;
  }

  int? getPreviousSibling(int key) {
    final res = elements[key].previousElementSibling;
    if (res == null) return null;
    elements.add(res);
    return elements.length - 1;
  }

  int? getNextSibling(int key) {
    final res = elements[key].nextElementSibling;
    if (res == null) return null;
    elements.add(res);
    return elements.length - 1;
  }

  // ============================================================
  // 数据提取层
  // ============================================================

  String? elementGetText(int key) => elements[key].text;

  Map<String, String> elementGetAttributes(int key) {
    return elements[key].attributes.map(
          (key, value) => MapEntry(key.toString(), value),
        );
  }

  List<String> getClassNames(int key) => elements[key].classes.toList();

  String? getId(int key) => elements[key].id;

  String? getLocalName(int key) => elements[key].localName;

  // ============================================================
  // 序列化层
  // ============================================================

  String? elementGetInnerHTML(int key) => elements[key].innerHtml;

  // ============================================================
  // 内部辅助
  // ============================================================

  List<int> _collectElementKeys(Iterable<dom.Element> src) {
    final keys = <int>[];
    for (final e in src) {
      elements.add(e);
      keys.add(elements.length - 1);
    }
    return keys;
  }

  /// 从 XPath 查询结果中提取 element 节点（跳过文本/注释节点）。
  ///
  /// `xpath_selector_html_parser` 的 `XPathNode` 类型未公开导出，因此用 `dynamic`。
  List<int> _collectXPathElementKeys(Iterable<dynamic> src) {
    final keys = <int>[];
    for (final xnode in src) {
      final node = xnode.node;
      if (node is dom.Element) {
        elements.add(node);
        keys.add(elements.length - 1);
      }
    }
    return keys;
  }

  /// 把 [dom.Node] 的类型转换为 JS 友好的字符串。
  String _nodeTypeString(dom.Node node) {
    return switch (node.nodeType) {
      dom.Node.ELEMENT_NODE => 'element',
      dom.Node.TEXT_NODE => 'text',
      dom.Node.COMMENT_NODE => 'comment',
      dom.Node.DOCUMENT_NODE => 'document',
      _ => 'unknown',
    };
  }
}
