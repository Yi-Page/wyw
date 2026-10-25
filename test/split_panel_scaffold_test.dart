import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyw/pages/player/widgets/split_panel_scaffold.dart';

/// 每个页签内容的「被创建次数」：用来验证切走再切回时 State 没有被重建。
final Map<String, int> _created = <String, int>{};

class _CountedBody extends StatefulWidget {
  const _CountedBody(this.label);

  final String label;

  @override
  State<_CountedBody> createState() => _CountedBodyState();
}

class _CountedBodyState extends State<_CountedBody> {
  int taps = 0;

  @override
  void initState() {
    super.initState();
    _created[widget.label] = (_created[widget.label] ?? 0) + 1;
  }

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => setState(() => taps++),
      child: Text('${widget.label}:$taps'),
    );
  }
}

void main() {
  setUp(_created.clear);

  Future<void> pumpScaffold(
    WidgetTester tester, {
    required int index,
    ValueChanged<int>? onTabChanged,
    VoidCallback? onClose,
    String? subPageTitle,
    VoidCallback? onBack,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 600,
            child: SplitPanelScaffold(
              tabs: const ['选集', '弹幕', '画面', '播放', '更多'],
              bodies: [
                for (final label in ['选集', '弹幕', '画面', '播放', '更多'])
                  _CountedBody(label),
              ],
              index: index,
              onTabChanged: onTabChanged ?? (_) {},
              onClose: onClose ?? () {},
              subPageTitle: subPageTitle,
              subPageBody: subPageTitle == null ? null : const Text('二级页内容'),
              onBack: onBack,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('五个页签都渲染，默认显示首个内容', (tester) async {
    await pumpScaffold(tester, index: 0);

    for (final label in ['选集', '弹幕', '画面', '播放', '更多']) {
      expect(find.text(label), findsWidgets, reason: '缺少页签 $label');
    }
    expect(find.text('选集:0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('页签里的 ListTile 不再触发「背景/水波纹被吞掉」断言', (tester) async {
    // 面板外壳必须是 `Material`（而不是 `Container(color:)` = `ColoredBox`）：
    // ListTile 的背景与水波纹画在最近的 Material 祖先上，若中间夹一个带色
    // ColoredBox，debug 下每个 ListTile 每帧都报
    // "ListTile background color or ink splashes may be invisible"
    //（真机实测刷爆日志，水波纹也确实失效）。
    //
    // 断言用**覆写 `FlutterError.onError`** 收集，照 Flutter 自己对这条断言的测试
    // 写法：它在 build 里 `reportError`，不会进 `tester.takeException()`。
    // 曾用 takeException 写过一版，即使把外壳换回 ColoredBox 也照样通过（空转），
    // 因此这里必须用 onError。
    final errors = <FlutterErrorDetails>[];
    // 用显式函数类型而不是 `FlutterExceptionHandler`：后者由 foundation 导出，
    // 本文件只 import 了 material。
    final void Function(FlutterErrorDetails)? oldHandler = FlutterError.onError;
    FlutterError.onError = errors.add;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 600,
              child: SplitPanelScaffold(
                tabs: const ['弹幕'],
                bodies: [
                  ListView(
                    children: [
                      // **必须有 onTap**：这条断言在 list_tile.dart 里有前置门槛——
                      // 只有 onTap/onLongPress/不透明 tileColor 三者至少一个成立才校验
                      //（否则按钮都没有的纯展示行不该关心水波纹）。少了 onTap，
                      // 用例会退化成空转（曾踩过）。
                      ListTile(
                        title: const Text('候选一'),
                        onTap: () {},
                      ),
                      ListTile(
                        title: const Text('候选二'),
                        selected: true,
                        onTap: () {},
                      ),
                    ],
                  ),
                ],
                index: 0,
                onTabChanged: (_) {},
                onClose: () {},
                onBack: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    } finally {
      FlutterError.onError = oldHandler;
    }

    expect(find.text('候选一'), findsOneWidget);
    expect(
      errors.map((details) => details.exceptionAsString()).toList(),
      isEmpty,
    );
  });

  testWidgets('点第二个页签回调下标 1', (tester) async {
    final tapped = <int>[];
    await pumpScaffold(tester, index: 0, onTabChanged: tapped.add);

    await tester.tap(find.text('弹幕').first);
    await tester.pumpAndSettle();

    expect(tapped, contains(1));
  });

  testWidgets('切走再切回不重建内容（页签保活）', (tester) async {
    await pumpScaffold(tester, index: 0);

    // 在第一个页签里改点状态。
    await tester.tap(find.text('选集:0'));
    await tester.pump();
    expect(find.text('选集:1'), findsOneWidget);

    // 切到第三个页签，再切回第一个。
    await tester.tap(find.text('画面').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('选集').first);
    await tester.pumpAndSettle();

    // State 没被重建（否则计数会变 2），且此前改的状态还在。
    expect(_created['选集'], 1);
    expect(find.text('选集:1'), findsOneWidget);
  });

  testWidgets('二级页：隐藏页签条、显示标题，返回回调', (tester) async {
    var backCalled = false;
    await pumpScaffold(
      tester,
      index: 0,
      subPageTitle: '画面调节',
      onBack: () => backCalled = true,
    );

    expect(find.text('画面调节'), findsOneWidget);
    expect(find.text('二级页内容'), findsOneWidget);
    // 页签条隐藏：页签文案不再出现（标题不是页签文案）。
    expect(find.text('选集'), findsNothing);
    expect(find.text('弹幕'), findsNothing);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(backCalled, isTrue);
  });

  testWidgets('关闭按钮回调', (tester) async {
    var closed = false;
    await pumpScaffold(tester, index: 0, onClose: () => closed = true);

    await tester.tap(find.byTooltip('收起面板'));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
  });

  testWidgets('窄面板（280px）不溢出', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            height: 420,
            child: SplitPanelScaffold(
              tabs: const ['选集', '弹幕', '画面', '播放', '更多'],
              bodies: [for (final label in ['选集', '弹幕', '画面', '播放', '更多']) _CountedBody(label)],
              index: 0,
              onTabChanged: (_) {},
              onClose: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
