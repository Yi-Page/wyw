import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobx/mobx.dart' as mobx;
import 'package:wyw/js/base_js_engine.dart';
import 'package:wyw/pages/plugin/plugin_controller.dart';
import 'package:wyw/plugins/plugin.dart';
import 'package:wyw/plugins/plugin_category.dart';
import 'package:wyw/plugins/plugin_category_index.dart';
import 'package:wyw/plugins/plugin_display_mode.dart';
import 'package:wyw/plugins/plugin_index.dart';
import 'package:wyw/plugins/plugin_source.dart';
import 'package:wyw/services/storage/settings_keys.dart';

/// 插件管理的纯逻辑回归测试。
///
/// 覆盖点：
///   - **命名链校验**（文件名 = 索引键 = 类名 = 引擎槽位）
///   - 插件名校验与大小写折叠唯一性
///   - `Plugin` 的六个持久化字段与序列化容错（运行时状态不落盘）
///   - `index.json`（数组）与 `categories.json`（数组）的读写、容错、`.bak`
///   - 分类图标调色板与分类注册表（内置优先、顺序 = 文件顺序、隐式登记）
///   - 控制器里不碰平台通道的部分：顺序（`movePlugin`）与分类解析
///
/// 控制器里依赖平台通道（path_provider / AssetManifest / flutter_qjs）的路径
/// 无法在单测中构造，因此这里只锁定可以纯函数化的判定逻辑。
void main() {
  // ===================== 命名链：源码形态校验 =====================

  group('PluginSourceRule.check 命名链', () {
    test('类名与插件名一致时通过', () {
      final check = PluginSourceRule.check(
        source: 'class hanime extends PluginSource {\n  name = "H"\n}\n',
        pluginName: 'hanime',
      );
      expect(check.ok, isTrue, reason: check.message);
      expect(check.hits.single.className, 'hanime');
      expect(check.hits.single.line, 1);
    });

    test('类名不一致时拒绝，并指出行号与实际类名', () {
      final check = PluginSourceRule.check(
        source: '// 头部注释\nclass other extends PluginSource {}\n',
        pluginName: 'hanime',
      );
      expect(check.ok, isFalse);
      expect(check.message, contains('other'));
      expect(check.message, contains('hanime'));
      expect(check.message, contains('第 2 行'));
    });

    test('仅大小写不同也拒绝（JS 大小写敏感 / 文件系统不敏感）', () {
      final check = PluginSourceRule.check(
        source: 'class Hanime extends PluginSource {}\n',
        pluginName: 'hanime',
      );
      expect(check.ok, isFalse);
      expect(check.message, contains('大小写'));
    });

    test('两处顶层类声明时拒绝', () {
      final check = PluginSourceRule.check(
        source: 'class a extends PluginSource {}\n'
            'class b extends PluginSource {}\n',
        pluginName: 'a',
      );
      expect(check.ok, isFalse);
      expect(check.message, contains('2 处'));
    });

    test('没有继承 PluginSource 的类时拒绝', () {
      final check = PluginSourceRule.check(
        source: 'class hanime {\n}\n',
        pluginName: 'hanime',
      );
      expect(check.ok, isFalse);
      expect(check.message, contains('未找到'));
    });

    test('空源码拒绝', () {
      expect(
        PluginSourceRule.check(source: '   \n', pluginName: 'a').ok,
        isFalse,
      );
    });

    test('缩进的类声明不计入（只认第 1 列）', () {
      final check = PluginSourceRule.check(
        source: 'class hanime extends PluginSource {\n'
            '  make() { class helper extends PluginSource {} }\n'
            '}\n',
        pluginName: 'hanime',
      );
      expect(check.ok, isTrue, reason: check.message);
      expect(check.hits.length, 1);
    });

    test('类声明必须单行（extends 换行会被拒绝）', () {
      final check = PluginSourceRule.check(
        source: 'class hanime\n  extends PluginSource {}\n',
        pluginName: 'hanime',
      );
      expect(check.ok, isFalse);
      expect(check.message, contains('未找到'));
    });

    test('基类写死 PluginSource：别名 / 其他基类不通过', () {
      final check = PluginSourceRule.check(
        source: 'class hanime extends Base {}\n',
        pluginName: 'hanime',
      );
      expect(check.ok, isFalse);
    });
  });

  // ===================== 格式与结构校验 =====================

  group('PluginSourceRule.check 格式与结构', () {
    test('删掉一半大括号 → 报「没有闭合」（这条以前查不出来）', () {
      final check = PluginSourceRule.check(
        source: 'class hanime extends PluginSource {\n'
            '  run() {\n'
            '    return 1;\n'
            '  }\n', // 少了最外层那个 }
        pluginName: 'hanime',
      );
      expect(check.ok, isFalse);
      expect(check.message, contains('没有闭合'));
      expect(check.message, contains('第 1 行'), reason: '要点出是哪个括号');
    });

    test('多余的右括号 → 报「没有对应」', () {
      final check = PluginSourceRule.check(
        source: 'class hanime extends PluginSource {\n  run() {}\n}\n}\n',
        pluginName: 'hanime',
      );
      expect(check.ok, isFalse);
      expect(check.message, contains('没有对应的'));
    });

    test('括号类型不匹配也会报出来', () {
      final check = PluginSourceRule.check(
        source: 'class hanime extends PluginSource {\n  run() {}\n)\n',
        pluginName: 'hanime',
      );
      expect(check.ok, isFalse);
      expect(check.message, contains('括号不配对'));
    });

    test('字面量 / 注释 / 正则里的括号不参与配平', () {
      const source = r'''
class hanime extends PluginSource {
  re = /[{(]/;
  a = '}';
  b = "{";
  c = `)`;
  run() {
    // 注释里写 })}] 也不算
    return this.re.test(this.a);
  }
}
''';
      final check =
          PluginSourceRule.check(source: source, pluginName: 'hanime');
      expect(check.ok, isTrue, reason: check.message);
      expect(check.hasWarnings, isFalse);
    });

    test('第二个顶层类（没有 extends PluginSource）也算数', () {
      final check = PluginSourceRule.check(
        source: 'class hanime extends PluginSource {\n  run() {}\n}\n'
            'class helper {\n  static x = 1;\n}\n',
        pluginName: 'hanime',
      );
      expect(check.ok, isFalse);
      expect(check.message, contains('2 处'));
      expect(check.message, contains('helper'));
    });

    test('有 class 但没 extends PluginSource → 指出找到的是哪个类', () {
      final check = PluginSourceRule.check(
        source: 'class hanime\n  extends PluginSource {}\n',
        pluginName: 'hanime',
      );
      expect(check.ok, isFalse);
      expect(check.message, contains('class hanime'));
    });

    test('类外有代码：只提示、不拦截（能跑的存量写法）', () {
      final check = PluginSourceRule.check(
        source: 'const CONFIG = { a: 1 };\n'
            'class hanime extends PluginSource {\n  run() {}\n}\n',
        pluginName: 'hanime',
      );
      expect(check.ok, isTrue, reason: '类外代码是合法 JS，不该拦注册');
      expect(check.hasWarnings, isTrue);
      expect(check.warnings.single, contains('之前'));
      expect(check.warnings.single, contains('CONFIG'));
    });

    test('类之后有代码也能报出来', () {
      final check = PluginSourceRule.check(
        source: 'class hanime extends PluginSource {\n  run() {}\n}\n'
            'const AFTER = 1;\n',
        pluginName: 'hanime',
      );
      expect(check.ok, isTrue);
      expect(check.warnings.single, contains('之后'));
    });

    test('类体内第 1 列的 } 不会让类体提前结束（happy / mxs 形态）', () {
      final check = PluginSourceRule.check(
        source: 'class hanime extends PluginSource {\n'
            '  run() {\n'
            '    return 1\n'
            '}\n' // 第 1 列的 } ：靠括号配对收尾，不是正则找 ^}
            '  more() {}\n'
            '}\n',
        pluginName: 'hanime',
      );
      expect(check.ok, isTrue, reason: check.message);
      expect(check.hasWarnings, isFalse, reason: '类体收尾后不该再有内容');
    });
  });

  // ===================== 内置插件过新校验 =====================

  group('内置插件必须过新校验', () {
    test('assets/plugin/*.js 全部通过（配平 + 恰好一个顶层类 + 类名匹配）', () {
      final files = Directory('assets/plugin')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.js'))
          .toList();
      expect(files, isNotEmpty);

      final failures = <String>[];
      final outerCode = <String>[];
      for (final file in files) {
        final name = file.uri.pathSegments.last.replaceFirst('.js', '');
        final check = PluginSourceRule.check(
          source: file.readAsStringSync(),
          pluginName: name,
        );
        if (!check.ok) failures.add('$name：${check.message}');
        if (check.hasWarnings) outerCode.add(name);
      }
      expect(failures, isEmpty, reason: failures.join('\n'));
      // 类外代码只提示：把当前事实钉住，免得误判「全部干净」
      expect(outerCode, isEmpty,
          reason: '这些内置插件本来就没有类外代码；有的话说明判定放宽了');
    });
  });

  group('PluginSourceRule.maskCommentsAndLiterals', () {
    test('掩码后长度不变（行号与偏移不漂）', () {
      const source = '// a\n/* b */\nconst s = "x";\nconst t = `y${1}z`;\n';
      expect(
        PluginSourceRule.maskCommentsAndLiterals(source).length,
        source.length,
      );
    });

    test('换行数量不变', () {
      const source = '// 注释\n/* 多\n行 */\nlet a = `模板\n字面量`;\n';
      String countNewlines(String text) =>
          RegExp('\n').allMatches(text).length.toString();
      expect(
        countNewlines(PluginSourceRule.maskCommentsAndLiterals(source)),
        countNewlines(source),
      );
    });

    test('注释里的假类声明不被计入', () {
      final check = PluginSourceRule.check(
        source: '// class fake extends PluginSource {}\n'
            'class hanime extends PluginSource {}\n',
        pluginName: 'hanime',
      );
      expect(check.ok, isTrue, reason: check.message);
      expect(check.hits.length, 1);
    });

    test('模板字面量里的假类声明不被计入', () {
      final check = PluginSourceRule.check(
        source: 'const inject = `\nclass fake extends PluginSource {}\n`;\n'
            'class hanime extends PluginSource {}\n',
        pluginName: 'hanime',
      );
      expect(check.ok, isTrue, reason: check.message);
      expect(check.hits.length, 1);
    });

    test('字符串里的转义引号不会提前结束掩码', () {
      final check = PluginSourceRule.check(
        source: 'const s = "\\" class fake extends PluginSource {}";\n'
            'class hanime extends PluginSource {}\n',
        pluginName: 'hanime',
      );
      expect(check.ok, isTrue, reason: check.message);
      expect(check.hits.length, 1);
    });

    test('正则字面量里的引号不会吃掉后面的类声明（ikmmh 形态）', () {
      // ikmmh.js:13 = /document\.cookie\s*=\s*"([^"]+)"/  —— 奇数个双引号
      final check = PluginSourceRule.check(
        source: 'const re = /document\\.cookie\\s*=\\s*"([^"]+)"/;\n'
            'function f() { return 1 }\n'
            'class hanime extends PluginSource {}\n',
        pluginName: 'hanime',
      );
      expect(check.ok, isTrue, reason: check.message);
      expect(check.hits.single.line, 3);
    });

    test('字符类里的斜杠不会提前结束正则', () {
      final check = PluginSourceRule.check(
        source: 'const re = /[/"]+/g;\nclass hanime extends PluginSource {}\n',
        pluginName: 'hanime',
      );
      expect(check.ok, isTrue, reason: check.message);
    });

    test('除号不被误判为正则（表达式之后）', () {
      final check = PluginSourceRule.check(
        source: 'const a = (b) / 2;\nconst c = d[0] / 3;\n'
            'class hanime extends PluginSource {}\n',
        pluginName: 'hanime',
      );
      expect(check.ok, isTrue, reason: check.message);
    });

    test('关键字之后的正则被正确识别', () {
      final check = PluginSourceRule.check(
        source: 'function f() { return /"/.test(s) }\n'
            'const g = typeof /x/ === "object";\n'
            'class hanime extends PluginSource {}\n',
        pluginName: 'hanime',
      );
      expect(check.ok, isTrue, reason: check.message);
    });
  });

  // ===================== 插件名规则 =====================

  group('PluginNameRules / Plugin.validateName', () {
    test('接受合法（小写）插件名', () {
      const valid = ['hanime', 'copy_manga', 'mh1234', 'fc_008nnn', '_private'];
      for (final name in valid) {
        expect(PluginNameRules.validate(name), isNull, reason: name);
        expect(Plugin.validateName(name), isNull, reason: name);
      }
    });

    test('拒绝含大写字母的名字（准入规则强制小写）', () {
      const invalid = ['Hanime', 'HANIME', 'A1_b2', 'hotManga'];
      for (final name in invalid) {
        expect(PluginNameRules.validate(name), isNotNull, reason: name);
      }
      // 提示要点明是大小写问题，而不是"字符集不对"
      expect(PluginNameRules.validate('Hanime'), contains('小写'));
    });

    test('存量判定：大写名字被认出是遗留名字，但不影响加载', () {
      expect(PluginNameRules.isLegacyName('Hanime'), isTrue);
      expect(PluginNameRules.isLegacyName('hanime'), isFalse);
      // 连字符等非法字符不算「遗留名字」——那本来就不该存在
      expect(PluginNameRules.isLegacyName('my-rule'), isFalse);
    });

    test('拒绝空名', () {
      expect(PluginNameRules.validate(''), '插件名不能为空');
    });

    test('拒绝以数字开头的名字', () {
      expect(PluginNameRules.validate('2fast'), isNotNull);
    });

    test('拒绝连字符 / 点 / 空格 / 路径分隔符', () {
      const invalid = ['my-rule', 'my.rule', 'my rule', 'a/b', r'a\b', '../evil'];
      for (final name in invalid) {
        expect(PluginNameRules.validate(name), isNotNull, reason: name);
      }
    });

    test('拒绝非 ASCII 名字', () {
      expect(PluginNameRules.validate('插件'), isNotNull);
    });

    test('拒绝 Windows 保留名', () {
      expect(PluginNameRules.validate('con'), isNotNull);
      expect(PluginNameRules.validate('NUL'), isNotNull);
      expect(PluginNameRules.validate('com1'), isNotNull);
      expect(PluginNameRules.validate('console'), isNull);
    });

    test('大小写折叠键用于查重', () {
      expect(PluginNameFold.of(' Hanime '), 'hanime');
      expect(PluginNameFold.of('hanime'), PluginNameFold.of('HANIME'));
    });
  });

  // ===================== 插件模型（六个持久化字段 + 派生） =====================

  group('Plugin 序列化', () {
    test('toJson 只写六个持久化字段（运行时状态不落盘）', () {
      final plugin = Plugin(
        name: 'demo',
        enabled: false,
        displayName: '演示',
        categoryId: 'manga',
        homepage: 'https://example.com',
        description: '简介',
      );
      expect(plugin.toJson(), {
        'name': 'demo',
        'enabled': false,
        'displayName': '演示',
        'categoryId': 'manga',
        'homepage': 'https://example.com',
        'description': '简介',
      });
    });

    test('fromJson 往返保持六个字段', () {
      final json = Plugin(
        name: 'demo',
        enabled: false,
        displayName: '演示',
        categoryId: 'manga',
        homepage: 'https://example.com',
        description: '简介',
      ).toJson();
      final back = Plugin.fromJson(json)!;
      expect(back.name, 'demo');
      expect(back.enabled, isFalse);
      expect(back.displayName, '演示');
      expect(back.categoryId, 'manga');
      expect(back.homepage, 'https://example.com');
      expect(back.description, '简介');
    });

    test('fromJson 容错：缺字段取默认、缺 name 返回 null、非对象返回 null', () {
      final minimal = Plugin.fromJson({'name': 'demo'})!;
      expect(minimal.enabled, isTrue);
      expect(minimal.displayName, '');
      expect(minimal.categoryId, '');
      expect(minimal.homepage, '');
      expect(minimal.description, '');

      expect(Plugin.fromJson({'enabled': true}), isNull);
      expect(Plugin.fromJson('demo'), isNull);
      expect(Plugin.fromJson(null), isNull);
      // 畸形字段不炸：一律 toString 后 trim
      expect(Plugin.fromJson({'name': '  demo  '})!.name, 'demo');
      expect(Plugin.fromJson({'name': 42})!.name, '42');
      // enabled 不是 bool 时按「启用」处理
      expect(Plugin.fromJson({'name': 'a', 'enabled': 'yes'})!.enabled, isTrue);
    });

    test('派生：fileName / filePath / title / isLoaded', () {
      final saved = Plugin.directory;
      Plugin.directory = '/plugins';
      addTearDown(() => Plugin.directory = saved);

      final plugin = Plugin(name: 'demo');
      expect(plugin.fileName, 'demo.js');
      expect(plugin.filePath, '/plugins/demo.js');
      expect(plugin.isLoaded, isFalse);
      // 展示名为空 → 回落插件名
      expect(plugin.title, 'demo');
      plugin.displayName = '演示';
      expect(plugin.title, '演示');
    });

    test('禁用只是换个字段值：记录与文件都留着', () {
      final plugin = Plugin(name: 'demo');
      expect(plugin.enabled, isTrue);
      plugin.enabled = false;
      expect(plugin.enabled, isFalse);
      expect(plugin.name, 'demo');
    });
  });

  // ===================== index.json =====================

  group('PluginIndex 序列化', () {
    test('encode 是数组，一条一个插件，数组顺序即列表顺序', () {
      final text = PluginIndex.encode([
        Plugin(name: 'a'),
        Plugin(name: 'b', enabled: false),
      ]);
      final decoded = jsonDecode(text) as List;
      expect(decoded, hasLength(2));
      expect((decoded[0] as Map)['name'], 'a');
      expect((decoded[1] as Map)['enabled'], false);
      // 不再有 format / version / plugins 包装
      expect(text.contains('"format"'), isFalse);
      expect(text.contains('"plugins"'), isFalse);
    });

    test('decode 容错：非数组 → 空表；缺 name / 非对象的项被丢弃', () {
      expect(PluginIndex.decode(null), isEmpty);
      expect(PluginIndex.decode('{}'), isEmpty);
      expect(PluginIndex.decode({'plugins': []}), isEmpty);
      expect(
        PluginIndex.decode([
          {'name': 'a'},
          {'enabled': true},
          'x',
          {'name': 'b'},
        ]).map((p) => p.name),
        ['a', 'b'],
      );
    });

    test('decode 同名只保留先出现的一条（大小写不同不算同名）', () {
      final list = PluginIndex.decode([
        {'name': 'a', 'displayName': '第一'},
        {'name': 'a', 'displayName': '第二'},
        {'name': 'A', 'displayName': '大小写不同'},
      ]);
      expect(list.map((p) => p.name), ['a', 'A']);
      expect(list.first.displayName, '第一');
    });
  });

  group('PluginIndex 文件读写', () {
    test('缺失 / 损坏 / 旧对象形态 → 空表（交给目录扫描重建）', () async {
      final dir = await Directory.systemTemp.createTemp('wyw-index-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/$pluginIndexFileName');

      expect(await PluginIndex.load(dir), isEmpty);

      await file.writeAsString('not json');
      expect(await PluginIndex.load(dir), isEmpty);

      // 旧版本是 {"format":…,"plugins":{…}} 对象形态
      await file.writeAsString(
          '{"format":"wyw-plugin-index","version":4,"plugins":{}}');
      expect(await PluginIndex.load(dir), isEmpty);
    });

    test('read 区分「没有文件」与「读不懂」（决定要不要走出厂安装）', () async {
      final dir = await Directory.systemTemp.createTemp('wyw-index-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/$pluginIndexFileName');

      // 没有文件 = 这台设备上还没有记录 → 允许走出厂安装
      expect((await PluginIndex.read(dir)).state, PluginIndexState.absent);

      // 坏内容 = 读不懂 → 绝不能当成「没有插件」（否则会盖掉用户的东西）
      await file.writeAsString('not json');
      final corrupt = await PluginIndex.read(dir);
      expect(corrupt.state, PluginIndexState.corrupt);
      expect(corrupt.isCorrupt, isTrue);
      expect(corrupt.records, isEmpty);

      // 能读的数组 = ok
      await file.writeAsString('[{"name":"a"}]');
      final ok = await PluginIndex.read(dir);
      expect(ok.state, PluginIndexState.ok);
      expect(ok.records.map((p) => p.name), ['a']);

      // 空数组也是 ok（写得出来、只是没有记录），不是 absent
      await file.writeAsString('[]');
      expect((await PluginIndex.read(dir)).state, PluginIndexState.ok);
    });

    test('save 后可读回，覆盖前留 .bak，不残留 .tmp', () async {
      final dir = await Directory.systemTemp.createTemp('wyw-index-');
      addTearDown(() => dir.delete(recursive: true));

      await PluginIndex.save(dir, [Plugin(name: 'a')]);
      await PluginIndex.save(dir, [Plugin(name: 'a'), Plugin(name: 'b')]);

      final back = await PluginIndex.load(dir);
      expect(back.map((p) => p.name), ['a', 'b']);
      expect(await File('${dir.path}/index.json.bak').exists(), isTrue);
      expect(await File('${dir.path}/index.json.tmp').exists(), isFalse);
    });
  });

  // ===================== categories.json =====================

  group('CategoryIndex / CustomCategory', () {
    test('分类 JSON 是数组，带 id / label / icon', () {
      final text = CategoryIndex.encode(const [
        CustomCategory(id: 'anime', label: '番剧', iconKey: 'tv'),
        CustomCategory(id: 'podcast', label: '播客'),
      ]);
      final decoded = jsonDecode(text) as List;
      expect(decoded, hasLength(2));
      expect(decoded[0], {'id': 'anime', 'label': '番剧', 'icon': 'tv'});
      expect(decoded[1], {'id': 'podcast', 'label': '播客', 'icon': ''});
    });

    test('fromJson 容错：缺 id / label 返回 null，裸字符串靠 fallbackId', () {
      final parsed =
          CustomCategory.fromJson({'id': 'a', 'label': '甲', 'icon': 'tv'})!;
      expect(parsed.id, 'a');
      expect(parsed.label, '甲');
      expect(parsed.iconKey, 'tv');

      expect(CustomCategory.fromJson({'id': 'a'}), isNull);
      expect(CustomCategory.fromJson({'label': '甲'}), isNull);
      expect(CustomCategory.fromJson(42), isNull);

      final legacy = CustomCategory.fromJson('甲', fallbackId: 'a')!;
      expect(legacy.id, 'a');
      expect(legacy.label, '甲');
      expect(legacy.iconKey, '');

      // 未知 icon key 原样读入，由 CategoryIcons.resolve 回落默认图标
      expect(
        CustomCategory.fromJson({'id': 'a', 'label': '甲', 'icon': '没这个'})!
            .iconKey,
        '没这个',
      );
    });

    test('decode 丢弃无效项、同 id 只留一条', () {
      final list = CategoryIndex.decode([
        {'id': 'a', 'label': '甲'},
        {'id': 'a', 'label': '重复'},
        {'label': '缺 id'},
      ]);
      expect(list.map((c) => c.id), ['a']);
      expect(list.first.label, '甲');
    });

    test('缺失 / 损坏 → 空表；save 后可读回并留 .bak', () async {
      final dir = await Directory.systemTemp.createTemp('wyw-cat-');
      addTearDown(() => dir.delete(recursive: true));

      expect(await CategoryIndex.load(dir), isEmpty);
      await File('${dir.path}/categories.json').writeAsString('{');
      expect(await CategoryIndex.load(dir), isEmpty);

      await CategoryIndex.save(
          dir, const [CustomCategory(id: 'a', label: '甲')]);
      await CategoryIndex.save(
          dir, const [CustomCategory(id: 'a', label: '乙')]);
      expect((await CategoryIndex.load(dir)).single.label, '乙');
      expect(await File('${dir.path}/categories.json.bak').exists(), isTrue);
    });
  });

  // ===================== 分类图标调色板 =====================

  group('CategoryIcons', () {
    test('resolve：空串 / 未知 key 回落默认图标，已知 key 得到对应图标', () {
      expect(CategoryIcons.resolve(''), CategoryIcons.fallback);
      expect(CategoryIcons.resolve(null), CategoryIcons.fallback);
      expect(CategoryIcons.resolve('没这个 key'), CategoryIcons.fallback);
      expect(CategoryIcons.resolve('tv'), Icons.live_tv_outlined);
      expect(CategoryIcons.resolve(' tv '), Icons.live_tv_outlined);
    });

    test('contains 只认调色板里的键', () {
      expect(CategoryIcons.contains('tv'), isTrue);
      expect(CategoryIcons.contains(''), isFalse);
      expect(CategoryIcons.contains(null), isFalse);
      expect(CategoryIcons.contains('没这个'), isFalse);
    });

    test('键唯一，且默认图标不在候选里（它是「没选」的表示）', () {
      expect(CategoryIcons.palette, isNotEmpty);
      expect(CategoryIcons.palette.keys.toSet().length,
          CategoryIcons.palette.length);
      expect(CategoryIcons.palette.containsValue(CategoryIcons.fallback),
          isFalse);
    });
  });

  // ===================== 分类注册表 =====================

  group('PluginCategoryRegistry', () {
    test('内置分类优先，自定义同 id 顶不掉内置', () {
      final registry = PluginCategoryRegistry(custom: const [
        CustomCategory(id: 'video', label: '我的视频'),
      ]);
      expect(registry.byId('video')!.label, '视频');
      expect(registry.byId('video')!.isBuiltin, isTrue);
    });

    test('自定义分类顺序 = 传入顺序（categories.json 顺序），不再按名字排序', () {
      final registry = PluginCategoryRegistry(custom: const [
        CustomCategory(id: 'z', label: '甲'),
        CustomCategory(id: 'a', label: '乙'),
      ]);
      expect(registry.custom.map((c) => c.id), ['z', 'a']);
    });

    test('自定义分类图标来自调色板；没选图标的用默认', () {
      final registry = PluginCategoryRegistry(custom: const [
        CustomCategory(id: 'anime', label: '番剧', iconKey: 'tv'),
        CustomCategory(id: 'other', label: '其他'),
      ]);
      expect(registry.byId('anime')!.icon, Icons.live_tv_outlined);
      expect(registry.byId('other')!.icon, CategoryIcons.fallback);
    });

    test('resolve 把未知 id 就地登记为隐式自定义分类（不退化成「其他」）', () {
      final registry = PluginCategoryRegistry();
      final resolved = registry.resolve('Podcast');
      expect(resolved.id, 'podcast');
      expect(resolved.label, 'Podcast');
      expect(resolved.isBuiltin, isFalse);
      // 大小写不敏感：再来一次拿的是同一个实例
      expect(identical(registry.resolve('podcast'), resolved), isTrue);
      expect(registry.resolve('   ').id, PluginCategory.unknownId);
      expect(registry.resolve(null).id, PluginCategory.unknownId);
    });
  });

  // ===================== 控制器：顺序 =====================

  group('PluginController.movePlugin', () {
    test('按名字挪到锚点之前；锚点为 null 表示挪到末尾', () {
      final controller = PluginController();
      mobx.runInAction(() {
        controller.plugins.addAll([
          Plugin(name: 'a'),
          Plugin(name: 'b'),
          Plugin(name: 'c'),
        ]);
      });

      controller.movePlugin(name: 'c', beforeName: 'a');
      expect(controller.plugins.map((p) => p.name), ['c', 'a', 'b']);

      controller.movePlugin(name: 'c', beforeName: 'b');
      expect(controller.plugins.map((p) => p.name), ['a', 'c', 'b']);

      controller.movePlugin(name: 'a', beforeName: null);
      expect(controller.plugins.map((p) => p.name), ['c', 'b', 'a']);

      // 名字不存在 → 原样不动
      controller.movePlugin(name: '不存在', beforeName: 'c');
      expect(controller.plugins.map((p) => p.name), ['c', 'b', 'a']);
    });

    test('禁用插件留在列表里（顺序与启用状态无关）', () {
      final controller = PluginController();
      mobx.runInAction(() {
        controller.plugins.addAll([
          Plugin(name: 'a'),
          Plugin(name: 'b', enabled: false),
          Plugin(name: 'c'),
        ]);
      });
      controller.movePlugin(name: 'a', beforeName: 'c');
      expect(controller.plugins.map((p) => p.name), ['b', 'a', 'c']);
      expect(controller.plugins.first.enabled, isFalse);
    });
  });

  // ===================== 集合写入的唯一入口 =====================

  group('PluginController.updatePlugin', () {
    test('不在列表里 → 追加到末尾；已在列表里 → 原地替换，位置不变', () {
      final controller = PluginController();
      controller.updatePlugin(Plugin(name: 'a'));
      controller.updatePlugin(Plugin(name: 'b'));
      expect(controller.plugins.map((p) => p.name), ['a', 'b']);

      final updated = Plugin(name: 'a', displayName: '甲');
      controller.updatePlugin(updated);

      expect(controller.plugins.map((p) => p.name), ['a', 'b'], reason: '不重排');
      // 列表里持有的就是传进去的那一个实例（全应用只有这一份）
      expect(identical(controller.plugins.first, updated), isTrue);
    });

    test('传回同一个实例也会触发通知 —— 这是 replaceRange 而不是 [] 的原因', () {
      final controller = PluginController();
      final plugin = Plugin(name: 'a');
      controller.updatePlugin(plugin);

      var runs = 0;
      final dispose = mobx.autorun((_) {
        controller.plugins.length;
        runs++;
      });
      expect(runs, 1, reason: 'autorun 先跑一次');

      plugin.enabled = false; // 就地改字段：MobX 看不见
      controller.updatePlugin(plugin); // 同一个实例

      expect(runs, 2, reason: '必须靠 replaceRange 触发；[]= 会因相等守卫静默跳过');
      dispose();
    });

    test('按名字逐字符匹配，不做大小写折叠（存量记录可能有大写名字）', () {
      final controller = PluginController();
      controller.updatePlugin(Plugin(name: 'hanime'));
      controller.updatePlugin(Plugin(name: 'Hanime'));

      controller.updatePlugin(Plugin(name: 'Hanime', displayName: '大写那条'));

      expect(controller.plugins.map((p) => p.name), ['hanime', 'Hanime']);
      expect(controller.plugins.last.displayName, '大写那条');
      expect(controller.plugins.first.displayName, isEmpty,
          reason: '折叠匹配会误改小写那条');
    });
  });

  // ===================== 控制器：分类 =====================

  group('PluginController 分类', () {
    test('填了 categoryId 就查表；留空且无实例可推断 → 「其他」', () {
      final controller = PluginController();
      final typed = Plugin(name: 'a')..categoryId = 'manga';
      final blank = Plugin(name: 'b');
      mobx.runInAction(() => controller.plugins.addAll([typed, blank]));

      expect(controller.categoryOf(typed).id, 'manga');
      expect(controller.categoryOf(blank).id, PluginCategory.unknownId);
    });

    test('新建自定义分类后，插件的 categoryId 能解析出标签与图标', () async {
      final controller = PluginController();
      final added = await controller.addCustomCategory(
        id: 'anime',
        label: '番剧',
        iconKey: 'tv',
      );
      expect(added.isSuccess, isTrue);

      final plugin = Plugin(name: 'a')..categoryId = 'anime';
      mobx.runInAction(() => controller.plugins.add(plugin));
      expect(controller.categoryOf(plugin).label, '番剧');
      expect(controller.categoryOf(plugin).icon, Icons.live_tv_outlined);
      expect(controller.customCategories.single.id, 'anime');
    });

    test('删分类会清掉指向它的插件 categoryId（别的插件不动）', () async {
      final controller = PluginController();
      await controller.addCustomCategory(id: 'anime', label: '番剧');
      final hit = Plugin(name: 'a')..categoryId = 'anime';
      final other = Plugin(name: 'b')..categoryId = 'manga';
      mobx.runInAction(() => controller.plugins.addAll([hit, other]));

      final result = await controller.removeCustomCategory('anime');
      expect(result.isSuccess, isTrue);
      expect(hit.categoryId, '');
      expect(other.categoryId, 'manga');
      expect(controller.customCategories, isEmpty);
      expect(controller.categoryOf(hit).id, PluginCategory.unknownId);
    });

    test('改名 + 换图标；未知图标 key 归一成空串', () async {
      final controller = PluginController();
      await controller.addCustomCategory(id: 'a', label: '甲');
      final result = await controller.updateCustomCategory(
        id: 'a',
        label: '乙',
        iconKey: '没这个 key',
      );
      expect(result.isSuccess, isTrue);
      expect(controller.customCategories.single.label, '乙');
      expect(controller.customCategories.single.iconKey, '');
    });

    test('拒绝：空 id、空名、与内置分类 id 冲突、重名、改不存在的分类', () async {
      final controller = PluginController();
      expect((await controller.addCustomCategory(id: ' ', label: '甲')).isFailure,
          isTrue);
      expect((await controller.addCustomCategory(id: 'a', label: ' ')).isFailure,
          isTrue);
      expect(
          (await controller.addCustomCategory(id: 'video', label: '甲')).isFailure,
          isTrue);

      await controller.addCustomCategory(id: 'a', label: '甲');
      // id 大小写不敏感：'A' 与 'a' 是同一个分类
      expect((await controller.addCustomCategory(id: 'A', label: '乙')).isFailure,
          isTrue);
      expect(
          (await controller.updateCustomCategory(
                  id: '不存在', label: '乙', iconKey: ''))
              .isFailure,
          isTrue);
      expect((await controller.removeCustomCategory('不存在')).isFailure, isTrue);
    });
  });

  // ===================== 对账：索引 × 磁盘 =====================

  group('PluginReconciliation.of', () {
    test('索引给顺序与用户字段：记录一条都不丢', () {
      final records = [
        Plugin(name: 'a', displayName: '甲', categoryId: 'manga'),
        Plugin(name: 'b', description: '乙'),
        Plugin(name: 'gone'),
      ];
      final result = PluginReconciliation.of(records, {'a', 'b', 'new'});

      // 记录全部保留（含文件没了的 gone）—— 顺序只来自索引
      expect(result.records.map((p) => p.name), ['a', 'b', 'gone']);
      // 用户填的字段原样保留（这正是「重启后不能归零」的那一层）
      expect(result.records[0].displayName, '甲');
      expect(result.records[0].categoryId, 'manga');
      expect(result.records[1].description, '乙');
    });

    test('记录的文件没了 → 进 missingFiles，不丢记录', () {
      final records = [
        Plugin(name: 'a'),
        Plugin(name: 'b'),
        Plugin(name: 'gone'),
      ];
      final result = PluginReconciliation.of(records, {'a', 'b'});

      expect(result.missingFiles, {'gone'});
      expect(result.orphanFiles, isEmpty);
      expect(result.hasMissingFiles, isTrue);
      // 记录还在（顺序与用户字段都保得住），由调用方标 fileMissing
      expect(result.records.map((p) => p.name), ['a', 'b', 'gone']);
    });

    test('磁盘上有、索引里没有的文件 → 进 orphanFiles（不删、不追加记录）', () {
      final records = [Plugin(name: 'a'), Plugin(name: 'b')];
      final result = PluginReconciliation.of(records, {'a', 'b', 'new'});

      expect(result.orphanFiles, ['new']);
      expect(result.missingFiles, isEmpty);
      expect(result.hasOrphanFiles, isTrue);
      // 没有被自动追加成「禁用记录」——外部代码不自动进列表
      expect(result.records.map((p) => p.name), ['a', 'b']);
    });

    test('孤儿清单已排序；磁盘集合的顺序不影响结果', () {
      final records = [Plugin(name: 'a'), Plugin(name: 'c')];
      final first = PluginReconciliation.of(records, {'z', 'a', 'm', 'c'});
      final second = PluginReconciliation.of(records, {'c', 'm', 'a', 'z'});
      expect(first.orphanFiles, ['m', 'z']);
      expect(second.orphanFiles, ['m', 'z']);
      expect(first.records.map((p) => p.name), ['a', 'c']);
      expect(second.records.map((p) => p.name), ['a', 'c']);
    });

    test('索引空 → 全部文件都是孤儿，记录为空', () {
      final result = PluginReconciliation.of(const [], {'a', 'b'});
      expect(result.records, isEmpty);
      expect(result.orphanFiles, ['a', 'b']);
      expect(result.missingFiles, isEmpty);
    });
  });

  // ===================== 出厂配置 =====================

  group('出厂配置 assets/plugin/index.json', () {
    List<Plugin> readSeed() => PluginIndex.decodeText(
          File('assets/plugin/index.json').readAsStringSync(),
        );

    test('与 assets/plugin 下的 .js 一一对应（不漏、不多、不重名）', () {
      final seed = readSeed();
      final jsNames = Directory('assets/plugin')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.endsWith('.js'))
          .map((n) => n.substring(0, n.length - 3))
          .toSet();

      expect(seed, isNotEmpty);
      expect(seed.map((p) => p.name).toSet().length, seed.length);
      expect(seed.map((p) => p.name).toSet(), jsNames);
    });

    test('全部禁用、每条都有分类与简介，分类必须是内置分类', () {
      final seed = readSeed();
      for (final plugin in seed) {
        expect(plugin.enabled, isFalse, reason: '${plugin.name} 不该初始启用');
        expect(plugin.categoryId, isNotEmpty, reason: '${plugin.name} 缺分类');
        expect(plugin.description, isNotEmpty, reason: '${plugin.name} 缺简介');
        expect(PluginCategory.builtinById(plugin.categoryId), isNotNull,
            reason: '${plugin.name} 的分类 ${plugin.categoryId} 不是内置分类');
      }
    });

    test('用它写入 index.json 能被读回（与运行时同格式）', () async {
      final dir = await Directory.systemTemp.createTemp('wyw-seed-');
      addTearDown(() => dir.delete(recursive: true));
      final seed = readSeed();

      await PluginIndex.save(dir, seed);
      final back = await PluginIndex.load(dir);
      expect(back.length, seed.length);
      expect(back.first.name, seed.first.name);
      expect(back.first.displayName, seed.first.displayName);
      expect(back.every((p) => !p.enabled), isTrue);
    });
  });

  group('插件名称显示方式（全局设置）', () {
    test('默认用展示名，且设置项属于界面组', () {
      expect(SettingsKeys.pluginNameDisplay.defaultValue,
          PluginNameDisplayMode.display);
      expect(SettingsKeys.pluginNameDisplay.group, SettingGroup.interface);
    });

    test('两种模式取值互不相同且含义自洽', () {
      expect(PluginNameDisplayMode.display, isNot(PluginNameDisplayMode.identity));
      expect(PluginNameDisplayMode.display, 'display');
      expect(PluginNameDisplayMode.identity, 'name');
    });
  });

  // ===================== Plugin 个体能力：代码文件 / 校验 / 修改 =====================
  //
  // 这一组锁定「插件自己的事归插件」：文件的读 / 写 / 改名 / 导出、源码校验、
  // 安装与更新的**事务顺序与回滚**。宿主（PluginController）不在这里 —— 它只管集合。

  group('Plugin 代码文件能力', () {
    late Directory dir;
    late String previousDirectory;

    /// 合法源码：顶层一处类声明，且类名 = 插件名（命名链第 3 环）
    String sourceFor(String name) => 'class $name extends PluginSource {\n}\n';

    setUp(() {
      previousDirectory = Plugin.directory;
      dir = Directory.systemTemp.createTempSync('wyw-plugin-file-');
      Plugin.directory = dir.path;
    });

    tearDown(() {
      Plugin.directory = previousDirectory;
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    // ----- 路径派生 -----

    test('nameFromFilePath：裸文件名与完整路径都反推得出，去掉 .js', () {
      expect(Plugin.nameFromFilePath('demo.js'), 'demo');
      expect(Plugin.nameFromFilePath('/plugins/demo.js'), 'demo');
      expect(Plugin.nameFromFilePath('plugins/abc.js'), 'abc');
      // 没有 .js 后缀时原样返回（容错，不抛）
      expect(Plugin.nameFromFilePath('demo'), 'demo');
    });

    // ----- 文件读写 -----

    test('exists / writeContent / getContent 往返', () async {
      final plugin = Plugin(name: 'demo');
      expect(await plugin.exists(), isFalse);

      await plugin.writeSource(sourceFor('demo'));
      expect(await plugin.exists(), isTrue);
      expect(await plugin.readSource(), sourceFor('demo'));
      expect(File(plugin.filePath).existsSync(), isTrue);
    });

    test('exportEntry：读盘导出；文件不在时返回 null', () async {
      final plugin = Plugin(name: 'demo');
      expect(await plugin.exportEntry(), isNull);

      await plugin.writeSource(sourceFor('demo'));
      final entry = await plugin.exportEntry();
      expect(entry, isNotNull);
      expect(entry!.name, 'demo');
      expect(entry.content, sourceFor('demo'));
    });

    test('alignFileName：把磁盘拼写改成索引拼写；已一致时不动文件', () async {
      // 索引里的拼写是权威（这里是大写 H），磁盘上却写了小写
      final plugin = Plugin(name: 'Hanime');
      final onDisk = File('${dir.path}${Platform.pathSeparator}hanime.js');
      await onDisk.writeAsString(sourceFor('Hanime'));

      expect(await plugin.alignFileName('hanime.js'), isTrue);
      expect(File(plugin.filePath).existsSync(), isTrue);

      // 已经一致 → 不再改名（返回 false 表示没动过）
      expect(await plugin.alignFileName(plugin.fileName), isFalse);
    });

    // ----- 校验是唯一入口 -----

    test('checkSource：判定与命名链一致（类名 = 插件名）', () {
      final plugin = Plugin(name: 'demo');
      expect(plugin.checkSource(sourceFor('demo')).ok, isTrue);
      expect(plugin.checkSource(sourceFor('other')).ok, isFalse);
      expect(plugin.checkSource('   \n').ok, isFalse);
    });

    // ----- install：校验 → 拒绝覆盖 → 写盘 → 注册，失败回滚 -----

    test('install：成功则落盘 + 注册', () async {
      final plugin = Plugin(name: 'demo');
      await plugin.install(sourceFor('demo'), _FakeEngine());

      expect(await plugin.exists(), isTrue);
      expect(await plugin.readSource(), sourceFor('demo'));
      expect(plugin.isLoaded, isTrue);
    });

    test('install：源码不合法时抛 PluginSourceError，且不写文件', () async {
      final plugin = Plugin(name: 'demo');
      await expectLater(
        plugin.install(sourceFor('other'), _FakeEngine()),
        throwsA(isA<PluginSourceError>()),
      );
      expect(await plugin.exists(), isFalse);
    });

    test('install：文件已存在时拒绝覆盖（不改动旧内容）', () async {
      final plugin = Plugin(name: 'demo');
      await plugin.writeSource('旧的代码');

      await expectLater(
        plugin.install(sourceFor('demo'), _FakeEngine()),
        throwsA(isA<PluginSourceError>()),
      );
      expect(await plugin.readSource(), '旧的代码');
    });

    test('install：注册失败时删掉刚写的文件，且不留半成品实例', () async {
      final plugin = Plugin(name: 'demo');
      await expectLater(
        plugin.install(sourceFor('demo'), _FakeEngine(failOnRegister: true)),
        throwsA(isA<_RegisterFailure>()),
      );
      expect(await plugin.exists(), isFalse, reason: '回滚应把刚写出的文件删掉');
      expect(plugin.entity, isNull);
      expect(plugin.isLoaded, isFalse);
    });

    // ----- updateSource：校验 → 写盘 → 已启用才热重载 -----

    test('updateSource：启用中则写盘 + 热重载（实例就绪）', () async {
      final plugin = Plugin(name: 'demo');
      await plugin.install(sourceFor('demo'), _FakeEngine());

      const next = 'class demo extends PluginSource {\n  x = 1\n}\n';
      await plugin.updateSource(next, _FakeEngine());

      expect(await plugin.readSource(), next);
      expect(plugin.isLoaded, isTrue);
    });

    test('updateSource：禁用中只改文件、不注册（引擎里不出现实例）', () async {
      final plugin = Plugin(name: 'demo', enabled: false);
      await plugin.updateSource(sourceFor('demo'), _FakeEngine());

      expect(await plugin.exists(), isTrue);
      expect(plugin.entity, isNull);
      expect(plugin.isLoaded, isFalse);
    });

    test('updateSource：源码不合法时不写盘（旧内容保持）', () async {
      final plugin = Plugin(name: 'demo', enabled: false);
      await plugin.writeSource(sourceFor('demo'));

      await expectLater(
        plugin.updateSource(sourceFor('other'), _FakeEngine()),
        throwsA(isA<PluginSourceError>()),
      );
      expect(await plugin.readSource(), sourceFor('demo'));
    });

    // ----- repairMissing：先把记录立起来、再补源码（详情页「新增 → 写代码」那条路）-----

    test('repairMissing：启用中则写盘 + 注册，并清掉 fileMissing', () async {
      // addPlugin 建出来的就是这种状态：有记录、没文件
      final plugin = Plugin(name: 'demo')..fileMissing = true;
      expect(await plugin.exists(), isFalse);

      await plugin.repairMissing(sourceFor('demo'), _FakeEngine());

      expect(await plugin.readSource(), sourceFor('demo'));
      expect(plugin.fileMissing, isFalse);
      expect(plugin.isLoaded, isTrue);
    });

    test('repairMissing：禁用中只写文件、不注册，同样清掉 fileMissing', () async {
      final plugin = Plugin(name: 'demo', enabled: false)..fileMissing = true;

      await plugin.repairMissing(sourceFor('demo'), _FakeEngine());

      expect(await plugin.exists(), isTrue);
      expect(plugin.fileMissing, isFalse);
      expect(plugin.isLoaded, isFalse);
    });

    test('repairMissing：源码不合法时不写盘，fileMissing 保持', () async {
      final plugin = Plugin(name: 'demo')..fileMissing = true;

      await expectLater(
        plugin.repairMissing(sourceFor('other'), _FakeEngine()),
        throwsA(isA<PluginSourceError>()),
      );
      expect(await plugin.exists(), isFalse);
      expect(plugin.fileMissing, isTrue);
    });

    // ----- 注册失败不留假就绪 -----

    test('register：失败时 entity 回到 null，不出现「isLoaded 为真但没实例」', () async {
      final plugin = Plugin(name: 'demo');
      await plugin.writeSource(sourceFor('demo'));

      await expectLater(
        plugin.register(_FakeEngine(failOnRegister: true)),
        throwsA(isA<_RegisterFailure>()),
      );
      expect(plugin.entity, isNull);
      expect(plugin.isLoaded, isFalse);
    });
  });
}

/// 注册路径的测试替身：真实引擎（flutter_qjs）在单测里跑不起来。
///
/// 只覆盖 [Plugin.register] 用到的 `evaluate`，让「注册成功 / 注册失败」两种结果
/// 都能构造出来 —— 回滚与「不留半成品」这两条不变量只在失败路径上体现。
class _FakeEngine extends BaseJsEngine {
  _FakeEngine({this.failOnRegister = false});

  final bool failOnRegister;

  @override
  Object? evaluate(String code, {String? name}) {
    if (failOnRegister) throw const _RegisterFailure();
    return null;
  }
}

/// 注册失败的替身异常（用具体类型断言，避免 `isA<Exception>()` 过宽）
class _RegisterFailure implements Exception {
  const _RegisterFailure();

  @override
  String toString() => '注册失败（测试替身）';
}
