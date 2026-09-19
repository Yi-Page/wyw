import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// 硬编码颜色防回归 guard。
///
/// 规范来源：docs/ui-routing-design-spec.md 第二部分 B1 与第三部分 8。
/// 规则：UI 层一律取自 Material 3 `ColorScheme`；仅以下三类允许字面量颜色，
/// 且必须集中在白名单文件里：
///   1. 媒体铬层固定集（叠加在任意视频帧/图片上的控件，对比度是功能需求）；
///   2. 用户可选内容色 palette（主题种子色列表、阅读画布等"数据"）；
///   3. 主题构建层（ColorScheme 的变换本身）与 JS 插件自定义色的透传层。
///
/// 白名单之外出现 `Colors.*` / `Color(0x…)` / `Color.fromARGB/RGBO` 即失败。
/// `Colors.transparent` 不算颜色语义，放行。
void main() {
  test('lib/ 内不得出现主题体系之外的硬编码颜色', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: '请在项目根目录运行 flutter test');

    const whitelist = <String, String>{
      // 媒体铬层固定集定义处（唯一允许出现白/黑字面量的 UI 文件）。
      'lib/bean/styles/media_chrome_colors.dart':
          '媒体铬层最小固定集定义处',
      // dev 工具终端配色（终端语义豁免，但必须具名）。
      'lib/bean/styles/js_console_colors.dart': 'JS 控制台配色定义处',
      // 主题种子色列表：用户可选"数据"，不是 UI。
      'lib/bean/settings/color_type.dart': '主题种子色 palette（用户可选数据）',
      // 插件分类标识色（categorical palette，挂在 PluginType 枚举上的数据）。
      'lib/plugins/plugin_type.dart': '插件分类标识色（categorical palette 数据）',
      // ColorScheme 的构建/变换本身（OLED 纯黑增强等）。
      'lib/utils/theme.dart': '主题构建层',
      // 阅读画布 palette：novelBackground 设置的支撑数据。
      'lib/pages/novel_reader/models/novel_reader_settings.dart':
          '阅读画布 palette（用户可选数据）',
      // JS 插件自定义颜色的解析/回退层（插件传什么色是插件的事）。
      'lib/js/': 'JS 插件自定义色透传/回退层',
    };

    bool isWhitelisted(String path) {
      final p = path.replaceAll('\\', '/');
      return whitelist.entries.any((e) => p.startsWith(e.key));
    }

    // 行注释整体剥掉（含 /// 文档示例），避免样例代码误报。
    String stripComment(String line) {
      final idx = line.indexOf('//');
      return idx >= 0 ? line.substring(0, idx) : line;
    }

    final colorPattern = RegExp(
      // \b 避免 MediaChromeColors.foreground 这类 token 名被误判
      r'\bColors\.[a-zA-Z]|\bColor\(0x|\bColor\.fromARGB|\bColor\.fromRGBO',
    );

    final violations = <String>[];
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('.g.dart')) continue; // 生成代码不扫
      if (isWhitelisted(entity.path)) continue;

      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        var code = stripComment(lines[i]);
        // transparent 不是颜色语义（系统栏/透明底），放行。
        code = code.replaceAll('Colors.transparent', '');
        if (colorPattern.hasMatch(code)) {
          violations.add('${entity.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }

    expect(violations, isEmpty, reason: '''
发现主题体系之外的硬编码颜色（规范见 docs/ui-routing-design-spec.md 第 8 节）：
内容层请改用 Theme.of(context).colorScheme；媒体铬层请用
MediaChromeColors；用户可选内容色请收进对应 palette 文件。
${violations.join('\n')}''');
  });
}
