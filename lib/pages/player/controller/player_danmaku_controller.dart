// ignore_for_file: library_private_types_in_public_api

import 'dart:ui' show FontWeight;

import 'package:canvas_danmaku/canvas_danmaku.dart' as canvas;
import 'package:mobx/mobx.dart';
import 'package:wyw/modules/danmaku/danmaku_module.dart';
import 'package:wyw/repositories/danmaku_shield_repository.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/services/storage/storage.dart';
import 'package:wyw/utils/constants.dart';
import 'package:wyw/utils/danmaku.dart';

part 'player_danmaku_controller.g.dart';

class PlayerDanmakuController = _PlayerDanmakuController
    with _$PlayerDanmakuController;

/// 弹幕时间轴换算。
///
/// 单独抽成纯函数是为了能脱离播放器与画布单测：弹幕时间轴对齐是弹幕功能
/// 最容易出错、也最难在真机上复现的部分。
abstract final class DanmakuTimeline {
  /// 播放位置 → 弹幕库中的秒数。
  ///
  /// [timelineOffsetSeconds] 为正表示"弹幕比视频晚 N 秒"，用户用它对齐
  /// 片头/广告造成的偏移。换算结果小于 0 表示该位置还没有弹幕，返回 null。
  static int? resolveSourceSecond(
    Duration playbackPosition,
    double timelineOffsetSeconds,
  ) {
    final sourceMilliseconds =
        playbackPosition.inMilliseconds - (timelineOffsetSeconds * 1000).round();
    if (sourceMilliseconds < 0) {
      return null;
    }
    return Duration(milliseconds: sourceMilliseconds).inSeconds;
  }

  /// 同一秒内多条弹幕的错峰延迟，避免瞬间齐发糊成一片。
  static int staggerDelayMilliseconds({
    required int index,
    required int total,
  }) {
    if (total <= 0) {
      return 0;
    }
    return index * 1000 ~/ total;
  }
}

abstract class _PlayerDanmakuController with Store {
  /// 按"整秒"分桶存放弹幕。
  ///
  /// 播放位置每秒才轮询一次，桶化后取当前秒只需一次 Map 查找，不必在播放
  /// 循环里遍历全部弹幕。
  final Map<int, List<DanmakuEntry>> _danmakusBySecond = {};

  /// 上一次灌进来的**去重前**原始弹幕。
  ///
  /// 留它是为了让「弹幕去重」开关在播放中能立刻生效（[reapplyDanmakuDeduplication]）：
  /// 合并发生在写入桶时，没有原始列表就只能重新联网取一次。一集通常几千条，
  /// 且换集/复位时会被一起替换。
  List<DanmakuEntry> _rawDanmakus = const [];

  int _scheduledGeneration = 0;
  bool _disposed = false;

  /// 已经应用到画布上的选项签名，用于判断设置是否真的变了（见
  /// [syncCanvasOptionIfChanged]）。
  String? _appliedOptionSignature;

  /// 弹幕开关（画布是否显示弹幕）。
  @observable
  bool danmakuOn = false;

  /// 弹幕加载中（用于 UI 显示进度）。
  @observable
  bool danmakuLoading = false;

  /// 当前使用的弹弹play 弹幕库编号（episodeId）；0 表示尚未匹配到弹幕库。
  @observable
  int danmakuEpisodeId = 0;

  /// 当前弹幕库的作品名，仅用于 UI 展示"当前用的是哪个库"。
  @observable
  String danmakuLibraryTitle = '';

  /// 弹幕画布控制器，由 `DanmakuScreen` 建好画布后回调注入。
  ///
  /// 画布未构建时保持 null，此时所有画布操作（清屏、暂停、改设置）都静默跳过 ——
  /// 播放页在画布出现前就可能触发换集/跳转，不能假设它一定存在。
  canvas.DanmakuController<dynamic>? canvasController;

