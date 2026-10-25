enum SettingGroup {
  player,
  danmaku,
  theme,
  interface,
  download,
  misc,
}

class SettingContext {
  const SettingContext({this.compactLayout = false});

  final bool compactLayout;
}

class SettingKey<T> {
  const SettingKey(
    this.name,
    this.defaultValue, {
    required this.group,
    this.defaultResolver,
  });

  final String name;
  final T defaultValue;
  final SettingGroup group;
  final T Function(SettingContext context)? defaultResolver;

  T resolveDefault(SettingContext context) {
    return defaultResolver?.call(context) ?? defaultValue;
  }
}

// Add new settings here. SettingsKeys is the public typed registry used by
// callers; new keys can use literal string names directly.
class SettingsKeys {
  static const hAenable = SettingKey<bool>(
    _SettingBoxKey.hAenable,
    true,
    group: SettingGroup.player,
  );
  static const hardwareDecoder = SettingKey<String>(
    _SettingBoxKey.hardwareDecoder,
    'auto-safe',
    group: SettingGroup.player,
  );
  static const searchEnhanceEnable = SettingKey<bool>(
    _SettingBoxKey.searchEnhanceEnable,
    true,
    group: SettingGroup.misc,
  );
  static const alwaysOntop = SettingKey<bool>(
    _SettingBoxKey.alwaysOntop,
    false,
    group: SettingGroup.misc,
  );
  static const defaultPlaySpeed = SettingKey<double>(
    _SettingBoxKey.defaultPlaySpeed,
    1.0,
    group: SettingGroup.player,
  );
  static const defaultShortcutForwardPlaySpeed = SettingKey<double>(
    _SettingBoxKey.defaultShortcutForwardPlaySpeed,
    2.0,
    group: SettingGroup.player,
  );
  static const defaultAspectRatioType = SettingKey<int>(
    _SettingBoxKey.defaultAspectRatioType,
    1,
    group: SettingGroup.player,
  );
  static const buttonSkipTime = SettingKey<int>(
    _SettingBoxKey.buttonSkipTime,
    80,
    group: SettingGroup.player,
  );
  static const arrowKeySkipTime = SettingKey<int>(
    _SettingBoxKey.arrowKeySkipTime,
    10,
    group: SettingGroup.player,
  );
  static const danmakuEnhance = SettingKey<bool>(
    _SettingBoxKey.danmakuEnhance,
    true,
    group: SettingGroup.danmaku,
  );
  static const danmakuBorder = SettingKey<bool>(
    _SettingBoxKey.danmakuBorder,
    true,
    group: SettingGroup.danmaku,
  );
  static const danmakuBorderSize = SettingKey<double>(
    _SettingBoxKey.danmakuBorderSize,
    1.5,
    group: SettingGroup.danmaku,
  );
  static const danmakuOpacity = SettingKey<double>(
    _SettingBoxKey.danmakuOpacity,
    1.0,
    group: SettingGroup.danmaku,
  );
  static final danmakuFontSize = SettingKey<double>(
    _SettingBoxKey.danmakuFontSize,
    25.0,
    group: SettingGroup.danmaku,
    defaultResolver: (context) => context.compactLayout ? 16.0 : 25.0,
  );
  static const danmakuTop = SettingKey<bool>(
    _SettingBoxKey.danmakuTop,
    true,
    group: SettingGroup.danmaku,
  );
  static const danmakuScroll = SettingKey<bool>(
    _SettingBoxKey.danmakuScroll,
    true,
    group: SettingGroup.danmaku,
  );
  static const danmakuBottom = SettingKey<bool>(
    _SettingBoxKey.danmakuBottom,
    false,
    group: SettingGroup.danmaku,
  );
  static const danmakuMassive = SettingKey<bool>(
    _SettingBoxKey.danmakuMassive,
    false,
    group: SettingGroup.danmaku,
  );
  static const danmakuDeduplication = SettingKey<bool>(
    _SettingBoxKey.danmakuDeduplication,
    false,
    group: SettingGroup.danmaku,
  );
  static const danmakuArea = SettingKey<double>(
    _SettingBoxKey.danmakuArea,
    1.0,
    group: SettingGroup.danmaku,
  );
  static const danmakuColor = SettingKey<bool>(
    _SettingBoxKey.danmakuColor,
    true,
    group: SettingGroup.danmaku,
  );
  static const danmakuDuration = SettingKey<double>(
    _SettingBoxKey.danmakuDuration,
    8.0,
    group: SettingGroup.danmaku,
  );
  static const danmakuLineHeight = SettingKey<double>(
    _SettingBoxKey.danmakuLineHeight,
    1.6,
    group: SettingGroup.danmaku,
  );
  static const danmakuTimeOffset = SettingKey<double>(
    _SettingBoxKey.danmakuTimeOffset,
    0.0,
    group: SettingGroup.danmaku,
  );
  static const danmakuChConvert = SettingKey<int>(
    _SettingBoxKey.danmakuChConvert,
    0,
    group: SettingGroup.danmaku,
  );
  static const danmakuEnabledByDefault = SettingKey<bool>(
    _SettingBoxKey.danmakuEnabledByDefault,
    false,
    group: SettingGroup.danmaku,
  );
  static const danmakuBiliBiliSource = SettingKey<bool>(
    _SettingBoxKey.danmakuBiliBiliSource,
    true,
    group: SettingGroup.danmaku,
  );
  static const danmakuGamerSource = SettingKey<bool>(
    _SettingBoxKey.danmakuGamerSource,
    true,
    group: SettingGroup.danmaku,
  );
  static const danmakuDanDanSource = SettingKey<bool>(
    _SettingBoxKey.danmakuDanDanSource,
    true,
    group: SettingGroup.danmaku,
  );
  static const danmakuFontWeight = SettingKey<int>(
    _SettingBoxKey.danmakuFontWeight,
    4,
    group: SettingGroup.danmaku,
  );
  static const danmakuFollowSpeed = SettingKey<bool>(
    _SettingBoxKey.danmakuFollowSpeed,
    true,
    group: SettingGroup.danmaku,
  );
  static const themeMode = SettingKey<String>(
    _SettingBoxKey.themeMode,
    'system',
    group: SettingGroup.theme,
  );
  static const themeColor = SettingKey<String>(
    _SettingBoxKey.themeColor,
    'default',
    group: SettingGroup.theme,
  );
  static const privateMode = SettingKey<bool>(
    _SettingBoxKey.privateMode,
    false,
    group: SettingGroup.player,
  );
  static const autoPlay = SettingKey<bool>(
    _SettingBoxKey.autoPlay,
    true,
    group: SettingGroup.player,
  );
  static const autoPlayNext = SettingKey<bool>(
    _SettingBoxKey.autoPlayNext,
    true,
    group: SettingGroup.player,
  );
  static const playResume = SettingKey<bool>(
    _SettingBoxKey.playResume,
    true,
    group: SettingGroup.player,
  );
  static const showPlayerError = SettingKey<bool>(
    _SettingBoxKey.showPlayerError,
    true,
    group: SettingGroup.player,
  );
  static const oledEnhance = SettingKey<bool>(
    _SettingBoxKey.oledEnhance,
    false,
    group: SettingGroup.theme,
  );
  static const displayMode = SettingKey<String?>(
    _SettingBoxKey.displayMode,
    null,
    group: SettingGroup.interface,
  );
  static const defaultStartupPage = SettingKey<String>(
    _SettingBoxKey.defaultStartupPage,
    '/tab/search/',
    group: SettingGroup.interface,
  );
  static const isWideScreen = SettingKey<bool>(
    _SettingBoxKey.isWideScreen,
    false,
    group: SettingGroup.interface,
  );
  static const lowMemoryMode = SettingKey<bool>(
    _SettingBoxKey.lowMemoryMode,
    false,
    group: SettingGroup.player,
  );
  static const showWindowButton = SettingKey<bool>(
    _SettingBoxKey.showWindowButton,
    false,
    group: SettingGroup.theme,
  );
  static const useDynamicColor = SettingKey<bool>(
    _SettingBoxKey.useDynamicColor,
    false,
    group: SettingGroup.theme,
  );
  static const exitBehavior = SettingKey<int>(
    _SettingBoxKey.exitBehavior,
    2,
    group: SettingGroup.interface,
  );
  static const playerDebugMode = SettingKey<bool>(
    _SettingBoxKey.playerDebugMode,
    false,
    group: SettingGroup.player,
  );
  static const syncPlayEndPoint = SettingKey<String>(
    _SettingBoxKey.syncPlayEndPoint,
    '127.0.0.1:8999',
    group: SettingGroup.player,
  );
  static const androidEnableOpenSLES = SettingKey<bool>(
    _SettingBoxKey.androidEnableOpenSLES,
    true,
    group: SettingGroup.player,
  );
  static const androidVideoRenderer = SettingKey<String>(
    _SettingBoxKey.androidVideoRenderer,
    'auto',
    group: SettingGroup.player,
  );
  static const androidAutoEnterPIP = SettingKey<bool>(
    _SettingBoxKey.androidAutoEnterPIP,
    false,
    group: SettingGroup.player,
  );
  static const defaultSuperResolutionMode = SettingKey<int>(
    _SettingBoxKey.defaultSuperResolutionMode,
    1,
    group: SettingGroup.player,
  );
  static const disableSuperResolutionWarning = SettingKey<bool>(
    _SettingBoxKey.disableSuperResolutionWarning,
    false,
    group: SettingGroup.player,
  );
  static const playerDisableAnimations = SettingKey<bool>(
    _SettingBoxKey.playerDisableAnimations,
    false,
    group: SettingGroup.player,
  );
  static const playerLogLevel = SettingKey<int>(
    _SettingBoxKey.playerLogLevel,
    2,
    group: SettingGroup.player,
  );
  static const useSystemFont = SettingKey<bool>(
    _SettingBoxKey.useSystemFont,
    false,
    group: SettingGroup.theme,
  );
  static const forceAdBlocker = SettingKey<bool>(
    _SettingBoxKey.forceAdBlocker,
    false,
    group: SettingGroup.player,
  );
  static const backgroundPlayback = SettingKey<bool>(
    _SettingBoxKey.backgroundPlayback,
    false,
    group: SettingGroup.player,
  );
  static const showRating = SettingKey<bool>(
    _SettingBoxKey.showRating,
    true,
    group: SettingGroup.interface,
  );
  static const showAnimeCounter = SettingKey<bool>(
    _SettingBoxKey.showAnimeCounter,
    false,
    group: SettingGroup.interface,
  );
  static const downloadParallelEpisodes = SettingKey<int>(
    _SettingBoxKey.downloadParallelEpisodes,
    2,
    group: SettingGroup.download,
  );
  static const downloadParallelSegments = SettingKey<int>(
    _SettingBoxKey.downloadParallelSegments,
    3,
    group: SettingGroup.download,
  );
  static const downloadDanmaku = SettingKey<bool>(
    _SettingBoxKey.downloadDanmaku,
    true,
    group: SettingGroup.download,
  );
  static const downloadDirectory = SettingKey<String>(
    _SettingBoxKey.downloadDirectory,
    '',
    group: SettingGroup.download,
  );
  // macOS only: security-scoped bookmark that keeps downloadDirectory
  // writable across app restarts under the sandbox.
  static const downloadDirectoryBookmark = SettingKey<String>(
    'downloadDirectoryBookmark',
    '',
    group: SettingGroup.download,
  );
  static const shortcutDialogShown = SettingKey<bool>(
    _SettingBoxKey.shortcutDialogShown,
    false,
    group: SettingGroup.misc,
  );
  static const brightnessVolumeGesture = SettingKey<bool>(
    _SettingBoxKey.brightnessVolumeGesture,
    true,
    group: SettingGroup.player,
  );

