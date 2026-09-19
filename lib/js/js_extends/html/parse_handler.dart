import 'package:wyw/js/js_extends/html/document_wrapper.dart';
import 'package:wyw/js/js_extends/html/html_registry.dart';

/// 解析层 handler。
///
/// **职责**：HTML 字符串 ↔ 可解析对象的转换 + 文档生命周期管理。
///
/// **注册的 JS function**：
///   - `parse` — 解析 HTML 字符串为 [DocumentWrapper]
///   - `dispose` — 释放文档（从注册表移除）
///
/// **与其它层的区别**：本层是少数会直接修改 [HtmlRegistry.documents] 的层
/// （其它层只读）。
class ParseHandler {
  /// 解析 HTML 字符串。
  ///
  /// JS 调用：`sendMessage({method: "html", function: "parse", key: <int>, data: <htmlString>})`
  static Object? parse(HtmlRegistry registry, Map<String, dynamic> data) {
    registry.documents[data['key']] = DocumentWrapper.fromHtml(data['data']);
    return null;
  }

  /// 释放文档。
  ///
  /// JS 调用：`sendMessage({method: "html", function: "dispose", key: <int>})`
  static Object? dispose(HtmlRegistry registry, Map<String, dynamic> data) {
    registry.documents.remove(data['key']);
    return null;
  }
}
