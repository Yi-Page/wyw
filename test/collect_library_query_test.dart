import 'package:flutter_test/flutter_test.dart';
import 'package:wyw/pages/collect/collect_library_query.dart';
import 'package:wyw/pages/collect/collect_page.dart';
import 'package:wyw/services/storage/collect_entry.dart';
import 'package:wyw/services/storage/collect_type.dart';

/// 收藏页查询：7 个 tab 的计数、搜索与排序。
///
/// 「全部」tab（`type == null`）**包含未收藏**——这是与 Kazumi 的关键差异
/// （Kazumi 的收藏页只展示已收藏项）。
void main() {
  CollectEntry make({
    required String id,
    required String title,
    CollectType type = CollectType.none,
    required DateTime visitTime,
    DateTime? collectedAt,
  }) =>
      CollectEntry(
        pluginName: 'pluginA',
        id: id,
        title: title,
        cover: '',
        visitTime: visitTime,
        kv: const {},
        collectType: type.value,
        collectedAt: collectedAt,
      );

  final entries = <CollectEntry>[
    make(
      id: 'a',
      title: 'Banana',
      type: CollectType.watching,
      visitTime: DateTime(2026, 1, 1),
      collectedAt: DateTime(2026, 3, 1),
    ),
    make(
      id: 'b',
      title: 'apple',
      type: CollectType.none,
      visitTime: DateTime(2026, 1, 3),
    ),
    make(
      id: 'c',
      title: 'Cherry',
      type: CollectType.watched,
      visitTime: DateTime(2026, 1, 2),
      collectedAt: DateTime(2026, 2, 1),
    ),
    make(
      id: 'd',
      title: 'date',
      type: CollectType.none,
      visitTime: DateTime(2026, 1, 4),
    ),
  ];

  group('tab 组成与顺序（已拍板契约）', () {
    test('全部 / 未收藏 / 在看 / 想看 / 看过 / 搁置 / 抛弃', () {
      expect(collectCategories, const <CollectType?>[
        null,
        CollectType.none,
        CollectType.watching,
        CollectType.planToWatch,
        CollectType.watched,
        CollectType.onHold,
        CollectType.abandoned,
      ]);
    });

    test('展示顺序与枚举数值顺序不同（看过在搁置之前）', () {
      expect(
        collectCategories.indexOf(CollectType.watched) <
            collectCategories.indexOf(CollectType.onHold),
        isTrue,
      );
      // 数值顺序照 Kazumi：搁置(3) < 看过(4)
      expect(CollectType.onHold.value < CollectType.watched.value, isTrue);
    });
  });

  group('分组日期键跟随排序', () {
    test('名称排序不分组，两个时间排序都分组', () {
      expect(CollectSort.title.groupsByDate, isFalse);
      expect(CollectSort.recentVisit.groupsByDate, isTrue);
      expect(CollectSort.recentlyChanged.groupsByDate, isTrue);
    });

    test('最近访问用访问时间；最近变更用收藏时间（未收藏回退访问时间）', () {
      final collected = make(
        id: 'a',
        title: 'a',
        type: CollectType.watching,
        visitTime: DateTime(2026, 1, 1),
        collectedAt: DateTime(2026, 3, 1),
      );
      final uncollected = make(
        id: 'b',
        title: 'b',
        visitTime: DateTime(2026, 1, 3),
      );

      expect(CollectSort.recentVisit.groupTimeOf(collected), DateTime(2026, 1, 1));
      expect(
        CollectSort.recentlyChanged.groupTimeOf(collected),
        DateTime(2026, 3, 1),
      );
      expect(
        CollectSort.recentlyChanged.groupTimeOf(uncollected),
        DateTime(2026, 1, 3),
      );
    });

    test('最近变更排序下同一日期必然连续（分组标题不会重复出现）', () {
      final list = <CollectEntry>[
        make(
          id: 'x',
          title: 'x',
          type: CollectType.watching,
          visitTime: DateTime(2026, 1, 1),
          collectedAt: DateTime(2026, 5, 2, 10),
        ),
        make(
          id: 'y',
          title: 'y',
          type: CollectType.watched,
          visitTime: DateTime(2026, 1, 2),
          collectedAt: DateTime(2026, 5, 2, 9),
        ),
        make(
          id: 'z',
          title: 'z',
          type: CollectType.watching,
          visitTime: DateTime(2026, 1, 3),
          collectedAt: DateTime(2026, 4, 1),
        ),
      ];

      final sorted =
          CollectLibraryQuery(list, '').results(null, CollectSort.recentlyChanged);
      expect(sorted.map((e) => e.id).toList(), ['x', 'y', 'z']);

      final days = sorted.map((e) {
        final t = CollectSort.recentlyChanged.groupTimeOf(e);
        return DateTime(t.year, t.month, t.day);
      }).toList();
      final runs = <DateTime>[];
      for (final day in days) {
        if (runs.isEmpty || runs.last != day) runs.add(day);
      }
      expect(runs.length, days.toSet().length,
          reason: '同一日期必须相邻，否则分组会被切成多段');
    });
  });

  group('默认页签设置值 → tab 下标', () {
    test('-1 表示全部', () {
      expect(collectTabIndexForSetting(-1), 0);
    });

    test('各收藏状态映射到对应 tab（与 collectCategories 顺序一致）', () {
      for (final type in CollectType.values) {
        expect(
          collectTabIndexForSetting(type.value),
          collectCategories.indexOf(type),
          reason: '${type.label}(${type.value})',
        );
      }
    });

    test('未知数值回退全部（而不是误判成未收藏）', () {
      expect(collectTabIndexForSetting(99), 0);
      expect(collectTabIndexForSetting(-7), 0);
    });
  });

  group('插件分类筛选（allowedPlugins）', () {
    CollectEntry make(String id, {String plugin = 'pluginA'}) => CollectEntry(
          pluginName: plugin,
          id: id,
          title: '标题 $id',
          cover: '',
          visitTime: DateTime(2026, 1, 1),
          kv: const {},
          collectType: CollectType.none.value,
        );

    final items = [
      make('a', plugin: 'ccc'),
      make('b', plugin: 'jm'),
      make('c', plugin: 'ccc'),
      make('d', plugin: 'hitomi'),
    ];

    test('null = 不过滤（全部）', () {
      final query = CollectLibraryQuery(items, '', allowedPlugins: null);
      expect(query.total, 4);
      expect(query.count(null), 4);
    });

    test('只保留允许的插件', () {
      final query = CollectLibraryQuery(
        items,
        '',
        allowedPlugins: const {'ccc'},
      );
      expect(query.total, 2);
      expect(
        query.results(null, CollectSort.recentVisit).map((e) => e.id).toList(),
        ['a', 'c'],
      );
    });

    test('计数跟随插件筛选（tab 计数与「全部」一致）', () {
      final query = CollectLibraryQuery(
        items,
        '',
        allowedPlugins: const {'jm', 'hitomi'},
      );
      expect(query.count(null), 2);
      expect(query.count(CollectType.none), 2);
      expect(query.count(CollectType.watching), 0);
    });

    test('插件筛选与标题搜索叠加', () {
      final query = CollectLibraryQuery(
        items,
        '标题 b',
        allowedPlugins: const {'ccc'},
      );
      expect(query.total, 0, reason: 'ccc 里没有标题 b');

      final query2 = CollectLibraryQuery(
        items,
        '标题 b',
        allowedPlugins: const {'jm'},
      );
      expect(query2.total, 1);
    });
  });

  group('计数', () {
    test('「全部」含未收藏，等于总条目数', () {
      final query = CollectLibraryQuery(entries, '');
      expect(query.count(null), 4);
      expect(query.total, 4);
    });

    test('各状态 tab 计数', () {
      final query = CollectLibraryQuery(entries, '');
      expect(query.count(CollectType.none), 2);
      expect(query.count(CollectType.watching), 1);
      expect(query.count(CollectType.watched), 1);
      expect(query.count(CollectType.planToWatch), 0);
      expect(query.count(CollectType.onHold), 0);
      expect(query.count(CollectType.abandoned), 0);
    });

    test('7 个 tab 计数之和 = 全部（未收藏 + 5 态并集 = 全集）', () {
      final query = CollectLibraryQuery(entries, '');
      final sum = [
        CollectType.none,
        CollectType.watching,
        CollectType.planToWatch,
        CollectType.watched,
        CollectType.onHold,
        CollectType.abandoned,
      ].fold<int>(0, (acc, type) => acc + query.count(type));
      expect(sum, query.count(null));
    });
  });

  group('搜索', () {
    test('按标题过滤（大小写不敏感）', () {
      final query = CollectLibraryQuery(entries, 'an');
      // Banana 命中；apple/date/Cherry 不命中
      expect(query.total, 1);
      expect(query.count(null), 1);
      expect(query.results(null, CollectSort.recentVisit).single.id, 'a');
    });

    test('多词 AND 匹配', () {
      final query = CollectLibraryQuery(entries, 'ban ana');
      expect(query.total, 1);
      expect(query.count(CollectType.watching), 1);
    });

    test('空搜索词不过滤', () {
      expect(CollectLibraryQuery(entries, '   ').total, 4);
    });

    test('搜索无结果时各 tab 计数为 0', () {
      final query = CollectLibraryQuery(entries, 'zzz');
      expect(query.count(null), 0);
      expect(query.count(CollectType.none), 0);
    });
  });

  group('筛选与排序', () {
    test('「全部」包含未收藏条目', () {
      final query = CollectLibraryQuery(entries, '');
      final all = query.results(null, CollectSort.recentVisit);
      expect(all.length, 4);
      expect(all.map((e) => e.id), containsAll(['b', 'd']));
    });

    test('按最近访问倒序', () {
      final query = CollectLibraryQuery(entries, '');
      final sorted = query.results(null, CollectSort.recentVisit);
      expect(sorted.map((e) => e.id).toList(), ['d', 'b', 'c', 'a']);
    });

    test('按最近变更倒序（未收藏回退到访问时间）', () {
      final query = CollectLibraryQuery(entries, '');
      final sorted = query.results(null, CollectSort.recentlyChanged);
      // collectedAt：a=3/1, c=2/1；未收藏回退 visitTime：d=1/4, b=1/3
      expect(sorted.map((e) => e.id).toList(), ['a', 'c', 'd', 'b']);
    });

    test('按名称升序（大小写不敏感）', () {
      final query = CollectLibraryQuery(entries, '');
      final sorted = query.results(null, CollectSort.title);
      expect(sorted.map((e) => e.id).toList(), ['b', 'a', 'c', 'd']);
    });

    test('状态 tab 只返回该状态条目', () {
      final query = CollectLibraryQuery(entries, '');
      expect(
        query.results(CollectType.none, CollectSort.recentVisit)
            .map((e) => e.id)
            .toList(),
        ['d', 'b'],
      );
      expect(
        query
            .results(CollectType.watching, CollectSort.recentVisit)
            .single
            .id,
        'a',
      );
      expect(query.results(CollectType.abandoned, CollectSort.recentVisit),
          isEmpty);
    });
  });
}
