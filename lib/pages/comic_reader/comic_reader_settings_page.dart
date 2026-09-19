import 'dart:io';

import 'package:flutter/material.dart';
import 'package:wyw/bean/settings/settings_detail_scaffold.dart';
import 'package:wyw/bean/settings/settings_list.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/pages/comic_reader/models/comic_reader_settings.dart';

/// 漫画阅读器设置页（"我的"页入口，见 settingsModule 的 /settings/comic-reader）。
///
/// 与阅读器内设置面板（_ComicReaderSettingsPanel）读写同一批
/// ComicReaderSettings 键，效果实时互通；本页无阅读器实例，
/// 修改后下次打开阅读器生效。
class ComicReaderSettingsPage extends StatefulWidget {
  const ComicReaderSettingsPage({super.key});

  @override
  State<ComicReaderSettingsPage> createState() =>
      _ComicReaderSettingsPageState();
}

class _ComicReaderSettingsPageState extends State<ComicReaderSettingsPage> {
  static const Map<String, String> _readerModes = {
    'galleryLeftToRight': '分页（从左到右）',
    'galleryRightToLeft': '分页（从右到左）',
    'galleryTopToBottom': '分页（从上到下）',
    'continuousLeftToRight': '连续（从左到右）',
    'continuousRightToLeft': '连续（从右到左）',
    'continuousTopToBottom': '连续（从上到下）',
  };

  final MenuController _readerModeMenu = MenuController();
  final MenuController _zoomPositionMenu = MenuController();

  /// 设置变更后触发自身重建，让各设置项（开关/下拉/滑块）显示实时更新。
  void _handleChanged(String key) {
    setState(() {});
  }

  Widget _switchTile(String title, String key, IconData icon) {
    return SettingsTile.switchTile(
      leading: icon,
      title: Text(title),
      initialValue: ComicReaderSettings.getBool(key),
      onToggle: (value) async {
        ComicReaderSettings.set(
            key, value ?? !ComicReaderSettings.getBool(key));
        _handleChanged(key);
      },
    );
  }

