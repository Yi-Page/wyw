import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyw/modules/danmaku/danmaku_module.dart';
import 'package:wyw/modules/danmaku/danmaku_episode_response.dart';
import 'package:wyw/modules/danmaku/danmaku_search_response.dart';
import 'package:wyw/modules/danmaku/danmaku_type_filter.dart';
import 'package:wyw/request/apis/danmaku_api.dart';

/// 全部样例都是手写 JSON（不联网）：字段名与形状抄自弹弹play 官方 swagger，
/// 覆盖正常数据与第三方接口常见的 null / 空数组 / 字段缺失。
Map<String, dynamic> _decode(String json) =>
    jsonDecode(json) as Map<String, dynamic>;

void main() {
  group('DanmakuSearchResponse（/api/v2/search/anime）', () {
    test('正常数据解析出全部候选字段', () {
      final response = DanmakuSearchResponse.fromJson(
        _decode('''
        {
          "success": true,
          "errorCode": 0,
          "errorMessage": null,
          "animes": [
            {
              "animeId": 18319,
              "bangumiId": "tmdb-tv-12345",
              "animeTitle": "葬送的芙莉莲",
              "type": "tvseries",
              "typeDescription": "TV动画",
              "imageUrl": "https://example.com/frieren.jpg",
              "startDate": "2023-09-29T00:00:00+08:00",
              "episodeCount": 28,
              "rating": 8.7,
              "isFavorited": false
            }
          ]
        }
        '''),
      );

      expect(response.animes, hasLength(1));
      final anime = response.animes.single;
      expect(anime.animeId, 18319);
      expect(anime.bangumiId, 'tmdb-tv-12345');
      expect(anime.animeTitle, '葬送的芙莉莲');
      expect(anime.type, 'tvseries');
      expect(anime.typeDescription, 'TV动画');
      expect(anime.imageUrl, 'https://example.com/frieren.jpg');
      expect(anime.startDate, '2023-09-29T00:00:00+08:00');
      expect(anime.episodeCount, 28);
      expect(anime.rating, 8.7);
      expect(anime.isFavorited, isFalse);
    });

    test('封面/上映日期/集数/评分为 null 时退化为空串与 0（不能抛）', () {
      final response = DanmakuSearchResponse.fromJson(
        _decode('''
        {
          "success": true,
          "animes": [
            {
              "animeId": 21832,
              "bangumiId": "tmdb-movie-21832",
              "animeTitle": "某剧场版",
              "type": "tmdbmovie",
              "typeDescription": null,
              "imageUrl": null,
              "startDate": null,
              "episodeCount": null,
              "rating": null,
              "isFavorited": null
            }
          ]
        }
        '''),
      );

      final anime = response.animes.single;
      expect(anime.animeId, 21832);
      expect(anime.bangumiId, 'tmdb-movie-21832');
      expect(anime.typeDescription, isEmpty);
      expect(anime.imageUrl, isEmpty);
      expect(anime.startDate, isEmpty);
      expect(anime.episodeCount, 0);
      expect(anime.rating, 0);
      expect(anime.isFavorited, isFalse);
    });

    test('animes 为空数组、缺失、显式 null 都退化为空列表', () {
      expect(
        DanmakuSearchResponse.fromJson(_decode('{"animes": []}')).animes,
        isEmpty,
      );
      expect(
        DanmakuSearchResponse.fromJson(_decode('{"success": true}')).animes,
        isEmpty,
      );
      expect(
        DanmakuSearchResponse.fromJson(_decode('{"animes": null}')).animes,
        isEmpty,
      );
    });

    test('数字字段以字符串形态返回时也能解析', () {
      final anime = DanmakuSearchResponse.fromJson(
        _decode('''
        {"animes": [{"animeId": "18319", "episodeCount": "28", "rating": "8.7"}]}
        '''),
      ).animes.single;
      expect(anime.animeId, 18319);
      expect(anime.episodeCount, 28);
      expect(anime.rating, 8.7);
    });
  });

  group('DanmakuBangumiDetail（/api/v2/bangumi/{bangumiId}）', () {
    test('正常数据保留字符串集号原文（不能猜成整数）', () {
      final detail = DanmakuBangumiDetail.fromJson(
        _decode('''
        {
          "animeId": 18319,
          "bangumiId": "tmdb-tv-12345",
          "animeTitle": "葬送的芙莉莲",
          "type": "tvseries",
          "typeDescription": "TV动画",
          "imageUrl": "https://example.com/frieren.jpg",
          "isOnAir": false,
          "episodes": [
            {
              "seasonId": "s1",
              "episodeId": 18319001,
              "episodeTitle": "冒险的结束",
              "episodeNumber": "1",
              "airDate": "2023-09-29T00:00:00+08:00"
            },
            {
              "seasonId": "s1",
              "episodeId": 18319013,
              "episodeTitle": "特别篇",
              "episodeNumber": "12.5",
              "airDate": null
            }
          ]
        }
        '''),
      );

      expect(detail.animeId, 18319);
      expect(detail.animeTitle, '葬送的芙莉莲');
      expect(detail.imageUrl, 'https://example.com/frieren.jpg');
      expect(detail.typeDescription, 'TV动画');
      expect(detail.episodes, hasLength(2));
      expect(detail.episodes.first.episodeId, 18319001);
      expect(detail.episodes.first.episodeTitle, '冒险的结束');
      expect(detail.episodes.first.episodeNumber, '1');
      // 官方定义 episodeNumber 为字符串，可能含字母/小数，必须原样保留。
      expect(detail.episodes.last.episodeNumber, '12.5');
    });

    test('空剧集、null 字段、缺失剧集列表都安全', () {
      final empty = DanmakuBangumiDetail.fromJson(
        _decode('''
        {"animeId": 1, "animeTitle": null, "imageUrl": null,
         "typeDescription": null, "episodes": []}
        '''),
      );
      expect(empty.animeTitle, isEmpty);
      expect(empty.imageUrl, isEmpty);
      expect(empty.typeDescription, isEmpty);
      expect(empty.episodes, isEmpty);

      final missing = DanmakuBangumiDetail.fromJson(
        _decode('{"animeId": 2}'),
      );
      expect(missing.episodes, isEmpty);
      expect(missing.imageUrl, isEmpty);

      final nullEpisodeNumber = DanmakuBangumiDetail.fromJson(
        _decode('''
        {"animeId": 3, "episodes": [{"episodeId": 3001, "episodeNumber": null}]}
        '''),
      ).episodes.single;
      expect(nullEpisodeNumber.episodeId, 3001);
      expect(nullEpisodeNumber.episodeTitle, isEmpty);
      expect(nullEpisodeNumber.episodeNumber, isEmpty);
    });

    test('实测形状：简介/评分/多语言标题/标签/季度/播出日期', () {
      // 字段与取值抄自真机实测的 /bangumi/17755 响应（柯南剧场版）：详情卡要展示的
      // 封面/简介/评分/多语言标题/标签全在这里，而搜索接口一个都不给。
      final detail = DanmakuBangumiDetail.fromJson(
        _decode('''
        {
          "animeId": 17755,
          "bangumiId": "tmdb-movie-119271",
          "animeTitle": "名侦探柯南 灰原哀物语～黑铁的神秘列车～",
          "typeDescription": "剧场版",
          "imageUrl": "https://example.com/conan.jpg",
          "isOnAir": false,
          "rating": 6.6,
          "intro": "以电视系列的热门角色灰原哀为中心。",
          "summary": "本作聚焦于将在4月14日上映的剧场版中的关键人物灰原哀。",
          "titles": [
            {"language": "主标题", "title": "名侦探柯南 灰原哀物语～黑铁的神秘列车～"},
            {"language": "官方标题，日语", "title": "名探偵コナン 灰原哀物語"}
          ],
          "tags": [
            {"id": 1, "name": "剧场版", "count": 81},
            {"id": 2, "name": "推理", "count": 28}
          ],
          "episodes": [
            {
              "seasonId": null,
              "episodeId": 177550001,
              "episodeTitle": "剧场版",
              "episodeNumber": "1",
              "airDate": "2023-01-06T00:00:00",
              "lastWatched": null
            }
          ]
        }
        '''),
      );

      expect(detail.bangumiId, 'tmdb-movie-119271');
      expect(detail.rating, 6.6);
      expect(detail.intro, isNotEmpty);
      expect(detail.summary, isNotEmpty);
      // 详情卡优先长简介，长简介缺失时才退回短简介。
      expect(detail.displayIntro, detail.summary);
      expect(detail.titles, hasLength(2));
      expect(detail.titles.last.language, '官方标题，日语');
      expect(detail.tags.map((tag) => tag.name), ['剧场版', '推理']);
      expect(detail.tags.first.count, 81);

      final episode = detail.episodes.single;
      // null 一律退化为空串：seasonId 用来分组、lastWatched 用来显示"上次看到哪"，
      // 两者在弹弹play 自有库/无登录态时都为 null，不能因此丢掉整条分集。
      expect(episode.seasonId, isEmpty);
      expect(episode.lastWatched, isEmpty);
      expect(episode.airDateLabel, '2023-01-06');
    });

    test('简介缺失时退回短简介；titles/tags 缺失或脏数据退化为空列表', () {
      final shortOnly = DanmakuBangumiDetail.fromJson(
        _decode('{"animeId": 1, "intro": "短简介", "episodes": []}'),
      );
      expect(shortOnly.summary, isEmpty);
      expect(shortOnly.displayIntro, '短简介');
      expect(shortOnly.titles, isEmpty);
      expect(shortOnly.tags, isEmpty);
      expect(shortOnly.rating, 0);
      expect(shortOnly.isOnAir, isFalse);

      expect(
        DanmakuBangumiDetail.fromJson(_decode('{"animeId": 2}')).displayIntro,
        isEmpty,
      );

      final dirty = DanmakuBangumiDetail.fromJson(
        _decode('{"animeId": 3, "titles": "x", "tags": null, "rating": "7.5"}'),
      );
      expect(dirty.titles, isEmpty);
      expect(dirty.tags, isEmpty);
      // 数字字符串要能容错成 double，否则详情卡会显示"无评分"。
      expect(dirty.rating, 7.5);

      // 播出日期短于 10 个字符或缺失时不给"日期"标签，而不是显示半截字符串。
      expect(
        DanmakuEpisodeRef.fromJson(_decode('{"episodeId": 1, "airDate": "2023"}'))
            .airDateLabel,
        isEmpty,
      );
      expect(
        DanmakuEpisodeRef.fromJson(_decode('{"episodeId": 1}')).airDateLabel,
        isEmpty,
      );
    });
  });

  group('DanmakuEntry（/api/v2/comment/{episodeId}）', () {
    test('正常弹幕：时间/模式/颜色/用户ID 逐段解析', () {
      final json = _decode('''
      {
        "count": 3,
        "comments": [
          {"cid": 1, "m": "前方高能", "p": "12.34,1,16777215,1234567"},
          {"cid": 2, "m": "底部弹幕", "p": "30.5,4,16711680,0"},
          {"cid": 3, "m": "顶部弹幕", "p": "45,5,65280,999"}
        ]
      }
      ''');
      final comments = DanmakuEntry.listFromJson(json['comments']);

      expect(json['count'], 3);
      expect(comments, hasLength(3));
      expect(comments[0].message, '前方高能');
      expect(comments[0].time, 12.34);
      expect(comments[0].type, 1);
      expect(comments[0].color.toARGB32(), 0xFFFFFFFF);
      // 第 4 段是用户ID（官方 swagger），不是弹幕来源。
      expect(comments[0].source, '1234567');
      expect(comments[1].time, 30.5);
      expect(comments[1].type, 4);
      expect(comments[1].color.toARGB32(), 0xFFFF0000);
      expect(comments[2].type, 5);
      expect(comments[2].color.toARGB32(), 0xFF00FF00);
    });

    test('comments 为空数组或缺失时解析出空列表', () {
      final empty = _decode('{"count": 0, "comments": []}');
      expect(DanmakuEntry.listFromJson(empty['comments']), isEmpty);
      // 字段整个缺失（或为 null）时同样退化为空列表，不抛异常。
      final missing = _decode('{"count": 0}');
      expect(DanmakuEntry.listFromJson(missing['comments']), isEmpty);
      expect(DanmakuEntry.listFromJson(null), isEmpty);
      expect(DanmakuEntry.listFromJson('不是数组'), isEmpty);
    });

    test('单条脏弹幕（m/p 缺失、p 段数不足）退化为安全默认值', () {
      final missing = DanmakuEntry.fromJson(_decode('{"cid": 9}'));
      expect(missing.message, isEmpty);
      expect(missing.time, 0);
      expect(missing.type, 1);
      expect(missing.color.toARGB32(), 0xFFFFFFFF);
      expect(missing.source, isEmpty);

      final shortP = DanmakuEntry.fromJson(
        _decode('{"cid": 10, "m": "只有时间", "p": "8.5,1"}'),
      );
      expect(shortP.time, 8.5);
      expect(shortP.type, 1);
      expect(shortP.color.toARGB32(), 0xFFFFFFFF);
      expect(shortP.source, isEmpty);

      final nullP = DanmakuEntry.fromJson(
        _decode('{"cid": 11, "m": null, "p": null}'),
      );
      expect(nullP.message, isEmpty);
      expect(nullP.time, 0);
    });

    test('toJson 往返后字段不变（p 串形状与接口一致）', () {
      final entry = DanmakuEntry.fromJson(
        _decode('{"cid": 1, "m": "往返", "p": "12.34,4,16711680,888"}'),
      );
      final json = entry.toJson();
      expect(json['m'], '往返');
      expect(json['p'], '12.34,4,16711680,888');

      final again = DanmakuEntry.fromJson(json);
      expect(again.message, entry.message);
      expect(again.time, entry.time);
      expect(again.type, entry.type);
      expect(again.color.toARGB32(), entry.color.toARGB32());
      expect(again.source, entry.source);
    });
  });

  group('凭证缺失时的静默降级契约', () {
    test('未配置凭证时三个端点都不发请求，直接抛 DandanNotConfiguredException',
        () async {
      // 本地/CI 测试不注入 --dart-define，凭证为空。万一将来给测试注入了
      // 凭证，这里直接跳过，避免用例真的去打网络。
      if (DanmakuApi.isConfigured) {
        return;
      }
      await expectLater(
        DanmakuApi.searchAnime('葬送的芙莉莲'),
        throwsA(isA<DandanNotConfiguredException>()),
      );
      await expectLater(
        DanmakuApi.getBangumiDetail('18319'),
        throwsA(isA<DandanNotConfiguredException>()),
      );
      await expectLater(
        DanmakuApi.getComments(18319001),
        throwsA(isA<DandanNotConfiguredException>()),
      );
    });
  });

  group('类型筛选与年份', () {
    test('DanmakuTypeFilter 的接口值与标签一一对应', () {
      // 值就是接口的 AnimeType 枚举串；"全部"必须是不传参数而不是传空串。
      expect(DanmakuTypeFilter.all.apiValue, isNull);
      expect(DanmakuTypeFilter.tv.apiValue, 'tvseries');
      expect(DanmakuTypeFilter.movie.apiValue, 'movie');
      expect(DanmakuTypeFilter.ova.apiValue, 'ova');
      expect(DanmakuTypeFilter.other.apiValue, 'other');
      expect(
        DanmakuTypeFilter.values.map((type) => type.label),
        ['全部', 'TV', '剧场版', 'OVA', '其它'],
      );
    });

    test('搜索条目的年份从 startDate 前 4 位解析，非法数据返回 null', () {
      int? yearOf(String json) =>
          DanmakuSearchAnime.fromJson(_decode(json)).year;

      expect(yearOf('{"animeId": 1, "startDate": "1996-01-08T00:00:00"}'), 1996);
      // 只有年份（正好 4 位）也算得出年份；不足 4 位才无从解析。
      expect(yearOf('{"animeId": 1, "startDate": "2023"}'), 2023);
      expect(yearOf('{"animeId": 1, "startDate": "199"}'), isNull);
      expect(yearOf('{"animeId": 1, "startDate": "abcd-01-01"}'), isNull);
      expect(yearOf('{"animeId": 1}'), isNull);
      expect(yearOf('{"animeId": 1, "startDate": null}'), isNull);
    });
  });
}
