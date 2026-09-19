import 'package:flutter/widgets.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';

/// 双击返回检测：封装「2 秒内再次按返回键才生效，否则 toast 提示」的常见模式。
///
/// 用法：
/// ```dart
/// final _doubleBackExit = DoubleBackExit(toastMessage: '再按一次退出应用');
///
/// void _onBackPressed(BuildContext context) {
///   if (!_doubleBackExit.handle(context)) return; // 第一次按下：已提示
///   Navigator.of(context).pop(); // 第二次按下：执行退出
/// }
/// ```
class DoubleBackExit {
  DoubleBackExit({required this.toastMessage});

  /// 首次按下时展示的提示文案。
  final String toastMessage;

  /// 两次按下的时间窗口。
  static const Duration interval = Duration(seconds: 2);

  DateTime? _lastPressedAt;

  /// 处理一次返回键。
  ///
  /// 返回 true 表示在时间窗口内再次按下（调用方应执行退出）；
  /// 返回 false 表示首次按下或间隔超时（已记录时间并 toast 提示）。
  bool handle(BuildContext context) {
    final last = _lastPressedAt;
    if (last == null || DateTime.now().difference(last) > interval) {
      _lastPressedAt = DateTime.now();
      WywDialog.showToast(message: toastMessage, context: context);
      return false;
    }
    return true;
  }

  /// 清除已记录的时间（例如子页面消费了返回事件时重置，避免误触发退出）。
  void reset() {
    _lastPressedAt = null;
  }
}
