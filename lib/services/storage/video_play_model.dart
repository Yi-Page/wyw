/// 播放资源路径类型。
///
/// - [direct]：直链（m3u8/mp4/flv...），直接交给播放器，无需嗅探
/// - [page]：播放页网址，需 WebView 资源嗅探
/// - [local]：本地文件地址，本地播放
/// - [resolve]：路径需执行插件固定逻辑才能得到真实路径（返回结果为前三类之一）
enum PlayPathType {
  direct,
  page,
  local,
  resolve;

  String get value => switch (this) {
        PlayPathType.direct => 'direct',
        PlayPathType.page => 'page',
        PlayPathType.local => 'local',
        PlayPathType.resolve => 'resolve',
      };

  static PlayPathType fromValue(String? v) => switch (v) {
        'direct' => PlayPathType.direct,
        'page' => PlayPathType.page,
        'local' => PlayPathType.local,
        _ => PlayPathType.resolve,
      };
}

/// 播放资源路径：一条可交给播放器（或需先执行插件逻辑）的资源描述。
///
/// 序列化/反序列化供两种场景共用：
///   - JS 插件 → Dart 的 navigateToVideo 传参
///   - 进度历史 VideoPlaybackProgress.sources 持久化
class PlayResourcePath {
  /// 播放页网址 / 直链 / 本地文件地址；[PlayPathType.resolve] 时可为空。
  final String url;

  final PlayPathType type;

  /// 仅 [PlayPathType.resolve] 时使用：执行插件固定逻辑取真实路径。
  final String? plugin;
  final String? method;
  final List<dynamic>? args;

  const PlayResourcePath({
    this.url = '',
    this.type = PlayPathType.resolve,
    this.plugin,
    this.method,
    this.args,
  });

  bool get isResolve => type == PlayPathType.resolve;

  Map<String, dynamic> toMap() => {
        'url': url,
        'type': type.value,
        if (plugin != null) 'plugin': plugin,
        if (method != null) 'method': method,
        if (args != null) 'args': args,
      };

  factory PlayResourcePath.fromMap(Map m) {
    final url = (m['url'] as String?) ?? '';
    final type = PlayPathType.fromValue(m['type'] as String?);
    if (type == PlayPathType.resolve) {
      return PlayResourcePath(
        url: url,
        type: type,
        plugin: m['plugin'] as String?,
        method: m['method'] as String?,
        args: (m['args'] as List?)?.cast<dynamic>(),
      );
    }
    return PlayResourcePath(url: url, type: type);
  }

  /// 判断字符串是否是媒体直链（与插件侧 direct 判定一致）。
  static bool isDirectUrl(String url) =>
      RegExp(r'\.(m3u8|mp4|flv|mkv|ts|webm)(\?|$)', caseSensitive: false)
          .hasMatch(url) ||
      url.contains('.m3u8');

  /// 解析插件 resolve 方法返回值：字符串 → 启发式判断 direct/page；对象 → 采用显式 type。
  static PlayResourcePath fromResolveResult(dynamic raw) {
    if (raw is String) {
      final t = isDirectUrl(raw) ? PlayPathType.direct : PlayPathType.page;
      return PlayResourcePath(url: raw, type: t);
    }
    if (raw is Map) {
      final url = (raw['url'] as String?) ?? '';
      final type = raw['type'] is String
          ? PlayPathType.fromValue(raw['type'] as String)
          : (isDirectUrl(url) ? PlayPathType.direct : PlayPathType.page);
      return PlayResourcePath(url: url, type: type);
    }
    return const PlayResourcePath(type: PlayPathType.resolve);
  }
}

/// 一集：资源描述 + 该集的运行时状态（解析直链、独立观看进度）。
///
/// 描述部分由插件进入时提供；状态部分由播放页在播放/解析过程中回填，
/// 调用方合并进 [VideoPlaybackProgress] 落盘。
class VideoPlayEpisode {
  final String name;

  final PlayResourcePath path;

  /// 该集解析出的媒体直链（resolve 执行后 / 嗅探成功后回填；空串表示未解析）。
  final String resolvedUrl;

  /// 该集独立观看进度（毫秒）。
  final int positionMs;

  /// 该集时长（毫秒）。
  final int durationMs;

  /// 该集上次观看时间。
  final DateTime? lastPlayedAt;

  const VideoPlayEpisode({
    required this.name,
    required this.path,
    this.resolvedUrl = '',
    this.positionMs = 0,
    this.durationMs = 0,
    this.lastPlayedAt,
  });

  VideoPlayEpisode copyWith({
    String? name,
    PlayResourcePath? path,
    String? resolvedUrl,
    int? positionMs,
    int? durationMs,
    DateTime? lastPlayedAt,
  }) {
    return VideoPlayEpisode(
      name: name ?? this.name,
      path: path ?? this.path,
      resolvedUrl: resolvedUrl ?? this.resolvedUrl,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
    );
  }

  /// 实际可交给播放器的地址：优先已解析直链，否则 path.url。
  String get effectiveUrl => resolvedUrl.isNotEmpty ? resolvedUrl : path.url;

  Map<String, dynamic> toMap() => {
        'name': name,
        'path': path.toMap(),
        'resolvedUrl': resolvedUrl,
        'positionMs': positionMs,
        'durationMs': durationMs,
        if (lastPlayedAt != null)
          'lastPlayedAt': lastPlayedAt!.toIso8601String(),
      };

  factory VideoPlayEpisode.fromMap(Map m) {
    // 兼容两种形态：
    //   - 持久化形态：{ name, path: {...}, resolvedUrl, ... }
    //   - 插件扁平形态：{ name, url, type, plugin, method, args }（字段平铺在 episode 层）
    final PlayResourcePath path;
    final nestedPath = m['path'];
    if (nestedPath is Map) {
      path = PlayResourcePath.fromMap(nestedPath.cast<String, dynamic>());
    } else {
      path = PlayResourcePath(
        url: (m['url'] as String?) ?? '',
        type: PlayPathType.fromValue(m['type'] as String?),
        plugin: m['plugin'] as String?,
        method: m['method'] as String?,
        args: (m['args'] as List?)?.cast<dynamic>(),
      );
    }
    return VideoPlayEpisode(
      name: (m['name'] as String?) ?? '',
      path: path,
      resolvedUrl: (m['resolvedUrl'] as String?) ?? '',
      positionMs: (m['positionMs'] as num?)?.toInt() ?? 0,
      durationMs: (m['durationMs'] as num?)?.toInt() ?? 0,
      lastPlayedAt: m['lastPlayedAt'] is String
          ? DateTime.tryParse(m['lastPlayedAt'] as String)
          : null,
    );
  }
}

/// 播放源（一条线路/来源）。
class VideoPlaySource {
  final String name;
  final List<VideoPlayEpisode> episodes;

  const VideoPlaySource({required this.name, required this.episodes});

  Map<String, dynamic> toMap() => {
        'name': name,
        'episodes': [for (final e in episodes) e.toMap()],
      };

  factory VideoPlaySource.fromMap(Map m) => VideoPlaySource(
        name: (m['name'] as String?) ?? '',
        episodes: (m['episodes'] as List?)
                ?.map((e) => VideoPlayEpisode.fromMap(
                    (e as Map).cast<String, dynamic>()))
                .toList() ??
            const [],
      );
}
