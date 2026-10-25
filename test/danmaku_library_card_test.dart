import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyw/bean/card/network_img_layer.dart';
import 'package:wyw/modules/danmaku/danmaku_episode_response.dart';
import 'package:wyw/modules/danmaku/danmaku_library_ref.dart';
import 'package:wyw/pages/player/danmaku_selection/widgets/library_card.dart';

/// 库卡片：**"当前使用"和"刚选中"共用这一个组件**，所以它的行为要单独钉住。
DanmakuBangumiDetail _detail() => DanmakuBangumiDetail.fromJson(const {
      'animeId': 19847,
      'bangumiId': '19847',
      'animeTitle': 'FX战士久留美',
      'typeDescription': 'TV动画',
      'intro': '简介正文',
      'rating': 7.5,
      'isOnAir': true,
      'titles': [
        {'language': '中文', 'title': 'FX战士久留美'},
        {'language': '日文', 'title': 'FX戦士くるみちゃん'},
        {'language': '英文', 'title': 'FX Senshi Kurumi-chan'},
      ],
      'episodes': [
        {
          'episodeId': 198470001,
          'episodeTitle': '第1集',
          'episodeNumber': '1',
          'airDate': '2019-01-06T00:00:00',
        },
      ],
    });

DanmakuLibraryRef _ref({String title = 'FX战士久留美', int year = 2024}) =>
    DanmakuLibraryRef(
      animeId: 19847,
      bangumiId: '19847',
      libraryTitle: title,
      intro: '简介',
      rating: 7.5,
      episodeCount: 4,
      year: year,
      savedAtMs: 1,
    );

Future<void> _pump(
  WidgetTester tester, {
  required DanmakuBangumiDetail? detail,
  DanmakuLibraryRef? ref,
  bool isCurrent = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 280,
          height: 420,
          child: DanmakuLibraryCard(
            ref: ref ?? _ref(),
            detail: detail,
            isCurrent: isCurrent,
            onRefresh: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('点标题轮流切换多语言名（曾经点了没反应）', (tester) async {
    await _pump(tester, detail: _detail());

    // 初始展示与快照同名的那一条（中文）。
    expect(find.text('FX战士久留美'), findsOneWidget);

    await tester.tap(find.text('FX战士久留美'));
    await tester.pumpAndSettle();
    expect(find.text('FX戦士くるみちゃん'), findsOneWidget);
    expect(find.text('FX战士久留美'), findsNothing);

    await tester.tap(find.text('FX戦士くるみちゃん'));
    await tester.pumpAndSettle();
    expect(find.text('FX Senshi Kurumi-chan'), findsOneWidget);

    // 转一圈回到第一条。
    await tester.tap(find.text('FX Senshi Kurumi-chan'));
    await tester.pumpAndSettle();
    expect(find.text('FX战士久留美'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('不再有「语言 · 点标题切换（i/n）」提示行', (tester) async {
    await _pump(tester, detail: _detail());

    expect(find.textContaining('点标题切换'), findsNothing);
    // 语言名本身也不再单独占一行。
    expect(find.text('中文'), findsNothing);
    expect(find.text('日文'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('封面按 Kazumi 详情页的比例：0.65、由高度决定宽度（此前 46×62/56×80 偏小）',
      (tester) async {
    await _pump(tester, detail: _detail());

    final cover = find.byType(NetworkImgLayer);
    expect(cover, findsOneWidget);
    final size = tester.getSize(cover);
    expect(size.height, 120);
    expect(size.width, moreOrLessEquals(120 * 0.65, epsilon: 0.5));
  });

  testWidgets('没有详情时只用快照渲染，标题退回快照标题', (tester) async {
    await _pump(tester, detail: null, ref: _ref(title: '某部番'));

    expect(find.text('某部番'), findsOneWidget);
    // 指标是**格子**（标签 + 值），不再是一行拼接字符串。
    expect(find.text('类型'), findsOneWidget);
    expect(find.text('年份'), findsOneWidget);
    expect(find.text('集数'), findsOneWidget);
    expect(find.text('评分'), findsOneWidget);
    expect(find.text('2024 年'), findsOneWidget);
    expect(find.text('4 集'), findsOneWidget);
    expect(find.text('7.5'), findsOneWidget);
    // 没有详情 → 类型未知显示破折号。
    expect(find.text('—'), findsOneWidget);
    expect(find.textContaining(' · '), findsNothing);
    expect(find.text('简介'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('连载中是标题右侧的徽标，不混进数值里', (tester) async {
    await _pump(tester, detail: _detail());

    expect(find.text('连载中'), findsOneWidget);
    // 类型这一格仍然是独立的值，没有被拼进状态。
    expect(find.text('TV动画'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('快照年份是 0（老记录）→ 用详情首集 airDate 兜底，不再显示破折号', (tester) async {
    await _pump(tester, detail: _detail(), ref: _ref(year: 0));

    expect(find.text('2019 年'), findsOneWidget);
    expect(find.text('—'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('快照年份有效时优先用它（详情首集是 2019，快照说 2024）', (tester) async {
    await _pump(tester, detail: _detail(), ref: _ref(year: 2024));

    expect(find.text('2024 年'), findsOneWidget);
    expect(find.text('2019 年'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
