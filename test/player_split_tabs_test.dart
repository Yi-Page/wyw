import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/bean/widget/tonal_card.dart';
import 'package:wyw/pages/download/download_controller.dart';
import 'package:wyw/pages/player/controller/player_aspect_ratio.dart';
import 'package:wyw/pages/player/controller/player_panel_controller.dart';
import 'package:wyw/pages/player/controller/player_super_resolution.dart';
import 'package:wyw/pages/player/controller/video_filter_controller.dart';
import 'package:wyw/pages/player/player_controller.dart';
import 'package:wyw/pages/player/split_tabs/player_split_tabs.dart';
import 'package:wyw/pages/player/split_tabs/split_tab_host.dart';
import 'package:wyw/pages/player/split_tabs/sub_danmaku.dart';
import 'package:wyw/pages/player/split_tabs/sub_display.dart';
import 'package:wyw/pages/player/split_tabs/tab_display.dart';
import 'package:wyw/modules/danmaku/danmaku_module.dart';
import 'package:wyw/pages/player/split_tabs/tab_danmaku_settings.dart';
import 'package:wyw/pages/player/widgets/split_panel_scaffold.dart';
import 'package:wyw/pages/video/video_controller.dart';
import 'package:wyw/repositories/download_repository.dart';
import 'package:wyw/services/download/download_manager.dart';
import 'package:wyw/services/player/audio_controller.dart';
import 'package:wyw/services/shaders/shader_asset_service.dart';
import 'package:wyw/services/storage/storage.dart';

/// 分屏面板的**面板级窄宽度体检**：在 280×420（§1.2 横屏面板最小宽 280）下
/// 逐个渲染 5 个页签与 5 个二级页，断言没有布局异常（`takeException()` 为 null
/// ⇒ 无溢出、无 `RenderFlex` 报错、无 `Expanded` 高度无界）。
///
/// 宿主用**真实** `PlayerController` / `VideoPageController`（面板行读的就是这些
/// observable），只有「超分辨率切换」换成记录调用的假回调——真回调会去配 mpv。
/// 外层套 `ModularApp` 只是为了让选集 tab 的 `inject<DownloadController>()` 能解析；
/// `WywDialog.observer` 挂上是为了让预设「删除」的确认框能弹出来。
///
/// 断言纪律（计划 §5）：只断言**行为与渲染结果**（不抛异常、关键文案可见、
/// 回调被调用、控制器字段被写入），不断言精确边距 / `ListView.padding` /
/// `Slider` 个数这类实现细节。
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

