import 'dart:io';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:wyw/services/platform/screen_orientation.dart';
import 'package:wyw/services/storage/storage.dart';

/// 应用方向管理的行为回归。
///
/// 覆盖三层：
///   1. 策略 → 平台参数的纯映射（含「自由旋转必须用 FULL_SENSOR」这条关键约束）；
///   2. 方向按钮的状态派生（图标 / 提示 / 菜单选中态）；
///   3. 占用栈语义——页面进入 acquire、退出 release，**退出后必须落回应用方向**，
///      这正是此前「退出阅读器后整个 App 转不动、播放页按钮却说可旋转」的根因。
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

  /// 被平台写入的调用序列，形如 `free:left`。
  final applied = <String>[];

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('wyw_orientation_test');
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

  setUp(() async {
    final service = ScreenOrientationService.instance;
    // 先摘掉可能残留的占用（避免跨用例串味），再清空记录。
    ScreenOrientationService.platformWriter = (_, __) async {};
    await service.release(ScreenOrientationService.ownerPlayer);
    await service.release(ScreenOrientationService.ownerReader);
    await GStorage.resetSettings([
      SettingsKeys.appScreenOrientation,
      SettingsKeys.playerScreenOrientation,
      SettingsKeys.readerScreenOrientation,
      SettingsKeys.landscapeDefaultSide,
    ]);
    applied.clear();
    ScreenOrientationService.platformWriter = (policy, side) async {
      applied.add('${policy.id}:${side.id}');
    };
  });

  group('策略 → 平台参数', () {
    test('Android 常量映射（左右横屏是不同常量）', () {
      expect(
        androidOrientationFor(
          ScreenOrientationPolicy.free,
          LandscapeSide.left,
        ),
        AndroidScreenOrientation.fullSensor,
      );
      expect(
        androidOrientationFor(
          ScreenOrientationPolicy.landscape,
          LandscapeSide.left,
        ),
        AndroidScreenOrientation.landscape,
      );
      expect(
        androidOrientationFor(
          ScreenOrientationPolicy.landscape,
          LandscapeSide.right,
        ),
        AndroidScreenOrientation.reverseLandscape,
      );
      expect(
        androidOrientationFor(
          ScreenOrientationPolicy.portrait,
          LandscapeSide.left,
        ),
        AndroidScreenOrientation.portrait,
      );
      expect(
        androidOrientationFor(
          ScreenOrientationPolicy.system,
          LandscapeSide.left,
        ),
        AndroidScreenOrientation.unspecified,
      );
    });

    test('「自由旋转」必须是 FULL_SENSOR：否则覆盖不了系统「自动旋转」开关', () {
      // Flutter 公共 API 只能表达 UNSPECIFIED / USER / FULL_USER 系列，那些都会
      // 尊重系统旋转锁；只有 SENSOR / FULL_SENSOR 系列在用户锁定旋转时仍启用传感器。
      expect(AndroidScreenOrientation.fullSensor, 10);
      expect(
        androidOrientationFor(
          ScreenOrientationPolicy.free,
          LandscapeSide.left,
        ),
        isNot(AndroidScreenOrientation.unspecified),
      );
    });

    test('iOS 期望方向列表（没有 FULL_SENSOR，降级为四向允许）', () {
      expect(
        deviceOrientationsFor(ScreenOrientationPolicy.system, LandscapeSide.left),
        isEmpty,
      );
      expect(
        deviceOrientationsFor(ScreenOrientationPolicy.free, LandscapeSide.left),
        DeviceOrientation.values,
      );
      expect(
        deviceOrientationsFor(
          ScreenOrientationPolicy.landscape,
          LandscapeSide.left,
        ),
        [DeviceOrientation.landscapeLeft],
      );
      expect(
        deviceOrientationsFor(
          ScreenOrientationPolicy.landscape,
          LandscapeSide.right,
        ),
        [DeviceOrientation.landscapeRight],
      );
      expect(
        deviceOrientationsFor(
          ScreenOrientationPolicy.portrait,
          LandscapeSide.left,
        ),
        [DeviceOrientation.portraitUp],
      );
    });
  });

  group('方向按钮状态派生', () {
    test('图标与提示跟着真实策略走', () {
      expect(
        orientationPolicyIcon(ScreenOrientationPolicy.free),
        Icons.screen_rotation,
      );
      expect(
        orientationPolicyIcon(ScreenOrientationPolicy.landscape),
        Icons.screen_lock_landscape,
      );
      expect(
        orientationPolicyIcon(ScreenOrientationPolicy.portrait),
        Icons.screen_lock_portrait,
      );
      expect(
        orientationPolicyTooltip(
          ScreenOrientationPolicy.free,
          LandscapeSide.left,
        ),
        contains('自由旋转'),
      );
      expect(
        orientationPolicyTooltip(
          ScreenOrientationPolicy.landscape,
          LandscapeSide.right,
        ),
        contains('右'),
      );
    });

    test('菜单四档：三档策略 + 横屏左右，且只有当前档选中', () {
      final items = orientationPolicyMenuItems(
        ScreenOrientationPolicy.landscape,
        LandscapeSide.right,
      );
      expect(items.length, 4);
      final selected = items.where((item) => item.selected).toList();
      expect(selected.length, 1);
      expect(selected.single.label, '横屏锁定 · 右');
      expect(selected.single.side, LandscapeSide.right);

      final freeItems = orientationPolicyMenuItems(
        ScreenOrientationPolicy.free,
        LandscapeSide.left,
      );
      expect(freeItems.where((item) => item.selected).length, 1);
      expect(freeItems.first.selected, isTrue);
    });
  });

  group('占用栈语义', () {
    test('旧阅读器设置迁移成新的阅读器方向（锁定 → 竖屏锁定）', () async {
      // 依赖执行顺序：这是第一个调用 init() 的用例（单例只 init 一次）。
      await GStorage.putSettingByName(
        ScreenOrientationService.legacyReaderLockKey,
        true,
      );
      await ScreenOrientationService.instance.init();
      expect(
        GStorage.getSetting(SettingsKeys.readerScreenOrientation),
        ScreenOrientationPolicy.portrait.id,
      );
      await GStorage.deleteSettingByName(
        ScreenOrientationService.legacyReaderLockKey,
      );
    });

    test('播放器占用自由旋转，退出后落回应用方向', () async {
      final service = ScreenOrientationService.instance;
      await GStorage.putSetting(
        SettingsKeys.appScreenOrientation,
        ScreenOrientationPolicy.system.id,
      );
      await service.applyBasePolicy();
      expect(applied.last, 'system:left');

      await service.acquire(
        ScreenOrientationService.ownerPlayer,
        ScreenOrientationService.playerPolicyFromSettings(),
      );
      expect(service.policy, ScreenOrientationPolicy.free);
      expect(applied.last, 'free:left');

      await service.release(ScreenOrientationService.ownerPlayer);
      expect(service.isPageOverrideActive, isFalse);
      expect(service.policy, ScreenOrientationPolicy.system);
      expect(applied.last, 'system:left');
    });

    test('阅读器默认竖屏锁定，退出即释放（泄漏回归）', () async {
      final service = ScreenOrientationService.instance;
      expect(
        ScreenOrientationService.readerPolicyFromSettings(),
        ScreenOrientationPolicy.portrait,
      );

      await service.acquire(
        ScreenOrientationService.ownerReader,
        ScreenOrientationService.readerPolicyFromSettings(),
      );
      expect(applied.last, 'portrait:left');

      // 退出阅读器：必须把方向交还出去，而不是把竖屏锁留在 Activity 上。
      await service.release(ScreenOrientationService.ownerReader);
      expect(service.isPageOverrideActive, isFalse);
      expect(applied.last, 'system:left');
    });

    test('嵌套占用按后进先出恢复', () async {
      final service = ScreenOrientationService.instance;
      await GStorage.putSetting(
        SettingsKeys.appScreenOrientation,
        ScreenOrientationPolicy.system.id,
      );
      await service.applyBasePolicy();

      await service.acquire(
        ScreenOrientationService.ownerReader,
        ScreenOrientationPolicy.portrait,
      );
      await service.acquire(
        ScreenOrientationService.ownerPlayer,
        ScreenOrientationPolicy.free,
      );
      expect(service.policy, ScreenOrientationPolicy.free);

      // 后进的先走：落回阅读器的竖屏锁定，而不是直接掉到应用方向。
      await service.release(ScreenOrientationService.ownerPlayer);
      expect(service.policy, ScreenOrientationPolicy.portrait);
      expect(applied.last, 'portrait:left');

      await service.release(ScreenOrientationService.ownerReader);
      expect(service.policy, ScreenOrientationPolicy.system);
      expect(applied.last, 'system:left');
    });

    test('横屏默认侧来自设置，页面内可切对侧且不写回设置', () async {
      final service = ScreenOrientationService.instance;
      await GStorage.putSetting(SettingsKeys.landscapeDefaultSide, 'right');
      await service.acquire(
        ScreenOrientationService.ownerPlayer,
        ScreenOrientationPolicy.landscape,
      );
      expect(applied.last, 'landscape:right');

      await service.updateActivePolicy(
        ScreenOrientationPolicy.landscape,
        side: LandscapeSide.left,
      );
      expect(applied.last, 'landscape:left');
      expect(service.landscapeSide, LandscapeSide.left);
      // 只影响本次：设置仍是「右」。
      expect(
        GStorage.getSetting(SettingsKeys.landscapeDefaultSide),
        LandscapeSide.right.id,
      );
    });

    test('页面内换档不写回设置（设置里那三项是「默认方向」）', () async {
      final service = ScreenOrientationService.instance;
      await GStorage.putSetting(
        SettingsKeys.playerScreenOrientation,
        ScreenOrientationPolicy.free.id,
      );
      await service.acquire(
        ScreenOrientationService.ownerPlayer,
        ScreenOrientationService.playerPolicyFromSettings(),
      );
      await service.updateActivePolicy(ScreenOrientationPolicy.portrait);
      expect(service.policy, ScreenOrientationPolicy.portrait);
      expect(
        GStorage.getSetting(SettingsKeys.playerScreenOrientation),
        ScreenOrientationPolicy.free.id,
      );

      await service.release(ScreenOrientationService.ownerPlayer);
      // 重新进入播放页时回到设置里的默认档。
      expect(
        ScreenOrientationService.playerPolicyFromSettings(),
        ScreenOrientationPolicy.free,
      );
    });

    test('页面方向读到「跟随系统」脏值时按自由旋转处理', () async {
      await GStorage.putSetting(
        SettingsKeys.playerScreenOrientation,
        ScreenOrientationPolicy.system.id,
      );
      await GStorage.putSetting(
        SettingsKeys.readerScreenOrientation,
        ScreenOrientationPolicy.system.id,
      );
      expect(
        ScreenOrientationService.playerPolicyFromSettings(),
        ScreenOrientationPolicy.free,
      );
      expect(
        ScreenOrientationService.readerPolicyFromSettings(),
        ScreenOrientationPolicy.free,
      );
    });

    test('页面占用期间改「应用方向」不抢栈顶，退出后落到新值', () async {
      final service = ScreenOrientationService.instance;
      await service.acquire(
        ScreenOrientationService.ownerPlayer,
        ScreenOrientationPolicy.free,
      );

      await GStorage.putSetting(
        SettingsKeys.appScreenOrientation,
        ScreenOrientationPolicy.portrait.id,
      );
      await service.applyBasePolicy();
      // 播放页占用中：生效策略不变，只是基准被刷新。
      expect(service.policy, ScreenOrientationPolicy.free);

      await service.release(ScreenOrientationService.ownerPlayer);
      expect(service.policy, ScreenOrientationPolicy.portrait);
      expect(applied.last, 'portrait:left');
    });
  });
}
