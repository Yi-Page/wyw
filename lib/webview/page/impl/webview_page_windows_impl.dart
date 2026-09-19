import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/webview/page/webview_page_controller.dart';

class WebviewPageWindowsImpl extends WebviewPageController {
  WebviewController? webViewController;
  final TextEditingController urlController = TextEditingController();
  bool _isWebviewSuspended = false;
  final List<StreamSubscription> _subscriptions = [];

  @override
  Future<void> init() async {
    webViewController ??= WebviewController();
    await webViewController?.initialize();
    await webViewController?.setBackgroundColor(Colors.transparent);
    await webViewController?.setPopupWindowPolicy(
      WebviewPopupWindowPolicy.allow,
    );
    _subscriptions.add(
      webViewController!.url.listen((url) {
        urlController.text = url;
      }),
    );
    initEventController.add(true);
  }

  @override
  Widget buildWebViewWidget(BuildContext context, String initialUrl) {
    if (webViewController == null || !webViewController!.value.isInitialized) {
      return const Text(
        'Not Initialized',
        style: TextStyle(fontSize: 24.0, fontWeight: FontWeight.w900),
      );
    }
    webViewController?.loadUrl(initialUrl);
    return Column(
      children: [
        Expanded(child: _buildWebViewStack(context)),
        _buildControlBar(),
      ],
    );
  }

  @override
  List<Widget>? buildAppbarActions() {
    return [
      IconButton(
        onPressed: () => webViewController?.goBack(),
        tooltip: '返回',
        icon: const Icon(Icons.arrow_back),
      ),
      IconButton(
        onPressed: () => webViewController?.goForward(),
        tooltip: '前进',
        icon: const Icon(Icons.arrow_forward),
      ),
      IconButton(
        onPressed: () => webViewController?.reload(),
        tooltip: '刷新',
        icon: const Icon(Icons.refresh),
      ),
      IconButton(
        icon: Icon(_isWebviewSuspended ? Icons.play_arrow : Icons.pause),
        tooltip: _isWebviewSuspended ? 'Resume webview' : 'Suspend webview',
        splashRadius: 20,
        onPressed: () async {
          if (_isWebviewSuspended) {
            await webViewController?.resume();
          } else {
            await webViewController?.suspend();
          }
          _isWebviewSuspended = !_isWebviewSuspended;
          onStateChanged?.call();
        },
      ),
      IconButton(
        icon: Icon(Icons.developer_mode),
        tooltip: 'Open DevTools',
        splashRadius: 20,
        onPressed: () {
          webViewController?.openDevTools();
        },
      ),
    ];
  }

  @override
  Widget buildUrlBar() {
    return TextField(
      decoration: InputDecoration(
        hintText: 'URL',
        contentPadding: EdgeInsets.all(10.0),
      ),
      textAlignVertical: TextAlignVertical.center,
      controller: urlController,
      onSubmitted: (val) {
        webViewController?.loadUrl(val);
      },
    );
  }

  Widget _buildWebViewStack(BuildContext context) {
    return Card(
      color: Colors.transparent,
      elevation: 0,
      clipBehavior: Clip.antiAliasWithSaveLayer,
      child: Stack(
        children: [
          Webview(webViewController!),
          StreamBuilder<LoadingState>(
            stream: webViewController?.loadingState,
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data == LoadingState.loading) {
                return LinearProgressIndicator();
              } else {
                return SizedBox();
              }
            },
          ),
        ],
      ),
    );
  }

  // 控制栏：返回/前进/刷新
  Widget _buildControlBar() {
    return SizedBox.shrink();
  }

  @override
  Future<String> getCookieString(String pageUrl) async {
    try {
      final result = await webViewController?.getCookies(pageUrl);
      return result ?? '';
    } catch (e, s) {
      WywLogger().e('${LogTag.webview} 读取 Cookie 失败 pageUrl=$pageUrl',
          error: e, stackTrace: s);
      return '';
    }
  }

  @override
  Future<void> unloadPage() async {
    try {
      await webViewController?.executeScript(
        "window.location.href = 'about:blank';",
      );
    } catch (e) {
      WywLogger()
          .d('${LogTag.webview} unloadPage 跳转 about:blank 失败（已忽略）', error: e);
    }
  }

  @override
  void dispose() {
    try {
      for (var s in _subscriptions) {
        s.cancel();
      }
      initEventController.close();
    } catch (_) {
      // 静默可接受：dispose 阶段取消订阅/关闭 controller 失败属常态，不影响销毁流程。
    }
    webViewController?.dispose();
    webViewController = null;
  }
}
