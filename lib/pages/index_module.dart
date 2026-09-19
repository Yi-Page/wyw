import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/bean/widget/image_preview.dart';
import 'package:wyw/pages/browse/browse_module.dart';
import 'package:wyw/pages/history/history_module.dart';
import 'package:wyw/pages/index_page.dart';
import 'package:wyw/pages/init_page.dart';
import 'package:wyw/pages/my/my_module.dart';
import 'package:wyw/pages/novel_reader/novel_reader_module.dart';
import 'package:wyw/pages/plugin/plugin_controller.dart';
import 'package:wyw/pages/comic_reader/comic_reader_module.dart';
import 'package:wyw/pages/route_error_page.dart';
import 'package:wyw/pages/search/search_module.dart';
import 'package:wyw/pages/settings/settings_module.dart';
import 'package:wyw/pages/video/video_module.dart';
import 'package:wyw/pages/webview/webview_module.dart';
import 'package:wyw/services/shaders/shader_asset_service.dart';
import 'package:wyw/services/storage/storage.dart';

import 'descriptor/descriptor_module.dart';
import 'js_dev/js_dev_module.dart';

final _tabTransition = CustomTransition(
  duration: const Duration(milliseconds: 70),
  transitionsBuilder: (context, animation, secondaryAnimation, child) {
    return FadeTransition(opacity: animation, child: child);
  },
);

final _imagePreviewTransition = CustomTransition(
  duration: const Duration(milliseconds: 220),
  transitionsBuilder: (context, animation, secondaryAnimation, child) {
    return FadeTransition(opacity: animation, child: child);
  },
);

final tabModule = createModule(
  path: '/tab',
  register: (c) {
    c.route(
      '/',
      child: (context, state) => const IndexPage(),
      transition: _tabTransition,
      children: (sub) {
        sub
          ..route(
            '/',
            guards: [
              (state) => GStorage.getSetting(SettingsKeys.defaultStartupPage),
            ],
            child: (context, state) => const SizedBox.shrink(),
          )
          ..module(searchModule)
          ..module(browseModule)
          ..module(myModule);
      },
    );
  },
);

/// 应用根模块
///
/// 负责应用初始化入口（[InitPage]）、Tab 框架、播放器、设置、详情页等顶层路由。
final indexModule = createModule(
  register: (c) {
    c
      ..route(
        '/',
        child: (context, state) => InitPage(
          pluginsController: inject<PluginController>(),
          shaderAssetService: inject<ShaderAssetService>(),
        ),
        transition: TransitionType.none,
      )
      ..route(
        '/error',
        child: (context, state) =>
            const RouteErrorPage(message: '初始化失败'),
      )
      ..module(tabModule)
      ..module(videoModule)
      ..module(historyModule)
      ..module(webviewModule)
      ..module(jsDevModule)
      ..module(descriptorModule)
      ..route(
        ImageViewer.routePath,
        child: (context, state) {
          final args = state.arguments;
          if (args is! ImageViewerRouteArgs) {
            return const RouteErrorPage(message: '图片预览参数无效，请返回后重试。');
          }
          return ImageViewer(
            imageUrls: args.imageUrls,
            initialIndex: args.initialIndex,
            heroTag: args.heroTag,
          );
        },
        transition: _imagePreviewTransition,
      )
      ..module(comicReaderModule)
      ..module(novelReaderModule)
      ..module(settingsModule);
  },
);
