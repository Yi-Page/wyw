import 'package:flutter_test/flutter_test.dart';
import 'package:wyw/services/storage/collect_entry.dart';
import 'package:wyw/services/storage/collect_type.dart';

/// 收藏条目模型与状态枚举的回归测试。
///
/// 关键约定：
///   - 数值与标签照 Kazumi 的 `CollectType`（`onHold=3` < `watched=4`），
///     因为数值会持久化；
///   - 未收藏（0）是插件收录历史时的默认状态；
///   - `mergeFromPlugin` 绝不覆盖用户的收藏状态。
void main() {
  CollectEntry entry({
    String title = '标题',
    int collectType = 0,
    DateTime? collectedAt,
  }) =>
      CollectEntry(
        pluginName: 'pluginA',
        id: 'id-1',
        title: title,
        cover: 'cover',
        visitTime: DateTime(2026, 1, 1),
        kv: const {'detailUrl': 'https://example.com/1'},
        collectType: collectType,
        collectedAt: collectedAt,
      );

  group('CollectType', () {
    test('数值与标签照 Kazumi', () {
      expect(CollectType.none.value, 0);
      expect(CollectType.watching.value, 1);
      expect(CollectType.planToWatch.value, 2);
      expect(CollectType.onHold.value, 3);
      expect(CollectType.watched.value, 4);
      expect(CollectType.abandoned.value, 5);

      expect(CollectType.none.label, '未收藏');
      expect(CollectType.watching.label, '在看');
      expect(CollectType.planToWatch.label, '想看');
      expect(CollectType.onHold.label, '搁置');
      expect(CollectType.watched.label, '看过');
      expect(CollectType.abandoned.label, '抛弃');
    });

    test('fromValue 往返一致，未知数值回退未收藏', () {
      for (final type in CollectType.values) {
        expect(CollectType.fromValue(type.value), type);
      }
      expect(CollectType.fromValue(99), CollectType.none);
      expect(CollectType.fromValue(-1), CollectType.none);
    });

    test('未收藏不是"已收藏"', () {
      expect(CollectType.none.isCollected, isFalse);
      for (final type in CollectType.values.where((t) => t != CollectType.none)) {
        expect(type.isCollected, isTrue);
      }
    });
  });

  group('CollectEntry', () {
    test('key 是 pluginName::id', () {
      expect(entry().key, 'pluginA::id-1');
    });

    test('toJson / fromJson 往返一致（含收藏状态）', () {
      final original = entry(
        collectType: CollectType.watched.value,
        collectedAt: DateTime(2026, 2, 3, 4, 5, 6),
      );
      final restored = CollectEntry.fromJson(original.toJson());

      expect(restored.pluginName, original.pluginName);
      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.cover, original.cover);
      expect(restored.visitTime, original.visitTime);
      expect(restored.kv, original.kv);
      expect(restored.collectType, original.collectType);
      expect(restored.collectedAt, original.collectedAt);
    });

    test('兼容旧 JSON：缺收藏字段即未收藏', () {
      final restored = CollectEntry.fromJson({
        'pluginName': 'pluginA',
        'id': 'id-1',
        'title': '标题',
        'cover': '',
        'visitTime': '2026-01-01T00:00:00.000',
        'kv': <String, dynamic>{},
      });
      expect(restored.collectType, 0);
      expect(restored.type, CollectType.none);
      expect(restored.collectedAt, isNull);
    });

    test('mergeFromPlugin 只更新插件字段，保留收藏状态', () {
      final collected = entry(
        collectType: CollectType.watching.value,
        collectedAt: DateTime(2026, 5, 5),
      );
      final merged = collected.mergeFromPlugin(
        title: '新标题',
        cover: '新封面',
        kv: const {'detailUrl': 'https://example.com/2'},
        visitTime: DateTime(2026, 6, 6),
      );

      expect(merged.title, '新标题');
      expect(merged.cover, '新封面');
      expect(merged.kv['detailUrl'], 'https://example.com/2');
      expect(merged.visitTime, DateTime(2026, 6, 6));
      // 收藏状态原样保留
      expect(merged.collectType, CollectType.watching.value);
      expect(merged.collectedAt, DateTime(2026, 5, 5));
    });

    test('withCollectType：切到已收藏刷新时间，切回未收藏清空', () {
      final now = DateTime(2026, 7, 7);
      final collected = entry().withCollectType(CollectType.onHold, now: now);
      expect(collected.collectType, CollectType.onHold.value);
      expect(collected.collectedAt, now);

      final uncollected =
          collected.withCollectType(CollectType.none, now: now);
      expect(uncollected.collectType, 0);
      expect(uncollected.collectedAt, isNull);
    });
  });
}
