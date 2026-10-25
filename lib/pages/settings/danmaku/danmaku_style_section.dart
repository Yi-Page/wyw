import 'package:flutter/material.dart';

import 'package:wyw/bean/settings/settings_list.dart';
import 'package:wyw/services/storage/storage.dart';

/// 弹幕「样式」的共用内容件——设置页与播放器分屏面板的「弹幕设置」tab
/// **唯一一份**实现（原来是内联在设置页里的，面板拿不到）。
///
/// 与 [DanmakuDisplaySection] 一样：**永远无头**，外边距由外壳经 [padding] 传入。
///
/// **不需要 `onChanged`**：这四项都会在约 1 秒内自己生效，无需外壳代劳——
///   - 描边 / 描边粗细 / 字重 → 进画布 `DanmakuOption`，播放循环每秒比对的选项签名
///     里已包含它们（`PlayerDanmakuController.syncCanvasOptionIfChanged`）；
///   - 弹幕颜色 → 发送每条弹幕时现读（`player_item.dart`），下一条即刻生效。
class DanmakuStyleSection extends StatefulWidget {
  const DanmakuStyleSection({
    super.key,
    this.padding = EdgeInsets.zero,
  });

  /// 外壳提供的外边距（本件不自带外壳职责）。
  final EdgeInsetsGeometry padding;

  @override
  State<DanmakuStyleSection> createState() => _DanmakuStyleSectionState();
}

class _DanmakuStyleSectionState extends State<DanmakuStyleSection> {
  static const String _sectionTitle = '弹幕样式';

  /// 写盘 + 重建回显。
  ///
  /// 值不从 State 字段读，而是 build 时重新读存储——这样「恢复默认设置」之类的
  /// **外部改写**也能立刻反映出来（照 [DanmakuDisplaySection] 的口径）。
  Future<void> _write<T extends Object>(SettingKey<T> key, T value) async {
    await GStorage.putSetting<T>(key, value);
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final border = GStorage.getSetting(SettingsKeys.danmakuBorder);
    final borderSize = GStorage.getSetting(SettingsKeys.danmakuBorderSize);
    final color = GStorage.getSetting(SettingsKeys.danmakuColor);
    final fontWeight = GStorage.getSetting(SettingsKeys.danmakuFontWeight);

    return Padding(
      padding: widget.padding,
      child: SettingsSection(
        title: const Text(_sectionTitle),
        margin: EdgeInsets.zero,
        tiles: [
          SettingsTile.switchTile(
            leading: Icons.border_color_rounded,
            title: const Text('弹幕描边'),
            initialValue: border,
            onToggle: (value) =>
                _write<bool>(SettingsKeys.danmakuBorder, value ?? !border),
          ),
          SettingsSliderTile(
            leading: Icons.line_weight_rounded,
            title: const Text('弹幕描边粗细'),
            value: borderSize,
            min: _borderSizeMin,
            max: _borderSizeMax,
            divisions: _borderSizeDivisions,
            valueLabel: borderSize.toStringAsFixed(1),
            onChanged: (value) => _write<double>(
              SettingsKeys.danmakuBorderSize,
              double.parse(value.toStringAsFixed(1)),
            ),
          ),
          SettingsTile.switchTile(
            leading: Icons.palette_rounded,
            title: const Text('弹幕颜色'),
            initialValue: color,
            onToggle: (value) =>
                _write<bool>(SettingsKeys.danmakuColor, value ?? !color),
          ),
          SettingsSliderTile(
            leading: Icons.format_bold_rounded,
            title: const Text('字体字重'),
            value: fontWeight.toDouble(),
            min: _fontWeightMin,
            max: _fontWeightMax,
            divisions: _fontWeightDivisions,
            valueLabel: '$fontWeight',
            onChanged: (value) =>
                _write<int>(SettingsKeys.danmakuFontWeight, value.toInt()),
          ),
        ],
      ),
    );
  }
}

/// 描边粗细的滑块范围（沿用设置页原值）。
const double _borderSizeMin = 0.1;
const double _borderSizeMax = 3;
const int _borderSizeDivisions = 29;

/// 字重滑块范围：存的是 `FontWeight.values` 的下标。
const double _fontWeightMin = 1;
const double _fontWeightMax = 9;
const int _fontWeightDivisions = 8;
