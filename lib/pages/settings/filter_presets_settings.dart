import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:wyw/bean/appbar/sys_app_bar.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/pages/player/controller/video_filter_controller.dart';
import 'package:wyw/pages/player/controller/video_filter_preset.dart';
import 'package:wyw/pages/player/widgets/video_filter_widgets.dart';

/// 画面调节（滤镜预设）管理页：设置页「播放设置 → 画面调节」进入。
///
/// 本页只是**薄壳**（`Scaffold` + `AppBar` + 滚动/居中约束 + 说明文字 + 新建入口）；
/// 预设列表本身在无头的 [FilterPresetsBody] 里，与播放器分屏面板的「画面调节」
/// 二级页（`lib/pages/player/split_tabs/sub_display.dart`）共用同一份实现。
///
/// 与播放器内「画面调节」面板共用同一套控制器与滑杆：
///   - 切换 / 编辑 / 删除预设全部**实时**生效（有播放器会话时立即下发）；
///   - 每个预设可单独编辑（重命名 / 滑杆调参 / 删除）。
class FilterPresetsSettings extends StatelessWidget {
  const FilterPresetsSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: const SysAppBar(
        title: Text('画面调节'),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    '把一套画面参数存成一个滤镜预设：锐化 / 对比度 / 饱和度 / '
                    '亮度 / 伽马。切换与编辑实时生效；正在使用的预设被删除时'
                    '会立即关闭画面调节。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: VideoFilterPresetPicker(),
                ),
                const SizedBox(height: 12),
                const FilterPresetsBody(),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 画面调节·**预设管理内容体**（无头）。
///
/// 每个预设一张卡片：切换（圆点，实时生效）/ 重命名 / 删除 / 5 个参数滑杆
/// （逐刻度下发播放器）。新建入口是 [VideoFilterPresetPicker]，由外层放在本
/// 内容体之前。
///
/// 不含 `Scaffold` / `AppBar` / 滚动视图 / 标题栏——外壳与滚动方式由调用方决定，
/// 边距经 [padding] 传入（与 `VideoDetailsContent` 同一范式，**不设** `embedded`
/// 之类的开关）。两个消费者：
///   - 设置页 [FilterPresetsSettings]（薄壳，路由 `/settings/player/filters/`）；
///   - 播放器分屏面板「画面调节」二级页（面板内嵌 CRUD，不再跳页）。
class FilterPresetsBody extends StatelessWidget {
  const FilterPresetsBody({
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  /// 卡片区外边距（设置页用默认 16；面板按自身宽度传入）。
  final EdgeInsetsGeometry padding;

  Future<void> _rename(BuildContext context, VideoFilterPreset preset) async {
    final name =
        await showFilterPresetNameDialog(context, '重命名滤镜预设', preset.name);
    if (name == null || name.isEmpty || name == preset.name) return;
    VideoFilterController.instance.updatePreset(preset.id, name: name);
  }

  Future<void> _delete(BuildContext context, VideoFilterPreset preset) async {
    final confirmed = await WywDialog.showConfirm(
      title: '删除滤镜预设',
      message: '删除「${preset.name}」${preset.isNeutral ? '' : '及其参数'}；'
          '若正在使用将实时关闭画面调节。',
      confirmText: '删除',
    );
    if (!confirmed) return;
    VideoFilterController.instance.deletePreset(preset.id);
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (context) {
      final controller = VideoFilterController.instance;
      return Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final preset in controller.presets)
              _PresetCard(
                preset: preset,
                active: controller.activePresetId == preset.id,
                onSetActive: () => controller.setActivePreset(preset.id),
                onRename: () => _rename(context, preset),
                onDelete: () => _delete(context, preset),
              ),
          ],
        ),
      );
    });
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.preset,
    required this.active,
    required this.onSetActive,
    required this.onRename,
    required this.onDelete,
  });

  final VideoFilterPreset preset;
  final bool active;
  final VoidCallback onSetActive;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      decoration: BoxDecoration(
        color: active ? colors.secondaryContainer.withValues(alpha: 0.35) : colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // 活动指示（Radio 已废弃，改用图标）
              InkWell(
                onTap: onSetActive,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    active
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 22,
                    color: active ? colors.primary : colors.outline,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  preset.name,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: onRename,
                child: const Text('重命名'),
              ),
              IconButton(
                tooltip: '删除预设',
                onPressed: onDelete,
                icon: Icon(Icons.delete_outline,
                    size: 20, color: colors.error),
              ),
            ],
          ),
          VideoFilterSliders(presetId: preset.id),
        ],
      ),
    );
  }
}
