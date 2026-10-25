import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:wyw/bean/settings/settings_list.dart';
import 'package:wyw/bean/widget/select_field.dart';
import 'package:wyw/pages/player/controller/player_aspect_ratio.dart';
import 'package:wyw/pages/player/controller/player_panel_controller.dart';
import 'package:wyw/pages/player/controller/player_super_resolution.dart';
import 'package:wyw/pages/player/controller/video_filter_controller.dart';
import 'package:wyw/pages/player/split_tabs/split_tab_host.dart';

/// 画面 tab：画面调节（二级页内嵌预设 CRUD）+ 超分辨率 + 视频比例 + 视频信息。
///
/// 行一律用既有设置组件（`SettingsList` / `SettingsSection` / `SelectTile` /
/// `SettingsTile`），不自造行样式也不硬编码颜色：面板行与设置页同源。
///
/// 状态全部读控制器的 observable（[Observer]），本页不缓存任何设置值：
///   - 超分辨率 → `playerController.playback.superResolutionMode`
///     （改由 `host.handleSuperResolutionChange`，与底栏入口同一动作）；
///   - 视频比例 → `playerController.panel.aspectRatioMode`（直接赋值，与
///     底栏比例菜单同一写法）；
///   - 画面调节 → `VideoFilterController` 活动预设（二级页里增删改）。
class DisplayTab extends StatelessWidget {
  const DisplayTab({super.key, required this.host});

  final SplitTabHost host;

  @override
  Widget build(BuildContext context) {
    final playerController = host.playerController;
    return Observer(builder: (context) {
      final activePreset = VideoFilterController.instance.activePreset;
      final superResolution = playerController.playback.superResolutionMode;
      return SettingsList(
        sections: [
          SettingsSection(
            title: const Text('画面'),
            tiles: [
              SettingsTile(
                leading: Icons.tune_rounded,
                title: const Text('画面调节'),
                description: const Text('锐化 / 对比度 / 饱和度 / 亮度 / 伽马'),
                value: Text(activePreset?.name ?? '关闭'),
                onPressed: (_) => host.openSubPage(SplitSubPage.filter),
              ),
              SelectTile<SuperResolutionMode>(
                leading: Icons.auto_awesome_rounded,
                title: const Text('超分辨率'),
                description: Text(superResolution.description),
                value: superResolution,
                options: _superResolutionOptions,
                onChanged: host.handleSuperResolutionChange,
              ),
              SelectTile<PlayerAspectRatio>(
                leading: Icons.aspect_ratio_rounded,
                title: const Text('视频比例'),
                value: playerController.panel.aspectRatioMode,
                options: _aspectRatioOptions,
                onChanged: (mode) =>
                    playerController.panel.aspectRatioMode = mode,
              ),
              SettingsTile(
                leading: Icons.info_outline_rounded,
                title: const Text('视频信息'),
                description: const Text('分辨率 / 码率 / 编码参数 / 运行日志'),
                onPressed: (_) => host.openSubPage(SplitSubPage.videoInfo),
              ),
            ],
          ),
        ],
      );
    });
  }
}

/// 超分辨率选项：取值与文案直接来自 [SuperResolutionMode] 本身（与底栏
/// 「超分辨率」菜单同款枚举、同序、同 `label`），不另建映射表。
///
/// 既有菜单的条目**没有**逐项图标（只有文字），这里保持一致；行首图标沿用
/// 设置页「超分辨率」行的 `auto_awesome_rounded`。
final List<SelectOption<SuperResolutionMode>> _superResolutionOptions = [
  for (final mode in SuperResolutionMode.values)
    SelectOption(value: mode, label: mode.label),
];

/// 视频比例选项：取值与文案直接来自 [PlayerAspectRatio] 本身（与底栏比例菜单
/// 同款枚举、同序、同 `label`）；选中后直接写 `panel.aspectRatioMode`。
final List<SelectOption<PlayerAspectRatio>> _aspectRatioOptions = [
  for (final ratio in PlayerAspectRatio.values)
    SelectOption(value: ratio, label: ratio.label),
];
