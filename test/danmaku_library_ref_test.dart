import 'package:flutter_test/flutter_test.dart';
import 'package:wyw/modules/danmaku/danmaku_episode_response.dart';
import 'package:wyw/modules/danmaku/danmaku_library_ref.dart';
import 'package:wyw/services/storage/history_progress.dart';

/// 造一个形状取自实测 `/bangumi/{id}` 响应的详情（`episodeCount` 只存在于搜索
/// 接口，这里刻意只给分集列表，用来验证"集数取详情列表长度"这条口径）。
DanmakuBangumiDetail _detail() {
  return DanmakuBangumiDetail.fromJson(const {
    'animeId': 266,
    'bangumiId': 'tmdb-tv-30983',
    'animeTitle': '名侦探柯南',
    'typeDescription': 'TV动画',
    'imageUrl': 'https://example.com/conan.jpg',
    'isOnAir': true,
    'rating': 7.7,
    'intro': '短简介',
    'summary': '长简介',
    'episodes': [
      {'episodeId': 2660001, 'episodeNumber': '1', 'episodeTitle': '第1话'},
      {'episodeId': 2660002, 'episodeNumber': '2', 'episodeTitle': '第2话'},
      {'episodeId': 2660003, 'episodeNumber': '3', 'episodeTitle': '第3话'},
    ],
  });
}