  /// 进入播放页时的「播放 ↔ 下载」协作模式（playOnly / playAndDownload / downloadOnly）。
  /// 默认「边播放边下载」，保持代理合流行为不变。
  static const playbackDownloadMode = SettingKey<String>(
    _SettingBoxKey.playbackDownloadMode,
    'playAndDownload',
    group: SettingGroup.player,
  );

  /// 选择播放方式后是否「整页沿用」：进入播放器后切换集数时继续使用进入时
  /// 选择的方式（合流 / 直接播放），不逐集询问。这是「选择播放方式」弹窗里
  /// 沿用开关的默认值（弹窗内可临时改，只对本次会话生效）。
  static const followPlayModeInPlayer = SettingKey<bool>(
    'followPlayModeInPlayer',
    true,
    group: SettingGroup.player,
  );

  /// 画面调节滤镜预设（JSON 数组，见 `VideoFilterPreset.toJson`）。
  static const videoFilterPresets = SettingKey<String>(
    'videoFilterPresets',
    '[]',
    group: SettingGroup.player,
  );

  /// 当前活动滤镜预设 id（'' = 关闭滤镜）。
  static const videoFilterActivePresetId = SettingKey<String>(
    'videoFilterActivePresetId',
    '',
    group: SettingGroup.player,
  );
  static const playerControllerLayerDisappearTime = SettingKey<int>(
    'playerControllerLayerDisappearTime',
    4000,
    group: SettingGroup.player,
  );
  static const defaultVolume = SettingKey<double>(
    'defaultVolume',
    100.0,
    group: SettingGroup.player,
  );
  static const playerMuted = SettingKey<bool>(
    'playerMuted',
    false,
    group: SettingGroup.player,
  );

