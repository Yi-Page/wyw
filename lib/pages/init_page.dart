import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_qjs/flutter_qjs.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/pages/download/download_controller.dart';
import 'package:wyw/pages/video/video_entry_launcher.dart';
import 'package:wyw/services/storage/video_play_model.dart';
import 'package:wyw/repositories/collect_repository.dart';
import 'package:wyw/repositories/history_repository.dart';
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

  CollectRepository get collectRepository => inject<CollectRepository>();

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
      collectRepository.init();
    } catch (e, s) {
      WywLogger().e('${LogTag.app} 收藏条目加载失败', error: e, stackTrace: s);
    }
    // 旧 JSON 后端 → Hive 的一次性迁移（幂等；失败保留旧文件，下次重试）
    try {
      unawaited(collectRepository.migrateFromJsonIfNeeded());
    } catch (e, s) {
      WywLogger().e('${LogTag.app} 收藏条目迁移失败（JSON → Hive）',
          error: e, stackTrace: s);
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

    // 通用对话框（venera 的 UI.showDialog）：每个按钮点击后回调对应的 JS 函数
    JSEngineCommonApi.onShowDialog = ({
      required String title,
      required String content,
      List<Map<String, dynamic>> actions = const [],
    }) {
      unawaited(WywDialog.show<void>(
        clickMaskDismiss: false,
        builder: (ctx) => AlertDialog(
          title: title.isEmpty ? null : Text(title),
          content: content.isEmpty
              ? null
              : SingleChildScrollView(child: Text(content)),
          actions: [
            for (final a in actions)
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _invokeJsCallback(a['callback']);
                },
                child: Text(a['text']?.toString() ?? '确定'),
              ),
          ],
        ),
      ));
    };

    // 输入框（venera 的 UI.showInputDialog）：返回输入文本，取消返回 null。
    // 支持插件传入图片（URL 字符串或 ArrayBuffer 字节，如 ccc 的验证码）。
    JSEngineCommonApi.onShowInputDialog = ({
      required String title,
      Object? image,
      Object? validator,
    }) async {
      // 用 TextFormField 而不是外部 TextEditingController：`showDialog` 的 future
      // 在**路由 pop 时**就完成了，但退场动画期间 TextField 仍挂在树上；此时
      // dispose 外部 controller 会让动画中的 TextField 摸到已销毁的 ChangeNotifier
      // （TextEditingController was used after being disposed）。
      // TextFormField 自带内部 controller，随 widget 一起销毁，没有这个时序问题。
      var text = '';
      String? error;
      return WywDialog.show<String>(
        clickMaskDismiss: false,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) {
            void confirm() {
              final msg = _runJsValidator(validator, text);
              if (msg != null) {
                setLocal(() => error = msg);
                return;
              }
              Navigator.of(ctx).pop(text);
            }

            return AlertDialog(
              title: title.isEmpty ? null : Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDialogImage(image),
                  TextFormField(
                    initialValue: '',
                    autofocus: true,
                    cursorColor: Theme.of(ctx).colorScheme.primary,
                    onChanged: (v) => text = v,
                    decoration: InputDecoration(
                      hintText: '请输入',
                      errorText: error,
                    ),
                    onFieldSubmitted: (_) => confirm(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('取消'),
                ),
                TextButton(onPressed: confirm, child: const Text('确定')),
              ],
            );
          },
        ),
      );
    };

    // 选择框（venera 的 UI.showSelectDialog）：返回选中下标，取消返回 null
    JSEngineCommonApi.onShowSelectDialog = ({
      required String title,
      required List<String> options,
      int? initialIndex,
    }) async {
      if (options.isEmpty) return null;
      return WywDialog.show<int>(
        builder: (ctx) => SimpleDialog(
          title: title.isEmpty ? null : Text(title),
          children: [
            for (var i = 0; i < options.length; i++)
              SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(options[i]),
                ),
              ),
          ],
        ),
      );
    };

    // 加载中对话框（venera 的 UI.showLoading / cancelLoading）
    JSEngineCommonApi.onShowLoading = ({Object? onCancel}) {
      final nav = rootNavigatorKey.currentState;
      if (nav == null) return -1;
      final id = ++_loadingDialogSeq;
      _loadingDialogs[id] = nav;
      unawaited(showDialog<void>(
        context: nav.context,
        barrierDismissible: false,
        builder: (_) => const PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 16),
                Expanded(child: Text('加载中…')),
              ],
            ),
          ),
        ),
      ));
      return id;
    };
    JSEngineCommonApi.onCancelLoading = (int id) {
      final nav = _loadingDialogs.remove(id);
      if (nav != null && nav.canPop()) nav.pop();
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
      // 结构化进入：插件一次传入完整播放源列表（含集数/直链/resolve 描述）。
      // 参数处理（历史回填 / 决策弹窗 / 构造路由参数）统一交给编排层，
      // 本处只做 JS 边界的数据整形。
      if (sources == null || sources.isEmpty) return;
      final effectiveVideoId =
          (videoId != null && videoId.isNotEmpty) ? videoId : videoUrl;
      await VideoEntryLauncher(ctx).openFromPlugin(
        pluginName: sourceKey ?? '',
        videoId: effectiveVideoId,
        title: effectiveTitle,
        cover: cover ?? '',
        sources: sources.map((m) => VideoPlaySource.fromMap(m)).toList(),
        initialSource: initialSource ?? 0,
        initialEpisode: initialEpisode ?? 0,
      );
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
      if (plugin == null || !plugin.isLoaded) return {};
      // 基类不再给能力方法留空实现，所以未实现的插件直接跳过（省一次必然失败的
      // invoke + 一条用不到的告警日志）；实现的才真调。
      if (!await pluginsController.hasMethod(sourceKey, 'getImageLoadingConfig')) {
        return {};
      }
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

  /// 加载中对话框的 id 序号与「id → NavigatorState」映射（供 cancelLoading 关闭）。
  int _loadingDialogSeq = 0;
  final Map<int, NavigatorState> _loadingDialogs = {};

  /// 调用 JS 传过来的回调函数（对话框按钮点击）。
  ///
  /// JS 函数跨到 Dart 侧是 [JSInvokable]；调用失败不应影响宿主（仅记日志）。
  void _invokeJsCallback(Object? callback) {
    if (callback == null) return;
    try {
      if (callback is JSInvokable) {
        callback.invoke(const []);
      } else if (callback is Function) {
        callback();
      }
    } catch (e, s) {
      WywLogger().w('${LogTag.js} 调用 JS 对话框回调失败', error: e, stackTrace: s);
    }
  }

  /// 调用插件传入的 JS 输入校验函数；返回非空字符串表示错误提示。
  ///
  /// 校验函数不可调用时放行 —— 不因宿主实现差异阻断用户输入。
  String? _runJsValidator(Object? validator, String text) {
    if (validator == null) return null;
    try {
      final r = validator is JSInvokable ? validator.invoke([text]) : null;
      if (r is String && r.isNotEmpty) return r;
    } catch (e, s) {
      WywLogger()
          .d('${LogTag.js} 调用 JS 输入校验函数失败（已忽略）', error: e, stackTrace: s);
    }
    return null;
  }

  /// 对话框内的图片：支持 URL 字符串或字节（ArrayBuffer → Uint8List）。
  /// 无法识别或加载失败时返回空 widget（不阻断输入）。
  Widget _buildDialogImage(Object? image) {
    if (image is String && image.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Image.network(
          image,
          height: 80,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      );
    }
    if (image is Uint8List && image.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Image.memory(
          image,
          height: 80,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      );
    }
    return const SizedBox.shrink();
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
    if (plugin == null || !plugin.isLoaded) {
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
      final entry = await collectRepository.find(
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
    if (plugin == null || !plugin.isLoaded) {
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
