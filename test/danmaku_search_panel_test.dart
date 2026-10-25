import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyw/bean/settings/capsule_tab_strip.dart';
import 'package:wyw/bean/widget/connected_tabs.dart';
import 'package:wyw/bean/widget/select_field.dart';
import 'package:wyw/modules/danmaku/danmaku_library_ref.dart';
import 'package:wyw/modules/danmaku/danmaku_type_filter.dart';
import 'package:wyw/pages/player/danmaku_selection/danmaku_search_panel.dart';

/// 弹幕选择面板的**版式契约**（2026-10 反馈重做后）：
/// 卡片（只有选中/持久化过才出现）→ 吸顶「搜索 / 选集」→ 内容，整页一个滚动体。
///
/// 这些用例不碰网络：没配置凭证时搜索框只显示提示，详情缓存读不到就退化成
/// "点一次取分集"。之所以值得测，是因为版式是纯视觉约定，坏了不会编译报错——
/// 只有真机点开才发现"卡片没了/切不过去"。
void main() {
  Future<void> pumpPanel(
    WidgetTester tester, {
    DanmakuLibraryRef? current,
    double width = 280,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            height: 420,
            child: DanmakuSearchPanel(
              initialKeyword: '',
              localEpisodeIndex: 0,
              current: current,
              onEpisodeSelected: (detail, index) async => true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('没选过：不显示卡片，只有「搜索 / 选集」与搜索空态（280px 不溢出）', (tester) async {
    await pumpPanel(tester);

    expect(find.text('搜索'), findsOneWidget);
    expect(find.text('选集'), findsOneWidget);
    expect(find.text('搜索弹弹play 作品'), findsOneWidget);
    expect(find.text('使用中'), findsNothing);
    // 「剧集搜索」兜底入口已按反馈删除。
    expect(find.textContaining('剧集搜索'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('搜索框挂顶：搜索框与类型下拉都在吸顶区、且同一行', (tester) async {
    await pumpPanel(tester);

    // 挂顶 = 位于 pinned 的 SliverPersistentHeader 子树里（滚多远都留在顶部）。
    expect(
      find.ancestor(
        of: find.byType(TextField),
        matching: find.byType(SliverPersistentHeader),
      ),
      findsOneWidget,
    );

    // 类型筛选从"搜索框下方一排 chips"变成同一行的下拉（`SelectField`）。
    final dropdown = find.byType(SelectField<DanmakuTypeFilter>);
    expect(dropdown, findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(
      tester.getCenter(dropdown).dy,
      moreOrLessEquals(tester.getCenter(find.byType(TextField)).dy, epsilon: 2),
      reason: '下拉应与搜索框同一行（居中对齐）',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('有进度记录快照：卡片自带「使用中」，不再有额外的"当前使用"行', (tester) async {
    await pumpPanel(
      tester,
      current: const DanmakuLibraryRef(
        animeId: 19847,
        bangumiId: '19847',
        libraryTitle: 'FX战士久留美',
        intro: '简介',
        rating: 7.5,
        episodeCount: 4,
        year: 2024,
        savedAtMs: 1,
      ),
    );

    // 卡片信息来自快照本身（断网也能显示"用的是哪一个"）。
    expect(find.text('FX战士久留美'), findsOneWidget);
    // 指标格（标签 + 值）而不是一行拼接字符串。
    expect(find.text('年份'), findsOneWidget);
    expect(find.text('2024 年'), findsOneWidget);
    expect(find.text('4 集'), findsOneWidget);
    expect(find.text('7.5'), findsOneWidget);
    expect(find.text('使用中'), findsOneWidget);
    // 文案里不再出现独立状态行那种"当前使用：…"。
    expect(find.textContaining('当前使用：'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('选集页签：缓存里没有分集时引导"取分集"，而不是空白', (tester) async {
    await pumpPanel(
      tester,
      current: const DanmakuLibraryRef(
        animeId: 19847,
        libraryTitle: 'FX战士久留美',
        episodeCount: 4,
        savedAtMs: 1,
      ),
    );

    await tester.tap(find.text('选集'));
    await tester.pumpAndSettle();

    expect(find.text('还没有这一部的分集'), findsOneWidget);
    expect(find.text('取分集'), findsOneWidget);
    // 搜索框属于搜索页签，切过去就该看不见。
    expect(find.text('番剧名称（至少 2 字）'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('切回搜索页签：搜索框回来（吸顶行两边都能到）', (tester) async {
    await pumpPanel(tester);

    await tester.tap(find.text('选集'));
    await tester.pumpAndSettle();
    expect(find.text('还没有选中作品'), findsOneWidget);

    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();
    expect(find.text('搜索弹弹play 作品'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 两个默认态必须分成两个用例：同一个 test 里二次 `pumpWidget` 会**复用已有
  // State**（同类型、同位置），`initState` 不再跑，第二个面板还带着第一次的
  // TabController，默认页签自然测不出来。
  testWidgets('没选过库：默认落在「搜索」', (tester) async {
    await pumpPanel(tester);

    expect(find.text('番剧名称（至少 2 字）'), findsOneWidget);
    expect(find.text('还没有选中作品'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('已选过库：默认落在「选集」（不用再点一次）', (tester) async {
    await pumpPanel(
      tester,
      current: const DanmakuLibraryRef(
        animeId: 19847,
        libraryTitle: 'FX战士久留美',
        episodeCount: 4,
        savedAtMs: 1,
      ),
    );

    // 搜索框让位，落点是选集内容（缓存里没分集时是引导文案）。
    expect(find.text('番剧名称（至少 2 字）'), findsNothing);
    expect(find.text('还没有这一部的分集'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('类型下拉可用：选中后触发器换成新类型（最宽的类型名也不溢出）', (tester) async {
    await pumpPanel(tester);

    expect(find.text('全部'), findsOneWidget);
    await tester.tap(find.byType(SelectField<DanmakuTypeFilter>));
    await tester.pumpAndSettle();

    // 弹层里列出全部类型，选中「剧场版」（3 个 CJK 字，宽度最紧的那一项）。
    await tester.tap(find.text('剧场版').last);
    await tester.pumpAndSettle();

    expect(find.text('剧场版'), findsOneWidget);
    expect(find.text('全部'), findsNothing);
    // 关键词不足 2 字，不应触发搜索（测试里也没网络）。
    expect(find.text('关键词至少 2 个字'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('「搜索 / 选集」是 ConnectedTabs：铺满整行、两段等宽', (tester) async {
    await pumpPanel(tester);

    // 组件层：用 Kazumi 播放器弹幕设置弹窗同款（M3 connected-button 组），
    // 不是胶囊页签条——这是明确指定的组件，不是样式偏好。
    expect(find.byType(ConnectedTabs), findsOneWidget);
    expect(find.byType(CapsuleTabStrip), findsNothing);

    // 几何层：ConnectedTabs 把剩余宽度平摊给各段，所以两段等宽、吃满**可用**宽度，
    // 且左右各留边距（曾经贴边，反馈要留边距）。
    final segments = find.descendant(
      of: find.byType(ConnectedTabs),
      matching: find.byType(InkWell),
    );
    expect(segments, findsNWidgets(2));
    final first = tester.getRect(segments.at(0));
    final second = tester.getRect(segments.at(1));

    expect(first.width, moreOrLessEquals(second.width, epsilon: 0.5));
    expect(first.left, moreOrLessEquals(12, epsilon: 0.5), reason: '左边距');
    expect(second.right, moreOrLessEquals(280 - 12, epsilon: 0.5), reason: '右边距');
    expect(tester.takeException(), isNull);
  });
}
