import 'package:flutter_test/flutter_test.dart';
import 'package:wyw/pages/player/controller/video_filter_preset.dart';

/// 画面调节滤镜预设的模型回归：GPU 着色器参数表生成与 JSON 持久化。
void main() {
  group('toShaderParams', () {
    test('全部默认 → null（不启用滤镜）', () {
      final preset = VideoFilterPreset(id: 'x', name: '默认');
      expect(preset.isNeutral, isTrue);
      expect(preset.toShaderParams(), isNull);
    });

    test('非默认参数 → 完整 5 键参数表（含默认值项，防切换残留）', () {
      final preset = VideoFilterPreset(
          id: 'x', name: 'x', contrast: 1.2, brightness: 0.1);
      expect(preset.toShaderParams(), {
        'wyw_filter_sharpness': 0.0,
        'wyw_filter_contrast': 1.2,
        'wyw_filter_saturation': 1.0,
        'wyw_filter_brightness': 0.1,
        'wyw_filter_gamma': 1.0,
      });
    });

    test('锐化 + 色彩 → 参数表含锐化与饱和度', () {
      final preset = VideoFilterPreset(
          id: 'x', name: 'x', sharpness: 0.8, saturation: 0.9);
      final params = preset.toShaderParams();
      expect(params, isNotNull);
      expect(params!['wyw_filter_sharpness'], 0.8);
      expect(params['wyw_filter_saturation'], 0.9);
      expect(params['wyw_filter_contrast'], 1.0);
      expect(params['wyw_filter_gamma'], 1.0);
    });

    test('仅锐化 → 参数表只锐化非默认', () {
      final preset = VideoFilterPreset(id: 'x', name: 'x', sharpness: 1.2);
      final params = preset.toShaderParams();
      expect(params, isNotNull);
      expect(params!['wyw_filter_sharpness'], 1.2);
      expect(params['wyw_filter_brightness'], 0.0);
    });
  });

  group('JSON', () {
    test('roundtrip 保真', () {
      final preset = VideoFilterPreset(
        id: 'a',
        name: '测试',
        sharpness: 0.5,
        contrast: 1.3,
        saturation: 0.8,
        brightness: -0.2,
        gamma: 1.1,
      );
      final restored = VideoFilterPreset.fromJson(preset.toJson());
      expect(restored.id, 'a');
      expect(restored.name, '测试');
      expect(restored.sharpness, 0.5);
      expect(restored.contrast, 1.3);
      expect(restored.saturation, 0.8);
      expect(restored.brightness, -0.2);
      expect(restored.gamma, 1.1);
    });

    test('越界值被 clamp', () {
      final restored = VideoFilterPreset.fromJson(const {
        'id': 'x',
        'name': 'x',
        'sharpness': 9,
        'brightness': -5,
        'gamma': 0,
        'contrast': -1,
      });
      expect(restored.sharpness, 2);
      expect(restored.brightness, -1);
      expect(restored.gamma, 0.2);
      expect(restored.contrast, 0);
    });
  });
}
