import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobx/mobx.dart' as mobx;
import 'package:wyw/bean/card/collect_entry_card.dart';
import 'package:wyw/pages/plugin/plugin_controller.dart';
import 'package:wyw/plugins/plugin.dart';
import 'package:wyw/services/storage/collect_entry.dart';
import 'package:wyw/services/storage/collect_type.dart';

/// 收藏卡片的行为回归。
///
/// 宿主把卡片包在 `Observer` 里（与收藏页一致），这样插件状态的 Observable
/// 变化能触发重建。
void main() {
  final entry = CollectEntry(
    pluginName: 'ccc',
    id: 'a',
    title: '作品 A',
    // 封面留空 → 占位，避免 widget 测试里发网络请求
    cover: '',
    visitTime: DateTime(2026, 1, 1),
    kv: const {},
    collectType: CollectType.watching.value,
    collectedAt: DateTime(2026, 1, 2),
  );

  Future<void> pumpCard(WidgetTester tester, double width) async {
    final module = createModule(register: (c) {
      c
        ..addSingleton<PluginController>(PluginController.new)
        ..route(
          '/',
          child: (context, state) => Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: Observer(
                  builder: (_) => CollectEntryCard(entry: entry),
                ),
              ),
            ),
          ),
        );
    });
    await tester.pumpWidget(
      ModularApp(
        module: module,
        child: Builder(
          builder: (context) =>
              MaterialApp.router(routerConfig: ModularApp.routerConfigOf(context)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 供「插件状态」分支测试：先对 controller 做 setup（往列表里加禁用 / 失败的插件）
  /// 再 pump —— 卡片首次构建就直接落在目标分支，不依赖 Observable 反应式重建。
  Future<void> pumpWithState(
    WidgetTester tester,
    void Function(PluginController controller) setup,
  ) async {
    final controller = PluginController();
    setup(controller);
    final module = createModule(register: (c) {
      c
        ..addSingleton<PluginController>(() => controller)
        ..route(
          '/',
          child: (context, state) => Scaffold(
            body: Center(
              child: SizedBox(
                width: 600,
                child: Observer(
                  builder: (_) => CollectEntryCard(entry: entry),
                ),
              ),
            ),
          ),
        );
    });
    await tester.pumpWidget(
      ModularApp(
        module: module,
        child: Builder(
          builder: (context) =>
              MaterialApp.router(routerConfig: ModularApp.routerConfigOf(context)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('插件未加载（已删除）：显示特定图标 + 错误提示 tooltip', (tester) async {
    await pumpCard(tester, 600);

    // 裸 controller 没有任何插件 → 插件名解析为「已删除」
    expect(find.byIcon(Icons.extension_off), findsOneWidget);
    expect(find.byTooltip('插件已删除'), findsOneWidget);
  });

  testWidgets('插件已禁用（文件还在）：不误报已删除，保留原扩展图标', (tester) async {
    await pumpWithState(
      tester,
      (c) => mobx.runInAction(
        () => c.plugins.add(Plugin(name: entry.pluginName, enabled: false)),
      ),
    );

    expect(find.byIcon(Icons.extension_off), findsNothing,
        reason: '禁用≠删除，不应显示删除图标');
    expect(find.byIcon(Icons.extension_outlined), findsOneWidget);
    expect(find.byTooltip('插件已删除'), findsNothing);
  });

  testWidgets('插件加载失败：不误报已删除', (tester) async {
    await pumpWithState(
      tester,
      (c) => mobx.runInAction(() {
        c.plugins.add(Plugin(name: entry.pluginName)..loadError = 'test failure');
      }),
    );

    expect(find.byIcon(Icons.extension_off), findsNothing);
    expect(find.byTooltip('插件已删除'), findsNothing);
  });

  testWidgets('窄行（400）：状态按钮只留图标，不出现文字', (tester) async {
    await pumpCard(tester, 400);

    expect(find.byType(FilledButton), findsNothing, reason: '不应出现带文字的形态');
    expect(find.byType(IconButton), findsOneWidget, reason: '只应有纯图标按钮');
    expect(find.text('在看'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('宽行（600）：状态按钮带文字', (tester) async {
    await pumpCard(tester, 600);

    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.text('在看'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('阈值边界内（500）：状态按钮带文字', (tester) async {
    await pumpCard(tester, 500);

    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.text('在看'), findsOneWidget);
  });

  testWidgets('阈值边界外（499）：状态按钮只留图标', (tester) async {
    await pumpCard(tester, 499);

    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(IconButton), findsOneWidget);
  });
}
