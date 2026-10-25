import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// 「禁止双入口」防回归 guard（规范：`docs/player-split-panel-plan.md` §6-8、P6 验收）。
///
/// v1 最致命的失误：分屏面板只是**第 5 个并行入口**——旧菜单/按钮一个没删，
/// 同一功能出现两份实现（定时关闭与投屏各两份、页签条手抄）。
///
/// 本测试对**已退场的标识符**做静态扫描（先剥掉行注释），谁把它们加回来就会红，
/// 因此"功能已收编进面板"不再只是口头声称。
void main() {
  test('lib/pages/player 内不得出现已退场的旧入口', () {
    final dir = Directory('lib/pages/player');
    expect(dir.existsSync(), isTrue, reason: '请在项目根目录运行 flutter test');

    // 已退场标识符 → 现在由谁承载（写清楚，方便后人判断该不该加回来）。
    const retired = <String, String>{
      '_buildMoreMenu': '顶栏「更多」菜单 → 已收编进面板各 tab',
      '_wideBottomControls': '底栏宽屏 MenuAnchor 簇（超分/倍速/比例）→ 画面/播放 tab',
      '_buildTimedShutdownMenu': '定时关闭子菜单 → 播放 tab（含自定义）',
      '_buildDownloadButton': '顶栏下载按钮 → 选集 tab 的逐集下载',
      '_downloadCurrentEpisode': '「播放即下载」动作 → 选集 tab 的逐集下载',
      'showSetSpeedSheet': '无调用者的倍速弹层死代码 → 播放 tab',
      'PlayerPanelHoldMenuAnchor': 'MenuAnchor 的 hold 封装（菜单退场后无引用）',
      'showVideoDetailsSheet': '视频详情弹层 → 画面 tab 的「视频信息」二级页',
      'showDanmakuSettingsSheet': '播放器弹幕设置弹层 → 弹幕 tab',
      'showVideoFilterSheet': '画面调节弹层 → 画面 tab 的「画面调节」二级页',
      'toggleEpisodePanel': '顶栏选集按钮 / 旧抽屉入口 → 选集 tab',
    };

    // 行注释整体剥掉：允许在注释里说明"这里原本是 X"。
    String stripComment(String line) {
      final idx = line.indexOf('//');
      return idx >= 0 ? line.substring(0, idx) : line;
    }

    final violations = <String>[];
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('.g.dart')) continue; // 生成代码不扫
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = stripComment(lines[i]);
        for (final entry in retired.entries) {
          if (code.contains(entry.key)) {
            violations.add(
              '${entity.path}:${i + 1}: ${entry.key} —— ${entry.value}',
            );
          }
        }
      }
    }

    expect(violations, isEmpty, reason: '''
发现已退场的旧入口又出现了（禁止双入口，见 docs/player-split-panel-plan.md §6-8）：
同一功能只允许面板里那一份实现；v1 正是因为旧入口没删而整体返工。
若确有正当理由要恢复某个入口，请先改计划文档的契约，再把它从本清单移除。
${violations.join('\n')}''');
  });
}