  /// 分屏面板宽度（横屏，**像素**；`0` = 未自定义，取
  /// `clamp(可用宽 / 3, 320, 420)`）。与 [playerSplitRatioPortrait] 单位不同。
  static const playerSplitRatioLandscape = SettingKey<double>(
    'playerSplitRatioLandscape',
    0.0,
    group: SettingGroup.player,
  );

  /// 分屏面板高度占比（竖屏，**容器高的比例**；`0` = 未自定义，取 45%）。
  static const playerSplitRatioPortrait = SettingKey<double>(
    'playerSplitRatioPortrait',
    0.0,
    group: SettingGroup.player,
  );

  /// 应用启动时的初始窗口大小预设（'auto' / 'small' / 'medium' / 'large' /
  /// 'xlarge'，见 constants.dart 的 initialWindowSizePresets）。仅桌面端生效。
  static const initialWindowSize = SettingKey<String>(
    'initialWindowSize',
    'auto',
    group: SettingGroup.interface,
  );

  /// 插件名称在界面上的显示方式（见 `PluginController.displayNameOf`）：
  ///   - `'display'`（默认）：用户覆盖 > 插件自称（`// name:` / 类字段）> 插件名；
  ///   - `'name'`：一律显示插件名（= 文件名 = JS 类名，即插件的唯一标识）。
  ///
  /// 「插件名」是标识，用于 tab key / 调用 / 配置键；把它显示出来便于与插件目录、
  /// 报错信息、插件文档里的名字对上号。
  static const pluginNameDisplay = SettingKey<String>(
    'pluginNameDisplay',
    'display',
    group: SettingGroup.interface,
  );

