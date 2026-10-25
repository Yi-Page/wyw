import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/services/storage/storage.dart';
import 'package:wyw/utils/device.dart';

/// 应用方向策略：全 App 唯一的方向口径。
///
/// 三档「页面方向」与一档「应用方向」共用这一个枚举，避免出现两套说法：
///
///   - [system]：跟随系统。**不干预**，系统「自动旋转」开着才能转，关着就转不动
///     （Android 上对应 `SCREEN_ORIENTATION_UNSPECIFIED`，仍受系统旋转锁约束）。
///   - [free]：自由旋转。**覆盖系统「自动旋转」开关**（Android 走 `FULL_SENSOR`，
///     系统关了自动旋转也照样随传感器转）。
///   - [landscape]：横屏锁定。钉死一侧（见 [LandscapeSide]），可随时切对侧。
///   - [portrait]：竖屏锁定。
///
/// 播放器 / 漫画阅读器只提供后三档（它们要「完全自由控制」，不留「跟随系统」
/// 这种含糊态）；[system] 只用于播放器与阅读器之外的界面。
enum ScreenOrientationPolicy {
  system('system', '跟随系统'),
  free('free', '自由旋转'),
  landscape('landscape', '横屏锁定'),
  portrait('portrait', '竖屏锁定');

  const ScreenOrientationPolicy(this.id, this.label);

  /// 持久化用的稳定 id（不要跟着界面文案改）。
  final String id;

  /// 界面文案。
  final String label;

  static ScreenOrientationPolicy fromId(
    String? id, {
    ScreenOrientationPolicy fallback = ScreenOrientationPolicy.system,
  }) {
    for (final value in values) {
      if (value.id == id) {
        return value;
      }
    }
    return fallback;
  }
}

/// 横屏锁定朝哪一侧。
///
/// 以 Android 的原生常量为准：[left] = `SCREEN_ORIENTATION_LANDSCAPE`，
/// [right] = `SCREEN_ORIENTATION_REVERSE_LANDSCAPE`（与 Flutter 的
/// `DeviceOrientation.landscapeLeft / landscapeRight` 同一口径）。
enum LandscapeSide {
  left('left', '左'),
  right('right', '右');

  const LandscapeSide(this.id, this.label);

  final String id;
  final String label;

  static LandscapeSide fromId(
    String? id, {
    LandscapeSide fallback = LandscapeSide.left,
  }) {
    for (final value in values) {
      if (value.id == id) {
        return value;
      }
    }
    return fallback;
  }
}

/// 用到的 Android `ActivityInfo.screenOrientation` 常量。
///
/// 只用「能覆盖系统自动旋转」的那几个：`SENSOR`/`FULL_SENSOR` 系列在
/// WindowManager 里即使在用户锁定旋转（`USER_ROTATION_LOCKED`）时也会启用传感器
/// （见 AOSP `DisplayRotation.needSensorRunning`），而 `USER`/`FULL_USER` 系列
/// 会尊重系统旋转锁——Flutter 的 `SystemChrome.setPreferredOrientations` 只能
/// 表达后者，所以覆盖系统开关这条必须走原生。
class AndroidScreenOrientation {
  AndroidScreenOrientation._();

  /// 不干预，交给系统。
  static const int unspecified = -1;

  /// 横屏（左）。
  static const int landscape = 0;

  /// 竖屏。
  static const int portrait = 1;

  /// 横屏（右）。
  static const int reverseLandscape = 8;

  /// 四个方向都随传感器，且**忽略**系统旋转锁。
  static const int fullSensor = 10;
}

/// 策略 → Android `requestedOrientation` 常量。
///
/// 纯函数，方便在没有设备的情况下单测整张映射表。
int androidOrientationFor(
  ScreenOrientationPolicy policy,
  LandscapeSide side,
) {
  return switch (policy) {
    ScreenOrientationPolicy.system => AndroidScreenOrientation.unspecified,
    ScreenOrientationPolicy.free => AndroidScreenOrientation.fullSensor,
    ScreenOrientationPolicy.landscape => side == LandscapeSide.left
        ? AndroidScreenOrientation.landscape
        : AndroidScreenOrientation.reverseLandscape,
    ScreenOrientationPolicy.portrait => AndroidScreenOrientation.portrait,
  };
}