  /// 是否已经拿到画布控制器（`DanmakuScreen` 尚未构建时为 false）。
  bool get hasCanvas => canvasController != null;

  /// 已加载的弹幕条数。
  int get danmakuCount =>
      _danmakusBySecond.values.fold(0, (sum, list) => sum + list.length);

  /// 「当前用的是哪个库」的状态文案。
  ///
  /// 播放器顶栏、弹幕 tab、弹幕设置 tab 读同一份。历史上这段判断曾在各调用处
  /// 各写一遍，漏掉 `danmakuLoading` 的那一处就会在加载中显示"未匹配"。
  String get libraryLabel {
    if (danmakuLoading) {
      return '弹幕加载中…';
    }
    if (danmakuEpisodeId == 0) {
      return '未匹配弹幕库';
    }
    return danmakuLibraryTitle.isEmpty ? '已匹配弹幕库' : danmakuLibraryTitle;
  }

  /// 每次清屏/跳转都会自增；播放循环排队的延迟任务据此判断自己是否已过期。
  int get scheduledGeneration => _scheduledGeneration;

  double get timelineOffsetSeconds =>
      GStorage.getSetting(SettingsKeys.danmakuTimeOffset);

  /// 当前屏蔽词。
  ///
  /// 每次都重新读存储而不是缓存：用户可能在后台播放/画中画时正好去设置页加了
  /// 一条，缓存住会让它在整轮播放里都不生效。读取的是内存里的 Hive 箱，代价很小；
  /// 播放循环每轮只取一次，不是每条弹幕取一次。
  List<String> get shieldRules => DanmakuShieldRepository.instance.rules();

  /// 按当前设置构造画布选项。
  ///
  /// 画布的 3 个"显示/隐藏"开关与设置项语义相反（设置里是"显示顶部弹幕"，
  /// 画布要的是"隐藏顶部弹幕"），这里统一取反，避免调用处各写一遍。
  /// [compactLayout] 用于让字号在小屏下取更小的默认值。
  canvas.DanmakuOption resolveCanvasOption({required bool compactLayout}) {
    final useSystemFont = GStorage.getSetting(SettingsKeys.useSystemFont);
    return canvas.DanmakuOption(
      hideTop: !GStorage.getSetting(SettingsKeys.danmakuTop),
      hideScroll: !GStorage.getSetting(SettingsKeys.danmakuScroll),
      hideBottom: !GStorage.getSetting(SettingsKeys.danmakuBottom),
      area: GStorage.getSetting(SettingsKeys.danmakuArea),
      opacity: GStorage.getSetting(SettingsKeys.danmakuOpacity),
      fontSize: GStorage.getSetting(
        SettingsKeys.danmakuFontSize,
        context: SettingContext(compactLayout: compactLayout),
      ),
      duration: GStorage.getSetting(SettingsKeys.danmakuDuration),
      lineHeight: GStorage.getSetting(SettingsKeys.danmakuLineHeight),
      strokeWidth: GStorage.getSetting(SettingsKeys.danmakuBorder)
          ? GStorage.getSetting(SettingsKeys.danmakuBorderSize)
          : 0.0,
      // 字重存的是 FontWeight.values 的下标，画布包按 values[i] 取值，
      // 越界会抛 RangeError —— 这里夹一次，坏数据不至于让弹幕整层崩掉。
      fontWeight: GStorage.getSetting(SettingsKeys.danmakuFontWeight)
          .clamp(0, FontWeight.values.length - 1),
      massiveMode: GStorage.getSetting(SettingsKeys.danmakuMassive),
      fontFamily: useSystemFont ? null : customAppFontFamily,
    );
  }

