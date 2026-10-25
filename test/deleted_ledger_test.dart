import 'package:flutter_test/flutter_test.dart';
import 'package:wyw/utils/deleted_ledger.dart';

/// 会话级「本次已删除」清单（收藏页与历史页共用的通用件）行为回归。
///
/// 契约：
///   - 最新删除在前
///   - 批量删除共享同一个 `deletedAt`，批次内保持传入顺序
///   - **不加上限**
///   - 出账按 `keyOf` 匹配
void main() {
  DeletedLedger<Map<String, String>> ledgerOf(
    Object Function(Map<String, String>) keyOf,
  ) =>
      DeletedLedger<Map<String, String>>(keyOf: keyOf);

  Map<String, String> item(String id) => {'id': id};

  test('泛型：同一套清单可服务两种条目类型', () {
    final strings = DeletedLedger<String>(keyOf: (s) => s);
    strings.add('a');
    expect(strings.count, 1);

    final maps = ledgerOf((m) => m['id']!);
    maps.add(item('a'));
    expect(maps.count, 1);
  });

  test('新增的删除记录排在最前', () {
    final ledger = ledgerOf((m) => m['id']!);
    ledger.add(item('a'), at: DateTime(2026, 1, 1, 10));
    ledger.add(item('b'), at: DateTime(2026, 1, 1, 11));

    expect(ledger.count, 2);
    expect(ledger.entries.map((r) => r.item['id']).toList(), ['b', 'a']);
    expect(ledger.entries.first.deletedAt, DateTime(2026, 1, 1, 11));
  });

  test('批量入账：共享同一删除时间，且保持传入顺序', () {
    final stamp = DateTime(2026, 1, 1, 12);
    final ledger = ledgerOf((m) => m['id']!)
      ..addAll([item('a'), item('b'), item('c')], at: stamp);

    // 传入顺序 = 用户当时看到的列表顺序（多选/清空的入参）
    expect(ledger.entries.map((r) => r.item['id']).toList(), ['a', 'b', 'c']);
    expect(ledger.entries.every((r) => r.deletedAt == stamp), isTrue);
  });

  test('批量入账后再单条删除，新删除排在最前', () {
    final stamp = DateTime(2026, 1, 1, 12);
    final ledger = ledgerOf((m) => m['id']!)
      ..addAll([item('a'), item('b')], at: stamp)
      ..add(item('c'), at: DateTime(2026, 1, 1, 13));

    expect(ledger.entries.map((r) => r.item['id']).toList(), ['c', 'a', 'b']);
  });

  test('出账按 keyOf 匹配；不存在时返回 null', () {
    final ledger = ledgerOf((m) => m['id']!)..add(item('a'));
    expect(ledger.remove(item('missing')), isNull);
    expect(ledger.count, 1);

    final removed = ledger.remove(item('a'));
    expect(removed, isNotNull);
    expect(removed!.item['id'], 'a');
    expect(ledger.isEmpty, isTrue);
  });

  test('清空记录只丢弃恢复机会（不涉及数据）', () {
    final ledger = ledgerOf((m) => m['id']!)
      ..addAll([item('a'), item('b')]);
    ledger.clear();
    expect(ledger.isEmpty, isTrue);
    expect(ledger.count, 0);
  });

  test('不加上限：大量删除全部保留', () {
    final ledger = ledgerOf((m) => m['id']!);
    for (var i = 0; i < 1000; i++) {
      ledger.add(item('id-$i'));
    }
    expect(ledger.count, 1000);
    expect(ledger.entries.first.item['id'], 'id-999');
    expect(ledger.entries.last.item['id'], 'id-0');
  });

  test('entries 是只读视图（外部改不动内部状态）', () {
    final ledger = ledgerOf((m) => m['id']!)..add(item('a'));
    expect(() => ledger.entries.clear(), throwsUnsupportedError);
    expect(ledger.count, 1);
  });
}