/// 策略 → iOS 的期望方向列表（`SystemChrome.setPreferredOrientations` 口径）。
///
/// iOS 没有 `FULL_SENSOR` 等价物：系统级的「竖排方向锁定」始终优先，所以
/// [ScreenOrientationPolicy.free] 在这里退化成「四向都允许」，[system] 则清空
/// 期望（不表达偏好，回到 Info.plist 声明的集合）。
List<DeviceOrientation> deviceOrientationsFor(
  ScreenOrientationPolicy policy,
  LandscapeSide side,
) {
  return switch (policy) {
    ScreenOrientationPolicy.system => const <DeviceOrientation>[],
    ScreenOrientationPolicy.free => DeviceOrientation.values,
    ScreenOrientationPolicy.landscape => side == LandscapeSide.left
        ? const [DeviceOrientation.landscapeLeft]
        : const [DeviceOrientation.landscapeRight],
    ScreenOrientationPolicy.portrait => const [DeviceOrientation.portraitUp],
  };
}

/// 播放器 / 漫画阅读器可选的三档（不含「跟随系统」）。
///
/// 这两处要的是「完全自由控制」：要么随传感器转、要么钉死某一侧，不留含糊态。
const List<ScreenOrientationPolicy> pageOrientationPolicies =
    <ScreenOrientationPolicy>[
  ScreenOrientationPolicy.free,
  ScreenOrientationPolicy.landscape,
  ScreenOrientationPolicy.portrait,
];

/// 方向按钮的图标：与**真实生效策略**一一对应。
IconData orientationPolicyIcon(ScreenOrientationPolicy policy) {
  return switch (policy) {
    ScreenOrientationPolicy.free => Icons.screen_rotation,
    ScreenOrientationPolicy.landscape => Icons.screen_lock_landscape,
    ScreenOrientationPolicy.portrait => Icons.screen_lock_portrait,
    ScreenOrientationPolicy.system => Icons.screen_rotation,
  };
}

/// 方向按钮的提示文案（也就是「按钮状态」的文本形态）。
String orientationPolicyTooltip(
  ScreenOrientationPolicy policy,
  LandscapeSide side,
) {
  return switch (policy) {
    ScreenOrientationPolicy.free => '方向：自由旋转（覆盖系统自动旋转）',
    ScreenOrientationPolicy.landscape => '方向：横屏锁定 · ${side.label}',
    ScreenOrientationPolicy.portrait => '方向：竖屏锁定',
    ScreenOrientationPolicy.system => '方向：跟随系统',
  };
}

/// 方向菜单的一项。
class OrientationPolicyMenuItem {
  const OrientationPolicyMenuItem({
    required this.label,
    required this.icon,
    required this.policy,
    required this.selected,
    this.side,
  });

  final String label;
  final IconData icon;
  final ScreenOrientationPolicy policy;

  /// 仅横屏锁定项有值（左 / 右）。
  final LandscapeSide? side;
  final bool selected;
}