  /// 播放中同步画布设置。
  ///
  /// 用户可能在播放页存活时改设置（后台播放、画中画，或从设置页返回），
  /// 那时画布已经建好了，`DanmakuScreen` 只认 `option` 的初始值，不会自己
  /// 重新读设置。这里每秒比对一次轻量签名，**只有真的变了**才调
  /// `updateOption` —— 该调用在画布包内部会做大量差异处理（必要时清空已渲染
  /// 的弹幕），不能无脑每秒调一次。
  void syncCanvasOptionIfChanged({required bool compactLayout}) {
    final controller = canvasController;
    if (controller == null) return;
    final resolved = resolveCanvasOption(compactLayout: compactLayout);
    final signature = _optionSignature(resolved);
    if (signature == _appliedOptionSignature) return;
    _appliedOptionSignature = signature;
    controller.updateOption(resolved);
  }

  static String _optionSignature(canvas.DanmakuOption option) {
    return '${option.fontSize}|${option.fontWeight}|${option.fontFamily}'
        '|${option.area}|${option.duration}|${option.opacity}'
        '|${option.hideTop}|${option.hideBottom}|${option.hideScroll}'
        '|${option.strokeWidth}|${option.massiveMode}|${option.lineHeight}';
  }

  int? resolveDanmakuSecond(Duration playbackPosition) {
    return DanmakuTimeline.resolveSourceSecond(
      playbackPosition,
      timelineOffsetSeconds,
    );
  }

  List<DanmakuEntry> danmakusForPlaybackPosition(Duration playbackPosition) {
    final second = resolveDanmakuSecond(playbackPosition);
    if (second == null) {
      return const [];
    }
    return _danmakusBySecond[second] ?? const [];
  }

  /// 弹幕来源是否被用户允许显示。
  ///
  /// 官方 API 里 `p` 串第 4 段是"用户ID"，但弹弹play 合并第三方弹幕时也可能
  /// 放进来源名，所以这里按"能不能解析成数字"区分两种情况：数字（用户ID）
  /// 只能归到弹弹play 自己那一档，否则按来源名匹配。这样三个开关都不会
  /// 变成"关掉就没弹幕"的假功能。
  bool isSourceEnabled(DanmakuEntry danmaku) {
    final source = danmaku.source;
    final looksLikeSource = source.isNotEmpty && int.tryParse(source) == null;
    if (!looksLikeSource) {
      return GStorage.getSetting(SettingsKeys.danmakuDanDanSource);
    }
    if (source.contains('BiliBili')) {
      return GStorage.getSetting(SettingsKeys.danmakuBiliBiliSource);
    }
    if (source.contains('Gamer')) {
      return GStorage.getSetting(SettingsKeys.danmakuGamerSource);
    }
    return GStorage.getSetting(SettingsKeys.danmakuDanDanSource);
  }

  @action
  void setDanmakuEnabled(bool value) {
    danmakuOn = value;
  }

  @action
  void setDanmakuLoading(bool value) {
    danmakuLoading = value;
  }

  /// 换集/跳转时清空画布，并让已排队未发出的延迟弹幕全部失效。
  void clearAndInvalidateScheduled() {
    _scheduledGeneration++;
    canvasController?.clear();
  }

  /// 开始一次弹幕加载：清掉旧弹幕，避免新旧库的弹幕混在一起。
  @action
  void beginDanmakuLoad() {
    _danmakusBySecond.clear();
    _rawDanmakus = const [];
    danmakuEpisodeId = 0;
    danmakuLibraryTitle = '';
    danmakuLoading = true;
  }

  /// 应用加载结果。[enableDanmaku] 为 false 时保留数据但不显示。
  @action
  void applyDanmakuLoad(
    List<DanmakuEntry> danmakus, {
    required int episodeId,
    required String libraryTitle,
    required bool enableDanmaku,
  }) {
    _danmakusBySecond.clear();
    // 留住去重前的原始列表：播放中改「弹幕去重」时不必重新联网取一次
    // （见 [reapplyDanmakuDeduplication]）。
    _rawDanmakus = danmakus;
    addDanmakus(danmakus);
    danmakuEpisodeId = episodeId;
    danmakuLibraryTitle = libraryTitle;
    danmakuOn = enableDanmaku && _danmakusBySecond.isNotEmpty;
    danmakuLoading = false;
    WywLogger().i(
        '${LogTag.danmaku} 应用弹幕 episodeId=$episodeId 总条数=$danmakuCount 显示=$danmakuOn');
  }

