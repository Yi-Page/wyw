import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:window_manager/window_manager.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/bean/settings/settings_detail_scaffold.dart';
import 'package:wyw/bean/settings/settings_list.dart';
import 'package:wyw/bean/widget/select_field.dart';
import 'package:wyw/pages/plugin/plugin_controller.dart';
import 'package:wyw/plugins/plugin_display_mode.dart';
import 'package:wyw/services/platform/screen_orientation.dart';
import 'package:wyw/services/storage/storage.dart';
import 'package:wyw/utils/constants.dart';
import 'package:wyw/utils/device.dart';

class InterfaceSettingsPage extends StatefulWidget {
  const InterfaceSettingsPage({super.key});

  @override
  State<InterfaceSettingsPage> createState() => _InterfaceSettingsPageState();
}

class _InterfaceSettingsPageState extends State<InterfaceSettingsPage> {
  late String defaultPage;
  late String initialWindowSize;
  late String pluginNameDisplay;
  late String appOrientation;
  late String playerOrientation;
  late String readerOrientation;
  late String landscapeSide;

  final PluginController _pluginController = inject<PluginController>();
  final ScreenOrientationService _orientation =
      ScreenOrientationService.instance;

  static const Map<String, String> defaultPageMap = {
    '/tab/search/': '搜索',
    '/tab/browse/': '浏览',
    '/tab/my/': '我的',
  };

  /// 插件名称显示方式（见 `PluginController.displayNameOf`）
  static const Map<String, String> pluginNameDisplayMap = {
    PluginNameDisplayMode.display: '插件展示名',
    PluginNameDisplayMode.identity: '插件名（文件名 / 类名）',
  };

  @override
  void initState() {
    super.initState();
    defaultPage = GStorage.getSetting(SettingsKeys.defaultStartupPage);
    initialWindowSize = GStorage.getSetting(SettingsKeys.initialWindowSize);
    pluginNameDisplay = _pluginController.useDisplayName
        ? PluginNameDisplayMode.display
        : PluginNameDisplayMode.identity;
    appOrientation = GStorage.getSetting(SettingsKeys.appScreenOrientation);
    playerOrientation =
        GStorage.getSetting(SettingsKeys.playerScreenOrientation);
    readerOrientation =
        GStorage.getSetting(SettingsKeys.readerScreenOrientation);
    landscapeSide = GStorage.getSetting(SettingsKeys.landscapeDefaultSide);
  }

  void updateDefaultPage(String page) {
    GStorage.putSetting(SettingsKeys.defaultStartupPage, page);
    setState(() {
      defaultPage = page;
    });
  }

  void updateInitialWindowSize(String value) {
    GStorage.putSetting(SettingsKeys.initialWindowSize, value);
    setState(() {
      initialWindowSize = value;
    });
  }

  /// 走 controller 而不是直接写 GStorage：controller 要同时更新内存值并通知
  /// 各页面重建（搜索页 tab、浏览页 tab、历史卡片都依赖它）。
  Future<void> updatePluginNameDisplay(String mode) async {
    await _pluginController.setPluginNameDisplay(mode);
    if (!mounted) return;
    setState(() {
      pluginNameDisplay = mode;
    });
  }

  /// 不重启，直接将窗口调整为当前选择的预设大小。
  Future<void> _applyWindowSizeNow() async {
    final size = initialWindowSizeSizes[initialWindowSize];
    if (size == null) {
      WywDialog.showToast(message: '自动模式下无固定大小，请先选择具体尺寸');
      return;
    }
    await windowManager.setSize(size);
    await windowManager.center();
    if (mounted) {
      WywDialog.showToast(
          message: '已调整为 ${size.width.toInt()} × ${size.height.toInt()}');
    }
  }

  Future<void> _updateAppOrientation(String value) async {
    await GStorage.putSetting(SettingsKeys.appScreenOrientation, value);
    if (!mounted) return;
    setState(() => appOrientation = value);
    // 立即生效（播放器 / 阅读器占用方向时不抢栈顶，退出时自然落回新值）。
    await _orientation.reloadFromSettings();
  }

  Future<void> _updatePlayerOrientation(String value) async {
    await GStorage.putSetting(SettingsKeys.playerScreenOrientation, value);
    if (!mounted) return;
    setState(() => playerOrientation = value);
  }

  Future<void> _updateReaderOrientation(String value) async {
    await GStorage.putSetting(SettingsKeys.readerScreenOrientation, value);
    if (!mounted) return;
    setState(() => readerOrientation = value);
  }

  Future<void> _updateLandscapeSide(String value) async {
    await GStorage.putSetting(SettingsKeys.landscapeDefaultSide, value);
    if (!mounted) return;
    setState(() => landscapeSide = value);
    await _orientation.reloadFromSettings();
  }

  /// 三处方向里有没有人选了「横屏锁定」——没有的话「横屏默认方向」是死设置。
  bool get _landscapeSideApplies =>
      appOrientation == ScreenOrientationPolicy.landscape.id ||
      playerOrientation == ScreenOrientationPolicy.landscape.id ||
      readerOrientation == ScreenOrientationPolicy.landscape.id;

