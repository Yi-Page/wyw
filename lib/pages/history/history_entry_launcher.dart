// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/bean/dialog/adaptive_bottom_sheet.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/bean/widget/video_episode_panel.dart';
import 'package:wyw/pages/comic_reader/comic_reader_page.dart';
import 'package:wyw/pages/comic_reader/models/comic_reader_types.dart';
import 'package:wyw/pages/download/download_controller.dart';
import 'package:wyw/pages/novel_reader/models/novel_reader_types.dart';
import 'package:wyw/pages/novel_reader/novel_reader_page.dart';
import 'package:wyw/pages/plugin/plugin_controller.dart';
import 'package:wyw/pages/video/video_route_args.dart';
import 'package:wyw/repositories/i_history_repository.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/services/storage/history_entry.dart';
import 'package:wyw/services/storage/history_progress.dart';
import 'package:wyw/services/storage/history_type.dart';
import 'package:wyw/services/storage/video_play_model.dart';
import 'package:wyw/services/video_source/resolution_service.dart';

/// 历史条目启动器：从 [HistoryEntry] 恢复上次进度。
///
/// 原先内联在进度历史卡片 State 中的续播/续读导航逻辑，抽到此处在
/// 进度历史卡片与「继续观看」置顶横滑区两处复用。
class HistoryEntryLauncher {
  HistoryEntryLauncher(this.context, this.entry);

  final BuildContext context;
  final HistoryEntry entry;

  /// 按类型分发：漫画/小说续读、视频续播；未知类型提示不支持。
  Future<void> open() async {
    if (entry.type == HistoryType.comic) {
      await _openComic();
      return;
    }
    if (entry.type == HistoryType.novel) {
      await _openNovel();
      return;
    }
    if (entry.type != HistoryType.video) {
      // v2 当前阶段只支持视频类型的 playback 接入
      WywDialog.showToast(message: '暂不支持该类型的续播');
      return;
    }
    final progress = entry.parseProgress();
    if (progress is! VideoPlaybackProgress) {
      WywDialog.showToast(message: '未找到可用播放入口');
      return;
    }
    if (progress.sources.isEmpty && progress.videoUrl.isEmpty) {
      WywDialog.showToast(message: '未找到可用播放入口');
      return;
    }
    // 直接续播上次看到的集（sources 为空时回退直链）
    final resumeSource = progress.sources.isEmpty
        ? 0
        : progress.lastSourceIndex.clamp(0, progress.sources.length - 1);
    final resumeEpisode = progress.sources.isEmpty
        ? 0
        : progress.lastEpisodeIndex.clamp(
            0,
            progress.sources[resumeSource].episodes.length - 1,
          );
    final resumeEp = progress.sources.isEmpty
        ? null
        : progress.sources[resumeSource].episodes[resumeEpisode];
    context.pushNamed(
      '/video/',
      arguments: VideoPageRouteArgs(
        videoId: progress.videoId,
        title: entry.title,
        cover: entry.cover,
        sourceKey: progress.sourceKey.isEmpty ? null : progress.sourceKey,
        sources: progress.sources,
        initialSource: resumeSource,
        initialEpisode: resumeEpisode,
        offsetMs: resumeEp?.positionMs ?? 0,
        onProgressChanged: (p) {
          // 历史续播同样回写进度（含重新解析出的直链），否则观看后记录不更新
          inject<IHistoryRepository>().setProgress(
            type: HistoryType.video,
            sourceId: entry.sourceId,
            title: entry.title,
            cover: entry.cover,
            progress: p.toMap(),
          );
        },
      ),
    );
  }

