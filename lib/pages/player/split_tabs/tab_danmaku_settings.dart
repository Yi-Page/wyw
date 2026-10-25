import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import 'package:wyw/bean/settings/settings_list.dart';
import 'package:wyw/pages/player/controller/player_panel_controller.dart';
import 'package:wyw/pages/player/split_tabs/split_tab_host.dart';
import 'package:wyw/pages/settings/danmaku/danmaku_display_section.dart';
import 'package:wyw/pages/settings/danmaku/danmaku_style_section.dart';
import 'package:wyw/pages/settings/danmaku/danmaku_time_offset_content.dart';
import 'package:wyw/services/storage/storage.dart';

/// 弹幕**设置** tab：总开关（与顶栏按钮双向同步）+ 来源开关 + 共用显示组
/// （简繁/显示效果/海量/去重）+ 共用样式组（描边/颜色/字重）+ 时间偏移 / 屏蔽
/// 两个二级页 + 离线弹幕缓存。
///
/// 「弹幕选择 / 换库」不在本 tab：它在同级的「弹幕」tab（`tab_danmaku.dart`）。
/// 选择是一件事、设置是另一件事——混在一起会让"当前用的是哪个库"和
/// "弹幕怎么显示"互相抢位置。
///
/// **与设置页同源**：显示组与样式组都是 `pages/settings/danmaku/` 里的共用内容件，
/// 本 tab 只负责把它们摆进分屏面板，并接手两件外壳才知道的事（见
/// [_onDisplayChanged]）。曾经这两组的部分行只内联在设置页里，导致"设置里有、
/// 面板里没有"（反馈原话）。
///
/// 值一律现读单一事实源：总开关读 `playerController.danmaku.danmakuOn`
/// （mobx observable，顶栏的弹幕按钮读写同一个），来源/时间偏移读 `GStorage`。
/// 本 tab **不缓存**任何设置值——缓存住就必然要在外面再拉一条同步通道
/// （v1 的教训：设置写入广播 + 订阅端 `setState` 全量重读）。
///
/// 行一律用既有设置组件（`SettingsList` / `SettingsSection` /
/// `SettingsTile` / `SettingsSliderTile` / 共用内容件），不自造行样式。
class DanmakuSettingsTab extends StatefulWidget {
  const DanmakuSettingsTab({super.key, required this.host});

  final SplitTabHost host;

  @override
  State<DanmakuSettingsTab> createState() => _DanmakuSettingsTabState();
}

class _DanmakuSettingsTabState extends State<DanmakuSettingsTab> {
  /// 与其它设置卡片对齐的外边距（`SettingsSection` 原来的默认外边距）。
  static const EdgeInsets _sectionPadding = EdgeInsets.fromLTRB(16, 0, 16, 16);

  @override
  Widget build(BuildContext context) {
    return SettingsList(
      sections: [
        _enabledSection(),
        _sourceSection(),
        // 显示效果：设置页与本面板**同一份内容件**（简繁/显示效果/海量/去重）。
        // `onChanged` 只做一件事：把刚落盘的改动推给画布（见 _onDisplayChanged）。
        DanmakuDisplaySection(
          padding: _sectionPadding,
          onChanged: _onDisplayChanged,
        ),
        // 样式同样共用（描边/描边粗细/颜色/字重）。这一组不需要回灌：
        // 描边与字重进画布 option、颜色在发送每条弹幕时现读，约 1 秒内自己生效。
        const DanmakuStyleSection(padding: _sectionPadding),
        _offlineSection(),
        _entriesSection(),
      ],
    );
  }

  /// 离线弹幕：下载完成后把该集弹幕一并缓存到剧集目录（`danmaku.json`），
  /// 飞行模式下也能出弹幕。
  ///
  /// 缓存的来源是**进度记录里的库 + 按集号对位**，所以这部作品必须先在这台设备上
  /// 选过一次库（否则下载时无从知道该抓哪个弹幕库）；集名对不上库分集时静默跳过，
  /// 宁可没有缓存也不猜错集。详见 `docs/danmaku-selection-plan.md` §5.2。
  Widget _offlineSection() {
    final enabled = GStorage.getSetting<bool>(SettingsKeys.downloadDanmaku);
    return SettingsSection(
      title: const Text('离线弹幕'),
      tiles: [
        SettingsTile.switchTile(
          leading: Icons.cloud_download_rounded,
          title: const Text('下载时缓存弹幕'),
          description: const Text('下完把这一集弹幕存进剧集目录，离线播放也能出'),
          initialValue: enabled,
          onToggle: (value) =>
              _setSource(SettingsKeys.downloadDanmaku, value ?? !enabled),
        ),
      ],
    );
  }

  /// 弹幕总开关（与播放器顶栏的弹幕按钮**双向同步**）。
  ///
  /// 链路：本行与顶栏按钮都 `Observer` 同一个 observable
  /// [PlayerDanmakuController.danmakuOn]，且都只通过
  /// [PlayerDanmakuController.setDanmakuEnabled] 改它。没有第二份状态，
  /// 因此不需要任何"回写/同步"代码：顶栏改了，`Observer` 让本行重建；
  /// 本行改了，顶栏按钮重建。
  Widget _enabledSection() {
    final danmaku = widget.host.playerController.danmaku;
    return Observer(
      builder: (context) {
        return SettingsSection(
          title: const Text('弹幕'),
          tiles: [
            SettingsTile.switchTile(
              leading: Icons.subtitles_rounded,
              title: const Text('弹幕'),
              description: Text(danmaku.libraryLabel),
              initialValue: danmaku.danmakuOn,
              onToggle: (value) =>
                  danmaku.setDanmakuEnabled(value ?? !danmaku.danmakuOn),
            ),
          ],
        );
      },
    );
  }

