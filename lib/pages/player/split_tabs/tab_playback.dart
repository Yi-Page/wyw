import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/bean/settings/settings_list.dart';
import 'package:wyw/bean/widget/select_field.dart';
import 'package:wyw/pages/player/skip_seconds_dialog.dart';
import 'package:wyw/pages/player/split_tabs/split_tab_host.dart';
import 'package:wyw/services/player/pip_utils.dart';
import 'package:wyw/services/player/remote.dart';
import 'package:wyw/services/player/timed_shutdown_service.dart';
import 'package:wyw/utils/constants.dart';
import 'package:wyw/utils/device.dart';

/// 播放 tab：倍速 / 音量 / 跳过秒数 / 定时关闭（含**自定义**）/ 画中画 /
/// 远程投屏 / 外部播放 / 截图。
///
/// 每一项都是**迁移**（移动，不是新写一套）：调用与判据逐条照搬
/// `player_item_panel.dart` 的底栏 MenuAnchor 簇（倍速）与顶栏「更多」菜单
/// （定时关闭 / 画中画 / 投屏 / 外部播放）。那些旧入口已在 P5 删除，全仓
/// 每个动作只剩本文件一份实现（§6-8）。
///
/// 行只由既有设计系统组件拼成（§6-3），当前值一律从 controller 的 observable
/// 读（`Observer`），不在这里缓存设置副本。
class PlaybackTab extends StatelessWidget {
  const PlaybackTab({super.key, required this.host});

  final SplitTabHost host;

  /// 倍速滑杆范围（既有档位见 `defaultPlaySpeedList`，步进 0.25）。
  static const double _minSpeed = 0.25;
  static const double _maxSpeed = 4;

