import 'package:flutter_test/flutter_test.dart';
import 'package:wyw/modules/download/download_module.dart';
import 'package:wyw/services/history/video_progress_merge.dart';
import 'package:wyw/services/storage/history_progress.dart';
import 'package:wyw/services/storage/video_code.dart';
import 'package:wyw/services/storage/video_play_model.dart';

/// 作品级身份（code）与进度回填的回归。
///
/// 背景：进度记录与下载记录原本各自拼 key（进度 `plugin:videoId`、下载
/// `plugin_videoId.hashCode`），两边互相找不到；下载页进入播放还把真实
/// `(线路,集)` 压成 (0,0)，一旦补上回写就会把整部剧进度削成单集。
/// 现在两件事各有护栏，这里把它们钉住：
///   1. [VideoCode] 是唯一的构造规则（含老记录派生）；
///   2. [mergeVideoProgressState] 按下标合并，但必须过"线路名 + 集标识"
///      二级校验，避免插件换序/插集把进度串到别的集上。
void main() {
  group('VideoCode 构造与拆分', () {
    test('有插件名时是 plugin:videoId', () {
      expect(VideoCode.of(pluginName: 'dushehub', videoId: '123'),
          'dushehub:123');
    });

    test('无插件名时退化为裸 videoId（与 v2 旧记录/手动播放口径一致）', () {
      expect(VideoCode.of(pluginName: '', videoId: 'https://a/b'), 'https://a/b');
    });

    test('videoId 为空 → 空串（调用方必须视为不可进入播放）', () {
      expect(VideoCode.of(pluginName: 'jm', videoId: ''), '');
    });

    test('拆分只对带插件前缀的 code 有意义', () {
      expect(VideoCode.pluginOf('jm:123'), 'jm');
      expect(VideoCode.videoIdOf('jm:123'), '123');
      // videoId 自身含冒号（URL）时，只按第一个冒号切分
      expect(VideoCode.videoIdOf('jm:https://a/b'), 'https://a/b');
    });

    test('记录侧派生：新记录读 code，老记录从 sourceKey/videoId 还原', () {
      expect(
        VideoCode.ofRecord(code: 'jm:1', sourceKey: 'x', videoId: 'y'),
        'jm:1',
      );
      expect(
        VideoCode.ofRecord(code: '', sourceKey: 'jm', videoId: '1'),
        'jm:1',
      );
      // 老记录连 sourceKey/videoId 都没有 → 无法关联，按无进度处理
      expect(VideoCode.ofRecord(code: '', sourceKey: '', videoId: ''), '');
    });
  });

  group('DownloadRecord.effectiveCode', () {
    DownloadRecord make({
      String code = '',
      String sourceKey = '',
      String videoId = '',
      int mediaId = 1,
    }) =>
        DownloadRecord(mediaId, '标题', '封面', 'jm', {}, DateTime(2024),
            videoId: videoId, sourceKey: sourceKey, code: code);

    test('新记录直接用它引用的进度 code', () {
      expect(make(code: 'jm:9').effectiveCode, 'jm:9');
    });

    test('老记录（无 code 字段）从 sourceKey/videoId 派生 → 仍能被找到', () {
      expect(make(sourceKey: 'jm', videoId: '9').effectiveCode, 'jm:9');
    });

    test('极老记录（三者皆空）→ 空串，表示无法关联', () {
      expect(make().effectiveCode, '');
    });

    test('物理 key 与 code 解耦（key 仍是 pluginName_mediaId，故无需迁移）', () {
      final record = make(
        code: 'jm:9',
        sourceKey: 'jm',
        videoId: '9',
        mediaId: '9'.hashCode,
      );
      expect(record.key, 'jm_${'9'.hashCode}');
      expect(record.effectiveCode, 'jm:9');
    });
  });

  group('mergeVideoProgressState：结构来自骨架，状态来自历史', () {
    VideoPlayEpisode ep(String name, {String url = '', int position = 0}) =>
        VideoPlayEpisode(
          name: name,
          path: PlayResourcePath(url: url, type: PlayPathType.resolve),
          positionMs: position,
        );

    VideoPlaySource src(String name, List<VideoPlayEpisode> eps) =>
        VideoPlaySource(name: name, episodes: eps);

    VideoPlaybackProgress history(List<VideoPlaySource> sources) =>
        VideoPlaybackProgress(videoId: 'v', sources: sources);

    test('线路名与集标识一致 → 回填 position/duration', () {
      final skeleton = [src('线路A', [ep('第1集', url: 'a1'), ep('第2集', url: 'a2')])];
      final hist = history([
        src('线路A', [
          VideoPlayEpisode(
            name: '第1集',
            path: const PlayResourcePath(url: 'a1', type: PlayPathType.resolve),
            positionMs: 5000,
            durationMs: 100000,
          ),
          VideoPlayEpisode(
            name: '第2集',
            path: const PlayResourcePath(url: 'a2', type: PlayPathType.resolve),
            positionMs: 7000,
          ),
        ]),
      ]);
      final merged = mergeVideoProgressState(skeleton: skeleton, history: hist);
      expect(merged[0].episodes[0].positionMs, 5000);
      expect(merged[0].episodes[0].durationMs, 100000);
      expect(merged[0].episodes[1].positionMs, 7000);
    });

    test('线路名不一致 → 整条线路的状态不合并（防换序串集）', () {
      final skeleton = [src('线路B', [ep('第1集', url: 'b1')])];
      final hist = history([
        src('线路A', [
          VideoPlayEpisode(
            name: '第1集',
            path: const PlayResourcePath(url: 'b1', type: PlayPathType.resolve),
            positionMs: 5000,
          ),
        ]),
      ]);
      final merged = mergeVideoProgressState(skeleton: skeleton, history: hist);
      expect(merged[0].episodes[0].positionMs, 0);
    });

    test('集标识不一致 → 该集状态不合并（防插集整体偏移）', () {
      final skeleton = [src('线路A', [ep('第1集', url: 'a2')])];
      final hist = history([
        src('线路A', [
          VideoPlayEpisode(
            name: '第1集',
            path: const PlayResourcePath(url: 'a1', type: PlayPathType.resolve),
            positionMs: 5000,
          ),
        ]),
      ]);
      final merged = mergeVideoProgressState(skeleton: skeleton, history: hist);
      expect(merged[0].episodes[0].positionMs, 0);
    });

    test('标识缺失（任一侧为空）→ 保守地按下标合并，不丢进度', () {
      final skeleton = [src('', [ep('', url: '')])];
      final hist = history([
        src('', [
          VideoPlayEpisode(
            name: '',
            path: const PlayResourcePath(url: '', type: PlayPathType.resolve),
            positionMs: 5000,
          ),
        ]),
      ]);
      final merged = mergeVideoProgressState(skeleton: skeleton, history: hist);
      expect(merged[0].episodes[0].positionMs, 5000);
    });

    test('无历史 / 历史无结构 → 原样返回骨架', () {
      final skeleton = [src('线路A', [ep('第1集', url: 'a1')])];
      expect(mergeVideoProgressState(skeleton: skeleton, history: null), skeleton);
      expect(
        mergeVideoProgressState(
          skeleton: skeleton,
          history: history(const []),
        ),
        skeleton,
      );
    });

    test('只回填状态，不改骨架的 name/path（结构以调用方为准）', () {
      final skeleton = [src('线路A', [ep('第1集(新)', url: 'new-url')])];
      final hist = history([
        src('线路A', [
          VideoPlayEpisode(
            name: '第1集(旧)',
            path: const PlayResourcePath(url: 'new-url', type: PlayPathType.page),
            positionMs: 5000,
            resolvedUrl: 'https://cdn/x.m3u8',
          ),
        ]),
      ]);
      final merged = mergeVideoProgressState(skeleton: skeleton, history: hist);
      expect(merged[0].episodes[0].name, '第1集(新)');
      expect(merged[0].episodes[0].path.type, PlayPathType.resolve);
      expect(merged[0].episodes[0].resolvedUrl, 'https://cdn/x.m3u8');
      expect(merged[0].episodes[0].positionMs, 5000);
    });
  });
}
