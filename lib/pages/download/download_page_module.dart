import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/pages/download/download_page.dart';
import 'package:wyw/pages/download/download_controller.dart';

/// 下载页路由模块（与 `modules/download/download_module.dart` 的 Hive 数据模型区分）。
final downloadPageModule = createModule(
  path: '/download',
  register: (c) {
    c.route(
      '/',
      child: (context, state) => DownloadPage(
        controller: inject<DownloadController>(),
      ),
    );
  },
);
