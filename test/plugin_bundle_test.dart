import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyw/plugins/plugin_bundle.dart';
import 'package:wyw/plugins/plugin_operation.dart';

/// 插件导入 / 导出包格式测试（P6）。
///
/// 包解析被刻意抽成纯函数，因此这些用例不需要文件系统与 JS 引擎。
void main() {
  group('encodePluginBundle', () {
    test('输出完整包结构', () {
      final json = encodePluginBundle(const [
        PluginBundleEntry(name: 'demo', content: 'class demo {}\n'),
      ]);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['format'], pluginBundleFormat);
      expect(decoded['version'], pluginBundleVersion);
      final plugins = decoded['plugins'] as List;
      expect(plugins, hasLength(1));
      expect((plugins.first as Map)['name'], 'demo');
      expect((plugins.first as Map)['content'], 'class demo {}\n');
    });

    test('空列表也能编码', () {
      final decoded =
          jsonDecode(encodePluginBundle(const [])) as Map<String, dynamic>;
      expect(decoded['plugins'], isEmpty);
    });
  });

  group('parsePluginBundle 三种形态', () {
    test('完整包', () {
      final result = parsePluginBundle(jsonEncode({
        'format': pluginBundleFormat,
        'version': 1,
        'plugins': [
          {'name': 'a', 'content': 'class a {}'},
          {'name': 'b', 'content': 'class b {}'},
        ],
      }));
      expect(result.isFatal, isFalse);
      expect(result.entries.map((e) => e.name), ['a', 'b']);
      expect(result.entries.first.content, 'class a {}');
      expect(result.failed, isEmpty);
    });

    test('裸数组', () {
      final result = parsePluginBundle(
        jsonEncode([
          {'name': 'a', 'content': 'class a {}'},
        ]),
      );
      expect(result.entries.map((e) => e.name), ['a']);
    });

    test('单插件对象', () {
      final result = parsePluginBundle(
        jsonEncode({'name': 'solo', 'content': 'class solo {}'}),
      );
      expect(result.entries.map((e) => e.name), ['solo']);
    });

    test('编码后解析可往返', () {
      const entries = [
        PluginBundleEntry(name: 'a', content: 'class a {}\n'),
        PluginBundleEntry(name: 'b', content: 'class b {}\n'),
      ];
      final result = parsePluginBundle(encodePluginBundle(entries));
      expect(result.entries.map((e) => e.name), ['a', 'b']);
      expect(result.entries[1].content, 'class b {}\n');
    });
  });

  group('parsePluginBundle 容错', () {
    test('非法 JSON 走整包错误', () {
      final result = parsePluginBundle('{not json');
      expect(result.isFatal, isTrue);
      expect(result.error, '不是合法的 JSON');
      expect(result.entries, isEmpty);
    });

    test('结构无法识别走整包错误', () {
      expect(parsePluginBundle('123').isFatal, isTrue);
      expect(parsePluginBundle('"text"').isFatal, isTrue);
      expect(parsePluginBundle('{"foo": 1}').isFatal, isTrue);
      expect(parsePluginBundle('{}').isFatal, isTrue);
    });

    test('空插件数组是合法的空结果（不是错误）', () {
      final result = parsePluginBundle(jsonEncode({'plugins': []}));
      expect(result.isFatal, isFalse);
      expect(result.entries, isEmpty);
      expect(result.failed, isEmpty);
    });

    test('逐条缺字段只影响该条', () {
      final result = parsePluginBundle(jsonEncode({
        'plugins': [
          {'name': 'ok', 'content': 'class ok {}'},
          {'content': '没有 name'},
          {'name': 'noContent', 'content': ''},
          'not a map',
          {'name': '  ', 'content': 'x'},
        ],
      }));
      expect(result.isFatal, isFalse);
      expect(result.entries.map((e) => e.name), ['ok']);
      expect(result.failed.keys, containsAll(['#2', 'noContent', '#4', '#5']));
      expect(result.failed['noContent'], '缺少 content');
      expect(result.failed['#4'], '条目不是对象');
    });

    test('name 两侧空白被裁剪', () {
      final result = parsePluginBundle(jsonEncode({
        'plugins': [
          {'name': '  spaced  ', 'content': 'class spaced {}'},
        ],
      }));
      expect(result.entries.single.name, 'spaced');
    });

    test('content 不做裁剪（保留源码原样，含首尾空白）', () {
      const content = '\n// description: x\nclass x {}\n';
      final result = parsePluginBundle(jsonEncode({
        'plugins': [
          {'name': 'x', 'content': content},
        ],
      }));
      expect(result.entries.single.content, content);
    });

    test('非字符串 name / content 通过 toString 兜底', () {
      final result = parsePluginBundle(jsonEncode({
        'plugins': [
          {'name': 123, 'content': 456},
        ],
      }));
      expect(result.entries.single.name, '123');
      expect(result.entries.single.content, '456');
    });
  });

  group('PluginImportReport', () {
    test('summary 组合成功与失败数', () {
      expect(const PluginImportReport().summary, '没有可导入的插件');
      expect(const PluginImportReport(imported: ['a']).summary, '成功 1 个');
      expect(
        const PluginImportReport(imported: ['a'], failed: {'b': 'x'}).summary,
        '成功 1 个，失败 1 个',
      );
      expect(const PluginImportReport(failed: {'b': 'x'}).summary, '失败 1 个');
    });

    test('hasFailure / isEmpty', () {
      expect(const PluginImportReport().isEmpty, isTrue);
      expect(const PluginImportReport().hasFailure, isFalse);
      expect(const PluginImportReport(imported: ['a']).isEmpty, isFalse);
      expect(const PluginImportReport(failed: {'a': 'x'}).hasFailure, isTrue);
    });
  });

  group('PluginOpResult / PluginCreateResult', () {
    test('成功与失败的判定', () {
      const ok = PluginOpResult.success();
      const bad = PluginOpResult.failure('坏了');
      expect(ok.isSuccess, isTrue);
      expect(ok.isFailure, isFalse);
      expect(bad.isFailure, isTrue);
      expect(bad.error, '坏了');
    });

    test('创建结果携带插件实例', () {
      const failure = PluginCreateResult.failure('名称非法');
      expect(failure.isFailure, isTrue);
      expect(failure.plugin, isNull);
      expect(failure.error, '名称非法');
    });
  });
}
