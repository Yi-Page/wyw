import 'package:flutter_test/flutter_test.dart';
import 'package:wyw/modules/download/download_module.dart';
import 'package:wyw/pages/video/video_entry_launcher.dart';
import 'package:wyw/services/storage/video_play_model.dart';

/// 下载记录 → 播放结构的回归。
///
/// 这条路径只在「下载页点进行中任务、但反查不到进度记录」时走（典型来源：从播放页
/// 选「只下载」，它不进播放器所以不写进度）。它唯一不能错的就是**下标**：播放页用
/// `(线路, 集)` 去找下载任务，错位就会建出身份错误的假任务。
DownloadEpisode _ep({
  required int sourceIndex,
  required int episodeIndex,
  String name = '',
  String sourceName = '',
  String url = '',
  int status = DownloadStatus.downloading,
}) {
  return DownloadEpisode(
    structuredEpisodeNumber(sourceIndex, episodeIndex),
    name,
    sourceIndex, // road（沿用旧字段语义）
    status,
    0.0,
    0,
    0,
    '',
    '',
    url,
    null,
    '',
    0,
    sourceIndex: sourceIndex,
    sourceName: sourceName,
  );
}

DownloadRecord _record(List<DownloadEpisode> episodes, {String code = 'p:v'}) {
  return DownloadRecord(
    1,
    '作品',
    '',
    'plugin',
    {for (final e in episodes) e.episodeNumber: e},
    DateTime(2026),
    videoId: 'v',
    sourceKey: 'p',
    code: code,
  );
}

void main() {
  group('buildSourcesFromDownloadRecord', () {
    test('连续集：名字/下标 1:1 对上，有直链的集是 direct', () {
      final sources = buildSourcesFromDownloadRecord(_record([
        _ep(sourceIndex: 0, episodeIndex: 0, name: '第1集', url: 'http://x/1.m3u8'),
        _ep(sourceIndex: 0, episodeIndex: 1, name: '第2集', url: 'http://x/2.m3u8'),
        _ep(sourceIndex: 0, episodeIndex: 2, name: '第3集', url: 'http://x/3.m3u8'),
      ]));

      expect(sources.length, 1);
      expect(sources[0].episodes.length, 3);
      expect(sources[0].episodes.map((e) => e.name).toList(),
          ['第1集', '第2集', '第3集']);
      expect(sources[0].episodes[1].path.type, PlayPathType.direct);
      expect(sources[0].episodes[1].path.url, 'http://x/2.m3u8');
    });

    test('集号跳号：补齐占位，目标下标**不得**被重排', () {
      // 只下了第 1、4 集：结构必须是 4 个槽位，第 4 集仍在 index 3。
      final sources = buildSourcesFromDownloadRecord(_record([
        _ep(sourceIndex: 0, episodeIndex: 0, name: '第1集', url: 'http://x/1.m3u8'),
        _ep(sourceIndex: 0, episodeIndex: 3, name: '第4集', url: 'http://x/4.m3u8'),
      ]));

      expect(sources[0].episodes.length, 4);
      expect(sources[0].episodes[3].name, '第4集');
      expect(sources[0].episodes[3].path.url, 'http://x/4.m3u8');
      // 缺的集是占位：名字留空（播放页回退显示「第N集」），且是 local 型 ——
      // 点它只会明确失败，不会在下载列表里造出多余任务。
      expect(sources[0].episodes[1].name, '');
      expect(sources[0].episodes[1].path.type, PlayPathType.local);
      expect(sources[0].episodes[1].path.url, '');
    });

    test('刚从下载页点的那一集，在结构里的下标与任务身份一致', () {
      const s = 1;
      const e = 4;
      final target = _ep(
        sourceIndex: s,
        episodeIndex: e,
        name: '第5集',
        sourceName: '线路B',
        url: 'http://x/5.m3u8',
      );
      final sources = buildSourcesFromDownloadRecord(_record([
        _ep(sourceIndex: 0, episodeIndex: 0, name: 'A1', url: 'http://a/1.m3u8'),
        target,
      ]));

      expect(sources.length, s + 1);
      expect(sources[s].name, '线路B');
      expect(sources[s].episodes.length, e + 1);
      expect(sources[s].episodes[e].path.url, 'http://x/5.m3u8');
      // 下标即身份：播放页拿 (s, e) 就能查到这条任务。
      expect(sources[s].episodes[e].name, '第5集');
    });

    test('中间缺的线路补一条占位线路，保证线路下标不乱', () {
      final sources = buildSourcesFromDownloadRecord(_record([
        _ep(sourceIndex: 0, episodeIndex: 0, name: 'A1', url: 'http://a/1.m3u8'),
        _ep(sourceIndex: 2, episodeIndex: 0, name: 'C1', url: 'http://c/1.m3u8'),
      ]));

      expect(sources.length, 3);
      expect(sources[1].episodes.length, 1);
      expect(sources[1].episodes[0].path.type, PlayPathType.local);
      expect(sources[2].episodes[0].path.url, 'http://c/1.m3u8');
    });

    test('还没解析出直链的集也是占位（不能给它 direct 空地址）', () {
      final sources = buildSourcesFromDownloadRecord(_record([
        _ep(
          sourceIndex: 0,
          episodeIndex: 0,
          name: '第1集',
          url: '',
          status: DownloadStatus.resolving,
        ),
      ]));

      expect(sources[0].episodes[0].path.type, PlayPathType.local);
      expect(sources[0].episodes[0].name, '第1集');
    });

    test('空记录 → 空结构（调用方据此走"还没有可播放地址"提示）', () {
      expect(buildSourcesFromDownloadRecord(_record(const [])), isEmpty);
    });
  });
}
