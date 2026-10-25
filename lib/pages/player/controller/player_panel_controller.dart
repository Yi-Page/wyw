// ignore_for_file: library_private_types_in_public_api

import 'dart:async';

import 'package:mobx/mobx.dart';
import 'package:wyw/pages/player/controller/player_aspect_ratio.dart';
import 'package:wyw/pages/player/controller/player_split_geometry.dart';
import 'package:wyw/services/storage/storage.dart';

part 'player_panel_controller.g.dart';

/// 分屏面板的页签（顺序即显示顺序）。
///
/// 6 个 tab：选集 / 弹幕 / 弹幕设置 / 画面 / 播放 / 更多。
/// 「弹幕」管**选择**（这一集用哪个弹幕库），「弹幕设置」管**显示与来源**；
/// 两者拆开是因为前者是"选一次"的动线、后者是"调一次"的动线，混在一个 tab 里
/// 会让"当前用的是哪个库"和"弹幕怎么显示"互相抢位置。
enum SplitPanelTab {
  episodes('选集'),
  danmaku('弹幕'),
  danmakuSettings('弹幕设置'),
  display('画面'),
  playback('播放'),
  more('更多');

  const SplitPanelTab(this.label);

  final String label;
}

/// 面板内的二级页：替换 body、带返回箭头、不重放动画。
///
/// 用**类型**而不是字符串桥接（v1 用 `enum.name` 字符串 + `switch`，改名即
/// 静默变成空 body）。
enum SplitSubPage {
  filter('画面调节'),
  videoInfo('视频信息'),
  shield('弹幕屏蔽'),
  timeOffset('弹幕时间偏移');

  const SplitSubPage(this.title);

  final String title;
}

class PlayerPanelController = _PlayerPanelController
    with _$PlayerPanelController;

abstract class _PlayerPanelController with Store {
  /// 视频比例
  @observable
  PlayerAspectRatio aspectRatioMode = PlayerAspectRatio.automatic;

  // 视频亮度
  @observable
  double brightness = 0;

  // 播放器界面控制
  @observable
  bool lockPanel = false;
  @observable
  bool showVideoController = true;
  @observable
  bool showSeekTime = false;
  @observable
  bool showBrightness = false;
  @observable
  bool showVolume = false;
  @observable
  bool showPlaySpeed = false;
  @observable
  bool brightnessSeeking = false;
  @observable
  bool volumeSeeking = false;
  int seekDirection = 0;
  @observable
  bool canHidePlayerPanel = true;

  // ==================== 分屏面板 ====================

  /// 面板是否展开。
  @observable
  bool splitPanelVisible = false;

  /// 当前页签（面板关闭再打开时保持）。
  @observable
  SplitPanelTab splitPanelTab = SplitPanelTab.episodes;

  /// 当前二级页（`null` = 显示页签内容）。
  @observable
  SplitSubPage? splitPanelSubPage;

  /// 横屏面板宽度（像素；`0` = 未自定义，取 `clamp(可用宽 / 3, 320, 420)`）。
  ///
  /// 单位与 [splitPanelHeightFraction] 不同：横屏存**像素**、竖屏存**占比**，
  /// 所以取值一律走 [player_split_geometry.dart] 里按轴向命名的函数。
  @observable
  double splitPanelWidth = 0;

  /// 竖屏面板高度占比（`0` = 未自定义，取容器高的 45%）。
  @observable
  double splitPanelHeightFraction = 0;

  Timer? _splitPersistTimer;

  /// 待落盘的比例（防抖窗口内被新的拖动覆盖）。
  ({SplitAxis axis, double value})? _pendingSplitExtent;

  /// 载入已保存的分屏比例（进播放页时调用一次）。
  @action
  void loadSplitPanelExtent() {
    splitPanelWidth = GStorage.getSetting(
      SettingsKeys.playerSplitRatioLandscape,
    );
    splitPanelHeightFraction = GStorage.getSetting(
      SettingsKeys.playerSplitRatioPortrait,
    );
  }

  /// 用户拖动分界线后更新比例；[stored] 单位随轴向（横屏像素 / 竖屏占比）。
  ///
  /// 落盘走防抖，真正的写入在 [flushSplitPanelExtent]（关闭面板 / 离开页面时
  /// 必须调用，否则防抖窗口内退出会丢）。v1 的定时器在 `dispose` 没取消，
  /// 页面卸载后还会写存储，这里由 [disposeSplitPanelPersistence] 兜住。
  @action
  void setSplitPanelExtent(SplitAxis axis, double stored) {
    if (axis == SplitAxis.horizontal) {
      splitPanelWidth = stored;
    } else {
      splitPanelHeightFraction = stored;
    }
    _pendingSplitExtent = (axis: axis, value: stored);
    _splitPersistTimer?.cancel();
    _splitPersistTimer = Timer(SplitPanelMetrics.ratioPersistDebounce, () {
      unawaited(flushSplitPanelExtent());
    });
  }

  /// 双击分界线：回到默认（存 `0` = 未自定义，两个方向都随容器自适应）。
  void resetSplitPanelExtent(SplitAxis axis) {
    setSplitPanelExtent(axis, 0);
  }

  /// 立即落盘待写入的比例。
  Future<void> flushSplitPanelExtent() async {
    _splitPersistTimer?.cancel();
    _splitPersistTimer = null;
    final pending = _pendingSplitExtent;
    if (pending == null) {
      return;
    }
    _pendingSplitExtent = null;
    if (pending.axis == SplitAxis.horizontal) {
      await GStorage.putSetting<double>(
        SettingsKeys.playerSplitRatioLandscape,
        pending.value,
      );
    } else {
      await GStorage.putSetting<double>(
        SettingsKeys.playerSplitRatioPortrait,
        pending.value,
      );
    }
  }

  /// 取消未落盘的防抖定时器（调用方应先 [flushSplitPanelExtent]）。
  void disposeSplitPanelPersistence() {
    _splitPersistTimer?.cancel();
    _splitPersistTimer = null;
  }

  @action
  void openSplitPanel([SplitPanelTab? tab]) {
    if (tab != null) {
      splitPanelTab = tab;
    }
    splitPanelVisible = true;
  }

  @action
  void closeSplitPanel() {
    splitPanelVisible = false;
    // 收起即落盘：刚拖完就收起/退出时，不能等防抖窗口。
    unawaited(flushSplitPanelExtent());
  }

  @action
  void toggleSplitPanel() {
    if (splitPanelVisible) {
      closeSplitPanel();
    } else {
      splitPanelVisible = true;
    }
  }

  @action
  void setSplitPanelTab(SplitPanelTab tab) {
    splitPanelTab = tab;
    // 切页签回到列表层（二级页属于某个页签）。
    splitPanelSubPage = null;
  }

  @action
  void openSplitPanelSubPage(SplitSubPage page) {
    splitPanelSubPage = page;
  }

  @action
  void closeSplitPanelSubPage() {
    splitPanelSubPage = null;
  }

  @action
  void reset() {
    lockPanel = false;
    showVideoController = true;
    showSeekTime = false;
    showBrightness = false;
    showVolume = false;
    showPlaySpeed = false;
    brightnessSeeking = false;
    volumeSeeking = false;
    seekDirection = 0;
    canHidePlayerPanel = true;
    // 分屏面板：收起（比例与页签是用户偏好，保留）。
    splitPanelVisible = false;
    splitPanelSubPage = null;
  }
}
