import 'package:wyw/js/js_extends/js_bridge.dart';

/// JS 端可调用的方法集合。
///
/// 对应 sendMessage({method: 'convert' | 'random' | 'uuid'}) 的处理。
/// 设计为纯数据处理工具（无状态），可被任意上下文实例化。
class JsDialog {
  /// 编码 / 加密主入口。
  ///
  /// 支持的 [data["type"]]：utf8 / gbk / base64 / md5 / sha1 / sha256 / sha512 /
  /// hmac / aes-ecb / aes-cbc / aes-cfb / aes-ofb / rsa。
  Object? handleDialogCallback(Map<String, dynamic> data) {
    switch (data['function']) {
      case 'showToast':
        // 不直接依赖 UI 层；通过宿主注入的回调展示 toast。
        // 默认 no-op，宿主应用可在启动时设置 [JSEngineCommonApi.onShowToast]。
        JSEngineCommonApi.onShowToast?.call(data['message']?.toString() ?? '');
    }
    return null;
  }
}
