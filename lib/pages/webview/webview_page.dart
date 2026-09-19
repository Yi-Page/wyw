import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/webview/page/webview_page_controller.dart';
import 'package:wyw/utils/double_back_exit.dart';

import '../../bean/appbar/sys_app_bar.dart';

class WebviewPage extends StatefulWidget {
  const WebviewPage({
    super.key,
    required this.url,
  });

  final String url;

  @override
  State<WebviewPage> createState() => _WebviewPageState();
}

class _WebviewPageState extends State<WebviewPage>
    with SingleTickerProviderStateMixin {
  final _doubleBackExit = DoubleBackExit(toastMessage: '再按一次退出 webview');
  late Future<void> _initFuture;
  late WebviewPageController _webviewPageController;

  @override
  void initState() {
    super.initState();
    _initFuture = initPlatformState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  Future<void> initPlatformState() async {
    _webviewPageController = WebviewPageControllerFactory.getController();
    _webviewPageController.onStateChanged = () {
      setState(() {});
    };
    await _webviewPageController.init();
  }

  @override
  void dispose() {
    _webviewPageController.dispose();
    super.dispose();
  }

  void onBackPressed(BuildContext context) {
    if (WywDialog.observer.hasWywDialog) {
      WywDialog.dismiss();
      return;
    }
    if (!_doubleBackExit.handle(context)) return;
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        return PopScope(
          // 关键：这里必须用 _onWillPop 的结果
          canPop: false,
          onPopInvokedWithResult: (bool didPop, Object? result) {
            if (didPop) {
              return;
            }
            onBackPressed(context);
          },
          child: Scaffold(
            appBar: SysAppBar(
              title: _webviewPageController.buildUrlBar(),
              actions: _webviewPageController.buildAppbarActions(),
            ),
            body: FutureBuilder<void>(
              future: _initFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 20),
                        Text('WebView 初始化中...'),
                      ],
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return Center(child: Text('初始化失败: ${snapshot.error}'));
                }
                return _webviewPageController.buildWebViewWidget(
                    context, widget.url);
              },
            ),
          ),
        );
      },
    );
  }
}

/// `/webview/` 路由参数（见 webviewModule）。
class WebviewPageRouteArgs {
  const WebviewPageRouteArgs({required this.url});

  final String url;
}
