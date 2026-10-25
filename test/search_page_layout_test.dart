import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:mobx/mobx.dart' as mobx;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:wyw/pages/plugin/plugin_controller.dart';
import 'package:wyw/pages/search/search_controller.dart';
import 'package:wyw/pages/search/search_page.dart';
import 'package:wyw/plugins/plugin.dart';
import 'package:wyw/services/storage/storage.dart';

/// 搜索页结果区版式契约（网格 → 纵向列表）：
///   1. 一个结果一张卡、独占一行 —— 宽度铺满窗口，不再按窗口宽度切 1/2/3 列；
///   2. 卡片高度由卡片自身内容决定 —— 不同高度的卡片不会被同排拉齐 / 裁切；
///   3. 聚合区块折叠时只展示前 3 条，展开后展示全部。
///
/// 背景：网格布局里卡片的宽度由 Dart 侧列数决定（宽屏 1/3 宽），高度由
/// `IntrinsicHeight` 按行取最大，插件没法自己定卡片尺寸；改成纵向列表后
/// 宽度跟窗口、高度跟内容。
///
/// 页面用 `SysAppBar` → `DesktopWindowConfig` → `GStorage.getSetting`，
/// 所以要按项目既有做法先 mock path_provider 再 `GStorage.init()`。
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';
}

class _LoadedPlugin extends Plugin {
  _LoadedPlugin({required super.name, super.displayName});

  /// 页面用 `readyPlugins`（`isLoaded`）筛可见插件；测试不建引擎，
  /// 直接声明「已就绪」。
  @override
  bool get isLoaded => true;
}

/// 造一张只关心尺寸的结果卡片：高度由参数决定，宽度交给列表。
Widget _resultCard(double height, {Key? key}) =>
    Card(key: key, child: SizedBox(height: height));

/// 启动搜索页。插件与搜索状态在调用前准备好（页面是纯展示，不触发搜索）。
Future<void> _pumpSearchPage(
  WidgetTester tester, {
  required SearchPageController searchController,
  List<Plugin> plugins = const [],
  double width = 1200,
  double height = 900,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final pluginController = PluginController();
  mobx.runInAction(() => pluginController.plugins.addAll(plugins));

  final module = createModule(register: (c) {
    c
      ..addSingleton<PluginController>(() => pluginController)
      ..addSingleton<SearchPageController>(() => searchController)
      ..route('/', child: (context, state) => const SearchPage());
  });
  await tester.pumpWidget(
    ModularApp(
      module: module,
      child: Builder(
        builder: (context) => MaterialApp.router(
          routerConfig: ModularApp.routerConfigOf(context),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('wyw_search_page_test');
    Hive.init(tempDir.path);
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await GStorage.init();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  testWidgets('单源 tab：一卡一行、宽度铺满窗口、高度由卡片内容决定', (tester) async {
    const shortKey = ValueKey('short');
    const tallKey = ValueKey('tall');
    final searchController = SearchPageController()
      ..activateTab('jm'); // 停在插件 tab（默认是聚合 tab）
    mobx.runInAction(() {
      searchController.tabStates['jm'] = SearchState(
        results: [
          _resultCard(60, key: shortKey),
          _resultCard(140, key: tallKey),
        ],
        hasMore: false,
        lastSearchTime: DateTime.now(),
      );
    });

    await _pumpSearchPage(
      tester,
      searchController: searchController,
      plugins: [_LoadedPlugin(name: 'jm', displayName: 'JM')],
    );

    final shortSize = tester.getSize(find.byKey(shortKey));
    final tallSize = tester.getSize(find.byKey(tallKey));

    // 整宽：窗口 1200 - SliverPadding 8*2；卡片自带的 margin 已包含在卡片尺寸里。
    // 网格布局下这里只有 ~1/3 宽，这条断言就是防回退的护栏。
    expect(shortSize.width, closeTo(1200 - 16, 1));
    expect(tallSize.width, shortSize.width);

    // 高度跟着内容走：两张卡高度差 = 内容高度差（网格的 IntrinsicHeight
    // 会把同排卡片拉成一样高）。
    expect(tallSize.height - shortSize.height, closeTo(80, 1));

    // 一卡一行：同一列、上下相邻。
    expect(tester.getTopLeft(find.byKey(shortKey)).dx,
        tester.getTopLeft(find.byKey(tallKey)).dx);
    expect(tester.getTopLeft(find.byKey(tallKey)).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.byKey(shortKey)).dy));
  });

  testWidgets('聚合 tab：折叠只展示前 3 条，展开后展示全部', (tester) async {
    final searchController = SearchPageController();
    mobx.runInAction(() {
      searchController.tabStates['jm'] = SearchState(
        results: [
          for (var i = 0; i < 5; i++) _resultCard(40, key: ValueKey('r$i')),
        ],
        hasMore: false,
        lastSearchTime: DateTime.now(),
      );
    });

    await _pumpSearchPage(
      tester,
      searchController: searchController,
      plugins: [_LoadedPlugin(name: 'jm', displayName: 'JM')],
    );

    // 区块头显示总数，内容默认折叠成前 3 条。
    expect(find.text('5 条'), findsOneWidget);
    expect(find.byKey(const ValueKey('r2')), findsOneWidget);
    expect(find.byKey(const ValueKey('r3')), findsNothing);
    expect(find.byKey(const ValueKey('r4')), findsNothing);

    // 点头部（「5 条」在可点击的区块头里）展开 → 5 条全出。
    await tester.tap(find.text('5 条'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('r3')), findsOneWidget);
    expect(find.byKey(const ValueKey('r4')), findsOneWidget);
  });
}