  /// 屏幕方向：播放器 / 漫画阅读器**之外**的界面用哪一档。
  ///
  /// 取值见 `ScreenOrientationService` 的 `ScreenOrientationPolicy`：
  ///   - `'system'`（默认）：跟随系统，系统「自动旋转」开着才转；
  ///   - `'free'`：自由旋转，**覆盖**系统「自动旋转」开关（Android `FULL_SENSOR`）；
  ///   - `'landscape'` / `'portrait'`：横屏 / 竖屏锁定。
  static const appScreenOrientation = SettingKey<String>(
    'appScreenOrientation',
    'system',
    group: SettingGroup.interface,
  );

  /// 播放器进入时的方向。默认自由旋转：一进播放页就能转（覆盖系统开关）。
  ///
  /// 只取 `'free'` / `'landscape'` / `'portrait'`——播放页要「完全自由控制」，
  /// 不提供「跟随系统」这种含糊态。
  static const playerScreenOrientation = SettingKey<String>(
    'playerScreenOrientation',
    'free',
    group: SettingGroup.interface,
  );

  /// 漫画阅读器进入时的方向（默认竖屏锁定）。取值同 [playerScreenOrientation]。
  static const readerScreenOrientation = SettingKey<String>(
    'readerScreenOrientation',
    'portrait',
    group: SettingGroup.interface,
  );

