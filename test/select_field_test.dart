import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyw/bean/settings/settings_list.dart';
import 'package:wyw/bean/widget/select_field.dart';

/// 下拉选择组件回归测试。
///
/// 守护三件事：
///   1. **空串选项**（如「全部」`value: ''`）能正常显示——改造前靠 `'\u0000'` 哨兵值
///      绕开 `DropdownButton` 的「空串 = 未选择」语义，现在必须由组件原生支持；
///   2. **[SelectField] 能放进 `AlertDialog`**——`AlertDialog` 会把 content 包进
///      `IntrinsicWidth` 查询内在尺寸，任何 `LayoutBuilder` 都会在此抛
///      "does not support returning intrinsic dimensions"，这条测试就是那道闸门；
///   3. 菜单交互契约：选中项带 ✓、点选回调、禁用项不可选。
Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  const options = <SelectOption<String>>[
    SelectOption(value: '', label: '全部'),
    SelectOption(value: 'comic', label: '漫画'),
    SelectOption(value: 'novel', label: '小说', enabled: false),
  ];

  /// 弹层「表面」（Material）的矩形。
  ///
  /// 断言弹层落点时取它而不是项内文本：条目内有 h16/v12 与图标的内边距，
  /// 触发器本身可能只有 20px 高——用文本质证时，即使弹层与触发器顶对齐，
  /// 文本也可能落在触发器下方，断言会假通过。
  Rect popupSurface(WidgetTester tester, String label) {
    return tester.getRect(
      find
          .ancestor(of: find.text(label), matching: find.byType(Material))
          .first,
    );
  }

  testWidgets('空串选项显示为「全部」而不是空白', (tester) async {
    await tester.pumpWidget(
      _host(
        SelectField<String>(
          value: '',
          options: options,
          onChanged: (_) {},
        ),
      ),
    );

    expect(find.text('全部'), findsOneWidget);
  });

  testWidgets('未选中时显示占位文案', (tester) async {
    await tester.pumpWidget(
      _host(
        SelectField<String>(
          value: null,
          options: options,
          onChanged: (_) {},
        ),
      ),
    );

    expect(find.text('请选择'), findsOneWidget);
  });

  testWidgets('SelectField 放进 AlertDialog 不触发内在尺寸断言', (tester) async {
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('筛选'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('类型'),
                    const SizedBox(height: 6),
                    SelectField<String>(
                      value: 'comic',
                      options: options,
                      onChanged: (_) {},
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('取消'),
                  ),
                ],
              ),
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // 触发器中显示当前选中项（AlertDialog 标题与内容同时存在时取内容那一个）。
    expect(find.text('漫画'), findsOneWidget);
  });

  testWidgets('展开菜单后选中项带 ✓，点选可切换并回调', (tester) async {
    String? picked;
    await tester.pumpWidget(
      _host(
        SelectField<String>(
          value: '',
          options: options,
          onChanged: (value) => picked = value,
        ),
      ),
    );

    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();

    // 恰好一个 ✓（当前选中项）。
    expect(find.byIcon(Icons.check), findsOneWidget);

    await tester.tap(find.text('漫画').last);
    await tester.pumpAndSettle();

    expect(picked, 'comic');
  });

  testWidgets('SelectTile 整行可点即展开菜单，禁用项不可选', (tester) async {
    String? picked;
    await tester.pumpWidget(
      _host(
        SelectTile<String>(
          title: const Text('类型'),
          value: '',
          options: options,
          onChanged: (value) => picked = value,
        ),
      ),
    );

    // 点标题（行内非值区域）也应展开菜单。
    await tester.tap(find.text('类型'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check), findsOneWidget);

    await tester.tap(find.text('小说').last);
    await tester.pumpAndSettle();
    expect(picked, isNull);
  });

  testWidgets('SelectMenuButton 禁用时不展开菜单', (tester) async {
    var called = false;
    await tester.pumpWidget(
      _host(
        SelectMenuButton<String>(
          value: 'comic',
          options: options,
          enabled: false,
          onChanged: (_) => called = true,
        ),
      ),
    );

    expect(find.text('漫画'), findsOneWidget);
    await tester.tap(find.text('漫画'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check), findsNothing);
    expect(called, isFalse);
  });

  // ---- 图标与勾选标记 ----

  const iconOptions = <SelectOption<String>>[
    SelectOption(
      value: 'system',
      label: '跟随系统',
      icon: Icons.brightness_auto_rounded,
    ),
    SelectOption(value: 'light', label: '浅色', icon: Icons.light_mode_rounded),
    SelectOption(value: 'dark', label: '深色', icon: Icons.dark_mode_rounded),
  ];

  testWidgets('选项图标渲染在弹层条目里，且选中项的图标出现在触发器上', (tester) async {
    await tester.pumpWidget(
      _host(
        SelectField<String>(
          value: 'dark',
          options: iconOptions,
          onChanged: (_) {},
        ),
      ),
    );

    // 触发器：当前选中项「深色」的图标 + 文案（+ 尾部 ▾）。
    expect(find.byIcon(Icons.dark_mode_rounded), findsOneWidget);
    expect(find.text('深色'), findsOneWidget);

    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();

    // 弹层：三个选项的图标都在（深色的图标此时触发器与弹层各一个）。
    expect(find.byIcon(Icons.brightness_auto_rounded), findsOneWidget);
    expect(find.byIcon(Icons.light_mode_rounded), findsOneWidget);
    expect(find.byIcon(Icons.dark_mode_rounded), findsNWidgets(2));
  });

  testWidgets('勾选标记在文案右侧', (tester) async {
    await tester.pumpWidget(
      _host(
        SelectField<String>(
          value: 'dark',
          options: iconOptions,
          onChanged: (_) {},
        ),
      ),
    );

    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();

    final surface = popupSurface(tester, '跟随系统');
    final check = tester.getRect(find.byIcon(Icons.check));
    expect(
      check.left,
      greaterThan(surface.left + surface.width / 2),
      reason: '对钩应落在弹层右半边（文案右侧），而不是左侧',
    );
  });

  // ---- 宽度跟随内容（省略回归）----
  //
  // 反面案例（已实测复现过）：弹层宽度只由触发器宽度与下限决定时，
  // 设置行尾触发器只有 57px 宽 → 弹层恒为 140px → `跟随系统` 这一条
  // （含选项图标 28 + ✓ 26 + 内边距 32）只剩下 54px，而文案固有宽度是 56px，
  // 正好被切掉 2px。下面断言「条目文案没有被省略」，并把弹层宽度也钉住。

  /// 条目文案是否被省略：渲染宽度应等于其固有宽度。
  void expectLabelNotTruncated(WidgetTester tester, String label) {
    final Finder finder = find.text(label);
    final Text textWidget = tester.widgetList<Text>(finder).last;
    final TextPainter painter = TextPainter(
      text: TextSpan(text: label, style: textWidget.style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final double intrinsic = painter.width;
    painter.dispose();

    expect(
      tester.getSize(finder.last).width,
      greaterThanOrEqualTo(intrinsic - 0.5),
      reason: '「$label」被省略了：渲染宽度小于固有宽度 $intrinsic',
    );
  }

  testWidgets('窄触发器下，选项文案不被省略（弹层宽度跟随内容）', (tester) async {
    await tester.pumpWidget(
      _host(
        SelectTile<String>(
          title: const Text('深色模式'),
          value: 'system',
          options: iconOptions,
          onChanged: (_) {},
        ),
      ),
    );

    await tester.tap(find.text('跟随系统'));
    await tester.pumpAndSettle();

    final surface = popupSurface(tester, '浅色');
    // 内容需求 = 文案 57 + 选项图标 28 + ✓ 26 + 内边距 32 = 143，故必然超过下限 140。
    // 修之前恒为 140（只取触发器宽度与下限），这条断言就是那时的证伪点。
    expect(
      surface.width,
      greaterThan(140.5),
      reason: '弹层宽度应随内容增长，而不是固定在下限 140',
    );
    // 选中项（带 ✓）与未选中项都要完整显示。
    expectLabelNotTruncated(tester, '跟随系统');
    expectLabelNotTruncated(tester, '浅色');
  });

  // ---- 定位语义回归 ----
  //
  // 守护弹层的位置语义：必须出现在触发器**正下方、左对齐**。
  // 实现是自建的「全屏透明 route + 手算定位」（见 showSelectPopup），位置由
  // `_SelectPopup.build` 里的规则决定，所以这两条断言直接锁住那段规则。
  // 证伪方式：把那里的 `top` 改成 `anchorRect.top + gap`（顶对齐），两条都会失败。
  //
  // 断言取**弹层表面**（Material）而不是项内文本：条目内有 h16/v12 与 ✓ 槽的
  // 内部留白，触发器本身可能只有 20px 高——用文本质证时即使弹层与触发器顶对齐，
  // 文本也可能落在触发器下方，断言会假通过。
  // 触发器传 `value: null` 显示占位文案，选项文案只存在于展开的弹层里，避免撞上触发器。

  testWidgets('SelectField 的弹层展开在字段正下方、左对齐', (tester) async {
    await tester.pumpWidget(
      _host(
        SelectField<String>(
          value: null,
          options: options,
          onChanged: (_) {},
        ),
      ),
    );

    final fieldRect = tester.getRect(find.byType(InputDecorator));
    await tester.tap(find.text('请选择'));
    await tester.pumpAndSettle();

    final surface = popupSurface(tester, '全部');
    expect(
      surface.top,
      greaterThanOrEqualTo(fieldRect.bottom),
      reason: '弹层应位于字段下方，而不是与字段顶对齐',
    );
    expect(
      surface.left,
      lessThan(fieldRect.left + 80),
      reason: '弹层应左对齐字段，而不是偏到字段右侧',
    );
  });

  testWidgets('SelectTile 的弹层展开在值区域正下方', (tester) async {
    await tester.pumpWidget(
      _host(
        SelectTile<String>(
          title: const Text('类型'),
          value: null,
          options: options,
          onChanged: (_) {},
        ),
      ),
    );

    // 锚点是行尾的「值」区域（文本 + ▾），不是整行。
    final anchorRect = tester.getRect(find.text('请选择'));
    await tester.tap(find.text('请选择'));
    await tester.pumpAndSettle();

    // 值区域贴着屏幕右缘，水平方向会被"翻成右对齐"的规则推到右侧，这里只断言垂直落点。
    final surface = popupSurface(tester, '全部');
    expect(
      surface.top,
      greaterThanOrEqualTo(anchorRect.bottom),
      reason: '弹层应位于值区域下方，而不是与值区域顶对齐',
    );
  });

  testWidgets('弹层超出屏幕右侧时被拉回可用区（自建定位的避让）', (tester) async {
    // 触发器贴在屏幕最右缘，而弹层最小宽度 140：按"左对齐触发器"算必然越界，
    // 必须翻成右对齐触发器（而不是画出屏幕——Kazumi 原版在这里会直接出屏）。
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: SelectMenuButton<String>(
              value: null,
              options: options,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('请选择'));
    await tester.pumpAndSettle();

    final surface = popupSurface(tester, '全部');
    final screen = tester.getRect(find.byType(Scaffold));
    expect(
      surface.right,
      lessThanOrEqualTo(screen.right + 0.5),
      reason: '弹层右边缘不得超出屏幕',
    );
    expect(
      surface.left,
      greaterThanOrEqualTo(screen.left - 0.5),
      reason: '弹层左边缘不得超出屏幕',
    );
  });

  testWidgets('下方空间不足时向上弹出，且底边贴着触发器（不按上限高度悬空）', (tester) async {
    // 反面案例：向上弹出时按 `top = anchor.top - gap - maxHeight` 定位，而 maxHeight
    // 只是上限、弹层实际由条目数决定高度（通常远小于上限）——于是短弹层会悬在
    // 触发器上方一二百像素处。修法是给「底边」定位。
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SelectField<String>(
              value: null,
              options: options,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('请选择'));
    await tester.pumpAndSettle();

    final field = tester.getRect(find.byType(InputDecorator));
    final surface = popupSurface(tester, '全部');
    expect(
      surface.bottom,
      lessThanOrEqualTo(field.top),
      reason: '下方放不下时应向上弹出',
    );
    expect(
      (field.top - surface.bottom).abs(),
      lessThanOrEqualTo(6),
      reason: '弹层底边应贴着触发器上沿（约 gap=4），而不是按上限高度悬空',
    );
  });

  testWidgets('窗口尺寸变化时弹层跟随触发器重新定位', (tester) async {
    // 反面案例：把打开时算好的 Rect 当成快照传进弹层，窗口一变弹层就留在旧位置，
    // 与触发器脱节（甚至在窗口变小后跑到屏幕外）。修法是弹层每帧重新读触发器位置
    // ——build 读到的是上一帧布局结果，所以帧末再复核一次。
    //
    // 这里刻意让触发器停在上半区、两种尺寸下都「向下弹出」：否则弹层会因下方不够
    // 而向上弹，把「位置是快照」这个被测缺陷和向上弹出的定位问题混在一起，测不准。
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // Alignment(0, -0.5)：触发器中心位于上半区，高度变化时它会上下移动，
          // 且两种尺寸下它下方都留得下弹层（保持向下弹出）。
          body: Align(
            alignment: const Alignment(0, -0.5),
            child: SelectField<String>(
              value: null,
              options: options,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    final before = tester.getRect(find.byType(InputDecorator));
    await tester.tap(find.text('请选择'));
    await tester.pumpAndSettle();
    expect(
      popupSurface(tester, '全部').top,
      greaterThan(before.bottom),
      reason: '前提：初始应向下弹出',
    );

    // logical 800×600 → 800×300（测试默认 physical 2400×1800 @3x）。
    tester.view.physicalSize = const Size(2400, 900);
    await tester.pumpAndSettle();

    final after = tester.getRect(find.byType(InputDecorator));
    expect(
      after.top,
      lessThan(before.top),
      reason: '窗口变矮后触发器应随之上移（前提：触发器确实动了）',
    );

    final surface = popupSurface(tester, '全部');
    expect(
      (surface.top - after.bottom).abs(),
      lessThanOrEqualTo(6),
      reason: '弹层顶边应贴着触发器的新下沿（快照式实现会留在打开时的位置）',
    );
  });
}
