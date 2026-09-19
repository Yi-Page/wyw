import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:wyw/bean/settings/settings_detail_scaffold.dart';
import 'package:wyw/bean/settings/settings_list.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/services/platform/secure_bookmark_service.dart';
import 'package:wyw/services/storage/storage.dart';
import 'package:wyw/utils/file_system.dart';

class DownloadSettingsPage extends StatefulWidget {
  const DownloadSettingsPage({super.key});

  @override
  State<DownloadSettingsPage> createState() => _DownloadSettingsPageState();
}

class _DownloadSettingsPageState extends State<DownloadSettingsPage> {
  late int parallelEpisodes;
  late int parallelSegments;
  String downloadDirectory = '';
  String defaultDownloadDirectory = '';
  bool isSelectingDirectory = false;

  @override
  void initState() {
    super.initState();
    parallelEpisodes =
        GStorage.getSetting(SettingsKeys.downloadParallelEpisodes);
    parallelSegments =
        GStorage.getSetting(SettingsKeys.downloadParallelSegments);
    downloadDirectory =
        GStorage.getSetting(SettingsKeys.downloadDirectory).trim();
    _loadDefaultDownloadDirectory();
  }

  bool get _canPickDirectory => supportsCustomDownloadDirectory;

  bool get _hasCustomDirectory =>
      _canPickDirectory && downloadDirectory.isNotEmpty;

  String get _effectiveDownloadDirectory =>
      _hasCustomDirectory ? downloadDirectory : defaultDownloadDirectory;

  Future<void> _loadDefaultDownloadDirectory() async {
    final directory = await getDefaultDownloadDirectory();
    if (!mounted) return;
    setState(() {
      defaultDownloadDirectory = directory;
    });
  }

  Future<void> _selectDownloadDirectory() async {
    if (!_canPickDirectory) {
      WywDialog.showToast(message: '当前平台不支持手动选择目录');
      return;
    }
    if (isSelectingDirectory) return;

    setState(() => isSelectingDirectory = true);
    try {
      final effectiveDirectory = _effectiveDownloadDirectory;
      final initialDirectory = effectiveDirectory.isNotEmpty &&
              await Directory(effectiveDirectory).exists()
          ? effectiveDirectory
          : null;
      final selectedPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择下载位置',
        initialDirectory: initialDirectory,
      );
      if (selectedPath == null || selectedPath.isEmpty) return;

      await ensureDirectoryWritable(selectedPath);
      if (!await SecureBookmarkService.persist(selectedPath)) {
        WywDialog.showToast(message: '无法获得该目录的持久访问权限，请更换目录');
        return;
      }
      await GStorage.putSetting(
        SettingsKeys.downloadDirectory,
        selectedPath,
      );
      if (mounted) {
        setState(() => downloadDirectory = selectedPath);
      }
      WywDialog.showToast(message: '下载位置已更新，仅对新下载生效');
    } on FileSystemException catch (e) {
      WywDialog.showToast(message: '无法写入该目录: ${e.message}');
    } catch (e) {
      WywDialog.showToast(message: '选择下载位置失败: $e');
    } finally {
      if (mounted) {
        setState(() => isSelectingDirectory = false);
      }
    }
  }

  Future<void> _resetDownloadDirectory() async {
    await SecureBookmarkService.clear();
    await GStorage.putSetting(SettingsKeys.downloadDirectory, '');
    if (mounted) {
      setState(() => downloadDirectory = '');
    }
    WywDialog.showToast(message: '已恢复默认下载位置，仅对新下载生效');
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: const Text('下载设置'),
      body: SettingsList(
        sections: [
          SettingsSection(
            title: const Text('并行下载'),
            tiles: [
              SettingsSliderTile(
                leading: Icons.album_rounded,
                title: const Text('集数并发'),
                description: const Text('同时下载多少集视频'),
                value: parallelEpisodes.toDouble(),
                valueLabel: '$parallelEpisodes',
                min: 1,
                max: 8,
                divisions: 7,
                onChanged: (value) {
                  setState(() {
                    parallelEpisodes = value.round();
                  });
                  GStorage.putSetting<int>(
                    SettingsKeys.downloadParallelEpisodes,
                    parallelEpisodes,
                  );
                },
              ),
              SettingsSliderTile(
                leading: Icons.segment_rounded,
                title: const Text('分片并发'),
                description: const Text('每集内同时下载多少个视频片段'),
                value: parallelSegments.toDouble(),
                valueLabel: '$parallelSegments',
                min: 1,
                max: 16,
                divisions: 15,
                onChanged: (value) {
                  setState(() {
                    parallelSegments = value.round();
                  });
                  GStorage.putSetting<int>(
                    SettingsKeys.downloadParallelSegments,
                    parallelSegments,
                  );
                },
              ),
            ],
          ),
          SettingsSection(
            title: const Text('下载位置'),
            tiles: [
              SettingsTile(
                leading: Icons.folder_rounded,
                onPressed: (_) => _selectDownloadDirectory(),
                title: const Text('选择下载位置'),
                description: Text(
                  _effectiveDownloadDirectory.isEmpty
                      ? '选择下载视频保存的位置'
                      : _effectiveDownloadDirectory,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                value: _hasCustomDirectory
                    ? TextButton(
                        onPressed: _resetDownloadDirectory,
                        child: const Text('恢复默认'),
                      )
                    : null,
              ),
            ],
          ),
          SettingsSection(
            title: const Text('说明'),
            tiles: [
              const SettingsTile(
                leading: Icons.info_outline_rounded,
                title: Text('关于并发设置'),
                description: Text(
                  '• 集数并发：同时下载多少集视频\n'
                  '• 分片并发：每集内同时下载多少个视频片段\n'
                  '• 较高的并发可提升速度，但可能被服务器限制\n'
                  '• 修改后对新开始的下载生效',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
