// ignore_for_file: library_private_types_in_public_api
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:mobx/mobx.dart';
import 'package:wyw/pages/player/controller/video_filter_preset.dart';
import 'package:wyw/services/storage/storage.dart';

part 'video_filter_controller.g.dart';

/// 画面调节滤镜预设控制器（单例）。
///
/// 职责：
///   - 持有预设列表与当前活动预设（'' = 关闭滤镜），JSON 持久化到设置；
///   - 播放器侧注册 [applyVf] 回调后，切换 / 编辑 / 删除活动预设都**实时**
///     向播放器下发（编辑中的活动预设每个滑杆刻度即时生效）。
class VideoFilterController extends _VideoFilterController
    with _$VideoFilterController {
  VideoFilterController() : super();

  static final VideoFilterController instance = VideoFilterController();
}

abstract class _VideoFilterController with Store {
  _VideoFilterController() {
    _load();
  }

  /// 持久化防抖：滑杆拖动只写一次。
  static const Duration _persistDebounce = Duration(milliseconds: 300);

  // 预设列表用 [ObservableList] 直接承载（不加 `@observable`，同 plugin_controller
  // 的模式）：列表内容变化即可让 Observer 重建。
  final ObservableList<VideoFilterPreset> presets = ObservableList<VideoFilterPreset>();

  /// 当前活动的预设 id；'' = 关闭滤镜。
  @observable
  String activePresetId = '';

  /// 播放器侧注册的应用入口（参数为着色器参数表；null = 关闭滤镜）。
  void Function(Map<String, double>? params)? applyVf;

  Timer? _persistTimer;

  VideoFilterPreset? get activePreset {
    for (final p in presets) {
      if (p.id == activePresetId) return p;
    }
    return null;
  }

  /// 当前应下发的着色器参数表；null = 不启用。
  Map<String, double>? get activeVf => activePreset?.toShaderParams();

  /// 播放器初始化完成后重新应用当前滤镜。
  void refresh() => _apply();

  void _load() {
    final raw = GStorage.getSetting<String>(SettingsKeys.videoFilterPresets);
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              presets.add(VideoFilterPreset.fromJson(
                  item.cast<String, dynamic>()));
            }
          }
        }
      } catch (_) {
        // 数据损坏：回落到默认预设
      }
    }
    if (presets.isEmpty) {
      presets.add(VideoFilterPreset(id: 'default', name: '默认'));
    }
    activePresetId =
        GStorage.getSetting<String>(SettingsKeys.videoFilterActivePresetId);
    if (activePresetId.isNotEmpty && activePreset == null) {
      activePresetId = '';
    }
  }

  void _persist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(_persistDebounce, () {
      GStorage.putSetting(
        SettingsKeys.videoFilterPresets,
        jsonEncode([for (final p in presets) p.toJson()]),
      );
      GStorage.putSetting(
          SettingsKeys.videoFilterActivePresetId, activePresetId);
    });
  }

  void _apply() => applyVf?.call(activeVf);

  /// 切换活动滤镜（'' = 关闭），实时生效。
  void setActivePreset(String id) {
    if (id.isNotEmpty && !presets.any((p) => p.id == id)) {
      return;
    }
    activePresetId = id;
    _persist();
    _apply();
  }

  /// 新建预设（默认参数，或复制 [from] 的参数），返回新预设 id。
  String addPreset({String? name, VideoFilterPreset? from}) {
    final source = from ?? activePreset;
    final preset = VideoFilterPreset(
      id: 'f${DateTime.now().microsecondsSinceEpoch}',
      name: (name == null || name.trim().isEmpty)
          ? '新滤镜 ${presets.length + 1}'
          : name.trim(),
      sharpness: source?.sharpness ?? 0,
      contrast: source?.contrast ?? 1,
      saturation: source?.saturation ?? 1,
      brightness: source?.brightness ?? 0,
      gamma: source?.gamma ?? 1,
    );
    presets.add(preset);
    _persist();
    return preset.id;
  }

  /// 编辑预设（名称 / 参数）；编辑**活动**预设时实时生效。
  void updatePreset(
    String id, {
    String? name,
    double? sharpness,
    double? contrast,
    double? saturation,
    double? brightness,
    double? gamma,
  }) {
    final index = presets.indexWhere((p) => p.id == id);
    if (index < 0) return;
    final current = presets[index];
    presets[index] = current.copyWith(
      name: name,
      sharpness: sharpness,
      contrast: contrast,
      saturation: saturation,
      brightness: brightness,
      gamma: gamma,
    );
    _persist();
    if (id == activePresetId) {
      _apply();
    }
  }

  /// 删除预设；删除活动预设则回到「关闭」并实时清除滤镜。
  void deletePreset(String id) {
    presets.removeWhere((p) => p.id == id);
    if (activePresetId == id) {
      activePresetId = '';
      _apply();
    }
    _persist();
  }

  /// 仅测试用：还原成"刚加载"的状态（默认预设 + 空活动，不写盘），
  /// 让单例在用例之间相互独立。
  @visibleForTesting
  void reset() {
    _persistTimer?.cancel();
    presets.clear();
    presets.add(VideoFilterPreset(id: 'default', name: '默认'));
    activePresetId = '';
    applyVf = null;
  }
}