/// 方向菜单项：三档策略 + 横屏的左右两侧（「允许切换到对侧方向」）。
///
/// 播放页与漫画阅读器底栏共用同一份菜单，避免两处各写一套。
List<OrientationPolicyMenuItem> orientationPolicyMenuItems(
  ScreenOrientationPolicy policy,
  LandscapeSide side,
) {
  return <OrientationPolicyMenuItem>[
    OrientationPolicyMenuItem(
      label: '自由旋转（覆盖系统自动旋转）',
      icon: Icons.screen_rotation,
      policy: ScreenOrientationPolicy.free,
      selected: policy == ScreenOrientationPolicy.free,
    ),
    OrientationPolicyMenuItem(
      label: '横屏锁定 · 左',
      icon: Icons.screen_lock_landscape,
      policy: ScreenOrientationPolicy.landscape,
      side: LandscapeSide.left,
      selected:
          policy == ScreenOrientationPolicy.landscape && side == LandscapeSide.left,
    ),
    OrientationPolicyMenuItem(
      label: '横屏锁定 · 右',
      icon: Icons.screen_lock_landscape,
      policy: ScreenOrientationPolicy.landscape,
      side: LandscapeSide.right,
      selected: policy == ScreenOrientationPolicy.landscape &&
          side == LandscapeSide.right,
    ),
    OrientationPolicyMenuItem(
      label: '竖屏锁定',
      icon: Icons.screen_lock_portrait,
      policy: ScreenOrientationPolicy.portrait,
      selected: policy == ScreenOrientationPolicy.portrait,
    ),
  ];
}

/// 一次「页面占用」：谁（[owner]）把方向按到了什么策略。
class _OrientationRequest {
  const _OrientationRequest({
    required this.owner,
    required this.policy,
    this.side,
  });

  final String owner;
  final ScreenOrientationPolicy policy;

  /// 仅 [ScreenOrientationPolicy.landscape] 有意义；null = 用设置里的默认侧。
  final LandscapeSide? side;
}

/// 应用方向的**唯一状态源**：谁在占用、当前生效策略、系统旋转开关的真实状态。
///
/// 职责边界：
///   - 这里只管「屏幕方向」；系统状态栏/导航栏的隐藏归 `DisplayModeService`；
///   - 页面进入 `acquire`、退出 `release`（栈式，后进先出）；栈空时回到
///     「应用方向」（播放器 / 阅读器之外的界面，见 [SettingsKeys.appScreenOrientation]）；
///   - 页面内的方向按钮通过 [updateActivePolicy] 临时改当前占用者的策略，
///     **不写回设置**（设置里那三项是「默认方向」，按钮是「本次」）。
///
/// 所有方向写入都先落到 [policy]/[landscapeSide] 这两个可读状态上，界面（播放页
/// 底栏按钮、阅读器底栏按钮）据此渲染，从而按钮状态与真实生效策略严格一致——
/// 不再出现「按钮说可旋转、屏幕却转不动」的脱节。
class ScreenOrientationService extends ChangeNotifier with WidgetsBindingObserver {
  ScreenOrientationService._();

  static final ScreenOrientationService instance = ScreenOrientationService._();

  /// 占用者标识。
  static const String ownerApp = 'app';
  static const String ownerPlayer = 'player';
  static const String ownerReader = 'reader';

  static const MethodChannel _channel = MethodChannel('com.yi.wyw/intent');

  /// 真正把策略写到平台的实现。
  ///
  /// 抽成可替换的函数只为测试：桌面测试宿主上 `Platform.isAndroid` 恒为 false，
  /// 无法走到 Android 分支；替换它就能断言「谁在占用 / 释放后落回哪一档」。
  /// 生产代码不要碰它。
  @visibleForTesting
  static Future<void> Function(
    ScreenOrientationPolicy policy,
    LandscapeSide side,
  ) platformWriter = _writeToPlatform;

  /// 旧阅读器设置键（已废弃，仅用于一次性迁移）。
  static const String legacyReaderLockKey = 'lockOrientationOnEntry';

  final List<_OrientationRequest> _requests = <_OrientationRequest>[];

  ScreenOrientationPolicy _basePolicy = ScreenOrientationPolicy.system;
  LandscapeSide _baseSide = LandscapeSide.left;
  bool _systemAutoRotateEnabled = true;
  bool _initialized = false;

  /// 当前**真实生效**的策略（栈顶占用者，栈空则应用方向）。
  ScreenOrientationPolicy get policy =>
      _requests.isEmpty ? _basePolicy : _requests.last.policy;

