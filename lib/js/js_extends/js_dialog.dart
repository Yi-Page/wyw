import 'package:wyw/js/js_extends/js_bridge.dart';

/// JS 端 `Dialog.*` 消息的处理入口。
///
/// 对应 `sendMessage({method: 'dialog', function: ...})`。
///
/// **分层约定**：本类不直接依赖 Flutter UI 层，只做「参数收敛 + 转发宿主回调」；
/// 真正的对话框由宿主在启动时通过 [JSEngineCommonApi] 上的静态回调注入
/// （见 `lib/pages/init_page.dart` 的 `_setupJsBridges`）。
///
/// **异步语义**：`showInputDialog` / `showSelectDialog` 返回 `Future`，
/// flutter_qjs 会把它转成 JS Promise，因此 JS 侧可以 `await`。
class JsDialog {
  /// 处理一条 `dialog` 消息。
  ///
  /// 支持的 [data]`['function']`：
  ///   - `showToast`        → 轻提示（同步）
  ///   - `showDialog`       → 带按钮的对话框（同步返回，按钮回调由宿主调用 JS 函数）
  ///   - `showInputDialog`  → 输入框，返回 `Future<String?>`（取消为 null）
  ///   - `showSelectDialog` → 选择框，返回 `Future<int?>`（取消为 null）
  ///   - `showLoading`      → 加载中对话框，返回可取消的 id
  ///   - `cancelLoading`    → 关闭加载中对话框
  Object? handleDialogCallback(Map<String, dynamic> data) {
    switch (data['function']) {
      case 'showToast':
        // 不直接依赖 UI 层；通过宿主注入的回调展示 toast。
        // 默认 no-op，宿主应用可在启动时设置 [JSEngineCommonApi.onShowToast]。
        JSEngineCommonApi.onShowToast?.call(data['message']?.toString() ?? '');
        return null;

      case 'showDialog':
        final rawActions = data['actions'];
        final actions = <Map<String, dynamic>>[];
        if (rawActions is List) {
          for (final a in rawActions) {
            if (a is Map) actions.add(Map<String, dynamic>.from(a));
          }
        }
        JSEngineCommonApi.onShowDialog?.call(
          title: data['title']?.toString() ?? '',
          content: data['content']?.toString() ?? '',
          actions: actions,
        );
        return null;

      case 'showInputDialog':
        final cb = JSEngineCommonApi.onShowInputDialog;
        if (cb == null) {
          // 宿主未接入：返回 null（等价于用户取消），插件侧应据此优雅降级。
          return null;
        }
        return cb(
          title: data['title']?.toString() ?? '',
          image: data['image'],
          validator: data['validator'],
        );

      case 'showSelectDialog':
        final cb = JSEngineCommonApi.onShowSelectDialog;
        if (cb == null) return null;
        final rawOptions = data['options'];
        final options = <String>[];
        if (rawOptions is List) {
          for (final o in rawOptions) {
            options.add(o?.toString() ?? '');
          }
        }
        return cb(
          title: data['title']?.toString() ?? '',
          options: options,
          initialIndex: (data['initialIndex'] as num?)?.toInt(),
        );

      case 'showLoading':
        final cb = JSEngineCommonApi.onShowLoading;
        if (cb == null) return -1;
        return cb(onCancel: data['onCancel']);

      case 'cancelLoading':
        JSEngineCommonApi.onCancelLoading
            ?.call((data['id'] as num?)?.toInt() ?? -1);
        return null;
    }
    return null;
  }
}
