/// 画面调节滤镜预设：一组可调参数，映射为一个 GPU 着色器（mpv 用户着色器）
/// 的 `#pragma parameter` 值表。
///
/// 参数语义与 mpv/ffmpeg 滤镜对齐：
///   - sharpness 锐化：0.0..2.0（0 = 关闭；unsharp 的 luma_amount）
///   - contrast 对比度：0.0..2.0（1 = 原样）
///   - saturation 饱和度：0.0..2.0（1 = 原样）
///   - brightness 亮度：-1.0..1.0（0 = 原样；**画面**亮度，不是屏幕亮度）
///   - gamma 伽马：0.2..3.0（1 = 原样）
class VideoFilterPreset {
  final String id;
  String name;
  double sharpness;
  double contrast;
  double saturation;
  double brightness;
  double gamma;

  VideoFilterPreset({
    required this.id,
    required this.name,
    this.sharpness = 0,
    this.contrast = 1,
    this.saturation = 1,
    this.brightness = 0,
    this.gamma = 1,
  });

  VideoFilterPreset copyWith({
    String? name,
    double? sharpness,
    double? contrast,
    double? saturation,
    double? brightness,
    double? gamma,
  }) {
    return VideoFilterPreset(
      id: id,
      name: name ?? this.name,
      sharpness: sharpness ?? this.sharpness,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      brightness: brightness ?? this.brightness,
      gamma: gamma ?? this.gamma,
    );
  }

  /// 是否全部为默认参数（等价关闭）。
  bool get isNeutral =>
      sharpness.abs() < 0.001 &&
      contrast == 1 &&
      saturation == 1 &&
      brightness == 0 &&
      gamma == 1;

  /// 转 GPU 着色器参数表；全部为默认参数（无实际效果）时返回 null。
  ///
  /// key 为 `assets/shaders/video_filters.glsl` 的参数名（`wyw_filter_*`），
  /// value 为参数值。播放器侧把当前值**烘焙**进该文件（`#define`，Anime4K
  /// v3 同款写法），再用 `change-list glsl-shaders remove` + `append` 强制
  /// mpv 重新加载——路径不变时 `set` 会被判定为"链无变化"而跳过重载，
  /// `glsl-shader-opts` 运行时修改同样不触发重载。
  /// 始终返回完整 5 键，避免切换预设时残留上一个预设的非默认值。
  Map<String, double>? toShaderParams() {
    if (isNeutral) return null;
    return {
      'wyw_filter_sharpness': sharpness,
      'wyw_filter_contrast': contrast,
      'wyw_filter_saturation': saturation,
      'wyw_filter_brightness': brightness,
      'wyw_filter_gamma': gamma,
    };
  }

  Map<String, dynamic> toJson() => {        'id': id,
        'name': name,
        'sharpness': sharpness,
        'contrast': contrast,
        'saturation': saturation,
        'brightness': brightness,
        'gamma': gamma,
      };

  factory VideoFilterPreset.fromJson(Map<String, dynamic> m) {
    return VideoFilterPreset(
      id: m['id'] as String? ?? '',
      name: m['name'] as String? ?? '',
      sharpness: ((m['sharpness'] as num?)?.toDouble() ?? 0).clamp(0, 2),
      contrast: ((m['contrast'] as num?)?.toDouble() ?? 1).clamp(0, 2),
      saturation: ((m['saturation'] as num?)?.toDouble() ?? 1).clamp(0, 2),
      brightness: ((m['brightness'] as num?)?.toDouble() ?? 0).clamp(-1, 1),
      gamma: ((m['gamma'] as num?)?.toDouble() ?? 1).clamp(0.2, 3),
    );
  }
}
