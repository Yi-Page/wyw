import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:mobx/mobx.dart' as mobx;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:wyw/pages/plugin/plugin_controller.dart';
import 'package:wyw/pages/plugin/plugin_detail_page.dart';
import 'package:wyw/plugins/plugin.dart';
import 'package:wyw/services/storage/storage.dart';

/// 插件详情页的布局回归：
///   1. 简介 / 主页与展示名**同款独立分段**，不再有「管理属性」分组；
///   2. 只有新建模式才用悬浮「保存」（属性即时生效、源码保存就在段内），
///      编辑模式因此不再需要底部留白。
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('wyw_plugin_detail_test');
    Hive.init(tempDir.path);
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await GStorage.init();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// [plugin] 传 null = 列表里查不到该名字 = 新建模式。
  Future<void> pumpDetail(
    WidgetTester tester, {
    String? name,
    Plugin? plugin,
  }) async {
    // 基本段是懒加载 ListView：窗口太矮时下面的分段根本不会被构建，故给足高度
    tester.view.physicalSize = const Size(700, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = PluginController();
    if (plugin != null) {
      mobx.runInAction(() => controller.plugins.add(plugin));
    }
    final module = createModule(register: (c) {
      c
        ..addSingleton<PluginController>(() => controller)
        ..route(
          '/',
          child: (context, state) => PluginDetailPage(pluginName: name),
        );
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

  /// 编辑模式：记录在、还没写源码（`fileMissing`）——不会碰磁盘。
  Plugin existing() =>
      Plugin(name: 'hanime', displayName: 'Hanime')..fileMissing = true;

  testWidgets('基本段：简介 / 主页各自成段，与展示名同款；没有「管理属性」分组', (tester) async {
    await pumpDetail(tester, name: 'hanime', plugin: existing());

    expect(find.text('管理属性'), findsNothing);
    expect(find.text('展示名'), findsOneWidget);
    expect(find.text('简介'), findsOneWidget);
    expect(find.text('主页'), findsOneWidget);
  });

  testWidgets('编辑模式：没有悬浮按钮（基本段底部不留白）', (tester) async {
    await pumpDetail(tester, name: 'hanime', plugin: existing());

    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('代码段：保存源码在段内操作行，仍无悬浮按钮', (tester) async {
    await pumpDetail(tester, name: 'hanime', plugin: existing());

    await tester.tap(find.text('代码'));
    await tester.pumpAndSettle();

    expect(find.text('保存源码'), findsOneWidget);
    expect(find.text('校验'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('新建模式：悬浮「保存」还在，且尚未开放代码段', (tester) async {
    // 名字不在列表里 = 新建
    await pumpDetail(tester, name: null);

    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    expect(find.text('代码'), findsNothing);
  });

  /// 切到代码段，把 [source] 灌进编辑器并点「校验」。
  Future<void> validate(WidgetTester tester, String source) async {
    await tester.tap(find.text('代码'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), source);
    await tester.pumpAndSettle();
    await tester.tap(find.text('校验'));
    await tester.pumpAndSettle();
  }

  testWidgets('校验：删掉一半大括号要报错（以前查不出来）', (tester) async {
    await pumpDetail(tester, name: 'hanime', plugin: existing());

    await validate(
      tester,
      'class hanime extends PluginSource {\n'
      '  run() {\n'
      '    return 1;\n'
      '  }\n', // 少了最外层那个 }
    );

    expect(find.textContaining('没有闭合'), findsOneWidget);
    expect(find.textContaining('校验通过'), findsNothing);
  });

  testWidgets('校验：类外有代码给提示，但仍算通过', (tester) async {
    await pumpDetail(tester, name: 'hanime', plugin: existing());

    await validate(
      tester,
      'const CONFIG = { a: 1 };\n'
      'class hanime extends PluginSource {\n  run() {}\n}\n',
    );

    expect(find.textContaining('校验通过'), findsOneWidget);
    expect(find.textContaining('类声明之外还有代码'), findsOneWidget);
  });

  testWidgets('校验：干净源码给通过结论', (tester) async {
    await pumpDetail(tester, name: 'hanime', plugin: existing());

    await validate(
      tester,
      'class hanime extends PluginSource {\n  run() {}\n}\n',
    );

    expect(find.textContaining('校验通过：括号配平'), findsOneWidget);
  });
}
