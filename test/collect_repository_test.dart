import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:wyw/repositories/collect_repository.dart';
import 'package:wyw/services/storage/collect_entry.dart';
import 'package:wyw/services/storage/collect_type.dart';

/// 收藏仓库（Hive 后端）的行为回归。
///
/// 最重要的一条：**插件 upsert 绝不能覆盖用户的收藏状态**——
/// 旧实现是整条替换，一旦加上 `collectType`，用户设的状态会被插件清成未收藏。
void main() {
  late Directory tempDir;
  late Box<CollectEntry> box;
  late int limit;
  late CollectRepository repository;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('wyw_collect_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(11)) {
      Hive.registerAdapter(CollectEntryAdapter());
    }
  });

  setUp(() async {
    box = await Hive.openBox<CollectEntry>('collectibles_test');
    await box.clear();
    limit = 0;
    repository = CollectRepository(
      box: box,
      uncollectedLimitReader: () => limit,
    );
  });

  tearDown(() async {
    await box.close();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> upsert(
    String id, {
    String title = '标题',
    String plugin = 'pluginA',
  }) =>
      repository.upsert(
        pluginName: plugin,
        id: id,
        title: title,
        cover: 'cover',
        kv: const {'detailUrl': 'https://example.com'},
      );

  group('upsert（合并语义）', () {
    test('新条目默认未收藏', () async {
      await upsert('a');
      final entry = await repository.find(pluginName: 'pluginA', id: 'a');
      expect(entry, isNotNull);
      expect(entry!.type, CollectType.none);
      expect(entry.collectedAt, isNull);
      expect(entry.title, '标题');
    });

    test('已收藏条目被插件 upsert 后收藏状态不变（核心回归）', () async {
      await upsert('a', title: '旧标题');
      await repository.setCollectType(
        pluginName: 'pluginA',
        id: 'a',
        type: CollectType.watching,
      );
      final collected =
          await repository.find(pluginName: 'pluginA', id: 'a');
      expect(collected!.type, CollectType.watching);
      final collectedAt = collected.collectedAt;
      expect(collectedAt, isNotNull);

      // 插件再次 open（用户又进了一次详情页）
      await upsert('a', title: '新标题');

      final after = await repository.find(pluginName: 'pluginA', id: 'a');
      expect(after!.title, '新标题', reason: '插件可写字段应更新');
      expect(after.type, CollectType.watching, reason: '收藏状态必须保留');
      expect(after.collectedAt, collectedAt, reason: '收藏时间必须保留');
      expect(box.length, 1, reason: '同 id 不应产生第二条');
    });

    test('id / pluginName 为空时抛错', () async {
      expect(
        () => repository.upsert(
          pluginName: 'pluginA',
          id: '',
          title: 't',
        ),
        throwsArgumentError,
      );
      expect(
        () => repository.upsert(
          pluginName: '',
          id: 'a',
          title: 't',
        ),
        throwsArgumentError,
      );
    });

    test('长 id（代理 URL）不会触发 Hive key 长度限制', () async {
      final longId = 'http://127.0.0.1:12345/m3u8?${'x' * 400}';
      await upsert(longId);
      final entry = await repository.find(pluginName: 'pluginA', id: longId);
      expect(entry, isNotNull);
      expect(entry!.id, longId);
    });
  });

  group('收藏状态', () {
    test('切换状态写入 collectedAt，切回未收藏清空', () async {
      await upsert('a');
      await repository.setCollectType(
        pluginName: 'pluginA',
        id: 'a',
        type: CollectType.watched,
      );
      var entry = await repository.find(pluginName: 'pluginA', id: 'a');
      expect(entry!.collectType, CollectType.watched.value);
      expect(entry.collectedAt, isNotNull);

      await repository.setCollectType(
        pluginName: 'pluginA',
        id: 'a',
        type: CollectType.none,
      );
      entry = await repository.find(pluginName: 'pluginA', id: 'a');
      expect(entry!.collectType, 0);
      expect(entry.collectedAt, isNull);
    });

    test('对不存在的条目设置状态是 no-op（收藏只作用于已有足迹）', () async {
      await repository.setCollectType(
        pluginName: 'pluginA',
        id: 'missing',
        type: CollectType.watching,
      );
      expect(box.length, 0);
    });
  });

  group('删除 / 撤销', () {
    test('删除即删除整条浏览历史（收藏状态随之消失）', () async {
      await upsert('a');
      await repository.setCollectType(
        pluginName: 'pluginA',
        id: 'a',
        type: CollectType.watching,
      );
      await repository.remove(pluginName: 'pluginA', id: 'a');
      expect(await repository.find(pluginName: 'pluginA', id: 'a'), isNull);
      expect(box.length, 0);
    });

    test('撤销把条目原样放回（保留 visitTime 与收藏状态）', () async {
      await upsert('a');
      await repository.setCollectType(
        pluginName: 'pluginA',
        id: 'a',
        type: CollectType.onHold,
      );
      final before = (await repository.find(pluginName: 'pluginA', id: 'a'))!;

      await repository.remove(pluginName: 'pluginA', id: 'a');
      await repository.restore(before);

      final after = (await repository.find(pluginName: 'pluginA', id: 'a'))!;
      expect(after.type, CollectType.onHold);
      expect(after.visitTime, before.visitTime);
      expect(after.collectedAt, before.collectedAt);
    });

    test('清空全部', () async {
      await upsert('a');
      await upsert('b');
      await repository.clearAll();
      expect(box.length, 0);
    });

    test('清空未收藏保留已收藏', () async {
      await upsert('a');
      await upsert('b');
      await upsert('c');
      await repository.setCollectType(
        pluginName: 'pluginA',
        id: 'b',
        type: CollectType.watching,
      );
      await repository.clearUncollected();

      final all = await repository.getAll();
      expect(all.length, 1);
      expect(all.single.id, 'b');
      expect(all.single.type, CollectType.watching);
    });
  });

  group('未收藏保留上限', () {
    Future<void> seed(int count) async {
      for (var i = 0; i < count; i++) {
        await upsert('id-$i', title: '标题 $i');
        // 拉开 visitTime，保证"最旧优先"可判定
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
    }

    test('无上限（0）不清理', () async {
      await seed(6);
      expect(await repository.enforceUncollectedLimit(), 0);
      expect(box.length, 6);
    });

    test('超限时按最近访问最旧优先清理', () async {
      await seed(6); // 无上限写入，避免 upsert 自动清理干扰
      limit = 3;
      final removed = await repository.enforceUncollectedLimit();
      expect(removed, 3);
      final all = await repository.getAll();
      expect(all.length, 3);
      // 保留的是最近访问的 3 条
      expect(all.map((e) => e.id).toSet(), {'id-5', 'id-4', 'id-3'});
    });

    test('已收藏条目永不参与自动清理', () async {
      await seed(4);
      await repository.setCollectType(
        pluginName: 'pluginA',
        id: 'id-0',
        type: CollectType.watching,
      );
      limit = 1;
      await repository.enforceUncollectedLimit();

      final all = await repository.getAll();
      expect(all.where((e) => e.type.isCollected).length, 1,
          reason: '已收藏的 id-0 必须留下');
      expect(all.where((e) => !e.type.isCollected).length, 1);
    });

    test('upsert 会自动触发上限清理', () async {
      await seed(4);
      limit = 2;
      await upsert('id-4');
      final all = await repository.getAll();
      expect(all.length, 2);
    });
  });

  group('恢复的同 key 合并语义', () {
    Future<CollectEntry> snapshotOf(String id) async =>
        (await repository.find(pluginName: 'pluginA', id: id))!;

    test('同 key 不存在 → 原样放回（保留访问时间与收藏状态）', () async {
      await upsert('a', title: '旧标题');
      await repository.setCollectType(
        pluginName: 'pluginA',
        id: 'a',
        type: CollectType.watching,
      );
      final snapshot = await snapshotOf('a');
      await repository.remove(pluginName: 'pluginA', id: 'a');

      await repository.restore(snapshot);

      final back = await snapshotOf('a');
      expect(back.title, '旧标题');
      expect(back.type, CollectType.watching);
      expect(back.visitTime, snapshot.visitTime);
      expect(back.collectedAt, snapshot.collectedAt);
    });

    test('同 key 已被插件重新 upsert → 保留新记录并补回收藏状态', () async {
      await upsert('a', title: '旧标题');
      await repository.setCollectType(
        pluginName: 'pluginA',
        id: 'a',
        type: CollectType.watching,
      );
      final snapshot = await snapshotOf('a');
      await repository.remove(pluginName: 'pluginA', id: 'a');

      // 插件又 upsert 了同一条（详情页「相关推荐」跳到同一作品）
      await upsert('a', title: '新标题');
      final fresh = await snapshotOf('a');
      expect(fresh.type, CollectType.none);

      await repository.restore(snapshot);

      final after = await snapshotOf('a');
      expect(after.title, '新标题', reason: '较新的插件字段必须保留');
      expect(after.visitTime, fresh.visitTime, reason: '访问时间不能倒退');
      expect(after.type, CollectType.watching, reason: '收藏状态补回');
      expect(after.collectedAt, snapshot.collectedAt, reason: '收藏时间沿用快照');
      expect(box.length, 1);
    });

    test('同 key 现存已是收藏态 → 不动（用户新状态优先）', () async {
      await upsert('a', title: '旧标题');
      await repository.setCollectType(
        pluginName: 'pluginA',
        id: 'a',
        type: CollectType.watching,
      );
      final snapshot = await snapshotOf('a');
      await repository.remove(pluginName: 'pluginA', id: 'a');

      await upsert('a', title: '新标题');
      await repository.setCollectType(
        pluginName: 'pluginA',
        id: 'a',
        type: CollectType.abandoned,
      );

      await repository.restore(snapshot);

      final after = await snapshotOf('a');
      expect(after.type, CollectType.abandoned, reason: '现存收藏状态优先');
      expect(after.title, '新标题');
    });
  });

  group('旧 JSON 迁移', () {
    test('导入旧文件（缺收藏字段 → 未收藏）', () async {
      final file = File('${tempDir.path}/plugin_history.json');
      await file.writeAsString(jsonEncode([
        {
          'pluginName': 'pluginA',
          'id': 'a',
          'title': '标题 A',
          'cover': 'coverA',
          'visitTime': '2026-01-01T00:00:00.000',
          'kv': {'detailUrl': 'https://example.com/a'},
        },
        {
          'pluginName': 'pluginB',
          'id': 'b',
          'title': '标题 B',
          'cover': '',
          'visitTime': '2026-01-02T00:00:00.000',
          'kv': <String, dynamic>{},
        },
      ]));

      final imported = await repository.importFromJsonFile(file);
      expect(imported, 2);
      expect(box.length, 2);

      final a = await repository.find(pluginName: 'pluginA', id: 'a');
      expect(a!.title, '标题 A');
      expect(a.type, CollectType.none);
      expect(a.kv['detailUrl'], 'https://example.com/a');
    });

    test('导入跳过本地已有条目（本地数据更新，不被旧 JSON 覆盖）', () async {
      await upsert('a', title: '本地标题');
      await repository.setCollectType(
        pluginName: 'pluginA',
        id: 'a',
        type: CollectType.abandoned,
      );

      final file = File('${tempDir.path}/plugin_history2.json');
      await file.writeAsString(jsonEncode([
        {
          'pluginName': 'pluginA',
          'id': 'a',
          'title': '旧 JSON 标题',
          'cover': '',
          'visitTime': '2026-01-01T00:00:00.000',
          'kv': <String, dynamic>{},
        },
      ]));

      expect(await repository.importFromJsonFile(file), 0);
      final a = (await repository.find(pluginName: 'pluginA', id: 'a'))!;
      expect(a.type, CollectType.abandoned, reason: '收藏状态必须保留');
      expect(a.title, '本地标题', reason: '本地数据更新，不应被旧 JSON 覆盖');
      expect(box.length, 1);
    });

    test('文件不存在 / 空文件返回 0', () async {
      expect(
        await repository.importFromJsonFile(
          File('${tempDir.path}/nope.json'),
        ),
        0,
      );
      final empty = File('${tempDir.path}/empty.json');
      await empty.writeAsString('  ');
      expect(await repository.importFromJsonFile(empty), 0);
    });
  });
}
