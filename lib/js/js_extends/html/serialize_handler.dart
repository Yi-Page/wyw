import 'package:wyw/js/js_extends/html/html_registry.dart';

/// 序列化层 handler。
///
/// **职责**：把元素转回 HTML 字符串。当前仅 `getInnerHTML` 一种形式，
/// 如需 `outerHTML` 等扩展能力可在此层添加。
///
/// **注册的 JS function**：
///   - `getInnerHTML` — 元素内部 HTML（不含元素自身标签）
class SerializeHandler {
  /// 元素内部 HTML。
  static String? elementGetInnerHTML(
      HtmlRegistry registry, Map<String, dynamic> data) {
    return registry.documents[data['doc']]!.elementGetInnerHTML(data['key']);
  }
}
