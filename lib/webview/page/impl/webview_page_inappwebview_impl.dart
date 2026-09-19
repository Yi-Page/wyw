import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';

import 'package:wyw/webview/page/webview_page_controller.dart';

class WebviewPageInAppWebviewImpl extends WebviewPageController {
  final ValueNotifier<double> progressNotifier = ValueNotifier(0.0);
  final ValueNotifier<String> urlNotifier = ValueNotifier('');

  PlatformInAppWebViewController? webViewController;
  final InAppWebViewSettings settings = InAppWebViewSettings(
    isInspectable: kDebugMode,
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,
  );

  late final PlatformPullToRefreshController pullToRefreshController;
  final TextEditingController urlController = TextEditingController();

  @override
  Future<void> init() async {
    await PlatformInAppWebViewController.static()
        .setWebContentsDebuggingEnabled(kDebugMode);
    pullToRefreshController = PlatformPullToRefreshController(
      PlatformPullToRefreshControllerCreationParams(
        // 下拉刷新指示色在 buildWebViewWidget 里随主题设置（此处无 BuildContext）
        settings: PullToRefreshSettings(),
        onRefresh: () async {
          webViewController?.reload();
        },
      ),
    );
    initEventController.add(true);
  }

  @override
  Widget buildWebViewWidget(BuildContext context, String initialUrl) {
    // 下拉刷新指示色随主题（init 时没有 BuildContext，只能在这里设置）
    pullToRefreshController.setColor(Theme.of(context).colorScheme.primary);
    return Column(
      children: [
        Expanded(child: _buildWebViewStack(context, initialUrl)),
        _buildControlBar(),
      ],
    );
  }

  @override
  List<Widget>? buildAppbarActions() {
    return [
      IconButton(
        icon: Icon(Icons.search),
        tooltip: 'Search',
        splashRadius: 20,
        onPressed: () {
          final uri = WebUri(urlController.text);
          final loadUri = uri.scheme.isEmpty
              ? WebUri('https://www.google.com/search?q=${urlController.text}')
              : uri;
          webViewController?.loadUrl(urlRequest: URLRequest(url: loadUri));
        },
      ),
    ];
  }

  @override
  Widget buildUrlBar() {
    return TextField(
      decoration: InputDecoration(hintText: 'URL'),
      controller: urlController,
      keyboardType: TextInputType.url,
      onSubmitted: (value) {
        final uri = WebUri(value);
        final loadUri = uri.scheme.isEmpty
            ? WebUri('https://www.google.com/search?q=$value')
            : uri;
        webViewController?.loadUrl(urlRequest: URLRequest(url: loadUri));
      },
    );
  }

  // WebView 主体
  Widget _buildWebViewStack(BuildContext context, String initialUrl) {
    return Stack(
      children: [
        PlatformInAppWebViewWidget(
          PlatformInAppWebViewWidgetCreationParams(
            initialUrlRequest: URLRequest(url: WebUri(initialUrl)),
            initialSettings: settings,
            pullToRefreshController: pullToRefreshController,
            onWebViewCreated: (ctrl) => webViewController = ctrl,
            onLoadStart: (_, uri) {
              urlNotifier.value = uri.toString();
              urlController.text = urlNotifier.value;
            },
            onPermissionRequest: (_, request) async => PermissionResponse(
              resources: request.resources,
              action: PermissionResponseAction.GRANT,
            ),
            shouldOverrideUrlLoading: (_, action) async {
              final uri = action.request.url!;
              if (![
                'http',
                'https',
                'file',
                'chrome',
                'data',
                'javascript',
                'about',
              ].contains(uri.scheme)) {
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                  return NavigationActionPolicy.CANCEL;
                }
              }
              return NavigationActionPolicy.ALLOW;
            },
            onLoadStop: (_, uri) {
              pullToRefreshController.endRefreshing();
              urlNotifier.value = uri.toString();
              urlController.text = urlNotifier.value;
            },
            onReceivedError: (_, __, ___) =>
                pullToRefreshController.endRefreshing(),
            onProgressChanged: (_, progress) {
              progressNotifier.value = progress / 100;
              if (progress == 100) pullToRefreshController.endRefreshing();
            },
            onUpdateVisitedHistory: (_, uri, __) {
              urlNotifier.value = uri.toString();
              urlController.text = urlNotifier.value;
            },
          ),
        ).build(context),
        // 进度条（响应式，无需setState）
        ValueListenableBuilder<double>(
          valueListenable: progressNotifier,
          builder: (_, value, __) {
            return value < 1.0
                ? LinearProgressIndicator(value: value)
                : const SizedBox();
          },
        ),
      ],
    );
  }

  // 控制栏：返回/前进/刷新
  Widget _buildControlBar() {
    return OverflowBar(
      alignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(
          onPressed: () => webViewController?.goBack(),
          child: const Icon(Icons.arrow_back),
        ),
        ElevatedButton(
          onPressed: () => webViewController?.goForward(),
          child: const Icon(Icons.arrow_forward),
        ),
        ElevatedButton(
          onPressed: () => webViewController?.reload(),
          child: const Icon(Icons.refresh),
        ),
      ],
    );
  }

  @override
  Future<String> getCookieString(String pageUrl) async {
    try {
      final manager = PlatformCookieManager(
        PlatformCookieManagerCreationParams(),
      );
      final cookies = await manager.getCookies(url: WebUri(pageUrl));
      return cookies.map((c) => '${c.name}=${c.value}').join('; ');
    } catch (e, s) {
      WywLogger().e('${LogTag.webview} 读取 Cookie 失败 pageUrl=$pageUrl',
          error: e, stackTrace: s);
      return '';
    }
  }

  @override
  Future<void> unloadPage() async => await webViewController?.loadUrl(
        urlRequest: URLRequest(url: WebUri('about:blank')),
      );

  @override
  void dispose() {
    webViewController = null;
    progressNotifier.dispose();
    urlNotifier.dispose();
    urlController.dispose();
  }
}
