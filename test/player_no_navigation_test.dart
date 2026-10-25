import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// 「播放页零跳转」硬原则的防回归 guard。
///
/// 规范来源：`docs/player-split-panel-plan.md` §1.4-1 —— 播放页内一切可调项必须
/// 在本页（分屏面板 / 播放器控件）完成，不得出现 `pushNamed` / `Navigator.push`
/// / `Modular.to` 这类**跳转他页**的调用（含"去设置页""管理预设"类入口）。
///
/// 只禁「推入新页」，不禁 `pop`（关闭弹层是合法且必需的）。
/// 已知历史违规：播放器「画面调节」弹层的「管理预设」曾跳去
/// `/settings/player/filters/`（该弹层已随面板退场，入口改为面板内嵌 CRUD）。
void main() {
  test('lib/pages/player 内不得出现跳转他页的调用', () {
    final playerDir = Directory('lib/pages/player');
    expect(playerDir.existsSync(), isTrue, reason: '请在项目根目录运行 flutter test');

    // 行注释整体剥掉（含 /// 文档），避免注释里的示例误报。
    String stripComment(String line) {
      final idx = line.indexOf('//');
      return idx >= 0 ? line.substring(0, idx) : line;
    }

    final navPattern = RegExp(
      r'pushNamed|Navigator\.push|Modular\.to\(',
    );

    final violations = <String>[];
    for (final entity in playerDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('.g.dart')) continue; // 生成代码不扫

      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = stripComment(lines[i]);
        if (navPattern.hasMatch(code)) {
          violations.add('${entity.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }

    expect(violations, isEmpty, reason: '''
播放页内不允许跳转他页（规范见 docs/player-split-panel-plan.md §1.4-1）：
能调的东西必须在播放页内完成（分屏面板 / 播放器控件），不要跳去设置页。
${violations.join('\n')}''');
  });
}
