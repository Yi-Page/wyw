import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyw/pages/collect/collect_deleted_dialog.dart';
import 'package:wyw/services/storage/collect_entry.dart';
import 'package:wyw/services/storage/collect_type.dart';
import 'package:wyw/utils/deleted_ledger.dart';

/// 收藏页「本次已删除」弹窗的行内容（外壳行为见 `deleted_entries_shell_test.dart`）。
void main() {
  CollectEntry entry({
    required String id,
    required String title,
    CollectType type = CollectType.none,
    String plugin = 'ccc',
  }) =>
      CollectEntry(
        pluginName: plugin,
        id: id,
        title: title,
        // 封面留空 → 占位容器，避免 widget 测试里发网络请求
        cover: '',
        visitTime: DateTime.now().subtract(const Duration(minutes: 30)),
        kv: const {},
        collectType: type.value,
        collectedAt: type.isCollected
            ? DateTime.now().subtract(const Duration(minutes: 5))
            : null,
      );

  DeletedRecord<CollectEntry> record(CollectEntry e) =>
      (item: e, deletedAt: DateTime.now().subtract(const Duration(minutes: 1)));

  Future<void> pump(
    WidgetTester tester, {
    required List<DeletedRecord<CollectEntry>> entries,
    required Future<void> Function(CollectEntry) onRestore,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showCollectDeletedDialog(
                  context,
                  entries: entries,
                  displayNameOf: (pluginName) => '插件展示名($pluginName)',
                  onRestore: onRestore,
                  onRestoreAll: (_) async {},
                  onClear: () {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('行内容：标题 / 来源插件展示名 / 条目 id / 收藏状态 / 删除时间', (tester) async {
    await pump(
      tester,
      entries: [
        record(entry(id: 'a', title: '作品 A', type: CollectType.watching)),
        record(entry(id: 'b', title: '作品 B', plugin: 'jm')),
      ],
      onRestore: (_) async {},
    );

    expect(find.text('作品 A'), findsOneWidget);
    expect(find.text('作品 B'), findsOneWidget);
    expect(find.textContaining('插件展示名(ccc)'), findsOneWidget);
    expect(find.textContaining('插件展示名(jm)'), findsOneWidget);
    expect(find.text('a'), findsOneWidget);
    expect(find.text('在看'), findsOneWidget);
    expect(find.text('未收藏'), findsOneWidget);
    expect(find.textContaining('访问'), findsWidgets);
    expect(find.textContaining('删除'), findsWidgets);
    expect(find.text('恢复'), findsNWidgets(2));
    // 收藏页专属副标题
    expect(find.textContaining('恢复后回到原来的位置与收藏状态'), findsOneWidget);
  });

  testWidgets('单条恢复回调收到该条目', (tester) async {
    final restored = <String>[];
    await pump(
      tester,
      entries: [
        record(entry(id: 'a', title: '作品 A')),
        record(entry(id: 'b', title: '作品 B')),
      ],
      onRestore: (e) async => restored.add(e.id),
    );

    await tester.tap(find.text('恢复').first);
    await tester.pumpAndSettle();

    expect(restored, ['a']);
    expect(find.text('作品 A'), findsNothing);
  });
}
