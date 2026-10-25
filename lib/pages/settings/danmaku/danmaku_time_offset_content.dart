import 'package:flutter/material.dart';

import 'package:wyw/bean/widget/tonal_card.dart';
import 'package:wyw/services/storage/storage.dart';

/// 弹幕时间偏移的取值范围（秒）与滑杆档数。
///
/// **唯一定义处**：弹层外壳（`danmaku_time_offset_sheet.dart`）与播放器分屏
/// 面板的时间偏移二级页都只挂本内容件，因此不再有第二份常量需要"手动同步"。
const double danmakuTimeOffsetMinSeconds = -180;
const double danmakuTimeOffsetMaxSeconds = 180;
const int danmakuTimeOffsetDivisions = 36;

/// 把存储里的偏移夹到合法范围并对齐到整秒。
double normalizeDanmakuTimeOffset(double value) {
  return value
      .round()
      .clamp(danmakuTimeOffsetMinSeconds, danmakuTimeOffsetMaxSeconds)
      .toDouble();
}

/// 偏移的可读文案："无偏移" / "延后 00:30" / "提前 01:00"。
String formatDanmakuTimeOffset(double value) {
  if (value == 0) {
    return '无偏移';
  }
  return '${value > 0 ? '延后' : '提前'} ${_formatDanmakuOffsetDuration(value)}';
}

String _formatDanmakuOffsetDuration(double value) {
  final totalSeconds = value.abs().round();
  final minutes = totalSeconds ~/ Duration.secondsPerMinute;
  final seconds = totalSeconds % Duration.secondsPerMinute;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

/// 弹幕时间轴校准的**无头内容件**：±1 秒微调、±3 分钟滑杆、一键恢复同步。
///
/// 只负责内容本身，**不含任何外壳**——没有底部弹层骨架、没有 `SafeArea`、
/// 没有标题栏与关闭按钮；内容外边距由调用方通过 [padding] 传入（而不是内置一个
/// `embedded` 之类的开关）。自带滚动容器（面板很矮，必须能滚），滚动边距同样由
/// [padding] 决定。
///
/// 两处宿主共用同一份实现、同一份取值范围：
///   - 播放器内「弹幕时间校准」底部弹层（`danmaku_time_offset_sheet.dart`，
///     薄外壳，边距 `materialBottomSheetContentPadding`）；
///   - 播放器分屏面板的「弹幕时间偏移」二级页（边距按面板宽度收窄）。
///
/// 值的唯一事实源是 `GStorage`（[SettingsKeys.danmakuTimeOffset]）：改动即落盘，
/// 并通过 [onTimelineOffsetChanged] 通知宿主让已排队的弹幕失效——宿主两侧传的
/// 都是 `playerController.danmaku.clearAndInvalidateScheduled`。
class DanmakuTimeOffsetContent extends StatefulWidget {
  const DanmakuTimeOffsetContent({
    super.key,
    this.onTimelineOffsetChanged,
    this.padding = EdgeInsets.zero,
  });

  /// 偏移变化后的通知（播放器侧用来作废已排队弹幕）。
  final VoidCallback? onTimelineOffsetChanged;

  /// 外壳提供的内容外边距（本件不自带外壳职责）。
  final EdgeInsetsGeometry padding;

  @override
  State<DanmakuTimeOffsetContent> createState() =>
      _DanmakuTimeOffsetContentState();
}

class _DanmakuTimeOffsetContentState extends State<DanmakuTimeOffsetContent> {
  late double _offset;

  @override
  void initState() {
    super.initState();
    final storedOffset =
        GStorage.getSetting<double>(SettingsKeys.danmakuTimeOffset);
    _offset = normalizeDanmakuTimeOffset(storedOffset);
    if (_offset != storedOffset) {
      GStorage.putSetting<double>(SettingsKeys.danmakuTimeOffset, _offset);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onTimelineOffsetChanged?.call();
        }
      });
    }
  }

  void _updateOffset(double value) {
    final offset = normalizeDanmakuTimeOffset(value);
    if (_offset == offset) {
      return;
    }
    setState(() {
      _offset = offset;
    });
    GStorage.putSetting<double>(SettingsKeys.danmakuTimeOffset, offset);
    widget.onTimelineOffsetChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SingleChildScrollView(
      padding: widget.padding,
      child: Column(children: [
        TonalCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Text(_offset == 0 ? '与视频同步' : (_offset > 0 ? '延后' : '提前'),
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: colors.onSurfaceVariant)),
              const SizedBox(height: 8),
              Row(children: [
                IconButton.filledTonal(
                  tooltip: '提前 1 秒',
                  onPressed: _offset > danmakuTimeOffsetMinSeconds
                      ? () => _updateOffset(_offset - 1)
                      : null,
                  icon: const Icon(Icons.remove_rounded),
                ),
                Expanded(
                    child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(_formatDanmakuOffsetDuration(_offset),
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: colors.onSurface,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      )),
                )),
                IconButton.filledTonal(
                  tooltip: '延后 1 秒',
                  onPressed: _offset < danmakuTimeOffsetMaxSeconds
                      ? () => _updateOffset(_offset + 1)
                      : null,
                  icon: const Icon(Icons.add_rounded),
                ),
              ]),
              const SizedBox(height: 16),
              Slider(
                value: _offset,
                min: danmakuTimeOffsetMinSeconds,
                max: danmakuTimeOffsetMaxSeconds,
                divisions: danmakuTimeOffsetDivisions,
                label: formatDanmakuTimeOffset(_offset),
                onChanged: _updateOffset,
              ),
              Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('提前 3 分钟', style: theme.textTheme.labelSmall),
                    Text('延后 3 分钟', style: theme.textTheme.labelSmall),
                  ]),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _offset != 0 ? () => _updateOffset(0) : null,
          child: const Text('恢复同步'),
        ),
      ]),
    );
  }
}
