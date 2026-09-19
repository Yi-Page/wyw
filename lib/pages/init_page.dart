import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/pages/download/download_controller.dart';
import 'package:wyw/pages/video/play_intent.dart';
import 'package:wyw/pages/video/video_route_args.dart';
import 'package:wyw/services/history/history_progress_reporter.dart';
import 'package:wyw/services/storage/video_play_model.dart';
import 'package:wyw/repositories/history_repository.dart';
import 'package:wyw/repositories/plugin_history_repository.dart';
import 'package:wyw/services/storage/history_progress.dart';
import 'package:wyw/services/storage/history_type.dart';
import 'package:wyw/services/storage/storage.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/shaders/shader_asset_service.dart';
import 'package:wyw/services/download/background_download_service.dart';
import 'package:wyw/services/platform/windows_shortcut.dart';
import 'package:wyw/services/platform/platform_environment_service.dart';
import 'package:wyw/utils/open_external_browser.dart';

import 'package:wyw/js/js_extends/js_bridge.dart';
import 'package:wyw/js/script_engine.dart';
import 'package:wyw/navigation.dart';
import 'package:wyw/pages/plugin/plugin_controller.dart';
import 'package:wyw/pages/novel_reader/novel_reader_page.dart';
import 'package:wyw/pages/novel_reader/models/novel_reader_types.dart';
import 'package:wyw/pages/comic_reader/image/image_downloader.dart';
import 'package:wyw/pages/comic_reader/comic_reader_page.dart';
import 'package:wyw/pages/comic_reader/models/comic_reader_types.dart';
import 'package:wyw/pages/descriptor/descriptor_page.dart';
import 'package:wyw/pages/webview/webview_page.dart';
import 'package:wyw/pages/search/search_controller.dart';

// ============================================================================
// 初始化页面
// 负责应用启动时的各项初始化工作
// ============================================================================

class InitPage extends StatefulWidget {
  const InitPage({
    super.key,
    required this.pluginsController,
    required this.shaderAssetService,
  });

  final PluginController pluginsController;
  final ShaderAssetService shaderAssetService;

  @override
  State<InitPage> createState() => _InitPageState();
}

class _InitPageState extends State<InitPage> {
  PluginController get pluginsController => widget.pluginsController;

  ShaderAssetService get shaderAssetService => widget.shaderAssetService;

  SearchPageController get searchController => inject<SearchPageController>();

  PluginHistoryRepository get historyRepository =>
      inject<PluginHistoryRepository>();

  ScriptEngine? _jsEngine;

  /// 应用自带进度历史（Hive 后端，与视频历史同一套实体/仓库）。
  late final HistoryRepository _historyRepo =
      HistoryRepository(box: GStorage.histories);

  /// 漫画封面缓存（key=comicId，值=封面 URL，来源：插件浏览历史）。
  final Map<String, String> _comicCoverCache = {};

  @override
  void initState() {
    super.initState();
    unawaited(_initializeApp());
  }