/// 面板宿主：真实控制器 + 记录调用的超分辨率假回调。
SplitTabHost _buildHost(List<SuperResolutionMode> superResolutionCalls) {
  final playerController =
      PlayerController(ShaderAssetService(), AudioController());
  return SplitTabHost(
    playerController: playerController,
    videoPageController: VideoPageController(),
    disableAnimations: true,
    setPlaybackSpeed: (_) async {},
    handleSuperResolutionChange: (mode) async => superResolutionCalls.add(mode),
    skipOP: () {},
    handleScreenshot: () {},
    showScreenshotCandidates: () {},
    pauseForTimedShutdown: () {},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late SplitTabHost host;
  late List<SuperResolutionMode> superResolutionCalls;

  /// 在 280×420 的面板尺寸下渲染 [child]（页签 body / 二级页 body）。
  ///
  /// [height] 只在"内容覆盖度"用例里放大（设置行是懒构建的，420 高放不下二十多行，
  /// 那种用例关心的是"这一项在不在"，不是版式；版式由默认的 420 高覆盖）。
  Future<void> pumpPanel(
    WidgetTester tester,
    Widget child, {
    double height = 420,
  }) async {
    final module = createModule(register: (c) {
      c
        // 选集 tab 会 `inject<DownloadController>()`：按 `core_module.dart` 的
        // 依赖链注册最小三件（仓储 → 管理器 → 控制器），不需要真实业务模块。
        ..addSingleton<IDownloadRepository>(DownloadRepository.new)
        ..addSingleton<IDownloadManager>(DownloadManager.new)
        ..addSingleton<DownloadController>(DownloadController.new)
        ..route(
          '/',
          child: (context, state) => Scaffold(
            body: SizedBox(width: 280, height: height, child: child),
          ),
        );
    });
    await tester.pumpWidget(
      ModularApp(
        module: module,
        // 挂上项目的对话框记账观察器，预设「删除」的确认框才弹得出来。
        navigatorObservers: [WywDialog.observer],
        child: Builder(
          builder: (context) => MaterialApp.router(
            routerConfig: ModularApp.routerConfigOf(context),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('wyw_split_tabs_test');
    Hive.init(tempDir.path);
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    // 「设置」箱刻意开成**内存 box**（`bytes:` 版本）。
    //
    // 原因：widget 测试跑在假时钟里，真实文件 I/O 的完成回调不会自己跑完，
    // 面板里点「新建 / 重命名 / 删除」触发的那次落盘会一直挂在写队列上，
    // 最终把 `Hive.close()` 挂死（Windows 上还会连带删不掉临时目录）。
    // 内存箱的写是 `Future.value()`，假时钟里也能完成；`GStorage.init()` 随后
    // 打开同名箱时直接复用这一个（Hive 不会重复打开）。
    // 真实磁盘落盘由 `video_filter_controller_test.dart` 覆盖，不在这里重复。
    await Hive.openBox<dynamic>('setting', bytes: Uint8List(0));
    await GStorage.init();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() {
    superResolutionCalls = <SuperResolutionMode>[];
    host = _buildHost(superResolutionCalls);
    VideoFilterController.instance.reset();
    host.playerController.panel.aspectRatioMode = PlayerAspectRatio.automatic;
    host.playerController.playback.superResolutionMode = SuperResolutionMode.off;
  });

  group('弹幕设置 tab（与设置页同源）', () {
    testWidgets('设置页那一批项在面板里也都在（曾只有来源/时间偏移）', (tester) async {
      // 设置行是懒构建的：默认测试窗口只有 800×600，3000 高的盒子会被裁到 600，
      // 列表只会建到一屏多。这里把窗口放大，让整张列表真的全部构建出来。
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpPanel(tester, DanmakuSettingsTab(host: host), height: 3000);

      for (final label in const [
        'BiliBili',
        'Gamer',
        '弹弹play',
        '简繁转换',
        '弹幕区域',
        '弹幕持续时间',
        '弹幕行高',
        '弹幕跟随视频倍速',
        '顶部弹幕',
        '底部弹幕',
        '滚动弹幕',
        '字体大小',
        '弹幕不透明度',
        '海量弹幕',
        '弹幕去重',
        '弹幕描边',
        '弹幕描边粗细',
        '弹幕颜色',
        '字体字重',
        '下载时缓存弹幕',
        '时间校准',
        '屏蔽规则',
      ]) {
        expect(find.text(label), findsOneWidget, reason: '面板缺少「$label」');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('改「弹幕去重」就地重跑分桶：不等换集、不联网', (tester) async {
      final danmaku = host.playerController.danmaku;
      await GStorage.putSetting<bool>(SettingsKeys.danmakuDeduplication, false);
      danmaku.applyDanmakuLoad(
        [
          for (var i = 0; i < 3; i++)
            DanmakuEntry(
              message: '哈哈',
              time: 10,
              type: 1,
              color: const Color(0xFFFFFFFF),
              source: 'DanDan',
            ),
          DanmakuEntry(
            message: '别的',
            time: 10,
            type: 1,
            color: const Color(0xFFFFFFFF),
            source: 'DanDan',
          ),
        ],
        episodeId: 1,
        libraryTitle: '某番',
        enableDanmaku: true,
      );
      expect(danmaku.danmakuCount, 4, reason: '关着去重时四条都在');

      await pumpPanel(tester, DanmakuSettingsTab(host: host), height: 3000);
      // 必须先滚到可视区：懒列表里"已构建但在视口外"的行，`tap` 会静默打偏
      // （命中不到那一行，测试却不会报错）。
      await tester.ensureVisible(find.text('弹幕去重'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('弹幕去重'));
      await tester.pumpAndSettle();

      // 三条相同内容合并成一条 + 另一条 = 2；不重新联网取弹幕也能立刻生效。
      expect(danmaku.danmakuCount, 2);
      expect(GStorage.getSetting<bool>(SettingsKeys.danmakuDeduplication), isTrue);
      expect(tester.takeException(), isNull);
    });
  });

  group('画面 tab（P4）', () {
    testWidgets('280px 下四行齐全且不溢出', (tester) async {
      await pumpPanel(tester, DisplayTab(host: host));

      expect(find.text('画面调节'), findsOneWidget);
      expect(find.text('锐化 / 对比度 / 饱和度 / 亮度 / 伽马'), findsOneWidget);
      expect(find.text('超分辨率'), findsOneWidget);
      expect(find.text('视频比例'), findsOneWidget);
      expect(find.text('视频信息'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('点「画面调节」在面板内打开画面调节二级页', (tester) async {
      await pumpPanel(tester, DisplayTab(host: host));

      await tester.tap(find.text('画面调节'));
      await tester.pumpAndSettle();

      expect(host.panel.splitPanelSubPage, SplitSubPage.filter);
      expect(tester.takeException(), isNull);
    });

    testWidgets('点「视频信息」在面板内打开视频信息二级页', (tester) async {
      await pumpPanel(tester, DisplayTab(host: host));

      await tester.tap(find.text('视频信息'));
      await tester.pumpAndSettle();

      expect(host.panel.splitPanelSubPage, SplitSubPage.videoInfo);
      expect(tester.takeException(), isNull);
    });

    testWidgets('超分辨率：行值来自 playback，选中调 host.handleSuperResolutionChange',
        (tester) async {
      host.playerController.playback.superResolutionMode =
          SuperResolutionMode.efficiency;
      await pumpPanel(tester, DisplayTab(host: host));
      // 行上的当前值 = playback.superResolutionMode。
      expect(find.text(SuperResolutionMode.efficiency.label), findsOneWidget);

      await tester.tap(find.text('超分辨率'));
      await tester.pumpAndSettle();
      for (final mode in SuperResolutionMode.values) {
        expect(find.text(mode.label), findsWidgets, reason: '缺少选项 ${mode.label}');
      }
      await tester.tap(find.text(SuperResolutionMode.quality.label).last);
      await tester.pumpAndSettle();

      expect(superResolutionCalls, [SuperResolutionMode.quality]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('视频比例：行值来自 panel，选中写回 panel.aspectRatioMode',
        (tester) async {
      host.playerController.panel.aspectRatioMode = PlayerAspectRatio.stretch;
      await pumpPanel(tester, DisplayTab(host: host));
      // 行上的当前值 = panel.aspectRatioMode。
      expect(find.text(PlayerAspectRatio.stretch.label), findsOneWidget);

      await tester.tap(find.text('视频比例'));
      await tester.pumpAndSettle();
      for (final ratio in PlayerAspectRatio.values) {
        expect(find.text(ratio.label), findsWidgets, reason: '缺少选项 ${ratio.label}');
      }
      await tester.tap(find.text(PlayerAspectRatio.crop.label).last);
      await tester.pumpAndSettle();

      expect(
        host.playerController.panel.aspectRatioMode,
        PlayerAspectRatio.crop,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('画面调节二级页（P4）：预设 CRUD 全在本页内完成', () {
    testWidgets('280px 下不溢出，切换/新建/重命名/删除入口都在本页', (tester) async {
      await pumpPanel(tester, FilterSubPage(host: host));

      expect(find.text('新建'), findsOneWidget);
      expect(find.text('重命名'), findsWidgets);
      expect(find.byTooltip('删除预设'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('点「新建」→ 本页内命名 → 预设被新建并启用', (tester) async {
      await pumpPanel(tester, FilterSubPage(host: host));

      await tester.tap(find.text('新建'));
      await tester.pumpAndSettle();
      expect(find.text('新建滤镜预设'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '面板内新建');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      final created = VideoFilterController.instance.presets
          .where((p) => p.name == '面板内新建');
      expect(created, hasLength(1));
      expect(
        VideoFilterController.instance.activePresetId,
        created.first.id,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('点「重命名」→ 本页内改名（不跳页）', (tester) async {
      await pumpPanel(tester, FilterSubPage(host: host));

      await tester.tap(find.text('重命名').first);
      await tester.pumpAndSettle();
      expect(find.text('重命名滤镜预设'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '改过的名字');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(
        VideoFilterController.instance.presets.any((p) => p.name == '改过的名字'),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('点「删除预设」→ 本页内确认后删除（不跳页）', (tester) async {
      await pumpPanel(tester, FilterSubPage(host: host));

      await tester.tap(find.byTooltip('删除预设').first);
      await tester.pumpAndSettle();
      expect(find.text('删除滤镜预设'), findsOneWidget);

      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect(VideoFilterController.instance.presets, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  group('视频信息二级页（P4）', () {
    testWidgets('280px 下有界高度内渲染概览/日志且不溢出', (tester) async {
      await pumpPanel(tester, VideoInfoSubPage(host: host));

      expect(find.text('概览'), findsOneWidget);
      expect(find.text('日志'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('全部页签在 280px 不溢出', () {
    for (final tab in SplitPanelTab.values) {
      testWidgets('页签「${tab.label}」', (tester) async {
        await pumpPanel(tester, buildSplitPanelTabs(host)[tab.index]);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('全部二级页在 280px 不溢出', () {
    for (final page in SplitSubPage.values) {
      testWidgets('二级页「${page.title}」', (tester) async {
        await pumpPanel(tester, buildSplitSubPage(host, page));
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('二级页主体不与顶部分割线贴合（真机反馈）', () {
    /// 面板二级页 = 头部（返回 + 标题）+ `Divider(height: 1)` + 主体。
    /// 主体若没有顶部边距就会贴在那条分割线上——弹幕那组三个二级页曾经如此
    /// （`_subPagePadding` 顶部为 0），而画面 tab 的两个二级页顶部是 12/8。
    Future<void> expectNotStuckToDivider(
      WidgetTester tester,
      String title,
      Widget body,
      Finder firstContent,
    ) async {
      await pumpPanel(
        tester,
        SplitPanelScaffold(
          tabs: const ['占位'],
          bodies: const [SizedBox.shrink()],
          index: 0,
          onTabChanged: (_) {},
          onClose: () {},
          subPageTitle: title,
          subPageBody: body,
          onBack: () {},
        ),
      );

      final dividerBottom = tester.getRect(find.byType(Divider)).bottom;
      final contentTop = tester.getRect(firstContent).top;
      expect(
        contentTop - dividerBottom,
        greaterThanOrEqualTo(8),
        reason: '「$title」主体顶边距分割线只有 ${contentTop - dividerBottom}px，贴住了',
      );
      expect(tester.takeException(), isNull);
    }

    testWidgets('时间校准二级页', (tester) async {
      await expectNotStuckToDivider(
        tester,
        '时间校准',
        TimeOffsetSubPage(host: host),
        find.byType(TonalCard).first,
      );
    });

    testWidgets('屏蔽规则二级页', (tester) async {
      await expectNotStuckToDivider(
        tester,
        '屏蔽规则',
        ShieldSubPage(host: host),
        find.byType(TextField).first,
      );
    });
  });
}
