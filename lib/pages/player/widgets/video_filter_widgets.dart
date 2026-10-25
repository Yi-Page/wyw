import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:wyw/pages/player/controller/video_filter_controller.dart';
import 'package:wyw/pages/player/controller/video_filter_preset.dart';

/// 画面调节滑杆组：编辑指定预设的参数，每个刻度**实时**下发到播放器
/// （活动预设由控制器在 updatePreset 时即时 apply）。
class VideoFilterSliders extends StatelessWidget {
  const VideoFilterSliders({super.key, required this.presetId});

  final String presetId;

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (context) {
      final controller = VideoFilterController.instance;
      VideoFilterPreset? preset;
      for (final p in controller.presets) {
        if (p.id == presetId) {
          preset = p;
          break;
        }
      }
      if (preset == null) {
        return const SizedBox.shrink();
      }
      final theme = Theme.of(context);
      Widget slider(
        String label,
        double value,
        double min,
        double max,
        ValueChanged<double> onChanged,
      ) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                child: Text(label, style: theme.textTheme.bodyMedium),
              ),
              Expanded(
                child: Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  onChanged: onChanged,
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  value.toStringAsFixed(2),
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        );
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          slider('锐化', preset.sharpness, 0, 2,
              (v) => controller.updatePreset(presetId, sharpness: v)),
          slider('对比度', preset.contrast, 0, 2,
              (v) => controller.updatePreset(presetId, contrast: v)),
          slider('饱和度', preset.saturation, 0, 2,
              (v) => controller.updatePreset(presetId, saturation: v)),
          slider('亮度', preset.brightness, -1, 1,
              (v) => controller.updatePreset(presetId, brightness: v)),
          slider('伽马', preset.gamma, 0.2, 3,
              (v) => controller.updatePreset(presetId, gamma: v)),
        ],
      );
    });
  }
}

/// 滤镜预设选择条：关闭 + 各预设（ChoiceChip，点击切换实时生效）+ 新建。
class VideoFilterPresetPicker extends StatelessWidget {
  const VideoFilterPresetPicker({super.key});

  Future<void> _create(BuildContext context) async {
    final controller = VideoFilterController.instance;
    final name = await showFilterPresetNameDialog(context, '新建滤镜预设', '');
    if (name == null || !context.mounted) return;
    final id = controller.addPreset(name: name);
    controller.setActivePreset(id);
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (context) {
      final controller = VideoFilterController.instance;
      final active = controller.activePresetId;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ChoiceChip(
            label: const Text('关闭'),
            selected: active.isEmpty,
            onSelected: (_) => controller.setActivePreset(''),
          ),
          for (final preset in controller.presets)
            ChoiceChip(
              label: Text(preset.name),
              selected: active == preset.id,
              onSelected: (_) => controller.setActivePreset(preset.id),
            ),
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: const Text('新建'),
            onPressed: () => _create(context),
          ),
        ],
      );
    });
  }
}

/// 预设命名输入弹窗；返回 null 表示取消。
Future<String?> showFilterPresetNameDialog(
  BuildContext context,
  String title,
  String initial,
) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 20,
        decoration: const InputDecoration(hintText: '预设名称'),
        onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: const Text('确定'),
        ),
      ],
    ),
  );
}