  /// 横屏锁定朝哪一侧（`'left'` / `'right'`）。
  ///
  /// 仅当应用 / 播放器 / 漫画阅读器任一处选了横屏锁定时才生效；播放页与阅读器内
  /// 的方向按钮随时可切到对侧（只影响本次，不改这里）。
  static const landscapeDefaultSide = SettingKey<String>(
    'landscapeDefaultSide',
    'left',
    group: SettingGroup.interface,
  );

  /// 收藏模块中「未收藏」条目的保留上限：
  ///   - `0`（默认）= 无上限（全留）
  ///   - `N > 0` = 超出 N 条时按最近访问时间最旧优先自动清理
  ///
  /// **已收藏条目永不参与自动清理。**
  static const uncollectedLimit = SettingKey<int>(
    'uncollectedLimit',
    0,
    group: SettingGroup.misc,
  );

  /// 收藏页「进入时的默认页签」：
  ///   - `-1`（默认）= 全部
  ///   - 其余 = `CollectType` 的数值（0 未收藏 / 1 在看 / 2 想看 / 3 搁置 /
  ///     4 看过 / 5 抛弃）
  ///
  /// 存状态数值而不是 tab 下标，避免 tab 顺序调整后设置错位。
  static const collectDefaultTab = SettingKey<int>(
    'collectDefaultTab',
    -1,
    group: SettingGroup.misc,
  );

  static final List<SettingKey<Object?>> all = [
    hAenable,
    hardwareDecoder,
    searchEnhanceEnable,
    alwaysOntop,
    defaultPlaySpeed,
    defaultShortcutForwardPlaySpeed,
    defaultAspectRatioType,
    buttonSkipTime,
    arrowKeySkipTime,
    danmakuEnhance,
    danmakuBorder,
    danmakuBorderSize,
    danmakuOpacity,
    danmakuFontSize,
    danmakuTop,
    danmakuScroll,
    danmakuBottom,
    danmakuMassive,
    danmakuDeduplication,
    danmakuArea,
    danmakuColor,
    danmakuDuration,
    danmakuLineHeight,
    danmakuTimeOffset,
    danmakuChConvert,
    danmakuEnabledByDefault,
    danmakuBiliBiliSource,
    danmakuGamerSource,
    danmakuDanDanSource,
    danmakuFontWeight,
    danmakuFollowSpeed,
    themeMode,
    themeColor,
    privateMode,
    autoPlay,
    autoPlayNext,
    playResume,
    showPlayerError,
    oledEnhance,
    displayMode,
    defaultStartupPage,
    isWideScreen,
    lowMemoryMode,
    showWindowButton,
    useDynamicColor,
    exitBehavior,
    playerDebugMode,
    syncPlayEndPoint,
    androidEnableOpenSLES,
    androidVideoRenderer,
    androidAutoEnterPIP,
    defaultSuperResolutionMode,
    disableSuperResolutionWarning,
    playerDisableAnimations,
    playerLogLevel,
    useSystemFont,
    forceAdBlocker,
    backgroundPlayback,
    showRating,
    showAnimeCounter,
    downloadParallelEpisodes,
    downloadParallelSegments,
    downloadDanmaku,
    downloadDirectory,
    downloadDirectoryBookmark,
    shortcutDialogShown,
    brightnessVolumeGesture,
    playbackDownloadMode,
    followPlayModeInPlayer,
    videoFilterPresets,
    videoFilterActivePresetId,
    playerControllerLayerDisappearTime,
    defaultVolume,
    playerMuted,
    playerSplitRatioLandscape,
    playerSplitRatioPortrait,
    initialWindowSize,
    pluginNameDisplay,
    appScreenOrientation,
    playerScreenOrientation,
    readerScreenOrientation,
    landscapeDefaultSide,
    uncollectedLimit,
    collectDefaultTab,
  ];

