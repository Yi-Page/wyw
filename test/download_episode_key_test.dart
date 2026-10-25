import 'package:flutter_test/flutter_test.dart';
import 'package:wyw/modules/download/download_module.dart';

/// 选集面板靠「线路:集数」当键从下载记录里取每一集的任务
/// （`DownloadController.episodeDownloadsFor` → `episodeDownloadKey`）。
///
/// 这条链路依赖 `structuredEpisodeNumber` 的编码与
/// `sourceIndexOf` / `episodeIndexOf` 的反解严格互逆；一旦写错，面板会把
/// 下载状态标到别的集上（表现为"每一集都显示已缓存"）。
void main() {
  group('结构化集数编码与反解互逆', () {
    test('往返一致（含 0 与多线路）', () {
      for (var source = 0; source < 5; source++) {
        for (var episode = 0; episode < 200; episode++) {
          final number = structuredEpisodeNumber(source, episode);
          expect(sourceIndexOf(number), source,
              reason: 'source=$source episode=$episode number=$number');
          expect(episodeIndexOf(number), episode,
              reason: 'source=$source episode=$episode number=$number');
        }
      }
    });

    test('相邻线路之间不会串键（每线路安全上限 99999 集）', () {
      // number = (s+1)*100000 + (e+1)，所以 e+1 必须 < 100000，
      // 即每线路最多 99999 集（e = 0..99998）—— 实际剧集远达不到。
      expect(structuredEpisodeNumber(0, 99998), 199999);
      expect(sourceIndexOf(199999), 0);
      expect(episodeIndexOf(199999), 99998);
      // 下一条线路的第一集
      expect(structuredEpisodeNumber(1, 0), 200001);
      expect(sourceIndexOf(200001), 1);
      expect(episodeIndexOf(200001), 0);
    });
  });

  test('episodeDownloadKey 是面板取任务用的键', () {
    expect(episodeDownloadKey(0, 0), '0:0');
    expect(episodeDownloadKey(2, 11), '2:11');
    // 与反解出来的键一致（episodeDownloadsFor 就是这么回填的）
    final number = structuredEpisodeNumber(3, 7);
    expect(
      episodeDownloadKey(sourceIndexOf(number), episodeIndexOf(number)),
      episodeDownloadKey(3, 7),
    );
  });
}
