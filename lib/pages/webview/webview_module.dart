import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/pages/webview/webview_page.dart';

import '../route_error_page.dart';

final webviewModule = createModule(
  path: '/webview',
  register: (c) {
    c.route(
      '/',
      transition: TransitionType.none,
      child: (context, state) {
        final args = state.arguments;
        if (args is! WebviewPageRouteArgs) {
          return const RouteErrorPage(message: '网址参数无效，请返回后重试。');
        }
        return WebviewPage(url: args.url);
      },
    );
  },
);
