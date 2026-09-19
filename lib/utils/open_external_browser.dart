import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';

/// 在外部浏览器打开链接（带确认弹窗）。
///
/// 先弹出「取消 / 打开」确认框（内容展示目标链接），用户确认后
/// 以 [LaunchMode.externalApplication] 交给操作系统，由默认浏览器
/// （或其他能处理该 scheme 的应用）打开，完全离开当前 app。
/// 打开失败（无可用应用 / 平台拒绝）时给出 Toast 提示。
///
/// [context] 可传入以指定弹窗挂载的上下文；缺省时由 [WywDialog] 的
/// 全局 observer 自动解析（JS 桥等无页面上下文场景也能工作）。
Future<void> openExternalBrowserWithConfirm(
  String url, {
  BuildContext? context,
}) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) {
    WywDialog.showToast(message: '链接无效，无法打开', context: context);
    return;
  }

  final confirmed = await WywDialog.showConfirm(
    context: context,
    title: '打开外部浏览器',
    message: '确定在外部浏览器打开以下链接吗？\n\n$url',
    confirmText: '打开',
    cancelText: '取消',
  );
  if (!confirmed) return;

  final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!launched) {
    // await 之后不再使用传入的 context（async gap 规则），
    // WywDialog 会通过全局 observer 自动解析 Toast 挂载上下文。
    WywDialog.showToast(message: '打开链接失败');
  }
}
