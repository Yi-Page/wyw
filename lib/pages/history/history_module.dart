import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/pages/history/history_page.dart';

/// 进度历史模块（应用自带资源的观看/阅读进度）。
///
/// 插件浏览历史已移入收藏模块（`/collect/` 的「全部」tab），所以这里不再有
/// `/browse` 直达路由；`/progress` 保留为语义直达别名。
final historyModule = createModule(
  path: '/history',
  register: (c) {
    c
      ..route(
        '/',
        child: (context, state) => const HistoryPage(),
      )
      ..route(
        '/progress',
        child: (context, state) => const HistoryPage(),
      );
  },
);
