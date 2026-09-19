import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/pages/player/player_controller.dart';
import 'package:wyw/pages/video/video_page.dart';
import 'package:wyw/pages/video/video_controller.dart';
import 'package:wyw/pages/video/video_route_args.dart';

/// 播放页模块：注册 /video 路由。
///
/// [PlayerController] 为路由级 Store 单例，进入路由时由本模块 provide。
/// 路由参数 `VideoPageRouteArgs`（结构化播放源列表 + 初始源/集）在
/// 页面构建时解析并 configure 注入 [VideoPageController]。
final videoModule = createModule(
  path: '/video',
  register: (c) {
    c.route(
      '/',
      provide: (s) => s.add<PlayerController>(PlayerController.new),
      child: (context, state) {
        final args = state.arguments;
        return VideoPage(
          playerController: context.read<PlayerController>(),
          videoPageController: inject<VideoPageController>(),
          args: args is VideoPageRouteArgs ? args : null,
        );
      },
    );
  },
);