  /// 弹幕来源开关：与 `danmaku_settings.dart` 的「弹幕来源」段同一批键、
  /// 同一文案、同一顺序（弹弹play 排在最后，与设置页一致）。
  Widget _sourceSection() {
    return SettingsSection(
      title: const Text('弹幕来源'),
      tiles: [
        _sourceTile(
          SettingsKeys.danmakuBiliBiliSource,
          Icons.live_tv_rounded,
          'BiliBili',
        ),
        _sourceTile(
          SettingsKeys.danmakuGamerSource,
          Icons.sports_esports_rounded,
          'Gamer',
        ),
        _sourceTile(
          SettingsKeys.danmakuDanDanSource,
          Icons.forum_rounded,
          '弹弹play',
        ),
      ],
    );
  }

  /// 一个来源开关：值现读 `GStorage`（唯一事实源），改完 `setState` 回显。
  ///
  /// 与设置页 `danmaku_settings.dart` 的写法一致：不做本地缓存、不加广播流
  /// （`GStorage` 只是存储，不允许在上面挂全局副作用）。
  Widget _sourceTile(SettingKey<bool> key, IconData leading, String title) {
    final enabled = GStorage.getSetting<bool>(key);
    return SettingsTile.switchTile(
      leading: leading,
      title: Text(title),
      initialValue: enabled,
      onToggle: (value) => _setSource(key, value ?? !enabled),
    );
  }

  Future<void> _setSource(SettingKey<bool> key, bool value) async {
    await GStorage.putSetting<bool>(key, value);
    if (!mounted) return;
    setState(() {});
  }

  /// 两个二级页入口：一律 `host.openSubPage(...)`，**不跳页**。
  Widget _entriesSection() {
    final host = widget.host;
    return SettingsSection(
      title: const Text('弹幕库'),
      tiles: [
        SettingsTile(
          leading: Icons.sync_rounded,
          title: const Text('时间校准'),
          description: Text(
            formatDanmakuTimeOffset(
              normalizeDanmakuTimeOffset(
                GStorage.getSetting<double>(SettingsKeys.danmakuTimeOffset),
              ),
            ),
          ),
          onPressed: (_) => host.openSubPage(SplitSubPage.timeOffset),
        ),
        SettingsTile(
          leading: Icons.filter_alt_outlined,
          title: const Text('屏蔽规则'),
          description: const Text('关键词与正则表达式'),
          onPressed: (_) => host.openSubPage(SplitSubPage.shield),
        ),
      ],
    );
  }

  /// 共用显示件改完并落盘后的**即时生效**。
  ///
  /// 与旧播放器弹幕设置弹层（`danmaku_settings_sheet.dart`，已随面板退场）
  /// 的 `_onDisplayChanged` 同一条路径：
  ///   - 区域 / 行高 / 字号 / 不透明度 → `option.copyWith(...)` 后
  ///     `canvasController.updateOption(...)`；
  ///   - 顶部 / 底部 / 滚动 → 画布语义与设置相反，`hideX: !value`；
  ///   - 持续时间 / 跟随倍速 → 不进画布 option，交给播放器按当前倍速重算
  ///     （`updateDanmakuSpeed(playback.playerSpeed)`）。
  ///
  /// 不改设置值的存储归属：落盘由共用内容件做（`GStorage` 仍是唯一事实源），
  /// 这里只负责"让画面立刻跟上"。
  void _onDisplayChanged(DanmakuDisplayChange change) {
    final danmaku = widget.host.playerController.danmaku;
    final controller = danmaku.canvasController;
    if (controller != null) {
      final updated = switch (change.property) {
        DanmakuDisplayProperty.area =>
          controller.option.copyWith(area: change.doubleValue),
        DanmakuDisplayProperty.lineHeight =>
          controller.option.copyWith(lineHeight: change.doubleValue),
        DanmakuDisplayProperty.fontSize =>
          controller.option.copyWith(fontSize: change.doubleValue),
        DanmakuDisplayProperty.opacity =>
          controller.option.copyWith(opacity: change.doubleValue),
        DanmakuDisplayProperty.top =>
          controller.option.copyWith(hideTop: !change.boolValue),
        DanmakuDisplayProperty.bottom =>
          controller.option.copyWith(hideBottom: !change.boolValue),
        DanmakuDisplayProperty.scroll =>
          controller.option.copyWith(hideScroll: !change.boolValue),
        DanmakuDisplayProperty.duration ||
        DanmakuDisplayProperty.followSpeed ||
        // 海量弹幕进的是画布 option，播放循环每秒比对的选项签名已包含它，
        // 这里不必额外做什么（约 1 秒内自己生效）。
        DanmakuDisplayProperty.massive ||
        DanmakuDisplayProperty.deduplication =>
          null,
      };
      if (updated != null) {
        controller.updateOption(updated);
      }
    }
    if (change.property == DanmakuDisplayProperty.duration ||
        change.property == DanmakuDisplayProperty.followSpeed) {
      danmaku.updateDanmakuSpeed(
        widget.host.playerController.playback.playerSpeed,
      );
    }
    if (change.property == DanmakuDisplayProperty.deduplication) {
      // 合并发生在**写入桶**的时候，所以改开关必须就地重跑一次分桶——否则要等
      // 下次换集/重新取弹幕才生效。有原始列表就能本地重算，不必联网。
      danmaku.reapplyDanmakuDeduplication();
    }
  }
}