  /// 弹出选集/线路面板，选中某集后进入播放页。
  Future<void> openEpisodePicker() async {
    final progress = entry.parseProgress();
    if (progress is! VideoPlaybackProgress) return;
    final selected = await _pickEpisode(progress);
    if (selected == null) return;
    final (source, episode) = selected;
    final ep = progress.sources[source].episodes[episode];
    context.pushNamed(
      '/video/',
      arguments: VideoPageRouteArgs(
        videoId: progress.videoId,
        title: entry.title,
        cover: entry.cover,
        sourceKey: progress.sourceKey.isEmpty ? null : progress.sourceKey,
        sources: progress.sources,
        initialSource: source,
        initialEpisode: episode,
        offsetMs: ep.positionMs,
        onProgressChanged: (p) {
          // 历史选集续播同样回写进度（含重新解析出的直链）
          inject<IHistoryRepository>().setProgress(
            type: HistoryType.video,
            sourceId: entry.sourceId,
            title: entry.title,
            cover: entry.cover,
            progress: p.toMap(),
          );
        },
      ),
    );
  }

  /// 弹出章节选择面板，选中某章后进入阅读器（带该章页码）。
  Future<void> openChapterPicker() async {
    final progress = entry.parseProgress();
    if (progress is! ComicProgress) return;
    final selected = await _pickChapter(progress);
    if (selected == null) return;
    _pushComic(
      progress,
      initialChapter: selected + 1,
      initialImageIndex: comicImageIndex(progress, selected),
      initialPage: comicLegacyPageIndex(progress, selected),
    );
  }

  Future<void> _openComic() async {
    final progress = entry.parseProgress();
    if (progress is! ComicProgress || progress.chapters.isEmpty) {
      WywDialog.showToast(message: '未找到可续读的漫画');
      return;
    }
    final idx = comicChapterIndex(progress);
    _pushComic(
      progress,
      initialChapter: idx + 1,
      initialImageIndex: comicImageIndex(progress, idx),
      initialPage: comicLegacyPageIndex(progress, idx),
    );
  }

  /// 以指定章/位置进入漫画阅读器。
  ///
  /// [initialImageIndex] 是新口径（图片序号，0 = 无）；[initialPage] 是旧数据里的
  /// 屏号（0 = 无），仅在图片序号缺失时兜底。
  void _pushComic(
    ComicProgress progress, {
    required int initialChapter,
    required int initialImageIndex,
    required int initialPage,
  }) {
    final chapters = progress.chapters.map((m) => _mapToChapter(m)).toList();
    final sourceKey = progress.sourceKey;
    final comicSourceId =
        sourceKey.isEmpty ? progress.comicId : '$sourceKey:${progress.comicId}';
    context.pushNamed(
      ComicReaderPage.routePath,
      arguments: ComicReaderPageRouteArgs(
        comicId: progress.comicId,
        comicTitle: progress.comicTitle,
        chapters: chapters,
        initialChapter: initialChapter.clamp(1, progress.chapters.length),
        initialImageIndex: initialImageIndex > 0 ? initialImageIndex : 0,
        initialPage: initialPage >= 1 ? initialPage : 1,
        sourceKey: sourceKey.isEmpty ? null : sourceKey,
        // 从历史卡片进入同样逐章记录进度
        onProgressChanged: (p) {
          if (sourceKey.isEmpty) return;
          final repo = inject<IHistoryRepository>();
          repo.setProgress(
            type: HistoryType.comic,
            sourceId: comicSourceId,
            title: progress.comicTitle,
            cover: entry.cover,
            progress: ComicProgress(
              chapterId: p.chapterId,
              pageIndex: p.page,
              comicId: progress.comicId,
              comicTitle: progress.comicTitle,
              sourceKey: sourceKey,
              chapters: progress.chapters,
              chapterProgress: [
                for (final cp in p.chapterProgress)
                  {
                    // 规范单位：图片序号 + 水位线；pageIndex/maxPage 保留给旧版本读取
                    'chapterId': cp.chapterId,
                    'imageIndex': cp.imageIndex,
                    'imageCount': cp.imageCount,
                    'seenUpToImage': cp.seenUpToImage,
                    'pageIndex': cp.pageIndex,
                    'maxPage': cp.maxPage,
                  },
              ],
              lastChapterIndex: p.chapter - 1,
            ).toMap(),
          );
        },
      ),
    );
  }

