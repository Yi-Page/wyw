import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/pages/collect/collect_controller.dart';
import 'package:wyw/pages/collect/collect_page.dart';
import 'package:wyw/repositories/collect_repository.dart';

/// 收藏模块（单路由页面，不在底部/侧边导航里；从「我的」页进入）。
final collectModule = createModule(
  path: '/collect',
  register: (c) {
    c
      ..addSingleton<CollectController>(
        () => CollectController(inject<CollectRepository>()),
      )
      ..route(
        '/',
        child: (context, state) => const CollectPage(),
      );
  },
);
