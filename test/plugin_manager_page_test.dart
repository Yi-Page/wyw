import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobx/mobx.dart' as mobx;
import 'package:wyw/bean/dialog/dialog.dart';
import 'package:wyw/bean/settings/settings_detail_scaffold.dart';
import 'package:wyw/pages/plugin/plugin_controller.dart';
import 'package:wyw/pages/plugin/plugin_manager_page.dart';
import 'package:wyw/plugins/plugin.dart';
import 'package:wyw/plugins/plugin_operation.dart';

/// 插件管理页的回归：
///   1. 已启用 / 已禁用**同一个列表**，禁用只在卡片上体现为一个「已禁用」标签
///      （不再有底部那块独立的「已禁用 N」分区）；
///   2. 窄面板下工具栏（搜索 + 类型 + 状态）不溢出；
///   3. 多选模式的动作齐全 —— 全选 / 取消全选 / 反选（选择条）+ 启用选中 / 禁用选中
///      （标题栏），且选择类动作只作用于**当前可见**列表；
///   4. 「异常」分区自带批量动作（全部导入 / 全部删除）：与标题同一行、靠右，
///      计数与分区一致，删除按类别走各自通道、失败项汇总进结果弹窗。
void main() {
  Future<PluginController> pumpManager(
    WidgetTester tester,
    List<Plugin> plugins, {
    double width = 900,
    double height = 700,
    PluginController? controller,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final c = controller ?? PluginController();
    mobx.runInAction(() => c.plugins.addAll(plugins));

    final module = createModule(register: (ctx) {
      ctx
        ..addSingleton<PluginController>(() => c)
        ..route(
          '/',
          // 嵌入式（设置页主从布局的右窗格）分支：不经过 SysAppBar，
          // 因为后者依赖启动期初始化的全局设置，单测里没有。
          child: (context, state) => const SettingsPaneScope(
            embedded: true,
            showBackButton: false,
            child: PluginManagerPage(),
          ),
        );
    });
    await tester.pumpWidget(
      ModularApp(
        module: module,
        // 挂上项目的对话框记账观察器，批量动作的确认框才弹得出来
        // （WywDialog.show 在没有 context 时回退到 observer.navigator）。
        navigatorObservers: [WywDialog.observer],
        child: Builder(
          builder: (context) => MaterialApp.router(
            routerConfig: ModularApp.routerConfigOf(context),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return c;
  }

  testWidgets('已启用与已禁用同列，禁用只多一个「已禁用」标签', (tester) async {
    await pumpManager(tester, [
      Plugin(name: 'hanime', displayName: 'Hanime'),
      Plugin(name: 'jm', displayName: 'JM', enabled: false),
    ]);

    // 两条都在同一个列表里
    expect(find.text('Hanime'), findsOneWidget);
    expect(find.text('JM'), findsOneWidget);
    // 禁用只体现为一个标签，且只有一条
    expect(find.text('已禁用'), findsOneWidget);
    // 底部那块独立分区已经没有了
    expect(find.text('已禁用 1'), findsNothing);
  });

  testWidgets('全启用时不出现「已禁用」标签', (tester) async {
    await pumpManager(tester, [
      Plugin(name: 'hanime', displayName: 'Hanime'),
      Plugin(name: 'jm', displayName: 'JM'),
    ]);

    expect(find.text('Hanime'), findsOneWidget);
    expect(find.text('JM'), findsOneWidget);
    expect(find.text('已禁用'), findsNothing);
  });

  testWidgets('窄面板（280）下工具栏与卡片都不溢出', (tester) async {
    await pumpManager(
      tester,
      [
        Plugin(name: 'hanime', displayName: 'Hanime'),
        Plugin(name: 'jm', displayName: 'JM', enabled: false),
      ],
      width: 280,
      height: 640,
    );

    expect(tester.takeException(), isNull);
    // 换行后两个筛选仍在（类型 / 状态）
    expect(find.text('类型'), findsOneWidget);
    expect(find.text('状态'), findsOneWidget);
  });

  // ===== 多选模式 =====

  /// 长按任意卡片进入多选模式（同时选中被长按的那一条）。
  Future<void> enterMultiSelect(WidgetTester tester, String title) async {
    await tester.longPress(find.text(title));
    await tester.pumpAndSettle();
  }

  /// 标题栏里的一个动作按钮（按 tooltip 定位到 IconButton 本体，取 onPressed 判断可用性）。
  IconButton actionButton(WidgetTester tester, String tooltip) {
    return tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip(tooltip),
        matching: find.byWidgetPredicate((w) => w is IconButton),
      ),
    );
  }

  /// 选择条里的一个动作按钮（tooltip 由页面自己包在 TextButton 外面，
  /// 所以按钮是 tooltip 的**子节点**，与标题栏那种「IconButton 内建 tooltip」方向相反）。
  TextButton selectionButton(WidgetTester tester, String tooltip) {
    return tester.widget<TextButton>(
      find.descendant(
        of: find.byTooltip(tooltip),
        matching: find.byWidgetPredicate((w) => w is TextButton),
      ),
    );
  }

  testWidgets('多选：全选 / 取消全选 / 反选 齐全，且清空不会退出多选', (tester) async {
    await pumpManager(tester, [
      Plugin(name: 'hanime', displayName: 'Hanime'),
      Plugin(name: 'jm', displayName: 'JM', enabled: false),
      Plugin(name: 'moe', displayName: 'Moe'),
    ]);

    await enterMultiSelect(tester, 'Hanime');
    expect(find.text('已选择 1 项'), findsOneWidget);

    // 全选：可见的 3 条全部选上
    await tester.tap(find.byTooltip('全选当前可见的规则'));
    await tester.pumpAndSettle();
    expect(find.text('已选择 3 项'), findsOneWidget);
    expect(find.text('已选 3 条 · 可见 3 条'), findsOneWidget);

    // 反选：可见的 3 条都在选中态 → 全部取消；**仍在多选模式**（不是自动退出）
    await tester.tap(find.byTooltip('反选当前可见的规则'));
    await tester.pumpAndSettle();
    expect(find.text('已选择 0 项'), findsOneWidget);
    expect(find.byTooltip('取消多选'), findsOneWidget);
    // 没有选中项时「取消全选」没有意义，置灰
    expect(selectionButton(tester, '取消全选（留在多选模式）').onPressed, isNull);

    // 反选：一条没选 → 全部选上
    await tester.tap(find.byTooltip('反选当前可见的规则'));
    await tester.pumpAndSettle();
    expect(find.text('已选择 3 项'), findsOneWidget);

    // 取消全选：清空，仍留在多选模式里
    await tester.tap(find.byTooltip('取消全选（留在多选模式）'));
    await tester.pumpAndSettle();
    expect(find.text('已选择 0 项'), findsOneWidget);
    expect(find.byTooltip('取消多选'), findsOneWidget);
  });

  testWidgets('多选：全选 / 反选只作用于当前可见列表', (tester) async {
    await pumpManager(tester, [
      Plugin(name: 'hanime', displayName: 'Hanime'),
      Plugin(name: 'jm', displayName: 'JM', enabled: false),
      Plugin(name: 'moe', displayName: 'Moe'),
    ]);

    await enterMultiSelect(tester, 'Hanime');
    await tester.tap(find.text('Moe'));
    await tester.pumpAndSettle();
    expect(find.text('已选择 2 项'), findsOneWidget);

    // 搜索把可见范围收窄到 jm 一条：已经选中的两条都在可见范围之外
    await tester.enterText(find.byType(TextField), 'jm');
    await tester.pumpAndSettle();
    expect(find.text('已选 2 条 · 可见 1 条'), findsOneWidget);

    // 全选：只补上可见的那条，可见范围之外的两条保持选中
    await tester.tap(find.byTooltip('全选当前可见的规则'));
    await tester.pumpAndSettle();
    expect(find.text('已选择 3 项'), findsOneWidget);

    // 反选：只翻转可见的那条，另外两条不受影响
    await tester.tap(find.byTooltip('反选当前可见的规则'));
    await tester.pumpAndSettle();
    expect(find.text('已选择 2 项'), findsOneWidget);
    expect(find.text('已选 2 条 · 可见 1 条'), findsOneWidget);
  });

  testWidgets('多选：启用选中 / 禁用选中 都在标题栏，选中为空时置灰', (tester) async {
    await pumpManager(tester, [
      Plugin(name: 'hanime', displayName: 'Hanime'),
      Plugin(name: 'jm', displayName: 'JM', enabled: false),
    ]);

    await enterMultiSelect(tester, 'Hanime');
    for (final tooltip in const ['禁用选中', '启用选中']) {
      expect(actionButton(tester, tooltip).onPressed, isNotNull, reason: tooltip);
    }

    await tester.tap(find.byTooltip('取消全选（留在多选模式）'));
    await tester.pumpAndSettle();

    for (final tooltip in const [
      '导出选中到剪贴板',
      '删除选中',
      '禁用选中',
      '启用选中',
    ]) {
      expect(actionButton(tester, tooltip).onPressed, isNull, reason: tooltip);
    }
    // 清空只是没有选中项，多选模式本身还在
    expect(find.byTooltip('全选当前可见的规则'), findsOneWidget);
    expect(find.byTooltip('取消多选'), findsOneWidget);
  });

  testWidgets('多选：启用选中先确认，确认框里带条数', (tester) async {
    await pumpManager(tester, [
      Plugin(name: 'hanime', displayName: 'Hanime'),
      Plugin(name: 'jm', displayName: 'JM', enabled: false),
    ]);

    await enterMultiSelect(tester, 'JM');
    await tester.tap(find.byTooltip('启用选中'));
    await tester.pumpAndSettle();

    expect(find.text('启用规则'), findsOneWidget);
    expect(find.textContaining('确定要启用选中的 1 条规则吗？'), findsOneWidget);

    // 取消：不动假目录里的插件文件
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('启用规则'), findsNothing);
    // 取消后仍然保持多选与选中状态
    expect(find.text('已选择 1 项'), findsOneWidget);
  });

  testWidgets('多选：卡片勾选框也能改选，取消最后一条不退出多选', (tester) async {
    await pumpManager(tester, [
      Plugin(name: 'hanime', displayName: 'Hanime'),
      Plugin(name: 'jm', displayName: 'JM', enabled: false),
      Plugin(name: 'moe', displayName: 'Moe'),
    ]);

    await enterMultiSelect(tester, 'Hanime');
    expect(find.byType(Checkbox), findsNWidgets(3));

    // 取消唯一被选中的那条：选择清空，但**仍在多选模式**（否则没法接着反选）
    await tester.tap(find.byType(Checkbox).at(0));
    await tester.pumpAndSettle();
    expect(find.text('已选择 0 项'), findsOneWidget);
    expect(find.byTooltip('取消多选'), findsOneWidget);

    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pumpAndSettle();
    expect(find.text('已选择 1 项'), findsOneWidget);
  });

  testWidgets('多选：全是启用状态时，启用选中直接提示「都已是启用状态」', (tester) async {
    await pumpManager(tester, [
      Plugin(name: 'hanime', displayName: 'Hanime'),
      Plugin(name: 'jm', displayName: 'JM', enabled: false),
    ]);

    await enterMultiSelect(tester, 'Hanime'); // hanime 本来就是启用状态
    await tester.tap(find.byTooltip('启用选中'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('启用'));
    await tester.pumpAndSettle();

    // 执行期走了「全部跳过」分支：给 toast，不做任何写盘
    expect(find.text('选中的规则都已经是「已启用」状态'), findsOneWidget);
    expect(find.byTooltip('取消多选'), findsNothing); // 批量动作结束就退出多选

    // 把 toast 的计时器走完，免得留下 pending timer
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('多选：批量启用失败时汇总进结果弹窗，并退出多选', (tester) async {
    final controller = await pumpManager(tester, [
      Plugin(name: 'hanime', displayName: 'Hanime'),
      Plugin(name: 'jm', displayName: 'JM', enabled: false),
    ]);

    await enterMultiSelect(tester, 'Hanime');
    await tester.tap(find.byTooltip('全选当前可见的规则'));
    await tester.pumpAndSettle();
    expect(find.text('已选择 2 项'), findsOneWidget);

    // 选中之后条目从列表里消失（真机上是刷新后插件被删掉），批量启用只能走
    // 「不在列表中」这条失败分支。
    //
    // 这里刻意**不**造「文件缺失」那条失败：`PluginController.enable` 每次都要
    // 先 await 真实的文件 I/O，而 widget 测试跑在假时钟里，真实 I/O 的回调不会
    // 自己跑完（同一坑见 player_split_tabs_test.dart 的内存箱说明），确认框点完
    // 之后流程会一直悬在那里。所以文件缺失 / 注册失败那两条分支由控制器单测覆盖。
    mobx.runInAction(controller.plugins.clear);
    await tester.pumpAndSettle();
    expect(find.text('已选 2 条 · 可见 0 条'), findsOneWidget);

    await tester.tap(find.byTooltip('启用选中'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('启用'));
    await tester.pumpAndSettle();

    // 断言只钉结构：标题、成功/失败条数、退出多选
    expect(find.text('启用结果'), findsOneWidget);
    expect(find.textContaining('成功 0 条'), findsOneWidget);
    expect(find.textContaining('失败 2 条'), findsOneWidget);
    expect(find.byTooltip('取消多选'), findsNothing);

    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
  });

  testWidgets('窄面板（280）下多选模式与选择条都不溢出', (tester) async {
    await pumpManager(
      tester,
      [
        Plugin(name: 'hanime', displayName: 'Hanime'),
        Plugin(name: 'jm', displayName: 'JM', enabled: false),
      ],
      width: 280,
      height: 640,
    );

    await enterMultiSelect(tester, 'Hanime');
    expect(tester.takeException(), isNull);

    // 选择条三个动作都在（换行排布，不靠省略号裁掉）
    expect(find.text('全选'), findsOneWidget);
    expect(find.text('取消全选'), findsOneWidget);
    expect(find.text('反选'), findsOneWidget);
    expect(find.text('已选 1 条 · 可见 2 条'), findsOneWidget);
  });

  // ===== 异常分区的批量动作 =====

  /// 四类异常俱全的控制器替身：
  ///   注册失败 `broken` / 文件缺失 `lost` / 未导入 `stray`、`stray2` / 文件名非法 `bad name`。
  _FakePluginController issueController() {
    final controller = _FakePluginController();
    mobx.runInAction(() {
      controller.plugins.addAll([
        Plugin(name: 'good', displayName: '正常插件'),
        Plugin(name: 'broken', displayName: '坏插件')..loadError = '注册失败：语法错误',
        Plugin(name: 'lost', displayName: '丢失插件')..fileMissing = true,
      ]);
      controller.unimportedFiles.addAll(const [
        PluginLoadFailure(
          name: 'stray',
          filePath: '/plugins/stray.js',
          message: '索引里没有它的记录',
        ),
        PluginLoadFailure(
          name: 'stray2',
          filePath: '/plugins/stray2.js',
          message: '索引里没有它的记录',
        ),
      ]);
      controller.invalidFiles.add(
        const PluginLoadFailure(
          name: 'bad name',
          filePath: '/plugins/bad name.js',
          message: '文件名不合法',
        ),
      );
    });
    return controller;
  }

  /// 确认框里那个「全部删除」（标题行与确认按钮同名，用 AlertDialog 限定）。
  Finder confirmButtonInDialog(String label) => find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(label),
      );

  testWidgets('异常分区：批量动作与标题同一行、靠右，计数与分区一致', (tester) async {
    await pumpManager(tester, const [], controller: issueController());

    // 分区标题的计数 = 四类之和；两个按钮各自带作用范围
    expect(find.text('异常 5'), findsOneWidget);
    // 「全部导入」只数「未导入」，「全部删除」数四类总和
    expect(find.text('全部导入 2'), findsOneWidget);
    expect(find.text('全部删除 5'), findsOneWidget);

    // 与标题**同一行**（竖直方向几乎重合），且在异常列表上方
    final titleY = tester.getCenter(find.text('异常 5')).dy;
    final actionY = tester.getCenter(find.text('全部删除 5')).dy;
    expect((actionY - titleY).abs(), lessThan(4), reason: '批量动作应与标题同一行');
    final firstTileY = tester.getTopLeft(find.text('丢失插件')).dy;
    expect(actionY, lessThan(firstTileY));

    // 靠右：标题在左、动作贴着面板右缘（900 宽）
    expect(
      tester.getCenter(find.text('全部导入 2')).dx,
      greaterThan(tester.getCenter(find.text('异常 5')).dx),
    );
    expect(tester.getTopRight(find.text('全部删除 5')).dx, greaterThan(750));
  });

  testWidgets('全部删除：按类别走对应通道，完成后给汇总 toast', (tester) async {
    final controller = issueController();
    await pumpManager(tester, const [], controller: controller);

    await tester.tap(find.text('全部删除 5'));
    await tester.pumpAndSettle();

    // 确认框说清每一类删的是什么
    expect(find.text('删除全部异常项'), findsOneWidget);
    expect(find.textContaining('确认删除异常分区里的全部 5 项'), findsOneWidget);
    expect(find.textContaining('· 文件缺失 1 条'), findsOneWidget);
    expect(find.textContaining('· 未导入 2 个'), findsOneWidget);

    await tester.tap(confirmButtonInDialog('全部删除'));
    await tester.pumpAndSettle();

    // 有记录的（缺文件 / 注册失败）走 deletePlugin；野文件按各自口径走 deleteStrayFile
    expect(controller.deletedPlugins, ['lost', 'broken']);
    expect(controller.deletedUnimported, ['stray', 'stray2']);
    expect(controller.deletedInvalid, ['bad name']);

    expect(find.text('已删除异常分区全部 5 项'), findsOneWidget);
    // 四项都清掉了 → 整个分区消失
    expect(find.textContaining('全部删除'), findsNothing);

    // 把 toast 的计时器走完，免得留下 pending timer
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('全部删除：单项失败汇总进结果弹窗，其余照删', (tester) async {
    final controller = issueController()..failures['broken'] = '文件被占用';
    await pumpManager(tester, const [], controller: controller);

    await tester.tap(find.text('全部删除 5'));
    await tester.pumpAndSettle();
    await tester.tap(confirmButtonInDialog('全部删除'));
    await tester.pumpAndSettle();

    expect(find.text('删除结果'), findsOneWidget);
    expect(find.textContaining('成功 4 项，失败 1 项'), findsOneWidget);
    // 失败明细用展示名，不是内部插件名
    expect(find.textContaining('坏插件：文件被占用'), findsOneWidget);

    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
  });

  testWidgets('全部导入：只认领「未导入」，结果按同一套口径汇总', (tester) async {
    final controller = issueController()..failures['stray2'] = '源码不合法';
    await pumpManager(tester, const [], controller: controller);

    await tester.tap(find.text('全部导入 2'));
    await tester.pumpAndSettle();

    expect(controller.adopted, ['stray', 'stray2']);
    expect(find.text('导入结果'), findsOneWidget);
    expect(find.textContaining('成功 1 个，失败 1 个'), findsOneWidget);
    expect(find.textContaining('stray2：源码不合法'), findsOneWidget);

    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    // 失败那条留在「未导入」里，按钮计数跟着减到 1
    expect(find.text('全部导入 1'), findsOneWidget);
  });

  testWidgets('全部删除：关键词筛选时只处理匹配项，确认框点明范围', (tester) async {
    final controller = issueController();
    await pumpManager(tester, const [], controller: controller);

    await tester.enterText(find.byType(TextField), 'stray');
    await tester.pumpAndSettle();
    expect(find.text('异常 2'), findsOneWidget);
    expect(find.text('全部删除 2'), findsOneWidget);

    await tester.tap(find.text('全部删除 2'));
    await tester.pumpAndSettle();
    expect(find.textContaining('当前有关键词「stray」筛选'), findsOneWidget);

    // 取消：一条都不动
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(controller.deletedPlugins, isEmpty);
    expect(controller.deletedUnimported, isEmpty);
    expect(controller.deletedInvalid, isEmpty);
  });

  testWidgets('窄面板（280）下异常分区与批量按钮仍是一行、不溢出', (tester) async {
    await pumpManager(
      tester,
      const [],
      controller: issueController(),
      width: 280,
      height: 640,
    );

    expect(tester.takeException(), isNull);
    // 窄面板退回「只有文案」的紧凑按钮，但**不换行**：两个按钮与标题仍同一行
    expect(find.text('全部导入 2'), findsOneWidget);
    expect(find.text('全部删除 5'), findsOneWidget);
    final titleY = tester.getCenter(find.text('异常 5')).dy;
    for (final label in const ['全部导入 2', '全部删除 5']) {
      expect(
        (tester.getCenter(find.text(label)).dy - titleY).abs(),
        lessThan(4),
        reason: '$label 应与标题同一行',
      );
    }
  });
}

/// 批量动作的控制器替身：**不碰真实文件**，只复刻「集合怎么变」。
///
/// 真控制器里每条删除 / 认领都要 `await` 真实文件 I/O，而 widget 测试跑在假时钟里
/// （同本文件多选那组的说明），确认框点完流程会一直悬在那里。这里把 I/O 换成立刻完成
/// 的 Future —— 页面要验证的正是「哪一类走了哪个通道、结果怎么汇总」。
class _FakePluginController extends PluginController {
  /// 走 `deletePlugin` 的名字（顺序 = 页面调用顺序）
  final List<String> deletedPlugins = [];

  /// 走 `deleteStrayFile(unimported: true)` 的名字
  final List<String> deletedUnimported = [];

  /// 走 `deleteStrayFile(unimported: false)` 的名字
  final List<String> deletedInvalid = [];

  /// 走 `adoptUnimportedFile` 的名字
  final List<String> adopted = [];

  /// 名字 -> 失败原因：配上的动作一律返回失败（验证汇总与「不回滚已成功的」）
  final Map<String, String> failures = {};

  @override
  Future<PluginOpResult> deletePlugin(String name) async {
    deletedPlugins.add(name);
    final failure = failures[name];
    if (failure != null) return PluginOpResult.failure(failure);
    mobx.runInAction(() => plugins.removeWhere((p) => p.name == name));
    return const PluginOpResult.success();
  }

  @override
  Future<PluginOpResult> deleteStrayFile(
    String name, {
    required bool unimported,
  }) async {
    (unimported ? deletedUnimported : deletedInvalid).add(name);
    final failure = failures[name];
    if (failure != null) return PluginOpResult.failure(failure);
    mobx.runInAction(() {
      (unimported ? unimportedFiles : invalidFiles)
          .removeWhere((file) => file.name == name);
    });
    return const PluginOpResult.success();
  }

  @override
  Future<PluginOpResult> adoptUnimportedFile(String name) async {
    adopted.add(name);
    final failure = failures[name];
    if (failure != null) return PluginOpResult.failure(failure);
    mobx.runInAction(() {
      unimportedFiles.removeWhere((file) => file.name == name);
      plugins.add(Plugin(name: name));
    });
    return const PluginOpResult.success();
  }
}

