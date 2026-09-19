import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyw/bean/appbar/app_bar_menu_button.dart';
import 'package:wyw/bean/settings/settings_detail_scaffold.dart';

/// `WywAppBarMenuButton` 防重复导航语义回归测试。
///
/// 锁定 docs/ui-routing-design-spec.md B9 节的三条行为：
/// 1. 已在本页 → 条目禁用（onPressed == null，可见但不响应）；
/// 2. 目标已在栈内（菜单链可证明）→ popUntil 回退既有实例，栈不嵌套；
/// 3. 跳转链失真（目标已被返回键弹掉）→ 落点判别后兜底 push，不静默失效。
///
/// 背景：modular 7 的 `routeState()` 只反映栈底，push 的页面不进 URL——
/// 组件靠 pagePath + 菜单链 + canPop 判别，这里的用例就是防回归的护栏。
const _defaultTestEntries = [
  AppBarMenuEntry(label: 'B', leadingIcon: Icons.star, route: '/b/'),
  AppBarMenuEntry(label: 'C', leadingIcon: Icons.star, route: '/c/'),
];

class _HostPage extends StatelessWidget {
  const _HostPage({
    required this.pagePath,
    this.entries = _defaultTestEntries,
  });

  final String pagePath;
  final List<AppBarMenuEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(pagePath),
        actions: [
          WywAppBarMenuButton(pagePath: pagePath, entries: entries),
        ],
      ),
      body: Center(child: Text('page:$pagePath')),
    );
  }
}

const _settingsTestEntries = [
  AppBarMenuEntry(label: 'B', leadingIcon: Icons.star, route: '/b/'),
  AppBarMenuEntry(
      label: '设置', leadingIcon: Icons.settings, route: '/settings/'),
];

Widget _app() {
  final module = createModule(register: (c) {
    c
      ..route('/',
          child: (context, state) => const _HostPage(pagePath: '/a/'))
      ..route('/b',
          child: (context, state) => const _HostPage(pagePath: '/b/'))
      ..route('/c',
          child: (context, state) => const _HostPage(pagePath: '/c/'));
  });
  return ModularApp(
    module: module,
    child: Builder(
      builder: (context) => MaterialApp.router(
        routerConfig: ModularApp.routerConfigOf(context),
      ),
    ),
  );
}

