import 'package:flutter_test/flutter_test.dart';
import 'package:wyw/modules/danmaku/danmaku_episode_response.dart';
import 'package:wyw/services/danmaku/danmaku_episode_matcher.dart';

DanmakuEpisodeRef _ep(int id, String number) =>
    DanmakuEpisodeRef(episodeId: id, episodeTitle: '第$number集', episodeNumber: number);

void main() {
  group('localEpisodeNumber（本地集名 → 集号）', () {
    test('优先认「第N集/话」', () {
      expect(localEpisodeNumber('第03集 1080P'), 3);
      expect(localEpisodeNumber('第 12 话 HDR'), 12);
      expect(localEpisodeNumber('1080P 第03集'), 3);
      expect(localEpisodeNumber('名侦探柯南 第1024集'), 1024);
    });

    test('剔除分辨率/编码/年份等"看起来像数字"的噪声', () {
      expect(localEpisodeNumber('[Lilith-Raws] 进击的巨人 - 05 [1080p]'), 5);
      expect(localEpisodeNumber('进击的巨人 S02 05 WEB-DL 1920x1080'), 5);
      expect(localEpisodeNumber('Frieren 28 x265 2023'), 28);
      expect(localEpisodeNumber('01'), 1);
      expect(localEpisodeNumber('EP05'), 5);
    });

    test('取不到集号时返回 null，而不是硬给一个数字', () {
      expect(localEpisodeNumber(''), isNull);
      expect(localEpisodeNumber('   '), isNull);
      expect(localEpisodeNumber('特别篇'), isNull);
      expect(localEpisodeNumber('SP'), isNull);
      // 只剩噪声（全部被剔除）→ 没有可用数字。
      expect(localEpisodeNumber('1080P WEB-DL'), isNull);
    });
  });

  group('matchLocalEpisodeToLibrary（本地集名 ↔ 库分集）', () {
    test('严格按 episodeNumber 匹配（含补零写法）', () {
      final episodes = [_ep(1, '1'), _ep(2, '2'), _ep(3, '03'), _ep(4, '4')];
      expect(
        matchLocalEpisodeToLibrary(localName: '第3集 1080P', episodes: episodes),
        2,
      );
      expect(
        matchLocalEpisodeToLibrary(localName: '第4集', episodes: episodes),
        3,
      );
    });

    test('库侧存在非纯数字短标题（如 C146 / 12.5）时不参与严格匹配', () {
      final episodes = [_ep(1, '1'), _ep(2, 'C146'), _ep(3, '12.5')];
      // 146 找不到 C146 这一条 → 返回 null（宁可跳过也不猜）
      expect(
        matchLocalEpisodeToLibrary(localName: '第146集', episodes: episodes),
        isNull,
      );
      expect(
        matchLocalEpisodeToLibrary(localName: '第1集', episodes: episodes),
        0,
      );
    });

    test('库侧完全没有短标题时才按序号对位', () {
      final noNumbers = [
        DanmakuEpisodeRef(episodeId: 1, episodeTitle: '冒险的结束'),
        DanmakuEpisodeRef(episodeId: 2, episodeTitle: '其实并不特别'),
        DanmakuEpisodeRef(episodeId: 3, episodeTitle: '魔法使的修行'),
      ];
      expect(
        matchLocalEpisodeToLibrary(localName: '第2集', episodes: noNumbers),
        1,
      );
      // 越界不猜
      expect(
        matchLocalEpisodeToLibrary(localName: '第9集', episodes: noNumbers),
        isNull,
      );
    });

    test('只要有一条可比较的短标题，就绝不退位（防止整体错位）', () {
      final mixed = [
        DanmakuEpisodeRef(episodeId: 1, episodeTitle: 'x', episodeNumber: ''),
        DanmakuEpisodeRef(episodeId: 2, episodeTitle: 'y', episodeNumber: '7'),
      ];
      // 第 5 集：严格匹配失败，但因为库侧有 '7' 这一条，不退位到"列表第 5 项"。
      expect(
        matchLocalEpisodeToLibrary(localName: '第5集', episodes: mixed),
        isNull,
      );
      expect(
        matchLocalEpisodeToLibrary(localName: '第7集', episodes: mixed),
        1,
      );
    });

    test('集名解析不出集号、或库分集为空 → null', () {
      final episodes = [_ep(1, '1'), _ep(2, '2')];
      expect(
        matchLocalEpisodeToLibrary(localName: '特别篇', episodes: episodes),
        isNull,
      );
      expect(
        matchLocalEpisodeToLibrary(localName: '第1集', episodes: const []),
        isNull,
      );
    });
  });
}