  Widget _menuItem(String text, bool selected, ColorScheme colorScheme) {
    return Container(
      height: 48,
      constraints: const BoxConstraints(minWidth: 112),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: TextStyle(
            color: selected ? colorScheme.primary : null,
          ),
        ),
      ),
    );
  }

  /// 恢复默认：确认弹窗 -> 删除全部持久化设置 -> 刷新本页。
  Future<void> _resetSettings() async {
    final shouldReset = await WywDialog.showConfirm(
      title: '恢复默认漫画阅读器设置',
      message: '阅读模式、翻页、缩放、性能与显示等参数将恢复为默认值。',
      confirmText: '恢复默认',
    );
    if (!shouldReset) return;
    await ComicReaderSettings.resetAll();
    if (!mounted) return;
    setState(() {});
    WywDialog.showToast(message: '已恢复默认漫画阅读器设置');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentMode = ComicReaderSettings.getString('readerMode');
    final zoomPosition = ComicReaderSettings.getString('longPressZoomPosition');
    return SettingsDetailScaffold(
      title: const Text('漫画阅读器设置'),
      body: SettingsList(
        maxWidth: 800,
        sections: [
          SettingsSection(title: const Text('分页'), tiles: [
            SettingsTile(
              leading: Icons.view_carousel_rounded,
              title: const Text('阅读模式'),
              onPressed: (_) {
                if (_readerModeMenu.isOpen) {
                  _readerModeMenu.close();
                } else {
                  _readerModeMenu.open();
                }
              },
              value: MenuAnchor(
                consumeOutsideTap: true,
                controller: _readerModeMenu,
                builder: (_, __, ___) => Text(
                  _readerModes[currentMode] ?? '分页（从左到右）',
                ),
                menuChildren: [
                  for (final e in _readerModes.entries)
                    MenuItemButton(
                      requestFocusOnHover: false,
                      onPressed: () {
                        ComicReaderSettings.set('readerMode', e.key);
                        _handleChanged('readerMode');
                        if (e.key.startsWith('continuous')) {
                          ComicReaderSettings.set(
                              'readerScreenPicNumberForLandscape', 1);
                          ComicReaderSettings.set(
                              'readerScreenPicNumberForPortrait', 1);
                          _handleChanged('readerScreenPicNumberForLandscape');
                          _handleChanged('readerScreenPicNumberForPortrait');
                        }
                      },
                      child:
                          _menuItem(e.value, currentMode == e.key, colorScheme),
                    ),
                ],
              ),
            ),
            SettingsSliderTile(
              leading: Icons.view_column_rounded,
              title: const Text('横向每屏图片数（分页模式）'),
              value: ComicReaderSettings.getInt(
                      'readerScreenPicNumberForLandscape')
                  .toDouble(),
              valueLabel:
                  '${ComicReaderSettings.getInt('readerScreenPicNumberForLandscape')} 张',
              min: 1,
              max: 5,
              divisions: 4,
              onChanged: (v) {
                ComicReaderSettings.set(
                    'readerScreenPicNumberForLandscape', v.toInt());
                _handleChanged('readerScreenPicNumberForLandscape');
              },
            ),
            SettingsSliderTile(
              leading: Icons.view_agenda_rounded,
              title: const Text('纵向每屏图片数（分页模式）'),
              value:
                  ComicReaderSettings.getInt('readerScreenPicNumberForPortrait')
                      .toDouble(),
              valueLabel:
                  '${ComicReaderSettings.getInt('readerScreenPicNumberForPortrait')} 张',
              min: 1,
              max: 5,
              divisions: 4,
              onChanged: (v) {
                ComicReaderSettings.set(
                    'readerScreenPicNumberForPortrait', v.toInt());
                _handleChanged('readerScreenPicNumberForPortrait');
              },
            ),
          ]),
          SettingsSection(
            title: const Text('操作'),
            tiles: [
              _switchTile('首页只显示单张图', 'showSingleImageOnFirstPage',
                  Icons.photo_outlined),
              _switchTile(
                  '点击翻页', 'enableTapToTurnPages', Icons.touch_app_rounded),
              _switchTile(
                  '反向点击翻页', 'reverseTapToTurnPages', Icons.touch_app_outlined),
              _switchTile(
                  '翻页动画', 'enablePageAnimation', Icons.animation_rounded),
              _switchTile(
                  '双击缩放', 'enableDoubleTapToZoom', Icons.zoom_in_rounded),
              _switchTile(
                  '长按缩放', 'enableLongPressToZoom', Icons.zoom_out_map_rounded),
              SettingsTile(
                leading: Icons.center_focus_strong_rounded,
                title: const Text('长按缩放位置'),
                onPressed: (_) {
                  if (_zoomPositionMenu.isOpen) {
                    _zoomPositionMenu.close();
                  } else {
                    _zoomPositionMenu.open();
                  }
                },
                value: MenuAnchor(
                  consumeOutsideTap: true,
                  controller: _zoomPositionMenu,
                  builder: (_, __, ___) =>
                      Text(zoomPosition == 'center' ? '屏幕中心' : '按住位置'),
                  menuChildren: [
                    for (final e in const {
                      'press': '按住位置',
                      'center': '屏幕中心',
                    }.entries)
                      MenuItemButton(
                        requestFocusOnHover: false,
                        onPressed: () {
                          ComicReaderSettings.set(
                              'longPressZoomPosition', e.key);
                          _handleChanged('longPressZoomPosition');
                        },
                        child: _menuItem(
                            e.value, zoomPosition == e.key, colorScheme),
                      ),
                  ],
                ),
              ),
              _switchTile(
                  '限制图片宽度（连续模式）', 'limitImageWidth', Icons.width_wide_rounded),
            ],
          ),
          SettingsSection(
            title: const Text('性能'),
            tiles: [
              SettingsSliderTile(
                leading: Icons.timer_rounded,
                title: const Text('自动翻页间隔（秒）'),
                value: ComicReaderSettings.getInt('autoPageTurningInterval')
                    .toDouble(),
                valueLabel:
                    '${ComicReaderSettings.getInt('autoPageTurningInterval')} 秒',
                min: 1,
                max: 20,
                divisions: 19,
                onChanged: (v) {
                  ComicReaderSettings.set('autoPageTurningInterval', v.toInt());
                  _handleChanged('autoPageTurningInterval');
                },
              ),
              SettingsSliderTile(
                leading: Icons.speed_rounded,
                title: const Text('鼠标滚动速度'),
                value: ComicReaderSettings.getDouble('readerScrollSpeed'),
                valueLabel:
                    '${ComicReaderSettings.getDouble('readerScrollSpeed').toStringAsFixed(1)}x',
                min: 0.5,
                max: 3,
                divisions: 25,
                onChanged: (v) {
                  ComicReaderSettings.set('readerScrollSpeed', v);
                  _handleChanged('readerScrollSpeed');
                },
              ),
              SettingsSliderTile(
                leading: Icons.swipe_rounded,
                title: const Text('滑动切章触发距离（连续模式）'),
                value: ComicReaderSettings.getDouble(
                    'continuousChapterSwitchThreshold'),
                valueLabel: ComicReaderSettings.getDouble(
                        'continuousChapterSwitchThreshold')
                    .round()
                    .toString(),
                min: 40,
                max: 200,
                divisions: 16,
                onChanged: (v) {
                  ComicReaderSettings.set(
                      'continuousChapterSwitchThreshold', v);
                  _handleChanged('continuousChapterSwitchThreshold');
                },
              ),
              SettingsSliderTile(
                leading: Icons.image_rounded,
                title: const Text('预加载图片数量'),
                value:
                    ComicReaderSettings.getInt('preloadImageCount').toDouble(),
                valueLabel:
                    '${ComicReaderSettings.getInt('preloadImageCount')} 张',
                min: 1,
                max: 16,
                divisions: 15,
                onChanged: (v) {
                  ComicReaderSettings.set('preloadImageCount', v.toInt());
                  _handleChanged('preloadImageCount');
                },
              ),
            ],
          ),
          SettingsSection(
            title: const Text('显示'),
            tiles: [
              if (Platform.isAndroid)
                _switchTile('音量键翻页', 'enableTurnPageByVolumeKey',
                    Icons.volume_up_rounded),
              _switchTile('显示时间与电量', 'enableClockAndBatteryInfoInReader',
                  Icons.access_time_rounded),
              _switchTile('显示系统状态栏', 'showSystemStatusBar',
                  Icons.settings_system_daydream_rounded),
              _switchTile(
                  '显示页码', 'showPageNumberInReader', Icons.numbers_rounded),
            ],
          ),
          SettingsSection(
            title: const Text('恢复默认设置'),
            tiles: [
              SettingsTile(
                leading: Icons.settings_backup_restore_rounded,
                onPressed: (_) => _resetSettings(),
                title: const Text('恢复默认设置'),
                description: const Text('将全部漫画阅读器参数恢复为默认值'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