  /// 当前真实生效的横屏侧（非横屏策略下仅表示「下次横屏用哪侧」）。
  ///
  /// 栈顶那次占用**显式指定过**侧（页面内按了「横屏锁定 · 右」）时以那次为准；
  /// 没指定（`side == null`，页面刚 acquire 的样子）时**当场读设置**，而不是用
  /// [_baseSide] 这份缓存：`_baseSide` 只在 init / [applyBasePolicy] 里刷新，而
  /// 「横屏默认方向」可以在设置页随时改，两者刷新时机一错开，页面就会被钉在改动
  /// 前的旧侧上（[ScreenOrientationPolicy] 的文档已把 `side == null` 定义为
  /// 「用设置里的默认侧」，这里必须照这个口径取值）。
  ///
  /// 基线本身（[_requests] 为空，即应用方向）仍用 [_baseSide]：那条路径允许
  /// [updateActivePolicy] 只在本次会话里改侧而不写回设置。
  LandscapeSide get landscapeSide => _requests.isEmpty
      ? _baseSide
      : (_requests.last.side ?? landscapeSideFromSettings());

  /// 「应用方向」（播放器 / 阅读器之外的界面）当前取值。
  ScreenOrientationPolicy get basePolicy => _basePolicy;

  /// 是否有页面正在占用方向（播放器 / 阅读器）。
  bool get isPageOverrideActive => _requests.isNotEmpty;

  /// 系统「自动旋转」是否开着。仅 Android 可查，其余平台恒为 true。
  ///
  /// 仅当策略为 [ScreenOrientationPolicy.system] 时它才会影响实际能否旋转；
  /// 界面据此显示提示（例如界面设置里给「跟随系统」加一句说明）。
  bool get systemAutoRotateEnabled => _systemAutoRotateEnabled;

  /// 读取设置（默认值见 [SettingsKeys]）。
  static ScreenOrientationPolicy appPolicyFromSettings() =>
      ScreenOrientationPolicy.fromId(
        GStorage.getSetting(SettingsKeys.appScreenOrientation),
      );

  static ScreenOrientationPolicy playerPolicyFromSettings() =>
      _pagePolicyFromSettings(
        SettingsKeys.playerScreenOrientation,
        fallback: ScreenOrientationPolicy.free,
      );

  static ScreenOrientationPolicy readerPolicyFromSettings() =>
      _pagePolicyFromSettings(
        SettingsKeys.readerScreenOrientation,
        fallback: ScreenOrientationPolicy.portrait,
      );

  /// 读播放器 / 阅读器的方向设置。
  ///
  /// 这两处不提供「跟随系统」（要的是「完全自由控制」），所以读到 system
  /// （旧值 / 脏值 / 手改的存储）时统一按自由旋转处理。
  static ScreenOrientationPolicy _pagePolicyFromSettings(
    SettingKey<String> key, {
    required ScreenOrientationPolicy fallback,
  }) {
    final policy = ScreenOrientationPolicy.fromId(
      GStorage.getSetting(key),
      fallback: fallback,
    );
    return policy == ScreenOrientationPolicy.system
        ? ScreenOrientationPolicy.free
        : policy;
  }

  static LandscapeSide landscapeSideFromSettings() => LandscapeSide.fromId(
    GStorage.getSetting(SettingsKeys.landscapeDefaultSide),
  );

