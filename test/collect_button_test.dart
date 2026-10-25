import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyw/bean/widget/collect_button.dart';
import 'package:wyw/services/storage/collect_type.dart';

/// 收藏状态按钮：菜单列出全部 6 个状态（未收藏也是合法状态之一），
/// 选中新状态回调；禁用时菜单不可用。
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required CollectType type,
    ValueChanged<CollectType>? onChanged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: CollectButton(type: type, onChanged: onChanged),
          ),
        ),
      ),
    );
  }

  testWidgets('图标按钮展示当前状态并可切换', (tester) async {
    CollectType? picked;
    await pump(
      tester,
      type: CollectType.none,
      onChanged: (value) => picked = value,
    );

    expect(find.byIcon(CollectButton.iconFor(CollectType.none)), findsOneWidget);

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    // 6 个状态都在菜单里
    for (final type in CollectType.values) {
      expect(find.text(type.label), findsOneWidget,
          reason: '${type.label} 应出现在菜单里');
    }

    await tester.tap(find.text('在看'));
    await tester.pumpAndSettle();
    expect(picked, CollectType.watching);
  });

  testWidgets('当前状态在菜单里被标记为选中且不可点', (tester) async {
    await pump(
      tester,
      type: CollectType.watched,
      onChanged: (_) {},
    );
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    final item = tester.widget<MenuItemButton>(
      find.ancestor(
        of: find.text('看过'),
        matching: find.byType(MenuItemButton),
      ),
    );
    expect(item.onPressed, isNull, reason: '已选中的状态不应再次触发回调');
  });

  testWidgets('禁用（onChanged 为 null）时不展开菜单', (tester) async {
    await pump(tester, type: CollectType.watching);
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    for (final type in CollectType.values) {
      expect(find.text(type.label), findsNothing);
    }
  });

  testWidgets('extend 形态显示状态文字', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: CollectButton.extend(
              type: CollectType.abandoned,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('抛弃'), findsOneWidget);
    expect(
      find.byIcon(CollectButton.iconFor(CollectType.abandoned)),
      findsOneWidget,
    );
  });
}