  /// 「屏幕方向」分组。
  ///
  /// 方向能力是移动端的事（桌面端窗口方向由窗口管理器管），桌面不显示这一组。
  Widget _orientationSection() {
    return ListenableBuilder(
      listenable: _orientation,
      builder: (context, _) {
        final followSystem = appOrientation == ScreenOrientationPolicy.system.id;
        final systemRotationOff =
            followSystem && !_orientation.systemAutoRotateEnabled;
        return SettingsSection(
          title: const Text('屏幕方向'),
          tiles: [
            SelectTile<String>(
              leading: Icons.screen_rotation_rounded,
              title: const Text('应用方向'),
              description: const Text(
                  '播放器 / 阅读器之外界面的方向。跟随系统：系统「自动旋转」开着才转；'
                  '自由旋转：覆盖系统开关，随传感器转；横屏 / 竖屏锁定：钉死一侧'),
              value: appOrientation,
              placeholder: '跟随系统',
              options: [
                for (final policy in ScreenOrientationPolicy.values)
                  SelectOption(value: policy.id, label: policy.label),
              ],
              onChanged: _updateAppOrientation,
            ),
            if (systemRotationOff)
              const SettingsTile(
                leading: Icons.info_outline_rounded,
                title: Text('系统「自动旋转」当前是关闭的'),
                description: Text(
                    '「跟随系统」时屏幕不会跟随设备旋转。要让这些界面也能转，选「自由旋转」，'
                    '或在系统快捷开关里打开自动旋转'),
                enabled: false,
              ),
            SelectTile<String>(
              leading: Icons.movie_filter_rounded,
              title: const Text('播放器默认方向'),
              description: const Text(
                  '进入播放页时按哪一档；播放页内的方向按钮可临时改（不影响这里）'),
              value: playerOrientation,
              placeholder: '自由旋转',
              options: [
                for (final policy in pageOrientationPolicies)
                  SelectOption(value: policy.id, label: policy.label),
              ],
              onChanged: _updatePlayerOrientation,
            ),
            SelectTile<String>(
              leading: Icons.auto_stories_rounded,
              title: const Text('漫画阅读器默认方向'),
              description: const Text('进入漫画阅读器时按哪一档；阅读器内的方向按钮可临时改'),
              value: readerOrientation,
              placeholder: '竖屏锁定',
              options: [
                for (final policy in pageOrientationPolicies)
                  SelectOption(value: policy.id, label: policy.label),
              ],
              onChanged: _updateReaderOrientation,
            ),
            SelectTile<String>(
              leading: Icons.screen_lock_landscape_rounded,
              title: const Text('横屏锁定默认方向'),
              description: Text(
                  _landscapeSideApplies
                      ? '横屏锁定时默认朝哪一侧；播放页与阅读器内可随时切到对侧'
                      : '当前三处方向都没有选「横屏锁定」，这一项暂不生效'),
              value: landscapeSide,
              placeholder: '左',
              enabled: _landscapeSideApplies,
              options: [
                for (final side in LandscapeSide.values)
                  SelectOption(value: side.id, label: side.label),
              ],
              onChanged: _updateLandscapeSide,
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: const Text('界面设置'),
      body: SettingsList(
        sections: [
          SettingsSection(
            title: const Text('启动'),
            tiles: [
              SelectTile<String>(
                leading: Icons.home_rounded,
                title: const Text('启动界面设置'),
                description: const Text('设置应用开启时的默认页面'),
                value: defaultPage,
                placeholder: '搜索',
                options: [
                  for (final entry in defaultPageMap.entries)
                    SelectOption(value: entry.key, label: entry.value),
                ],
                onChanged: updateDefaultPage,
              ),
            ],
          ),
          if (!isDesktop()) _orientationSection(),
          SettingsSection(
            title: const Text('插件'),
            tiles: [
              SelectTile<String>(
                leading: Icons.extension_rounded,
                title: const Text('插件名称显示'),
                description: const Text(
                    '界面上的插件名称用哪个：展示名（可自定义）还是插件名（文件名 / JS 类名）'),
                value: pluginNameDisplay,
                placeholder: '插件展示名',
                options: [
                  for (final entry in pluginNameDisplayMap.entries)
                    SelectOption(value: entry.key, label: entry.value),
                ],
                onChanged: updatePluginNameDisplay,
              ),
            ],
          ),
          if (isDesktop())
            SettingsSection(
              title: const Text('窗口'),
              tiles: [
                SelectTile<String>(
                  leading: Icons.open_in_full_rounded,
                  title: const Text('初始窗口大小'),
                  description: const Text('设置应用启动时的窗口大小，重启应用后生效'),
                  value: initialWindowSize,
                  placeholder: '自动（跟随屏幕）',
                  options: [
                    for (final entry in initialWindowSizePresets.entries)
                      SelectOption(value: entry.key, label: entry.value),
                  ],
                  onChanged: updateInitialWindowSize,
                ),
                SettingsTile(
                  leading: Icons.check_rounded,
                  onPressed: (_) => _applyWindowSizeNow(),
                  title: const Text('立即应用窗口大小'),
                  description: const Text('不重启，直接将窗口调整为当前选择的尺寸'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
