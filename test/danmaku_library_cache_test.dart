import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:wyw/modules/danmaku/danmaku_episode_response.dart';
import 'package:wyw/repositories/danmaku_library_cache_repository.dart';

/// 弹幕库详情缓存：**重数据（分集/标题/标签）单独按库 id 存**，进度记录里只留
/// 小快照 + 引用。这里覆盖它的读写、容错与淘汰——它们是"进场默认展示选集"的
/// 全部依据，坏掉的话表现是"选集空白"，很难从界面反推。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late Box<String> box;
  late DanmakuLibraryCacheRepository repo;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('wyw_danmaku_cache_test');
    Hive.init(tempDir.path);
    box = await Hive.openBox<String>('danmaku_library_cache_test');
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() async {
    await box.clear();
    repo = DanmakuLibraryCacheRepository(box: box);
  });

  /// 真实形状的 `/bangumi/{id}` 载荷（多语言标题、标签、分集）。
  Map<String, dynamic> payload({int animeId = 19847}) => {
        'animeId': animeId,
        'bangumiId': '$animeId',
        'animeTitle': 'FX战士久留美',
        'imageUrl': 'https://example.com/cover.jpg',
        'typeDescription': 'TV动画',
        'intro': '简介正文',
        'rating': 7.5,
        'isOnAir': true,
        'titles': [
          {'language': '中文', 'title': 'FX战士久留美'},
          {'language': '日文', 'title': 'FX戦士くるみちゃん'},
        ],
        'tags': [
          {'name': '日常', 'count': 30},
        ],
        'episodes': [
          {
            'episodeId': 198470001,
            'episodeTitle': '第1集',
            'episodeNumber': '1',
            'airDate': '2024-01-06T00:00:00',
          },
          {
            'episodeId': 198470002,
            'episodeTitle': '第2集',
            'episodeNumber': '2',
            'airDate': '',
          },
        ],
      };

  DanmakuBangumiDetail detailOf({int animeId = 19847}) =>
      DanmakuBangumiDetail.fromJson(payload(animeId: animeId));

  test('存进去能原样读回来（分集/多语言标题/标签都不丢）', () async {
    await repo.save('19847', detailOf());

    final loaded = repo.read('19847');
    expect(loaded, isNotNull);
    expect(loaded!.animeId, 19847);
    expect(loaded.bangumiId, '19847');
    expect(loaded.animeTitle, 'FX战士久留美');
    expect(loaded.intro, '简介正文');
    expect(loaded.rating, 7.5);
    expect(loaded.isOnAir, isTrue);
    expect(loaded.episodes.length, 2);
    expect(loaded.episodes.first.episodeId, 198470001);
    expect(loaded.episodes.first.episodeNumber, '1');
    expect(loaded.episodes.first.airDateLabel, '2024-01-06');
    expect(loaded.episodes.last.airDateLabel, '');
    expect(loaded.titles.map((item) => item.language), ['中文', '日文']);
    expect(loaded.titles.last.title, 'FX戦士くるみちゃん');
    expect(loaded.tags.single.name, '日常');
    expect(loaded.tags.single.count, 30);
  });

  test('没写过的库返回 null（调用方据此退化成"点一次取分集"）', () {
    expect(repo.read('999999'), isNull);
    expect(repo.read(''), isNull);
  });

  test('损坏的缓存按无缓存处理并清掉，不抛给界面', () async {
    await box.put('19847', '{"detail": {"animeId": 1984');
    expect(repo.read('19847'), isNull);
    expect(box.get('19847'), isNull, reason: '坏条目应当被顺手清掉');

    await box.put('19848', '不是 JSON');
    expect(repo.read('19848'), isNull);

    await box.put('19849', '{"detail": {"animeId": 0}}');
    expect(repo.read('19849'), isNull, reason: 'animeId 无效的条目等于没有');
  });

  test('超过上限按写入时间淘汰最旧的，避免无限增长', () async {
    final total = DanmakuLibraryCacheRepository.maxEntries + 2;
    for (var i = 0; i < total; i++) {
      await repo.save('id$i', detailOf(animeId: 1000 + i));
      // 让 `fetchedAtMs` 严格递增：同一毫秒内的淘汰顺序没有定义，
      // 否则这条用例会随机失败（不是实现问题，是时间分辨率问题）。
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }

    expect(box.length, DanmakuLibraryCacheRepository.maxEntries);
    expect(repo.read('id0'), isNull, reason: '最旧的应当被淘汰');
    expect(repo.read('id1'), isNull);
    expect(repo.read('id${total - 1}'), isNotNull, reason: '最新的必须留着');
  });

  test('允许注入别的箱（测试与将来的迁移都靠它）', () async {
    final other = DanmakuLibraryCacheRepository(box: box);
    await other.save('19847', detailOf());
    expect(repo.read('19847')?.animeTitle, 'FX战士久留美');
  });
}
