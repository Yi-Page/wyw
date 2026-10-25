import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyw/modules/download/download_module.dart';
import 'package:wyw/pages/video/episode_selection_panel.dart';
import 'package:wyw/services/storage/video_play_model.dart';

/// 选集面板的信息密度回归：每一行要能一眼看出
///   - **有没有下载**（图标：已缓存 / 缓存中 / 未缓存 outline）；
///   - **观看时长 / 总时长 + 百分比**（`看到 12:34 / 45:00（28%）`）。
void main() {
  VideoPlayEpisode ep(String name, {int position = 0, int duration = 0}) =>
      VideoPlayEpisode(
        name: name,
        path: PlayResourcePath(
          url: 'https://n/$name.m3u8',
          type: PlayPathType.direct,
        ),
        positionMs: position,
        durationMs: duration,
      );

  DownloadEpisode task(int number, int status, double percent) =>
      DownloadEpisode(
        number,
        '第$number集',
        0,
        status,
        percent,
        10,
        0,
        '',
        '/tmp',
        '',
        null,
        '',
        0,
      );

  Future<void> pumpPanel(
    WidgetTester tester, {
    required List<VideoPlaySource> roads,
    Map<String, DownloadEpisode> downloads = const {},
    int selectedEpisode = 0,
    int currentPositionMs = 0,
    int currentDurationMs = 0,
    bool isOffline = false,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 420,
          height: 640,
          child: EpisodeSelectionPanel(
            title: '测试剧',
            roads: roads,
            selectedRoad: 0,
            selectedEpisode: selectedEpisode,
            onEpisodeSelected: (_, __) {},
            downloads: downloads,
            isOffline: isOffline,
            currentPositionMs: currentPositionMs,
            currentDurationMs: currentDurationMs,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('未看 / 看到一半 / 已看完 与下载状态同排展示', (tester) async {
    await pumpPanel(
      tester,
      roads: [
        VideoPlaySource(name: '线路A', episodes: [
          ep('第1集', position: 754000, duration: 2700000), // 12:34 / 45:00
          ep('第2集'), // 未看
          ep('第3集', position: 100000, duration: 100000), // 已看完
        ]),
      ],
      downloads: {
        episodeDownloadKey(0, 0): task(1, DownloadStatus.completed, 1),
        episodeDownloadKey(0, 1): task(2, DownloadStatus.downloading, 0.45),
      },
    );

    expect(find.textContaining('看到 12:34 / 45:00（28%）'), findsOneWidget);
    expect(find.textContaining('已缓存'), findsOneWidget);
    expect(find.textContaining('缓存 45%'), findsOneWidget);
    // 看完的集也照常显示进度（100%），不做"已看完"特例
    expect(find.textContaining('看到 1:40 / 1:40（100%）'), findsOneWidget);
    expect(find.textContaining('已看完'), findsNothing);

    // 下载图标：已缓存 / 缓存中 / 未缓存（outline）
    expect(find.byIcon(Icons.download_done_rounded), findsOneWidget);
    expect(find.byIcon(Icons.downloading_rounded), findsOneWidget);
    expect(find.byIcon(Icons.download_outlined), findsOneWidget);

    // 进度用百分比表达，不再单独画进度条
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('第2集'), findsOneWidget);
  });

  testWidgets('当前集的实时位置覆盖持久化值', (tester) async {
    await pumpPanel(
      tester,
      roads: [
        VideoPlaySource(name: '线路A', episodes: [
          ep('第1集', position: 1000, duration: 600000),
        ]),
      ],
      selectedEpisode: 1,
      currentPositionMs: 300000,
      currentDurationMs: 600000,
    );

    expect(find.textContaining('看到 5:00 / 10:00（50%）'), findsOneWidget);
    expect(find.textContaining('当前选集'), findsOneWidget);
  });

  testWidgets('时长未知时只显示观看位置；离线态不画下载图标', (tester) async {
    await pumpPanel(
      tester,
      roads: [
        VideoPlaySource(name: '线路A', episodes: [ep('第1集', position: 65000)]),
      ],
      isOffline: true,
    );

    expect(find.textContaining('看到 1:05'), findsOneWidget);
    expect(find.byIcon(Icons.download_outlined), findsNothing);
    expect(find.byIcon(Icons.download_done_rounded), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('没看过也没时长时，不显示观看那一项', (tester) async {
    await pumpPanel(
      tester,
      roads: [
        VideoPlaySource(name: '线路A', episodes: [ep('第1集')]),
      ],
    );

    expect(find.textContaining('看到'), findsNothing);
    expect(find.textContaining('时长'), findsNothing);
  });

  group('工具栏滚动按钮', () {
    List<VideoPlayEpisode> longRoad(int count) => [
          for (var i = 1; i <= count; i++)
            // 隔一集取一个长名字 → 行高可变（1~2 行），专门覆盖"不是等高"的情况
            ep(i.isEven ? '第$i集 一个很长的剧集名称，用来换成两行显示' : '第$i集'),
        ];

    double panelOffset(WidgetTester tester) =>
        tester.widget<CustomScrollView>(find.byType(CustomScrollView))
            .controller!
            .offset;

    testWidgets('「回到顶部」在列表滚下去后回到 0', (tester) async {
      await pumpPanel(
        tester,
        roads: [VideoPlaySource(name: '线路A', episodes: longRoad(40))],
      );

      final controller =
          tester.widget<CustomScrollView>(find.byType(CustomScrollView))
              .controller!;
      controller.jumpTo(600);
      await tester.pumpAndSettle();
      expect(panelOffset(tester), greaterThan(0));

      await tester.tap(find.byTooltip('回到顶部'));
      await tester.pumpAndSettle();

      expect(panelOffset(tester), 0);
    });

    testWidgets('打开面板即自动定位到选中集（历史页选集弹窗同款）', (tester) async {
      await pumpPanel(
        tester,
        roads: [VideoPlaySource(name: '线路A', episodes: longRoad(60))],
        selectedEpisode: 45,
      );

      // 首次布局后自动滚过去（宿主不需要自己调 revealCurrentEpisode）
      expect(find.text('第45集'), findsOneWidget);
      expect(panelOffset(tester), greaterThan(0));
    });

    testWidgets('回到顶部后点「定位当前集」再回到目标集', (tester) async {
      await pumpPanel(
        tester,
        roads: [VideoPlaySource(name: '线路A', episodes: longRoad(60))],
        selectedEpisode: 45,
      );

      await tester.tap(find.byTooltip('回到顶部'));
      await tester.pumpAndSettle();
      expect(panelOffset(tester), 0);
      expect(find.text('第45集'), findsNothing); // 顶部看不到远处那一集

      await tester.tap(find.byTooltip('定位当前集'));
      await tester.pumpAndSettle();

      expect(find.text('第45集'), findsOneWidget);
      expect(panelOffset(tester), greaterThan(0));
    });
  });
}
