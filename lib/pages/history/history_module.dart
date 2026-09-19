import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/pages/history/history_page.dart';
import 'package:wyw/pages/history/plugin_history_controller.dart';
import 'package:wyw/repositories/plugin_history_repository.dart';

final historyModule = createModule(
  path: '/history',
  register: (c) {
    c
      ..addSingleton<PluginHistoryController>(
        () => PluginHistoryController(inject<PluginHistoryRepository>()),
      )
      ..route(
        '/',
        child: (context, state) => const HistoryPage(),
      )
      ..route(
        '/browse',
        child: (context, state) =>
            const HistoryPage(initialTab: HistoryTab.browse),
      )
      ..route(
        '/progress',
        child: (context, state) =>
            const HistoryPage(initialTab: HistoryTab.progress),
      );
  },
);