Future<void> _openMenuAndTap(WidgetTester tester, String label) async {
  await tester.tap(find.byIcon(Icons.more_vert));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

int _hostPageCount(WidgetTester tester) =>
    // 栈顶以下的页面被 Navigator 包进 Offstage，必须关掉 skipOffstage
    // 才能数到完整栈深（诊断结论：组件压栈行为正常，见 B9 节）。
    tester.widgetList(find.byType(_HostPage, skipOffstage: false)).length;

void main() {
  testWidgets('已在本页的条目禁用，其余条目可用', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    // 从 /a/ 进入 /b/
    await _openMenuAndTap(tester, 'B');
    expect(find.text('page:/b/'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    final bItem =
        tester.widget<MenuItemButton>(find.widgetWithText(MenuItemButton, 'B'));
    expect(bItem.onPressed, isNull, reason: '已在 /b/，B 条目应禁用');
    final cItem =
        tester.widget<MenuItemButton>(find.widgetWithText(MenuItemButton, 'C'));
    expect(cItem.onPressed, isNotNull, reason: 'C 条目应可用');
  });

  testWidgets('目标在栈内：回退既有实例而不是嵌套', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    // /a/ → B → /b/；再模拟非菜单入口（如「我的」页 tile）把 /c/ 压到 /b/ 之上，
    // 构造 a→b→c 夹心栈（互斥进入不会产生这种栈，真实触发源是 tile/深链）
    await _openMenuAndTap(tester, 'B');
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .context
        .pushNamed('/c/');
    await tester.pumpAndSettle();
    expect(_hostPageCount(tester), 3, reason: '前置：栈为 a→b→c');
    // 在 /c/ 点 B：/b/ 在栈内（presence）→ popUntil 回退，c 被抛出
    await _openMenuAndTap(tester, 'B');
    expect(_hostPageCount(tester), 2, reason: '应回退到 /b/，c 被抛出');
    expect(find.text('page:/b/'), findsOneWidget);
  });

  testWidgets('目标已不在栈内（presence 注销）→ 直接 push', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    // /a/ → B → /b/，再用系统级 pop 返回 /a/（pop 触发 /b/ dispose，
    // presence 随之注销——目标已确实不在栈内）
    await _openMenuAndTap(tester, 'B');
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .pop();
    await tester.pumpAndSettle();
    expect(
        find.text('page:/a/', skipOffstage: false), findsOneWidget);
    // 再点 B：presence 已注销 → 直接 push
    await _openMenuAndTap(tester, 'B');
    expect(_hostPageCount(tester), 2, reason: '应重新 push 到 /b/');
    expect(find.text('page:/b/'), findsOneWidget);
  });

  testWidgets('互斥：进入新菜单区块时，栈内旧菜单区块被抛出', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    // /a/ → B → /b/ → C：C 不在栈内 → 互斥进入，/b/ 被抛出
    await _openMenuAndTap(tester, 'B');
    await _openMenuAndTap(tester, 'C');
    expect(_hostPageCount(tester), 2, reason: '栈应为 a→c，b 被抛出');
    expect(find.text('page:/b/', skipOffstage: false), findsNothing,
        reason: '历史区块不应残留在栈中');
    expect(find.text('page:/c/'), findsOneWidget);
  });

  testWidgets('设置壳内（单栏）：设置条目走壳内 onBack，不触发根栈导航', (tester) async {
    var backCalls = 0;
    final module = createModule(register: (c) {
      c.route(
        '/',
        child: (context, state) => SettingsPaneScope(
          embedded: false,
          showBackButton: false,
          onBack: () => backCalls++,
          child: const _HostPage(
            pagePath: '/settings/logs/',
            entries: _settingsTestEntries,
          ),
        ),
      );
    });
    await tester.pumpWidget(ModularApp(
      module: module,
      child: Builder(
        builder: (context) =>
            MaterialApp.router(routerConfig: ModularApp.routerConfigOf(context)),
      ),
    ));
    await tester.pumpAndSettle();

    await _openMenuAndTap(tester, '设置');
    expect(backCalls, 1, reason: '应走壳内 onBack 回分类列表');
    // 没有发生根栈导航：宿主页原地不动，栈深不变
    expect(find.text('page:/settings/logs/', skipOffstage: false),
        findsOneWidget);
    expect(_hostPageCount(tester), 1);
  });

  testWidgets('设置壳内：其他条目照常 push；双栏嵌入时设置条目禁用', (tester) async {
    final module = createModule(register: (c) {
      c.route(
        '/',
        child: (context, state) => SettingsPaneScope(
          embedded: true,
          showBackButton: false,
          onBack: null,
          child: const _HostPage(
            pagePath: '/settings/logs/',
            entries: _settingsTestEntries,
          ),
        ),
      );
      c.route('/b',
          child: (context, state) => const _HostPage(pagePath: '/b/'));
    });
    await tester.pumpWidget(ModularApp(
      module: module,
      child: Builder(
        builder: (context) =>
            MaterialApp.router(routerConfig: ModularApp.routerConfigOf(context)),
      ),
    ));
    await tester.pumpAndSettle();

    // 双栏嵌入：人已在设置界面 → 设置条目禁用
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    final settingsItem = tester.widget<MenuItemButton>(
        find.widgetWithText(MenuItemButton, '设置'));
    expect(settingsItem.onPressed, isNull, reason: '双栏嵌入时已在设置界面');
    // 禁用项点了不应有反应，且菜单保持打开
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    expect(_hostPageCount(tester), 1);
    // 菜单仍开着：直接点 B（壳保留在栈下，b 压在壳上）
    await tester.tap(find.text('B').last);
    await tester.pumpAndSettle();
    expect(find.text('page:/b/'), findsOneWidget);
    expect(_hostPageCount(tester), 2);
  });
}
