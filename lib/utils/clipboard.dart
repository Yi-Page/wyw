import 'package:flutter/services.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';

/// 复制 [text] 到剪贴板。
///
/// 默认复制成功后 toast 提示 [toastMessage]；传 null 则静默复制
/// （用于已有其他提示的入口，如批量操作按钮）。
Future<void> copyToClipboard(String text,
    {String? toastMessage = '已复制到剪贴板'}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (toastMessage != null) {
    WywDialog.showToast(message: toastMessage);
  }
}