  /// 加载失败/无弹幕：清空并关闭显示，但保留 [episodeId] 便于 UI 提示。
  @action
  void applyUnavailableDanmakuLoad({
    required int episodeId,
    required String libraryTitle,
  }) {
    _danmakusBySecond.clear();
    _rawDanmakus = const [];
    danmakuEpisodeId = episodeId;
    danmakuLibraryTitle = libraryTitle;
    danmakuOn = false;
    danmakuLoading = false;
  }

  /// 「弹幕去重」开关在播放中改动的即时生效：按当前设置**重新分桶**。
  ///
  /// 合并发生在写入桶的时候（[addDanmakus]），所以开关本身对已经在桶里的弹幕没有
  /// 影响——没有这个方法就只能等下次换集/重新取弹幕才生效。有原始列表就能在本地
  /// 重算，不必联网。
  ///
  /// 刻意不是 `@action`：这里只动非 observable 的桶（[danmakuCount] 是普通 getter），
  /// 外壳改完自己 setState 即可，不必为一行组合逻辑重跑代码生成。
  void reapplyDanmakuDeduplication() {
    if (_rawDanmakus.isEmpty) return;
    // 与换集同一条清理路径：已经在画的旧弹幕必须清掉，否则合并前后会同时存在。
    clearAndInvalidateScheduled();
    _danmakusBySecond.clear();
    addDanmakus(_rawDanmakus);
  }

  /// 把"这一集用哪个库"的选择整体复位（换集、读不到离线缓存时调用）。
  ///
  /// 分集映射刻意不持久化，所以换集后必须**主动复位**：否则上一集的弹幕会留在
  /// 画布上继续跑，看起来像"新一集自动带了弹幕"。清画布要连排队中的延迟任务一起
  /// 作废，所以走 [clearAndInvalidateScheduled]。
  ///
  /// 它刻意不是 `@action`：所有 observable 的写入都在下面两个方法内部完成，
  /// 这里只是把它们组合起来，这样就不必为一行组合逻辑重跑代码生成。
  void resetEpisodeSelection() {
    clearAndInvalidateScheduled();
    applyUnavailableDanmakuLoad(episodeId: 0, libraryTitle: '');
  }

  void addDanmakus(List<DanmakuEntry> danmakus) {
    final bool deduplicationEnable =
        GStorage.getSetting(SettingsKeys.danmakuDeduplication);

    final List<DanmakuEntry> listToAdd = deduplicationEnable
        ? mergeDuplicateDanmakus(danmakus, timeWindowSeconds: 5)
        : danmakus;

    for (final element in listToAdd) {
      final second = element.time.toInt();
      (_danmakusBySecond[second] ??= <DanmakuEntry>[]).add(element);
    }
  }

  /// 暂停/恢复画布动画（跟随播放器的暂停与恢复）。
  void pauseCanvas() {
    canvasController?.pause();
  }

  void resumeCanvas() {
    canvasController?.resume();
  }

  /// 播放倍速变化时同步弹幕滚动时长（开启"跟随倍速"才有意义）。
  void updateDanmakuSpeed(double playerSpeed) {
    final controller = canvasController;
    if (controller == null || playerSpeed <= 0) {
      return;
    }
    final baseDuration = GStorage.getSetting(SettingsKeys.danmakuDuration);
    final followSpeed = GStorage.getSetting(SettingsKeys.danmakuFollowSpeed);

    final duration = followSpeed ? (baseDuration / playerSpeed) : baseDuration;
    controller.updateOption(controller.option.copyWith(duration: duration));
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _scheduledGeneration++;
    _danmakusBySecond.clear();
    canvasController = null;
    _appliedOptionSignature = null;
  }
}