  /// 应用启动时调用一次：迁移旧设置、读基准策略、查系统旋转开关、按上。
  Future<void> init() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    await _migrateLegacyReaderLock();
    _basePolicy = appPolicyFromSettings();
    _baseSide = landscapeSideFromSettings();
    await refreshSystemRotationState();
    await applyBasePolicy();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }
    // 回到前台：系统可能被用户在别处改过（自动旋转开关、当前旋转），重新对账。
    unawaited(refreshSystemRotationState().then((_) => _reapply()));
  }

  /// 应用方向（播放器 / 阅读器之外的界面）。
  ///
  /// 页面占用期间只刷新基准值，不抢栈顶——退出页面时自然落回新基准。
  Future<void> applyBasePolicy() async {
    _basePolicy = appPolicyFromSettings();
    _baseSide = landscapeSideFromSettings();
    if (_requests.isNotEmpty) {
      notifyListeners();
      return;
    }
    await _reapply();
  }

  /// 设置页改完方向后调用：重读基准 + 刷新系统开关，占用中不打断页面。
  Future<void> reloadFromSettings() async {
    await refreshSystemRotationState();
    await applyBasePolicy();
  }

  /// 页面进入时占用方向。同一 owner 重复占用只保留最后一次。
  Future<void> acquire(
    String owner,
    ScreenOrientationPolicy policy, {
    LandscapeSide? side,
  }) async {
    _requests.removeWhere((request) => request.owner == owner);
    _requests.add(_OrientationRequest(owner: owner, policy: policy, side: side));
    await _reapply();
  }

  /// 页面退出时释放占用，落回栈内上一层（没有别人占用就是应用方向）。
  Future<void> release(String owner) async {
    final before = _requests.length;
    _requests.removeWhere((request) => request.owner == owner);
    if (_requests.length == before) {
      return;
    }
    await _reapply();
  }

  /// 页面内方向按钮：改当前占用者（或应用方向）的策略，不写回设置。
  Future<void> updateActivePolicy(
    ScreenOrientationPolicy policy, {
    LandscapeSide? side,
  }) async {
    if (_requests.isEmpty) {
      _basePolicy = policy;
      if (side != null) {
        _baseSide = side;
      }
    } else {
      final top = _requests.last;
      _requests[_requests.length - 1] = _OrientationRequest(
        owner: top.owner,
        policy: policy,
        side: side ?? top.side,
      );
    }
    await _reapply();
  }

  /// 查一次系统「自动旋转」开关（Android 专用；失败按「开着」处理）。
  Future<void> refreshSystemRotationState() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      final state = await _channel
          .invokeMapMethod<String, dynamic>('getOrientationState');
      final enabled = state?['autoRotateEnabled'];
      if (enabled is bool && enabled != _systemAutoRotateEnabled) {
        _systemAutoRotateEnabled = enabled;
        notifyListeners();
      }
    } catch (e, s) {
      WywLogger().w(
        '${LogTag.platform} 查询系统自动旋转开关失败（按开启处理）',
        error: e,
        stackTrace: s,
      );
    }
  }

  /// 把关键路径上的一次方向写入吞掉异常：方向设置失败不该影响播放/阅读。
  Future<void> _reapply() async {
    await platformWriter(policy, landscapeSide);
    notifyListeners();
  }

  /// 平台默认写入：Android 走原生 `requestedOrientation`，其余走 Flutter 通道。
  static Future<void> _writeToPlatform(
    ScreenOrientationPolicy policy,
    LandscapeSide side,
  ) async {
    if (isDesktop()) {
      return;
    }
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod<void>('setOrientation', {
          'orientation': androidOrientationFor(policy, side),
        });
      } else {
        await SystemChrome.setPreferredOrientations(
          deviceOrientationsFor(policy, side),
        );
      }
    } catch (e, s) {
      WywLogger().e(
        '${LogTag.platform} 应用屏幕方向失败 policy=${policy.id} side=${side.id}',
        error: e,
        stackTrace: s,
      );
    }
  }

  /// 旧版「阅读器进入时默认锁定竖屏」→ 新的阅读器方向设置（一次性）。
  Future<void> _migrateLegacyReaderLock() async {
    final legacy = GStorage.getSettingByName(legacyReaderLockKey);
    if (legacy is! bool) {
      return;
    }
    // 新键已有显式值时不覆盖用户的新选择。
    if (GStorage.getSettingByName(SettingsKeys.readerScreenOrientation.name) !=
        null) {
      return;
    }
    await GStorage.putSetting(
      SettingsKeys.readerScreenOrientation,
      (legacy ? ScreenOrientationPolicy.portrait : ScreenOrientationPolicy.free)
          .id,
    );
  }
}
