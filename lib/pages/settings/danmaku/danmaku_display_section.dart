import 'package:flutter/material.dart';

import 'package:wyw/bean/settings/settings_list.dart';
import 'package:wyw/pages/settings/danmaku/danmaku_ch_convert_tile.dart';
import 'package:wyw/services/storage/storage.dart';

/// 小屏判据：最短边 < 600 时字号默认值取小号。
///
/// 与设置页、播放器内 `resolveCanvasOption(compactLayout: …)` 的口径一致。
const double danmakuCompactLayoutShortestSide = 600;

const double danmakuAreaMin = 0;
const double danmakuAreaMax = 1;
const int danmakuAreaDivisions = 8;

const double danmakuDurationMinSeconds = 2;
const double danmakuDurationMaxSeconds = 16;
const int danmakuDurationDivisions = 14;

const double danmakuLineHeightMin = 0;
const double danmakuLineHeightMax = 3;
const int danmakuLineHeightDivisions = 30;
const int danmakuLineHeightFractionDigits = 1;

const double danmakuFontSizeMin = 10;
const double danmakuFontSizeMax = 48;

const double danmakuOpacityMin = 0.1;
const double danmakuOpacityMax = 1;
const int danmakuOpacityFractionDigits = 2;

/// 百分比类取值（区域 / 不透明度）换算成整数百分号的倍率。
const double danmakuPercentScale = 100;

/// 「弹幕显示效果」里会即时影响画面的项。
///
/// 外壳（播放器内在的弹幕设置）据此把改动推给画布；设置页不需要，就不传回调。
enum DanmakuDisplayProperty {
  area,
  duration,
  lineHeight,
  followSpeed,
  top,
  bottom,
  scroll,
  fontSize,
  opacity,

  /// 海量弹幕（叠加绘制）。进画布 option，外壳不必额外处理——播放循环每秒比对的
  /// 选项签名里已包含它。
  massive,

  /// 弹幕去重。**合并发生在写入桶的时候**，所以要外壳重跑一次分桶
  /// （`PlayerDanmakuController.reapplyDanmakuDeduplication`）才在播放中生效。
  deduplication,
}

/// 一次显示效果改动：哪一项、变成了什么。
///
/// [value] 滑块项为 `double`（已按本件约定归一：时长取整秒、行高与不透明度各保留
/// 固定小数位、字号向下取整），开关项为 `bool`。
class DanmakuDisplayChange {
  const DanmakuDisplayChange(this.property, this.value);

  final DanmakuDisplayProperty property;
  final Object value;

  double get doubleValue => value as double;
  bool get boolValue => value as bool;
}

/// 弹幕「显示效果」的共用内容件——设置页与播放器分屏面板的「弹幕设置」tab
/// **唯一一份**实现。
///
/// **永远无头**：不含标题栏、关闭按钮、底部弹层外壳、`SafeArea`、滚动容器；
/// 外边距一律由外壳经 [padding] 传入（本件内部不再自加外边距，见下方说明），
/// 因此不使用 `embedded` 之类的布尔开关分叉。
///
/// 值的唯一事实源是 `GStorage`（构造后每次 build 重新读取），写入即落盘：
///   - 设置页：`SettingsList` 里的一张卡片，不传 [onChanged]；
///   - 播放器面板：外壳给 [padding]，并用 [onChanged] 把改动即时推给画布。
///
/// [padding] 承担的是原来 `SettingsSection` 默认外边距的角色：设置页传
/// `EdgeInsets.fromLTRB(16, 0, 16, 16)`（与其它卡片对齐），面板传自己的外边距。
///
/// 卡内顺序照设置页原样：**简繁转换 → 显示效果各项 → 海量弹幕 → 弹幕去重**。
/// 后三项曾经是外壳经 `leadingTiles`/`trailingTiles` 插进来的"本页专有行"——
/// 那两个插槽只服务于已退场的播放器弹层，插槽没了消费者以后，面板就再也拿不到
/// 这三项（"设置里有、面板里没有"的来源）。现在它们由本件直接内置，两端必然一致。
class DanmakuDisplaySection extends StatefulWidget {
  const DanmakuDisplaySection({
    super.key,
    this.padding = EdgeInsets.zero,
    this.onChanged,
  });