  /// 从历史进度直接续读小说：用保存的完整进入参数重建阅读器。
  Future<void> _openNovel() async {
    final progress = entry.parseProgress();
    if (progress is! ReadProgress || progress.chapters.isEmpty) {
      WywDialog.showToast(message: '未找到可续读的小说');
      return;
    }
    final chapters =
        progress.chapters.map((m) => _mapToNovelReaderChapter(m)).toList();
    context.pushNamed(
      NovelReaderPage.routePath,
      arguments: NovelReaderPageRouteArgs(
        novelId: progress.novelId,
        novelTitle:
            progress.novelTitle.isEmpty ? entry.title : progress.novelTitle,
        chapters: chapters,
        initialChapter: progress.chapter >= 1 ? progress.chapter : 1,
        sourceKey: progress.sourceKey.isEmpty ? null : progress.sourceKey,
      ),
    );
  }

  /// 弹出选集/线路面板，返回用户选中的 (sourceIndex, episodeIndex)。
  Future<(int, int)?> _pickEpisode(VideoPlaybackProgress progress) async {
    return showAdaptiveBottomSheet<(int, int)>(
      context: context,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.6,
        child: VideoEpisodePanel(
          title: entry.title,
          sources: progress.sources,
          currentSourceIndex: progress.lastSourceIndex,
          currentEpisodeIndex: progress.lastEpisodeIndex,
          onEpisodeTap: (s, e) => Navigator.of(sheetContext).pop((s, e)),
          sourceKey: progress.sourceKey,
          videoId: progress.videoId,
          onDownloadEpisode: (s, e) async {
            final src =
                progress.sources[s.clamp(0, progress.sources.length - 1)];
            final ep = src.episodes[e.clamp(0, src.episodes.length - 1)];
            final downloadController = inject<DownloadController>();
            // 下载不负责解析：先经解析服务拿成品直链（缓存直链直接用）。
            // 生命周期三段式：预创建（resolving，下载页立即可见）→ 解析 → 入队/标记失败。
            var mediaUrl = ep.resolvedUrl.isNotEmpty ? ep.resolvedUrl : '';
            final needsResolve =
                mediaUrl.isEmpty && ep.path.type != PlayPathType.direct;
            if (needsResolve) {
              await downloadController.prepareStructuredEpisode(
                sourceKey: progress.sourceKey,
                videoId: progress.videoId,
                title: entry.title,
                cover: entry.cover,
                sourceIndex: s,
                episodeIndex: e,
                episodeName: ep.name,
                sourceName: src.name,
              );
            } else if (mediaUrl.isEmpty) {
              mediaUrl = ep.path.url;
            }
            if (needsResolve) {
              final resolver = ResolutionService(
                  pluginController: inject<PluginController>());
              try {
                mediaUrl = (await resolver.resolve(ep.path)).url;
              } catch (err) {
                WywLogger().w('${LogTag.download} 下载前解析播放地址失败 name=${ep.name}',
                    error: err);
                await downloadController.failPreparedEpisode(
                  sourceKey: progress.sourceKey,
                  videoId: progress.videoId,
                  sourceIndex: s,
                  episodeIndex: e,
                  message: '解析播放地址失败',
                );
                WywDialog.showToast(message: '解析播放地址失败，无法下载');
                return;
              } finally {
                await resolver.dispose();
              }
            }
            final ok = await downloadController.downloadStructuredEpisode(
              sourceKey: progress.sourceKey,
              videoId: progress.videoId,
              title: entry.title,
              cover: entry.cover,
              sourceIndex: s,
              episodeIndex: e,
              episodeName: ep.name,
              sourceName: src.name,
              resolvedUrl: mediaUrl,
            );
            WywDialog.showToast(message: ok ? '已加入下载队列' : '下载失败');
          },
        ),
      ),
    );
  }

  /// 弹出章节/线路面板，返回用户选中的章 index（0-based）。
  Future<int?> _pickChapter(ComicProgress progress) async {
    final lastIndex = comicChapterIndex(progress);
    return showAdaptiveBottomSheet<int>(
      context: context,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('选择章节', style: TextStyle(fontSize: 18)),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: progress.chapters.length,
                itemBuilder: (context, index) {
                  final ch = progress.chapters[index];
                  final title = (ch['title'] as String?) ?? '第 ${index + 1} 话';
                  final page = comicPageIndex(progress, index);
                  final selected = index == lastIndex;
                  return ListTile(
                    dense: true,
                    title: Text(title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: page >= 1 ? Text('看到第 $page 张') : null,
                    selected: selected,
                    onTap: () => Navigator.of(sheetContext).pop(index),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 原始章节描述 → [ComicReaderChapter]（与 init_page._chapterFromMap 一致）。
  ComicReaderChapter _mapToChapter(Map<String, dynamic> c) {
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

  /// 惰性加载章节图片（经插件执行方法）。
  Future<List<String>> _loadChapterImagesFromPlugin(
    String pluginName,
    String method,
    List<dynamic> args,
  ) async {
    final plugin = inject<PluginController>().getPlugin(pluginName);
    if (plugin == null || !plugin.isRegistered) {
      throw '插件 $pluginName 未注册';
    }
    final raw = await plugin.invoke(method, args);
    if (raw is List) {
      return raw.map((e) => e is String ? e : e.toString()).toList();
    }
    throw '插件 $pluginName.$method 未返回图片列表';
  }

  /// 原始章节描述 → [NovelReaderChapter]（与 init_page._novelChapterFromMap 一致）。
  NovelReaderChapter _mapToNovelReaderChapter(Map<String, dynamic> c) {
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

  /// 惰性加载章节正文（经插件执行方法）。
  Future<String> _loadNovelContentFromPlugin(
    String pluginName,
    String method,
    List<dynamic> args,
  ) async {
    final plugin = inject<PluginController>().getPlugin(pluginName);
    if (plugin == null || !plugin.isRegistered) {
      throw '插件 $pluginName 未注册';
    }
    final raw = await plugin.invoke(method, args);
    if (raw is String) {
      return raw;
    }
    throw '插件 $pluginName.$method 未返回正文文本';
  }

  /// 上次看的章 index（0-based；越界/未知时回退到 0，并由调用方夹取）。
  static int comicChapterIndex(ComicProgress p) {
    if (p.chapters.isEmpty) return 0;
    if (p.lastChapterIndex >= 0 && p.lastChapterIndex < p.chapters.length) {
      return p.lastChapterIndex;
    }
    final idx = p.chapters.indexWhere((c) => c['id'] == p.chapterId);
    return idx >= 0 ? idx : 0;
  }

  /// 指定章（0-based）的**图片序号**（规范单位，1-based）；旧数据/未看过返回 0。
  static int comicImageIndex(ComicProgress p, int idx) {
    final cp = _chapterProgressOf(p, idx);
    if (cp == null) return 0;
    return (cp['imageIndex'] as num?)?.toInt() ?? 0;
  }

  /// 旧数据里的屏号（0 = 未知）。新数据恒为 0，由 [comicImageIndex] 取代。
  static int comicLegacyPageIndex(ComicProgress p, int idx) {
    final cp = _chapterProgressOf(p, idx);
    if (cp == null) return 0;
    if ((cp['imageIndex'] as num?)?.toInt() != null) return 0;
    return (cp['pageIndex'] as num?)?.toInt() ?? 0;
  }

  /// 展示/兼容用：优先图片序号，旧数据回退到屏号（未看过返回 0）。
  static int comicPageIndex(ComicProgress p, int idx) {
    final imageIndex = comicImageIndex(p, idx);
    if (imageIndex > 0) return imageIndex;
    return comicLegacyPageIndex(p, idx);
  }

  static Map<String, dynamic>? _chapterProgressOf(ComicProgress p, int idx) {
    if (idx < 0 || idx >= p.chapters.length) return null;
    final id = p.chapters[idx]['id'] as String? ?? '';
    for (final cp in p.chapterProgress) {
      if (cp['chapterId'] == id) return cp;
    }
    return null;
  }
}