  @override
  Widget build(BuildContext context) {
    final controller = host.playerController;
    final playback = controller.playback;

    return Observer(
      builder: (context) {
        // 只读本页要显示的 observable：与音量/倍速无关的 observable 变化
        // 不会重建这份列表（§0-10）。
        final double speed = playback.playerSpeed.clamp(_minSpeed, _maxSpeed);
        final double volume = playback.volume.clamp(0.0, 100.0);
        final int screenshotCount = controller.screenshots.candidates.length;

        return SettingsList(
          sections: [
            SettingsSection(
              title: const Text('速度与音量'),
              tiles: [
                SettingsSliderTile(
                  leading: Icons.speed_rounded,
                  title: const Text('播放速度'),
                  description: const Text('0.25x ~ 4x'),
                  value: speed,
                  valueLabel: '${playback.playerSpeed}x',
                  min: _minSpeed,
                  max: _maxSpeed,
                  divisions: ((_maxSpeed - _minSpeed) / 0.25).round(),
                  onChanged: (value) {
                    unawaited(host.setPlaybackSpeed(_snapSpeed(value)));
                  },
                ),
                SelectTile<double>(
                  leading: Icons.bolt_rounded,
                  title: const Text('常用档位'),
                  description: const Text('与设置页「默认倍速」同一组档位'),
                  value: defaultPlaySpeedList.contains(playback.playerSpeed)
                      ? playback.playerSpeed
                      : null,
                  placeholder: '自定义',
                  options: [
                    for (final double preset in defaultPlaySpeedList)
                      SelectOption(value: preset, label: '${preset}x'),
                  ],
                  onChanged: (value) {
                    unawaited(host.setPlaybackSpeed(value));
                  },
                ),
                SettingsSliderTile(
                  leading: Icons.volume_up_rounded,
                  title: const Text('音量'),
                  value: volume,
                  valueLabel: '${volume.round()}%',
                  min: 0,
                  max: 100,
                  divisions: 100,
                  onChanged: (value) {
                    unawaited(controller.setVolume(value));
                  },
                ),
              ],
            ),
            SettingsSection(
              title: const Text('跳过与定时'),
              tiles: [
                SettingsTile(
                  leading: Icons.fast_forward_rounded,
                  title: const Text('跳过片头 / 片尾'),
                  description: const Text('顶栏「跳过」按钮快进的秒数，长按该按钮也可修改'),
                  // `buttonSkipTime` 是 observable，改完会自动重建本行。
                  value: Text('${playback.buttonSkipTime} 秒'),
                  onPressed: (context) {
                    showSkipSecondsDialog(
                      currentSkipTime: playback.buttonSkipTime,
                      onSave: (seconds) {
                        controller.setButtonForwardTime(seconds);
                      },
                    );
                  },
                ),
                ValueListenableBuilder<int>(
                  valueListenable: TimedShutdownService().setMinutesNotifier,
                  builder: (context, minutes, child) => SelectTile<int>(
                    leading: Icons.timer_outlined,
                    title: const Text('定时关闭'),
                    value: minutes,
                    // 自定义时长不在档位里 → 显示「自定义」而不是空白。
                    placeholder: '自定义',
                    options: const [
                      SelectOption(value: 0, label: '不开启'),
                      SelectOption(value: 15, label: '15 分钟'),
                      SelectOption(value: 30, label: '30 分钟'),
                      SelectOption(value: 60, label: '60 分钟'),
                    ],
                    onChanged: _applyTimedShutdown,
                  ),
                ),
                SettingsTile(
                  leading: Icons.more_time_rounded,
                  title: const Text('自定义定时'),
                  description: const Text('按小时 / 分钟精确设置'),
                  onPressed: (context) {
                    TimedShutdownService.showCustomTimerDialog(
                      onExpired: host.pauseForTimedShutdown,
                    );
                  },
                ),
                ValueListenableBuilder<int>(
                  valueListenable:
                      TimedShutdownService().remainingSecondsNotifier,
                  builder: (context, remainingSeconds, child) => SettingsTile(
                    leading: Icons.hourglass_bottom_rounded,
                    title: const Text('剩余时间'),
                    value: Text(
                      remainingSeconds > 0
                          ? TimedShutdownService().formatRemainingTime()
                          : '未开启',
                    ),
                  ),
                ),
              ],
            ),
            SettingsSection(
              title: const Text('画面与输出'),
              tiles: [
                // 判据与既有「更多」菜单一致（桌面非全屏，或 Android）。
                if ((isDesktop() && !host.videoPageController.isFullscreen) ||
                    Platform.isAndroid)
                  SettingsTile(
                    leading: Icons.picture_in_picture_alt_rounded,
                    title: const Text('画中画'),
                    description: const Text('切换小窗播放'),
                    onPressed: (context) {
                      unawaited(_togglePip());
                    },
                  ),
                SettingsTile(
                  leading: Icons.cast_rounded,
                  title: const Text('远程投屏'),
                  description: const Text('投屏前暂停，结束后按原状态恢复播放'),
                  onPressed: (context) {
                    unawaited(_castVideo());
                  },
                ),
                SettingsTile(
                  leading: Icons.open_in_new_rounded,
                  title: const Text('外部播放'),
                  description: const Text('用系统播放器打开当前地址'),
                  onPressed: (context) {
                    unawaited(controller.launchExternalPlayer());
                  },
                ),
                SettingsTile(
                  leading: Icons.photo_camera_outlined,
                  title: const Text('截取当前画面'),
                  description: isDesktop()
                      ? const Text('加入候选列表，可在「截图候选」里挑选与裁剪')
                      : const Text('直接保存到相册'),
                  onPressed: (context) => host.handleScreenshot(),
                ),
                // 候选挑选是桌面端独有的工作流（与顶栏截图控件同判据）。
                if (isDesktop())
                  SettingsTile(
                    leading: Icons.photo_library_outlined,
                    title: const Text('截图候选'),
                    value: Text('$screenshotCount 张'),
                    enabled: screenshotCount > 0,
                    onPressed: (context) => host.showScreenshotCandidates(),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// 滑杆取值对齐 0.25 的整数倍，避免 0.30000000000000004 之类的值写进播放器。
  double _snapSpeed(double value) => (value * 4).roundToDouble() / 4;

  /// 定时关闭：`0` = 不开启；档位与既有子菜单一致（15 / 30 / 60）。
  ///
  /// 文案与既有实现逐字一致（`已设置 X 后定时关闭`）。
  void _applyTimedShutdown(int minutes) {
    final service = TimedShutdownService();
    if (minutes <= 0) {
      service.cancel();
      return;
    }
    service.start(minutes, onExpired: host.pauseForTimedShutdown);
    WywDialog.showToast(
      message: '已设置 ${service.formatMinutesToDisplay(minutes)} 后定时关闭',
    );
  }

  /// 与既有「更多」菜单同款：先暂停 → 投屏 → 完成后按需恢复。
  Future<void> _castVideo() async {
    final controller = host.playerController;
    final bool needRestart = controller.playback.playing;
    await controller.pause();
    try {
      await RemotePlay().castVideo(controller.videoUrl);
    } finally {
      if (needRestart) {
        await controller.play();
      }
    }
  }

  Future<void> _togglePip() async {
    final videoPageController = host.videoPageController;
    final controller = host.playerController;
    final bool toggled = await PipUtils.togglePip(
      isPip: videoPageController.isPip,
      isPlaying: controller.playback.playing,
      width: controller.debug.playerWidth,
      height: controller.debug.playerHeight,
    );
    if (isDesktop()) {
      videoPageController.isPip = toggled;
    }
  }
}