void main() {
  group('DanmakuLibraryRef', () {
    test('由详情构造：集数取详情分集列表长度，刷新 id 优先字符串 bangumiId', () {
      final ref = DanmakuLibraryRef.fromDetail(_detail(), savedAtMs: 123);

      expect(ref.animeId, 266);
      expect(ref.bangumiId, 'tmdb-tv-30983');
      expect(ref.libraryTitle, '名侦探柯南');
      expect(ref.imageUrl, 'https://example.com/conan.jpg');
      expect(ref.rating, 7.7);
      // 详情分集列表是权威集数：搜索接口的 episodeCount 对 TMDB 源恒为 1。
      expect(ref.episodeCount, 3);
      expect(ref.displayIntro, '长简介');
      expect(ref.refreshableId, 'tmdb-tv-30983');
      expect(ref.savedAtMs, 123);
      expect(ref.isValid, isTrue);
    });

    test('refreshableId 在没有 bangumiId 时退回数字 animeId', () {
      const ref = DanmakuLibraryRef(animeId: 266, libraryTitle: 'x', savedAtMs: 0);
      expect(ref.refreshableId, '266');
    });

    test('displayIntro：长简介为空时退回短简介', () {
      const shortOnly =
          DanmakuLibraryRef(animeId: 1, libraryTitle: 'x', intro: '短', savedAtMs: 0);
      expect(shortOnly.displayIntro, '短');

      const bothEmpty = DanmakuLibraryRef(animeId: 1, libraryTitle: 'x', savedAtMs: 0);
      expect(bothEmpty.displayIntro, isEmpty);
    });

    test('isValid：缺作品编号或缺标题都算无效（宁可当作没选过）', () {
      expect(
        const DanmakuLibraryRef(animeId: 0, libraryTitle: 'x', savedAtMs: 0)
            .isValid,
        isFalse,
      );
      expect(
        const DanmakuLibraryRef(animeId: 1, libraryTitle: '', savedAtMs: 0)
            .isValid,
        isFalse,
      );
      expect(
        const DanmakuLibraryRef(animeId: 1, libraryTitle: 'x', savedAtMs: 0)
            .isValid,
        isTrue,
      );
    });

    test('JSON 往返不丢字段', () {
      final ref = DanmakuLibraryRef.fromDetail(_detail(), savedAtMs: 999);
      final restored = DanmakuLibraryRef.fromMap(ref.toMap());

      expect(restored.animeId, ref.animeId);
      expect(restored.bangumiId, ref.bangumiId);
      expect(restored.libraryTitle, ref.libraryTitle);
      expect(restored.imageUrl, ref.imageUrl);
      expect(restored.intro, ref.intro);
      expect(restored.summary, ref.summary);
      expect(restored.rating, ref.rating);
      expect(restored.episodeCount, ref.episodeCount);
      expect(restored.year, ref.year);
      expect(restored.savedAtMs, ref.savedAtMs);
    });

    test('year 由调用方带入（详情接口没有 startDate），并随快照持久化', () {
      expect(DanmakuLibraryRef.fromDetail(_detail(), year: 1996).year, 1996);
      // 不传就是"未知"，不能瞎猜
      expect(DanmakuLibraryRef.fromDetail(_detail()).year, 0);

      final withYear = DanmakuLibraryRef.fromDetail(_detail(), year: 1996);
      expect(DanmakuLibraryRef.fromMap(withYear.toMap()).year, 1996);
      // 本次重构**之前**写下的记录没有 year 键 → 退化 0 而不是抛
      expect(
        DanmakuLibraryRef.fromMap(const {'animeId': 266, 'libraryTitle': 'x'})
            .year,
        0,
      );
    });

    test('year 为 0 时用详情首集 airDate 兜底，且调用方给的值优先', () {
      DanmakuBangumiDetail withAirdate(String airDate) =>
          DanmakuBangumiDetail.fromJson({
            'animeId': 266,
            'animeTitle': '名侦探柯南',
            'episodes': [
              {'episodeId': 2660001, 'episodeTitle': '第1话', 'airDate': airDate},
            ],
          });

      // 详情接口不返回 startDate，只有每集的 airDate——0 表示"当时没拿到"，
      // 不是"确定没有年份"，所以要走兜底（否则老记录永远显示 `—`）。
      expect(
        DanmakuLibraryRef.fromDetail(withAirdate('2019-01-06T00:00:00')).year,
        2019,
      );
      expect(DanmakuLibraryRef.fromDetail(withAirdate('2019-01-06')).year, 2019);
      // 显式传 0 同样视为未知 → 兜底。
      expect(
        DanmakuLibraryRef.fromDetail(withAirdate('2019-01-06T00:00:00'), year: 0)
            .year,
        2019,
      );
      // 搜索结果的系列级年份更准，优先于首集（续作/分割放送的年可能不同）。
      expect(
        DanmakuLibraryRef.fromDetail(withAirdate('2019-01-06T00:00:00'), year: 2024)
            .year,
        2024,
      );
      // 空 airDate / 脏数据 → 仍是 0，不抛。
      expect(DanmakuLibraryRef.fromDetail(withAirdate('')).year, 0);
      expect(
        DanmakuLibraryRef.fromDetail(withAirdate('0000-00-00T00:00:00')).year,
        0,
      );
      expect(DanmakuLibraryRef.fromDetail(_detail()).year, 0);
    });

    test('快照**不含**重数据：分集/多语言标题/标签只进详情缓存箱', () {
      // 进度记录每 5–15 秒就被整体重写一次，而分集列表可达上千集；
      // 把它塞进快照等于每次写都重新序列化一份大对象（用户明确否掉了这个做法）。
      // 这条用例把"键集"钉死：以后谁往里加字段，这里会先红。
      final map = DanmakuLibraryRef.fromDetail(_detail()).toMap();
      expect(map.containsKey('episodes'), isFalse);
      expect(map.containsKey('titles'), isFalse);
      expect(map.containsKey('tags'), isFalse);
      expect(map.keys.toSet(), {
        'animeId',
        'bangumiId',
        'libraryTitle',
        'imageUrl',
        'intro',
        'summary',
        'rating',
        'episodeCount',
        'year',
        'savedAtMs',
      });
    });

    test('脏数据（数字字符串 / null / 缺字段）退化而不抛', () {
      final ref = DanmakuLibraryRef.fromMap(const {
        'animeId': '266',
        'libraryTitle': '名侦探柯南',
        'rating': '7.5',
        'episodeCount': '1372',
      });
      expect(ref.animeId, 266);
      expect(ref.rating, 7.5);
      expect(ref.episodeCount, 1372);
      expect(ref.bangumiId, isEmpty);
      expect(ref.imageUrl, isEmpty);
      expect(ref.summary, isEmpty);

      // 空 Map / 全 null / 类型不对：一律退化成"无效"，不抛。
      expect(DanmakuLibraryRef.fromMap(const {}).isValid, isFalse);
      expect(
        DanmakuLibraryRef.fromMap(const {'animeId': null, 'libraryTitle': 5})
            .isValid,
        isFalse,
      );
    });
  });

  group('VideoPlaybackProgress.danmaku（进度记录里的弹幕库条目）', () {
    const ref = DanmakuLibraryRef(
      animeId: 266,
      bangumiId: 'tmdb-tv-30983',
      libraryTitle: '名侦探柯南',
      imageUrl: 'https://example.com/conan.jpg',
      intro: '短简介',
      summary: '长简介',
      rating: 7.7,
      episodeCount: 1372,
      year: 1996,
      savedAtMs: 5,
    );

    test('往返保留弹幕库条目，且不影响进度其余字段', () {
      final progress = VideoPlaybackProgress(
        videoId: 'v',
        sources: const [],
        lastSourceIndex: 1,
        lastEpisodeIndex: 2,
        danmaku: ref,
      );
      final restored = VideoPlaybackProgress.fromMap(progress.toMap());

      expect(restored.danmaku?.animeId, 266);
      expect(restored.danmaku?.libraryTitle, '名侦探柯南');
      expect(restored.danmaku?.episodeCount, 1372);
      expect(restored.danmaku?.rating, 7.7);
      expect(restored.danmaku?.bangumiId, 'tmdb-tv-30983');
      expect(restored.danmaku?.year, 1996);
      expect(restored.lastSourceIndex, 1);
      expect(restored.lastEpisodeIndex, 2);
    });

    test('旧记录（没有 danmaku 字段）读出 null：等同于"还没选过"', () {
      final restored = VideoPlaybackProgress.fromMap(const {
        'videoId': 'v',
        'sources': [],
        'lastSourceIndex': 0,
        'lastEpisodeIndex': 3,
      });
      expect(restored.danmaku, isNull);
      expect(restored.lastEpisodeIndex, 3);
    });

    test('空壳/脏数据视为"没选过"，避免显示一张空白"当前使用"卡片', () {
      expect(
        VideoPlaybackProgress.fromMap(const {'videoId': 'v', 'danmaku': {}})
            .danmaku,
        isNull,
      );
      expect(
        VideoPlaybackProgress.fromMap(const {'videoId': 'v', 'danmaku': 'x'})
            .danmaku,
        isNull,
      );
      expect(
        VideoPlaybackProgress.fromMap(
          const {'videoId': 'v', 'danmaku': {'animeId': 1}},
        ).danmaku,
        isNull,
      );
      expect(
        VideoPlaybackProgress.fromMap(const {'videoId': 'v', 'danmaku': null})
            .danmaku,
        isNull,
      );
    });

    test('未选库时 toMap 写出 null（保留键），读写两侧键集稳定', () {
      final map = const VideoPlaybackProgress(videoId: 'v').toMap();
      expect(map.containsKey('danmaku'), isTrue);
      expect(map['danmaku'], isNull);
    });
  });
}