  Future<void> _initializeApp() async {
    _loadShaders();

    await _checkRunningOnX11();
    await _pluginInit();
    await _showShortcutDialog();
    _loadHistory();
    await _loadJsEngine();
    _setupJsBridges();
    try {
      await inject<DownloadController>().init();
      _setupBackgroundDownloadNavigation();
    } catch (e) {
      WywLogger().e('${LogTag.app} 初始化下载控制器失败', error: e);
    }

    if (!mounted) {
      return;
    }
    _startDefaultPage();
    // delay to ensure that the default page is fully loaded
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) {
      return;
    }
  }

  /// 配置后台下载通知的跳转与通知权限回调
  void _setupBackgroundDownloadNavigation() {
    final backgroundService = BackgroundDownloadService();

    backgroundService.onNavigateToDownloadRequested = () {
      Future.delayed(const Duration(milliseconds: 300), () {
        try {
          final navigationContext = rootNavigatorKey.currentContext;
          if (navigationContext == null || !navigationContext.mounted) return;
          navigationContext.pushNamed('/settings/download/');
        } catch (e) {
          WywLogger().w('${LogTag.app} 跳转下载设置页失败', error: e);
        }
      });
    };

    backgroundService.onNotificationPermissionRequired = () async {
      final result = await WywDialog.show<bool>(
        clickMaskDismiss: false,
        builder: (context) {
          return AlertDialog(
            title: const Text('需要通知权限'),
            content: const Text(
              '开启通知权限后，可以在后台下载时显示进度，并防止系统终止下载任务。\n\n'
              '如果拒绝，下载功能仍可使用，但在后台时可能被系统中断。',
            ),
            actions: [
              TextButton(
                onPressed: () => WywDialog.dismiss(popWith: false),
                child: Text(
                  '稍后再说',
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.outline),
                ),
              ),
              TextButton(
                onPressed: () => WywDialog.dismiss(popWith: true),
                child: const Text('开启'),
              ),
            ],
          );
        },
      );
      return result ?? false;
    };
  }

  /// 启动默认页面
  void _startDefaultPage() {
    final defaultStartupPage =
        GStorage.getSetting(SettingsKeys.defaultStartupPage);
    if (!mounted) {
      return;
    }
    context.navigate(defaultStartupPage);
  }

  Future<void> _loadShaders() async {
    await shaderAssetService.copyShadersToExternalDirectory();
  }

  void _loadHistory() async {
    try {
      historyRepository.init();
    } catch (e, s) {
      WywLogger().e('${LogTag.app} 播放历史加载失败', error: e, stackTrace: s);
    }
    // v2 → v3 进度历史就地迁移（幂等，仅视频旧条目）
    try {
      unawaited(_historyRepo.migrateV3());
    } catch (e, s) {
      WywLogger().e('${LogTag.app} 播放历史 v2→v3 迁移失败（migrateV3）',
          error: e, stackTrace: s);
    }
  }

  /// 初始化 JS 引擎
  Future<void> _loadJsEngine() async {
    _jsEngine = ScriptEngine();
    await _jsEngine!.init();
  }

  /// 设置 JS 引擎的 Dart 桥接回调
  void _setupJsBridges() {
    // Toast 提示
    JSEngineCommonApi.onShowToast = (String msg) {
      WywDialog.showToast(message: msg);
    };

    // 外部浏览器打开链接（宿主弹确认框，确认后才打开）
    JSEngineCommonApi.onOpenExternalBrowser = (String url) {
      unawaited(openExternalBrowserWithConfirm(url));
    };

    // 跳转视频播放页面（含播放方式决策层：决策完成后才进入播放页）
    JSEngineCommonApi.onNavigateToVideo = (String videoUrl,
        {String? title,
        String? cover,
        String? videoId,
        String? sourceKey,
        int? initialSource,
        int? initialEpisode,
        List<Map<String, dynamic>>? sources}) async {
      final ctx = rootNavigatorKey.currentState?.context;
      if (ctx == null) return;
      final effectiveTitle =
          (title != null && title.isNotEmpty) ? title : videoUrl;
      // 结构化进入：插件一次传入完整播放源列表（含集数/直链/resolve 描述）
      if (sources == null || sources.isEmpty) return;
      final playSources =
          sources.map((m) => VideoPlaySource.fromMap(m)).toList();
      final effectiveVideoId =
          (videoId != null && videoId.isNotEmpty) ? videoId : videoUrl;
      final effectiveSourceKey = sourceKey ?? '';

      // 定位初始集（决策对象）
      final initialSourceIndex =
          (initialSource ?? 0).clamp(0, playSources.length - 1);
      final initialEpisodes = playSources[initialSourceIndex].episodes;
      final initialEpisodeIndex =
          (initialEpisode ?? 0).clamp(0, initialEpisodes.length - 1);
      final initialEpisode0 = initialEpisodes[initialEpisodeIndex];

      // ① 历史合并：取该集缓存直链与续播位置（决策输入；页内 configure 会再全量合并）
      var cachedUrl = initialEpisode0.resolvedUrl;
      var offsetMs = 0;
      final historySourceId = effectiveSourceKey.isEmpty
          ? effectiveVideoId
          : '$effectiveSourceKey:$effectiveVideoId';
      final historyEntry = HistoryProgressReporter()
          .findEntry(type: HistoryType.video, sourceId: historySourceId);
      if (historyEntry != null) {
        final history = historyEntry.parseProgress();
        if (history is VideoPlaybackProgress) {
          final histSrc = initialSourceIndex < history.sources.length
              ? history.sources[initialSourceIndex]
              : null;
          final histEp =
              (histSrc != null && initialEpisodeIndex < histSrc.episodes.length)
                  ? histSrc.episodes[initialEpisodeIndex]
                  : null;
          cachedUrl = histEp?.resolvedUrl ?? cachedUrl;
          offsetMs = histEp?.positionMs ?? 0;
        }
      }

      // ② 决策（弹窗 / 「只下载」副作用都在决策层内完成）
      final decision = await PlayIntentDecider.decide(
        context: ctx,
        path: initialEpisode0.path,
        sourceKey: effectiveSourceKey,
        videoId: effectiveVideoId,
        sourceIndex: initialSourceIndex,
        episodeIndex: initialEpisodeIndex,
        episodeName: initialEpisode0.name,
        sourceName: playSources[initialSourceIndex].name,
        videoTitle: effectiveTitle,
        videoCover: cover ?? '',
        cachedUrl: cachedUrl,
      );
      if (decision == null || !ctx.mounted) return; // 暂不播放 / 只下载已完成

      // ③ 进播放页（携带决策产物：播放方式 + 静默代理开关）
      final args = VideoPageRouteArgs(
        videoId: effectiveVideoId,
        title: effectiveTitle,
        cover: cover ?? '',
        sourceKey: sourceKey,
        sources: playSources,
        initialSource: initialSourceIndex,
        initialEpisode: initialEpisodeIndex,
        offsetMs: offsetMs,
        playMode: decision.mode,
        allowProxyPlayback: decision.allowProxyPlayback,
        onProgressChanged: (progress) {
          // 播放页回吐整部剧进度 → 写进度历史（sourceId 统一规则）
          _historyRepo.setProgress(
            type: HistoryType.video,
            sourceId: (sourceKey == null || sourceKey.isEmpty)
                ? effectiveVideoId
                : '$sourceKey:$effectiveVideoId',
            title: effectiveTitle,
            cover: cover ?? '',
            progress: progress.toMap(),
          );
        },
      );
      ctx.pushNamed('/video/', arguments: args);
    };

    // 跳转 WebView 页面
    JSEngineCommonApi.onNavigateToWebview = (String url) {
      final ctx = rootNavigatorKey.currentState?.context;
      if (ctx == null) return;
      ctx.pushNamed('/webview/', arguments: WebviewPageRouteArgs(url: url));
    };

    // 跳转漫画阅读器页面（从 JS 插件进入）
    JSEngineCommonApi.onNavigateToReader = (
      String comicId,
      String comicTitle,
      List<Map<String, dynamic>> chapters, {
      String? sourceKey,
      int initialChapter = 1,
      int initialPage = 1,
    }) {
      final ctx = rootNavigatorKey.currentState?.context;
      if (ctx == null) return;
      if (chapters.isEmpty) return;
      // 用与视频一致的 History 体系存漫画进度。
      // sourceId 用 `sourceKey:comicId` 复合键，避免跨源 comicId 冲突。
      final comicSourceId = sourceKey == null ? comicId : '$sourceKey:$comicId';
      // 注意：从插件进入阅读器不自动恢复上次进度（漫画阅读习惯通常是
      // 从插件指定的话从头看）；续读统一走历史页（history_page 卡片点击）。
      // 预取封面（从插件浏览历史），供进度历史卡片展示。
      if (sourceKey != null && !_comicCoverCache.containsKey(comicId)) {
        unawaited(_prefetchComicCover(sourceKey, comicId));
      }
      ctx.pushNamed(
        ComicReaderPage.routePath,
        arguments: ComicReaderPageRouteArgs(
          comicId: comicId,
          comicTitle: comicTitle,
          chapters: [for (final c in chapters) _chapterFromMap(c)],
          initialChapter: initialChapter,
          initialPage: initialPage,
          sourceKey: sourceKey,
          // 进入自动定位到上次看的章/页（插件指定章/页优先时仍可传参覆盖）
          autoResume: true,
          // 保存阅读进度（翻页/切章/图片加载完成时触发）
          onProgressChanged: (progress) {
            if (sourceKey == null) return;
            // 逐章进度：每章独立记录，规范单位是图片序号 + 水位线
            // （pageIndex/maxPage 保留给旧版本读取）
            final chapterProgress = [
              for (final cp in progress.chapterProgress)
                {
                  'chapterId': cp.chapterId,
                  'imageIndex': cp.imageIndex,
                  'imageCount': cp.imageCount,
                  'seenUpToImage': cp.seenUpToImage,
                  'pageIndex': cp.pageIndex,
                  'maxPage': cp.maxPage
                },
            ];
            _historyRepo.setProgress(
              type: HistoryType.comic,
              sourceId: comicSourceId,
              title: comicTitle,
              cover: _comicCoverCache[comicId] ?? '',
              progress: ComicProgress(
                chapterId: progress.chapterId,
                pageIndex: progress.page,
                // 存下重新进入阅读器的完整参数，供历史页直接续读
                comicId: comicId,
                comicTitle: comicTitle,
                sourceKey: sourceKey,
                chapters: chapters,
                chapterProgress: chapterProgress,
                lastChapterIndex: progress.chapter - 1,
              ).toMap(),
            );
          },
        ),
      );
    };

    // 跳转小说阅读器页面（从 JS 插件进入）
    JSEngineCommonApi.onNavigateToNovelReader = (
      String novelId,
      String novelTitle,
      List<Map<String, dynamic>> chapters, {
      String? sourceKey,
      int initialChapter = 1,
    }) {
      final ctx = rootNavigatorKey.currentState?.context;
      if (ctx == null) return;
      if (chapters.isEmpty) return;
      // 与漫画一致：sourceId 用 `sourceKey:novelId` 复合键，避免跨源 novelId 冲突。
      final novelSourceId = sourceKey == null ? novelId : '$sourceKey:$novelId';
      ctx.pushNamed(
        NovelReaderPage.routePath,
        arguments: NovelReaderPageRouteArgs(
          novelId: novelId,
          novelTitle: novelTitle,
          chapters: [for (final c in chapters) _novelChapterFromMap(c)],
          initialChapter: initialChapter,
          sourceKey: sourceKey,
          // 保存阅读进度（切章/滚动时触发）
          onProgressChanged: (progress) {
            if (sourceKey == null) return;
            _historyRepo.setProgress(
              type: HistoryType.novel,
              sourceId: novelSourceId,
              title: novelTitle,
              progress: {
                'chapterId': progress.chapterId,
                'chapter': progress.chapter,
                'scrollY': progress.scrollY,
                'charOffset': progress.charOffset,
                'novelId': novelId,
                'novelTitle': novelTitle,
                'sourceKey': sourceKey,
                'chapters': chapters,
              },
            );
          },
        ),
      );
    };

    // 阅读器图片加载配置：调用插件的 getImageLoadingConfig(url, comicId, epId)
    // 拿自定义 headers / modifyImage 还原脚本等（对应 venera 的 comic.onImageLoad）
    ImageDownloader.fetchImageLoadingConfig = (
      String sourceKey,
      String imageKey,
      String cid,
      String eid,
    ) async {
      final plugin = pluginsController.getPlugin(sourceKey);
      if (plugin == null || !plugin.isRegistered) return {};
      try {
        final raw = await plugin.invoke('getImageLoadingConfig', [
          imageKey,
          cid,
          eid,
        ]);
        if (raw is Map) return Map<String, dynamic>.from(raw);
      } catch (e) {
        WywLogger()
            .w('${LogTag.app} 获取图片加载配置失败 sourceKey=$sourceKey', error: e);
      }
      return {};
    };

    // JS 描述符按钮跳转到 descriptor 页面（JS 边界仍是 Map，进路由前收敛为强类型）
    JSEngineCommonApi.onNavigateToDescriptor = (Map<String, dynamic> args) {
      final ctx = rootNavigatorKey.currentState?.context;
      if (ctx == null) return;
      ctx.pushNamed(
        '/descriptor/',
        arguments: DescriptorPageRouteArgs.fromRawMap(args),
      );
    };
  }

  /// 把 JS 传来的章节描述转成 [ComicReaderChapter]。
  ///
  /// 两种形态：
  /// - `{id, title, images: [url...]}`：预加载图片列表
  /// - `{id, title, plugin, method, args}`：惰性加载——切章时通过插件执行方法取图片
  ComicReaderChapter _chapterFromMap(Map<String, dynamic> c) {
    final images = (c['images'] as List?)?.whereType<String>().toList();
    final pluginName = c['plugin'] as String?;
    final method = c['method'] as String?;
    final args = (c['args'] as List?) ?? const [];
    return ComicReaderChapter(
      id: c['id'] as String? ?? '',
      title: c['title'] as String? ?? '',
      images: images,
      loadImages: (images == null && pluginName != null && method != null)
          ? () => _loadChapterImagesFromPlugin(pluginName, method, args)
          : null,
    );
  }

  /// 把 JS 传来的小说章节描述转成 [NovelReaderChapter]。
  ///
  /// 两种形态：
  /// - `{id, title, content}`：预加载正文文本
  /// - `{id, title, plugin, method, args}`：惰性加载——切章时通过插件执行方法取正文
  NovelReaderChapter _novelChapterFromMap(Map<String, dynamic> c) {
    final content = c['content'] as String?;
    final pluginName = c['plugin'] as String?;
    final method = c['method'] as String?;
    final args = (c['args'] as List?) ?? const [];
    return NovelReaderChapter(
      id: c['id'] as String? ?? '',
      title: c['title'] as String? ?? '',
      content: content,
      loadContent: (content == null && pluginName != null && method != null)
          ? () => _loadNovelContentFromPlugin(pluginName, method, args)
          : null,
    );
  }

  /// 惰性加载：通过插件执行方法获取章节正文。
  Future<String> _loadNovelContentFromPlugin(
    String pluginName,
    String method,
    List<dynamic> args,
  ) async {
    final plugin = pluginsController.getPlugin(pluginName);
    if (plugin == null || !plugin.isRegistered) {
      throw '插件 $pluginName 未注册';
    }
    final raw = await plugin.invoke(method, args);
    if (raw is String) {
      return raw;
    }
    throw '插件 $pluginName.$method 未返回正文文本';
  }

  /// 从插件浏览历史预取漫画封面（供进度历史卡片展示）。
  Future<void> _prefetchComicCover(String sourceKey, String comicId) async {
    try {
      final entry = await historyRepository.find(
        pluginName: sourceKey,
        id: comicId,
      );
      if (entry != null && entry.cover.isNotEmpty) {
        _comicCoverCache[comicId] = entry.cover;
      }
    } catch (e) {
      WywLogger()
          .d('${LogTag.app} 预取漫画封面失败（已忽略，不影响进度保存） comicId=$comicId', error: e);
    }
  }

  /// 惰性加载：通过插件执行方法获取图片 URL 列表。
  Future<List<String>> _loadChapterImagesFromPlugin(
    String pluginName,
    String method,
    List<dynamic> args,
  ) async {
    final plugin = pluginsController.getPlugin(pluginName);
    if (plugin == null || !plugin.isRegistered) {
      throw '插件 $pluginName 未注册';
    }
    final raw = await plugin.invoke(method, args);
    if (raw is List) {
      return raw.map((e) => e is String ? e : e.toString()).toList();
    }
    throw '插件 $pluginName.$method 未返回图片列表';
  }

  Future<void> _checkRunningOnX11() async {
    if (!Platform.isLinux) {
      return;
    }
    bool isRunningOnX11 = await PlatformEnvironmentService.isRunningOnX11();
    if (isRunningOnX11) {
      await WywDialog.show(
        clickMaskDismiss: false,
        builder: (context) {
          return PopScope(
            canPop: false,
            child: AlertDialog(
              title: const Text('X11环境检测'),
              content: const Text(
                  '检测到您当前运行在X11环境下，Wyw在X11环境下可能出现性能问题或界面异常，建议切换到Wayland以获得更好的体验。您是否希望在X11下继续使用Wyw？'),
              actions: [
                TextButton(
                  onPressed: () {
                    exit(0);
                  },
                  child: Text(
                    '退出',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.outline),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    WywDialog.dismiss();
                  },
                  child: const Text('继续'),
                ),
              ],
            ),
          );
        },
      );
    }
  }

  Future<void> _showShortcutDialog() async {
    if (!Platform.isWindows) return;
    if (GStorage.getSetting(SettingsKeys.shortcutDialogShown)) {
      return;
    }

    final create = await WywDialog.show<bool>(
      clickMaskDismiss: false,
      builder: (context) => AlertDialog(
        title: const Text('创建桌面快捷方式'),
        content: const Text('是否在桌面创建 Wyw 的快捷方式？'),
        actions: [
          TextButton(
            onPressed: () => WywDialog.dismiss(popWith: false),
            child: Text('暂不创建',
                style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          ),
          TextButton(
            onPressed: () => WywDialog.dismiss(popWith: true),
            child: const Text('创建'),
          ),
        ],
      ),
    );

    await GStorage.putSetting(SettingsKeys.shortcutDialogShown, true);
    if (create ?? false) {
      final success = await WindowsShortcut.createDesktopShortcut();
      WywDialog.showToast(message: success ? '桌面快捷方式已创建' : '桌面快捷方式创建失败');
    }
  }

  Future<void> _pluginInit() async {
    try {
      await pluginsController.init();
      await searchController.init();
    } catch (e, s) {
      WywLogger().e('${LogTag.app} 插件初始化失败', error: e, stackTrace: s);
    }
  }

  // ==========================================================================
  // UI
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    return const LoadingWidget();
  }
}

class LoadingWidget extends StatelessWidget {
  const LoadingWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Container());
  }
}
