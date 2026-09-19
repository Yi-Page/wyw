import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/pages/js_dev/js_dev_controller.dart';
import 'package:wyw/pages/js_dev/js_dev_page.dart';

/// JS 脚本测试台模块。
///
/// [JsDevController]（脚本引擎 + 日志状态）为路由级 Store 单例，由本模块 provide。
final jsDevModule = createModule(
  path: '/js-dev',
  register: (c) {
    c.route(
      '/',
      provide: (s) => s.add<JsDevController>(JsDevController.new),
      child: (context, state) =>
          JsDevPage(controller: context.read<JsDevController>()),
    );
  },
);
