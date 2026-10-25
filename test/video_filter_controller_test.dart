import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:wyw/pages/player/controller/video_filter_controller.dart';
import 'package:wyw/services/storage/storage.dart';

/// 画面调节滤镜预设控制器的行为回归（真实 Hive 设置箱）。
///
/// 覆盖：默认预设、新建/切换实时下发、编辑活动预设实时下发、
/// 删除活动预设回关闭、JSON 持久化。
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('wyw_filter_ctrl_test');
    Hive.init(tempDir.path);
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await GStorage.init();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() {
    VideoFilterController.instance.reset();
  });

  test('默认预设 + 活动为空（关闭）', () {
    final c = VideoFilterController.instance;
    expect(c.presets.length, 1);
    expect(c.presets.first.name, '默认');
    expect(c.activePresetId, '');
    expect(c.activePreset, isNull);
  });

  test('新建 + 切换实时下发着色器参数表', () {
    final c = VideoFilterController.instance;
    final applied = <Map<String, double>?>[];
    c.applyVf = applied.add;
    final id = c.addPreset(name: '明亮');
    c.updatePreset(id, contrast: 1.2);
    expect(applied, isEmpty, reason: '非活动预设的编辑不应下发');
    c.setActivePreset(id);
    expect(c.activePresetId, id);
    expect(applied.last, isNotNull);
    expect(applied.last!['wyw_filter_contrast'], 1.2);
    c.applyVf = null;
  });

  test('编辑活动预设实时下发；删除活动预设回关闭并清除', () {
    final c = VideoFilterController.instance;
    final applied = <Map<String, double>?>[];
    c.applyVf = applied.add;
    final id = c.addPreset(name: '测试');
    c.setActivePreset(id);
    applied.clear();
    c.updatePreset(id, sharpness: 0.5);
    expect(applied.last, isNotNull);
    expect(applied.last!['wyw_filter_sharpness'], 0.5);
    c.deletePreset(id);
    expect(c.activePresetId, '');
    expect(applied.last, isNull);
    c.applyVf = null;
  });

  test('切换/编辑持久化到设置箱', () async {
    final c = VideoFilterController.instance;
    final id = c.addPreset(name: '持久');
    c.updatePreset(id, gamma: 1.5);
    c.setActivePreset(id);
    // 等持久化防抖落盘
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final raw = GStorage.getSetting<String>(SettingsKeys.videoFilterPresets);
    expect(raw, contains('持久'));
    expect(raw, contains('1.5'));
    expect(
      GStorage.getSetting<String>(SettingsKeys.videoFilterActivePresetId),
      id,
    );
  });
}