  static List<SettingKey<Object?>> byGroup(SettingGroup group) {
    return [
      for (final key in all)
        if (key.group == group) key
    ];
  }

  SettingsKeys._();
}

// Historical Hive key names used by settings created before the typed registry.
// Keep these strings stable so existing users keep their saved settings.
// New settings do not need to be added here unless they intentionally reuse an
// existing persisted key.
class _SettingBoxKey {
  static const String hAenable = 'hAenable',
      hardwareDecoder = 'hardwareDecoder',
      searchEnhanceEnable = 'searchEnhanceEnable',
      alwaysOntop = 'alwaysOntop',
      defaultPlaySpeed = 'defaultPlaySpeed',
      defaultShortcutForwardPlaySpeed = 'defaultShortcutForwardPlaySpeed',
      defaultAspectRatioType = 'defaultAspectRatioType',
      buttonSkipTime = 'buttonSkipTime',
      arrowKeySkipTime = 'arrowKeySkipTime',
      danmakuEnhance = 'danmakuEnhance',
      danmakuBorder = 'danmakuBorder',
      danmakuBorderSize = 'danmakuBorderSize',
      danmakuOpacity = 'danmakuOpacity',
      danmakuFontSize = 'danmakuFontSize',
      danmakuTop = 'danmakuTop',
      danmakuScroll = 'danmakuScroll',
      danmakuBottom = 'danmakuBottom',
      danmakuMassive = 'danmakuMassive',
      danmakuDeduplication = 'danmakuDeduplication',
      danmakuArea = 'danmakuArea',
      danmakuColor = 'danmakuColor',
      danmakuDuration = 'danmakuDuration',
      danmakuLineHeight = 'danmakuLineHeight',
      danmakuTimeOffset = 'danmakuTimeOffset',
      danmakuChConvert = 'danmakuChConvert',
      danmakuEnabledByDefault = 'danmakuEnabledByDefault',
      danmakuBiliBiliSource = 'danmakuBiliBiliSource',
      danmakuGamerSource = 'danmakuGamerSource',
      danmakuDanDanSource = 'danmakuDanDanSource',
      danmakuFontWeight = 'danmakuFontWeight',
      danmakuFollowSpeed = 'danmakuFollowSpeed',
      themeMode = 'themeMode',
      themeColor = 'themeColor',
      privateMode = 'privateMode',
      autoPlay = 'autoPlay',
      autoPlayNext = 'autoPlayNext',
      playResume = 'playResume',
      showPlayerError = 'showPlayerError',
      oledEnhance = 'oledEnhance',
      displayMode = 'displayMode',
      defaultStartupPage = 'defaultStartupPage',

      /// Deprecated
      isWideScreen = 'isWideScreen',
      lowMemoryMode = 'lowMemoryMode',
      showWindowButton = 'showWindowButton',
      useDynamicColor = 'useDynamicColor',
      exitBehavior = 'exitBehavior',
      playerDebugMode = 'playerDebugMode',
      syncPlayEndPoint = 'syncPlayEndPoint',
      androidEnableOpenSLES = 'androidEnableOpenSLES',
      androidVideoRenderer = 'androidVideoRenderer',
      androidAutoEnterPIP = 'androidAutoEnterPIP',
      defaultSuperResolutionMode = 'defaultSuperResolutionType',
      disableSuperResolutionWarning = 'superResolutionWarn',
      playerDisableAnimations = 'playerDisableAnimations',
      playerLogLevel = 'playerLogLevel',
      useSystemFont = 'useSystemFont',
      forceAdBlocker = 'forceAdBlocker',
      backgroundPlayback = 'backgroundPlayback',
      showRating = 'showRating',
      showAnimeCounter = 'showAnimeCounter',
      downloadParallelEpisodes = 'downloadParallelEpisodes',
      downloadParallelSegments = 'downloadParallelSegments',
      downloadDanmaku = 'downloadDanmaku',
      downloadDirectory = 'downloadDirectory',
      shortcutDialogShown = 'shortcutDialogShown',
      brightnessVolumeGesture = 'brightnessVolumeGesture',
      playbackDownloadMode = 'playbackDownloadMode';
}
