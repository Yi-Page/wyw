import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyw/bean/dialog/deleted_entries_dialog.dart';
import 'package:wyw/utils/deleted_ledger.dart';

/// 「本次已删除」弹窗外壳（收藏页 / 历史页共用）的行为回归。
///
/// 尺寸与样式对齐播放器截图管理弹窗（`player_screenshot_sheet.dart`），
/// 这里用最小的 tile 只验证外壳：标题/副标题/行/底部动作/恢复/空态/窄屏/Esc。
void main() {
  DeletedRecord<String> record(String id) =>
      (item: id, deletedAt: DateTime.now().subtract(const Duration(minutes: 2)));

  Future<void> pumpDialog(
    WidgetTester tester, {
    required List<DeletedRecord<String>> entries,
    required Future<void> Function(String) onRestore,
    required Future<void> Function(List<String>) onRestoreAll,
    required VoidCallback onClear,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDeletedEntriesDialog<String>(
                  context,
                  entries: entries,
                  subtitleOf: (count) => '$count 条 · 测试副标题',
                  semanticsOf: (r) => '条目 ${r.item}',
                  tileBuilder: (r, wide, onRestore) => Material(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    child: Row(
                      children: [
                        Expanded(child: Text('行 ${r.item}')),
                        TextButton(
                          onPressed: onRestore,
                          child: const Text('恢复'),
                        ),
                      ],
                    ),
                  ),
                  onRestore: onRestore,
                  onRestoreAll: onRestoreAll,
                  onClear: onClear,
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

  testWidgets('渲染标题/副标题/行与底部动作', (tester) async {
    await pumpDialog(
      tester,
      entries: [record('a'), record('b')],
      onRestore: (_) async {},
      onRestoreAll: (_) async {},
      onClear: () {},
    );

    expect(find.text('本次已删除'), findsOneWidget);
    expect(find.text('2 条 · 测试副标题'), findsOneWidget);
    expect(find.text('行 a'), findsOneWidget);
    expect(find.text('行 b'), findsOneWidget);
    expect(find.text('全部恢复（2）'), findsOneWidget);
    expect(find.text('清空记录'), findsOneWidget);
    expect(find.text('关闭'), findsOneWidget);
  });

  testWidgets('单条恢复：回调收到该条目，行从弹窗消失', (tester) async {
    final restored = <String>[];
    await pumpDialog(
      tester,
      entries: [record('a'), record('b')],
      onRestore: (item) async => restored.add(item),
      onRestoreAll: (_) async {},
      onClear: () {},
    );

    await tester.tap(find.text('恢复').first);
    await tester.pumpAndSettle();

    expect(restored, ['a']);
    expect(find.text('行 a'), findsNothing);
    expect(find.text('行 b'), findsOneWidget);
    expect(find.text('全部恢复（1）'), findsOneWidget);
  });

  testWidgets('全部恢复：回调收到全部条目，弹窗转为空态', (tester) async {
    final restoredAll = <List<String>>[];
    await pumpDialog(
      tester,
      entries: [record('a'), record('b')],
      onRestore: (_) async {},
      onRestoreAll: (items) async => restoredAll.add(items),
      onClear: () {},
    );

    await tester.tap(find.text('全部恢复（2）'));
    await tester.pumpAndSettle();

    expect(restoredAll.single, ['a', 'b']);
    expect(find.text('行 a'), findsNothing);
    expect(find.text('本次没有待恢复的删除记录'), findsOneWidget);
  });

  testWidgets('清空记录：回调触发且弹窗关闭', (tester) async {
    var cleared = 0;
    await pumpDialog(
      tester,
      entries: [record('a')],
      onRestore: (_) async {},
      onRestoreAll: (_) async {},
      onClear: () => cleared++,
    );

    await tester.tap(find.text('清空记录'));
    await tester.pumpAndSettle();

    expect(cleared, 1);
    expect(find.text('本次已删除'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('空清单：显示空态且动作禁用', (tester) async {
    await pumpDialog(
      tester,
      entries: const [],
      onRestore: (_) async {},
      onRestoreAll: (_) async {},
      onClear: () {},
    );

    expect(find.text('本次没有待恢复的删除记录'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '清空记录'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('Esc 关闭弹窗', (tester) async {
    await pumpDialog(
      tester,
      entries: [record('a')],
      onRestore: (_) async {},
      onRestoreAll: (_) async {},
      onClear: () {},
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('本次已删除'), findsNothing);
  });

  testWidgets('窄视口走非宽布局且不溢出', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpDialog(
      tester,
      entries: [record('a'), record('b')],
      onRestore: (_) async {},
      onRestoreAll: (_) async {},
      onClear: () {},
    );

    expect(tester.takeException(), isNull);
    expect(find.text('行 b'), findsOneWidget);
  });
}