  /// 外壳提供的外边距（本件不自带外壳职责）。
  final EdgeInsetsGeometry padding;

  /// 落盘后的改动通知；设置页不需要即时生效画面，传 null。
  final ValueChanged<DanmakuDisplayChange>? onChanged;

  @override
  State<DanmakuDisplaySection> createState() => _DanmakuDisplaySectionState();
}

class _DanmakuDisplaySectionState extends State<DanmakuDisplaySection> {
  static const String _sectionTitle = '弹幕显示';

  /// 落盘 + 回显 + 通知外壳。
  ///
  /// 先写后 `setState`，与设置页原实现一致（`await GStorage.putSetting` 后再
  /// `setState`）；值本身不从字段读，而是 build 时重新读存储，所以「恢复默认设置」
  /// 之类的**外部改写**也能立刻反映出来。
  Future<void> _commit<T extends Object>(
    SettingKey<T> key,
    DanmakuDisplayProperty property,
    T value,
  ) async {
    await GStorage.putSetting<T>(key, value);
    if (!mounted) return;
    setState(() {});
    widget.onChanged?.call(DanmakuDisplayChange(property, value));
  }

  @override
  Widget build(BuildContext context) {
    final area = GStorage.getSetting(SettingsKeys.danmakuArea);
    final duration = GStorage.getSetting(SettingsKeys.danmakuDuration);
    final lineHeight = GStorage.getSetting(SettingsKeys.danmakuLineHeight);
    final followSpeed = GStorage.getSetting(SettingsKeys.danmakuFollowSpeed);
    final top = GStorage.getSetting(SettingsKeys.danmakuTop);
    final bottom = GStorage.getSetting(SettingsKeys.danmakuBottom);
    final scroll = GStorage.getSetting(SettingsKeys.danmakuScroll);
    final opacity = GStorage.getSetting(SettingsKeys.danmakuOpacity);
    final fontSize = GStorage.getSetting<double>(
      SettingsKeys.danmakuFontSize,
      context: SettingContext(
        compactLayout: MediaQuery.sizeOf(context).shortestSide <
            danmakuCompactLayoutShortestSide,
      ),
    );
    final massive = GStorage.getSetting(SettingsKeys.danmakuMassive);
    final deduplication =
        GStorage.getSetting<bool>(SettingsKeys.danmakuDeduplication);

    return Padding(
      padding: widget.padding,
      child: SettingsSection(
        title: const Text(_sectionTitle),
        // 外边距由 [DanmakuDisplaySection.padding] 统一负责，这里不再叠加。
        margin: EdgeInsets.zero,
        tiles: [
          // 简繁转换自己写存储（它只在下次联网取弹幕时生效，本件无需转发通知）。
          const DanmakuChConvertTile(),
          SettingsSliderTile(
            leading: Icons.crop_free_rounded,
            title: const Text('弹幕区域'),
            value: area,
            min: danmakuAreaMin,
            max: danmakuAreaMax,
            divisions: danmakuAreaDivisions,
            valueLabel: '${(area * danmakuPercentScale).round()}%',
            onChanged: (value) => _commit(
              SettingsKeys.danmakuArea,
              DanmakuDisplayProperty.area,
              value,
            ),
          ),
          SettingsSliderTile(
            leading: Icons.timer_rounded,
            title: const Text('弹幕持续时间'),
            value: duration,
            min: danmakuDurationMinSeconds,
            max: danmakuDurationMaxSeconds,
            divisions: danmakuDurationDivisions,
            valueLabel: '${duration.round()} 秒',
            onChanged: (value) => _commit(
              SettingsKeys.danmakuDuration,
              DanmakuDisplayProperty.duration,
              value.roundToDouble(),
            ),
          ),
          SettingsSliderTile(
            leading: Icons.format_line_spacing_rounded,
            title: const Text('弹幕行高'),
            value: lineHeight,
            min: danmakuLineHeightMin,
            max: danmakuLineHeightMax,
            divisions: danmakuLineHeightDivisions,
            valueLabel:
                lineHeight.toStringAsFixed(danmakuLineHeightFractionDigits),
            onChanged: (value) => _commit(
              SettingsKeys.danmakuLineHeight,
              DanmakuDisplayProperty.lineHeight,
              double.parse(
                value.toStringAsFixed(danmakuLineHeightFractionDigits),
              ),
            ),
          ),
          SettingsTile.switchTile(
            leading: Icons.speed_rounded,
            title: const Text('弹幕跟随视频倍速'),
            description: const Text('开启后弹幕速度会随视频倍速而改变'),
            initialValue: followSpeed,
            onToggle: (value) => _commit(
              SettingsKeys.danmakuFollowSpeed,
              DanmakuDisplayProperty.followSpeed,
              value ?? !followSpeed,
            ),
          ),
          SettingsTile.switchTile(
            leading: Icons.vertical_align_top_rounded,
            title: const Text('顶部弹幕'),
            initialValue: top,
            onToggle: (value) => _commit(
              SettingsKeys.danmakuTop,
              DanmakuDisplayProperty.top,
              value ?? !top,
            ),
          ),
          SettingsTile.switchTile(
            leading: Icons.vertical_align_bottom_rounded,
            title: const Text('底部弹幕'),
            initialValue: bottom,
            onToggle: (value) => _commit(
              SettingsKeys.danmakuBottom,
              DanmakuDisplayProperty.bottom,
              value ?? !bottom,
            ),
          ),
          SettingsTile.switchTile(
            leading: Icons.swap_horiz_rounded,
            title: const Text('滚动弹幕'),
            initialValue: scroll,
            onToggle: (value) => _commit(
              SettingsKeys.danmakuScroll,
              DanmakuDisplayProperty.scroll,
              value ?? !scroll,
            ),
          ),
          SettingsSliderTile(
            leading: Icons.format_size_rounded,
            title: const Text('字体大小'),
            value: fontSize,
            min: danmakuFontSizeMin,
            max: danmakuFontSizeMax,
            valueLabel: '${fontSize.floor()}',
            onChanged: (value) => _commit(
              SettingsKeys.danmakuFontSize,
              DanmakuDisplayProperty.fontSize,
              value.floorToDouble(),
            ),
          ),
          SettingsSliderTile(
            leading: Icons.opacity_rounded,
            title: const Text('弹幕不透明度'),
            value: opacity,
            min: danmakuOpacityMin,
            max: danmakuOpacityMax,
            valueLabel: '${(opacity * danmakuPercentScale).round()}%',
            onChanged: (value) => _commit(
              SettingsKeys.danmakuOpacity,
              DanmakuDisplayProperty.opacity,
              double.parse(
                value.toStringAsFixed(danmakuOpacityFractionDigits),
              ),
            ),
          ),
          SettingsTile.switchTile(
            leading: Icons.layers_rounded,
            title: const Text('海量弹幕'),
            description: const Text('弹幕过多时进行叠加绘制'),
            initialValue: massive,
            onToggle: (value) => _commit(
              SettingsKeys.danmakuMassive,
              DanmakuDisplayProperty.massive,
              value ?? !massive,
            ),
          ),
          SettingsTile.switchTile(
            leading: Icons.filter_alt_rounded,
            title: const Text('弹幕去重'),
            description: const Text('相同内容弹幕过多时合并为一条弹幕'),
            initialValue: deduplication,
            onToggle: (value) => _commit(
              SettingsKeys.danmakuDeduplication,
              DanmakuDisplayProperty.deduplication,
              value ?? !deduplication,
            ),
          ),
        ],
      ),
    );
  }
}
