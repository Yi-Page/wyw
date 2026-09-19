import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/bean/settings/settings_detail_scaffold.dart';
import 'package:wyw/bean/settings/settings_list.dart';
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
  final MenuController defaultPageMenuController = MenuController();
  late String initialWindowSize;
  final MenuController windowSizeMenuController = MenuController();

  static const Map<String, String> defaultPageMap = {
    '/tab/search/': '搜索',
    '/tab/browse/': '浏览',
    '/tab/my/': '我的',
  };

  @override
  void initState() {
    super.initState();
    defaultPage = GStorage.getSetting(SettingsKeys.defaultStartupPage);
    initialWindowSize = GStorage.getSetting(SettingsKeys.initialWindowSize);
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

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: const Text('界面设置'),
      body: SettingsList(
        sections: [
          SettingsSection(
            title: const Text('启动'),
            tiles: [
              SettingsTile(
                leading: Icons.home_rounded,
                onPressed: (_) async {
                  if (defaultPageMenuController.isOpen) {
                    defaultPageMenuController.close();
                  } else {
                    defaultPageMenuController.open();
                  }
                },
                title: const Text('启动界面设置'),
                description: const Text('设置应用开启时的默认页面'),
                value: MenuAnchor(
                  consumeOutsideTap: true,
                  controller: defaultPageMenuController,
                  builder: (_, __, ___) {
                    return Text(
                      defaultPageMap[defaultPage] ?? '搜索',
                    );
                  },
                  menuChildren: [
                    for (final entry in defaultPageMap.entries)
                      MenuItemButton(
                        requestFocusOnHover: false,
                        onPressed: () => updateDefaultPage(entry.key),
                        child: Container(
                          height: 48,
                          constraints: const BoxConstraints(minWidth: 112),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              entry.value,
                              style: TextStyle(
                                color: entry.key == defaultPage
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (isDesktop())
            SettingsSection(
              title: const Text('窗口'),
              tiles: [
                SettingsTile(
                  leading: Icons.open_in_full_rounded,
                  onPressed: (_) {
                    if (windowSizeMenuController.isOpen) {
                      windowSizeMenuController.close();
                    } else {
                      windowSizeMenuController.open();
                    }
                  },
                  title: const Text('初始窗口大小'),
                  description: const Text('设置应用启动时的窗口大小，重启应用后生效'),
                  value: MenuAnchor(
                    consumeOutsideTap: true,
                    controller: windowSizeMenuController,
                    builder: (_, __, ___) {
                      return Text(
                        initialWindowSizePresets[initialWindowSize] ??
                            '自动（跟随屏幕）',
                      );
                    },
                    menuChildren: [
                      for (final entry in initialWindowSizePresets.entries)
                        MenuItemButton(
                          requestFocusOnHover: false,
                          onPressed: () => updateInitialWindowSize(entry.key),
                          child: Container(
                            height: 48,
                            constraints: const BoxConstraints(minWidth: 160),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                entry.value,
                                style: TextStyle(
                                  color: entry.key == initialWindowSize
                                      ? Theme.of(context).colorScheme.primary
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
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
