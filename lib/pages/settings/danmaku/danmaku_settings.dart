import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/bean/settings/settings_detail_scaffold.dart';
import 'package:wyw/bean/settings/settings_list.dart';
import 'package:wyw/pages/settings/danmaku/danmaku_display_section.dart';
import 'package:wyw/pages/settings/danmaku/danmaku_style_section.dart';
import 'package:wyw/services/storage/storage.dart';

/// 与其它设置卡片对齐的外边距（`SettingsSection` 原来的默认外边距）。
const EdgeInsets _sectionPadding = EdgeInsets.fromLTRB(16, 0, 16, 16);

/// 弹幕设置页。
///
/// 显示与样式两组都是**两端共用的内容件**（本页 + 播放器分屏面板的「弹幕设置」
/// tab），这样"设置里有、播放器面板里没有"不会再出现：
///   - [DanmakuDisplaySection]：简繁转换 + 显示效果 + 海量弹幕 + 弹幕去重；
///   - [DanmakuStyleSection]：描边 / 描边粗细 / 弹幕颜色 / 字体字重。
///
/// 本页只留**页面专有**的三块：来源开关、屏蔽词入口、恢复默认。
class DanmakuSettingsPage extends StatefulWidget {
  const DanmakuSettingsPage({super.key});

  @override
  State<DanmakuSettingsPage> createState() => _DanmakuSettingsPageState();
}

class _DanmakuSettingsPageState extends State<DanmakuSettingsPage> {
  late bool danmakuBiliBiliSource;
  late bool danmakuGamerSource;
  late bool danmakuDanDanSource;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadSourceSettings();
  }

  void _loadSourceSettings() {
    danmakuBiliBiliSource =
        GStorage.getSetting<bool>(SettingsKeys.danmakuBiliBiliSource);
    danmakuGamerSource =
        GStorage.getSetting<bool>(SettingsKeys.danmakuGamerSource);
    danmakuDanDanSource =
        GStorage.getSetting<bool>(SettingsKeys.danmakuDanDanSource);
  }

  Future<void> _setSource(SettingKey<bool> key, bool value) async {
    await GStorage.putSetting<bool>(key, value);
    if (!mounted) return;
    setState(_loadSourceSettings);
  }

  Future<void> resetDanmakuSettings() async {
    final bool shouldReset = await WywDialog.show<bool>(
          builder: (context) => AlertDialog(
            title: const Text('恢复默认弹幕设置'),
            content: const Text('弹幕来源、显示和样式设置将恢复为默认值，关键词屏蔽列表不会被清空。'),
            actions: [
              TextButton(
                onPressed: () => WywDialog.dismiss(popWith: false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => WywDialog.dismiss(popWith: true),
                child: const Text('恢复默认'),
              ),
            ],
          ),
        ) ??
        false;
    if (!shouldReset) return;

    await GStorage.resetDanmakuSettings();
    if (!mounted) return;
    // 显示与样式两组都由共用内容件自己从存储读，重建即回显默认值。
    setState(_loadSourceSettings);
    WywDialog.showToast(message: '已恢复默认弹幕设置');
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: const Text('弹幕设置'),
      body: SettingsList(
        sections: [
          SettingsSection(
            title: const Text('弹幕来源'),
            tiles: [
              SettingsTile.switchTile(
                leading: Icons.live_tv_rounded,
                onToggle: (value) => _setSource(
                  SettingsKeys.danmakuBiliBiliSource,
                  value ?? !danmakuBiliBiliSource,
                ),
                title: const Text('BiliBili'),
                initialValue: danmakuBiliBiliSource,
              ),
              SettingsTile.switchTile(
                leading: Icons.sports_esports_rounded,
                onToggle: (value) => _setSource(
                  SettingsKeys.danmakuGamerSource,
                  value ?? !danmakuGamerSource,
                ),
                title: const Text('Gamer'),
                initialValue: danmakuGamerSource,
              ),
              SettingsTile.switchTile(
                leading: Icons.forum_rounded,
                onToggle: (value) => _setSource(
                  SettingsKeys.danmakuDanDanSource,
                  value ?? !danmakuDanDanSource,
                ),
                title: const Text('弹弹play'),
                initialValue: danmakuDanDanSource,
              ),
            ],
          ),
          SettingsSection(
            title: const Text('弹幕屏蔽'),
            tiles: [
              SettingsTile(
                leading: Icons.block_rounded,
                onPressed: (_) {
                  context.pushNamed('/settings/danmaku/shield');
                },
                title: const Text('关键词屏蔽'),
              ),
            ],
          ),
          const DanmakuDisplaySection(padding: _sectionPadding),
          const DanmakuStyleSection(padding: _sectionPadding),
          SettingsSection(
            tiles: [
              SettingsTile(
                leading: Icons.settings_backup_restore_rounded,
                onPressed: (_) => resetDanmakuSettings(),
                title: const Text('恢复默认设置'),
                description: const Text('将弹幕相关设置恢复为默认值'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
