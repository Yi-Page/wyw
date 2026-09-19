import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/pages/download/download_controller.dart';
import 'package:wyw/pages/history/history_controller.dart';
import 'package:wyw/pages/browse/browse_controller.dart';
import 'package:wyw/pages/plugin/plugin_controller.dart';
import 'package:wyw/pages/search/search_controller.dart';
import 'package:wyw/pages/video/video_controller.dart';
import 'package:wyw/repositories/download_repository.dart';
import 'package:wyw/repositories/history_repository.dart';
import 'package:wyw/repositories/i_history_repository.dart';
import 'package:wyw/repositories/plugin_history_repository.dart';
import 'package:wyw/services/download/download_manager.dart';
import 'package:wyw/services/player/audio_controller.dart';
import 'package:wyw/services/shaders/shader_asset_service.dart';
import 'package:wyw/services/storage/storage.dart';

/// Root-owned application data and cross-feature coordinators.
///
/// Registers the application-wide singletons that downstream modules reach
/// through [Modular.get] / [inject]. Anything that survives the whole session
/// (player, settings, JS engine, shader assets, etc.) lives here.
final coreModule = createModule(
  register: (c) {
    c
      // Repository layer (v2 universal history).
      // 实际注入到 JS 桥由 ProductionScriptEngine.init() 完成（需要 pluginName resolver）
      ..addSingleton<IHistoryRepository>(
        () => HistoryRepository(
          box: GStorage.histories,
        ),
      )
      // 插件浏览历史（JSON 文件后端，与 IHistoryRepository 完全独立）
      ..addSingleton<PluginHistoryRepository>(PluginHistoryRepository.new)
      // 视频下载
      ..addSingleton<IDownloadRepository>(DownloadRepository.new)
      ..addSingleton<IDownloadManager>(DownloadManager.new)
      // Service layer.
      ..addSingleton<AudioController>(AudioController.new)
      ..addSingleton<ShaderAssetService>(ShaderAssetService.new)
      // 分类浏览 Tab 状态（应用级单例）
      ..addSingleton<BrowseController>(BrowseController.new)
      // Cross-feature state and coordinators.
      ..addSingleton<PluginController>(PluginController.new)
      ..addSingleton<SearchPageController>(SearchPageController.new)
      ..addSingleton<HistoryController>(HistoryController.new)
      ..addSingleton<VideoPageController>(VideoPageController.new)
      ..addSingleton<DownloadController>(DownloadController.new);
  },
);
