/// 弹弹play 开放 API 的响应模型（剧集 / 作品详情类）。
///
/// 对应 `/api/v2/search/episodes` 与 `/api/v2/bangumi/{bangumiId}`。
/// 这是第三方接口：`nullable: true` 的字段随时可能为 null，列表也可能是空数组
/// 或缺失，因此所有 `fromJson` 一律容错，缺失值退化为空串 / 0 / false。
library;

/// 剧集引用：跨 `/search/episodes` 与 `/bangumi/{bangumiId}` 复用的最小单元。
///
/// 必须使用接口返回的 `episodeId`，不要用 `animeId * 10000 + 集号` 去猜：
/// `episodeNumber` 官方定义为「剧集短标题（可以用来排序，非纯数字，可能包含
/// 字母）」，猜算法在非纯数字集号上必然取不到弹幕（实测柯南有 `"C146"` 这种）。
class DanmakuEpisodeRef {
  /// 弹幕库编号（int64），取弹幕时直接使用。
  final int episodeId;

  /// 剧集完整标题。
  final String episodeTitle;

  /// 剧集短标题，可用于排序与展示；`/search/episodes` 不返回该字段。
  final String episodeNumber;

  /// 季度 id。非空表示该作品被拆成多个季度——**实测只有 TMDB 数据源才会给出**，
  /// 弹弹play 自有库恒为空串，所以分集列表不能依赖"按季分组"。
  final String seasonId;

  /// 该集播出时间（date-time，形如 `2024-01-06T00:00:00`；可能为空）。
  final String airDate;

  /// 该集上次观看时间；只有携带用户 token 时才返回，wyw 无登录态，恒为空。
  final String lastWatched;

  const DanmakuEpisodeRef({
    required this.episodeId,
    required this.episodeTitle,
    this.episodeNumber = '',
    this.seasonId = '',
    this.airDate = '',
    this.lastWatched = '',
  });

  factory DanmakuEpisodeRef.fromJson(Map<String, dynamic> json) {
    return DanmakuEpisodeRef(
      episodeId: _asInt(json['episodeId']),
      episodeTitle: _asString(json['episodeTitle']),
      episodeNumber: _asString(json['episodeNumber']),
      seasonId: _asString(json['seasonId']),
      airDate: _asString(json['airDate']),
      lastWatched: _asString(json['lastWatched']),
    );
  }

  /// 持久化用的扁平行。
  ///
  /// 键与 [DanmakuEpisodeRef.fromJson] 完全一致，因此可以用 `fromJson` 直接读回
  /// （弹幕库详情缓存就是这么存的，见 `DanmakuLibraryCacheRepository`）。
  Map<String, dynamic> toMap() => {
        'episodeId': episodeId,
        'episodeTitle': episodeTitle,
        'episodeNumber': episodeNumber,
        'seasonId': seasonId,
        'airDate': airDate,
        'lastWatched': lastWatched,
      };

  /// 播出日期（只取 `yyyy-MM-dd` 部分，形如 `2023-01-06`；解析不出返回空串）。
  String get airDateLabel =>
      airDate.length >= 10 ? airDate.substring(0, 10) : '';
}

/// 作品的多语言标题（`titles[]`）。
///
/// 实测同一作品最多 5 种写法，`language` 是接口给的中文描述：
/// `主标题` / `主标题，日语罗马字` / `别名，英语` / `官方标题，日语` /
/// `官方标题，繁体中文`。详情卡据此提供标题语言切换。
class DanmakuTitle {
  final String language;
  final String title;

  const DanmakuTitle({required this.language, required this.title});

  factory DanmakuTitle.fromJson(Map<String, dynamic> json) {
    return DanmakuTitle(
      language: _asString(json['language']),
      title: _asString(json['title']),
    );
  }

  Map<String, dynamic> toMap() => {'language': language, 'title': title};
}

/// 作品标签（`tags[]`），`count` 是被标记次数，可用于按热度截取展示。
class DanmakuTag {
  final String name;
  final int count;

  const DanmakuTag({required this.name, required this.count});

  factory DanmakuTag.fromJson(Map<String, dynamic> json) {
    return DanmakuTag(
      name: _asString(json['name']),
      count: _asInt(json['count']),
    );
  }

  Map<String, dynamic> toMap() => {'name': name, 'count': count};
}

/// `/api/v2/bangumi/{bangumiId}` 的 `bangumi` 字段。
///
/// 这是拿到权威 `episodeId` 的正路：搜索接口只给作品，分集必须走详情。
/// 同时它是**简介的唯一来源**（实测响应 27 个字段）：`/search/anime` 不返回简介，
/// 能返回简介的 `/search/adv` 对现有 AppId 是 `errorCode=11 验证用户权限失败`，
/// 所以"选中后在详情卡展示简介"用的就是这次本就要发的请求，不额外增加请求。
class DanmakuBangumiDetail {
  final int animeId;

  /// 字符串形式的作品 id（数字串或 `tmdb-tv-30983` 这类）。
  ///
  /// 刷新详情时优先用它请求：接口两种形式都接受，而字符串形式是接口自己的
  /// 规范 id，不受数字编号未来变化影响。
  final String bangumiId;

  final String animeTitle;
  final String imageUrl;
  final String typeDescription;

  /// 短简介（Staff 简介或剧情简介），实测柯南主系列 231 字。
  final String intro;

  /// 长简介（剧情简介）。
  final String summary;

  /// 综合评分（0-10，decimal）。
  final double rating;

  /// 是否连载中。
  final bool isOnAir;

  /// 多语言标题；接口可能不返回或返回空数组。
  final List<DanmakuTitle> titles;

  /// 标签（带被标记次数）。
  final List<DanmakuTag> tags;

  /// `BangumiEpisode` 列表按接口顺序保留（接口已按集号排好）。
  final List<DanmakuEpisodeRef> episodes;

  const DanmakuBangumiDetail({
    required this.animeId,
    this.bangumiId = '',
    required this.animeTitle,
    required this.imageUrl,
    required this.typeDescription,
    this.intro = '',
    this.summary = '',
    this.rating = 0,
    this.isOnAir = false,
    this.titles = const [],
    this.tags = const [],
    required this.episodes,
  });

  /// 详情卡优先展示的简介：长简介为空时退回短简介。
  String get displayIntro => summary.isNotEmpty ? summary : intro;

  /// 作品年份：取**第一集**能解析出的播出年份，解析不出返回 0。
  ///
  /// 详情接口**不返回** `startDate`，只有每集的 `airDate`（实测
  /// `"airDate":"2023-01-06T00:00:00"`），所以"作品年份"在详情侧只能这么推。
  /// 搜索结果里有系列级的 `startDate`，那个更准、优先级更高（见
  /// `DanmakuLibraryRef.fromDetail`）。
  ///
  /// 它存在的意义是**兜底与自愈**：进度记录里 `year == 0` 表示"当时没拿到"
  /// （老记录、或接口没给 startDate），而不是"确定没有年份"；有了这条推导，
  /// 下一次点分集或刷新就能把年份补进快照，卡片也不会永远显示 `—`。
  int get firstAirYear {
    for (final episode in episodes) {
      final label = episode.airDateLabel;
      if (label.length < 4) continue;
      final year = int.tryParse(label.substring(0, 4));
      if (year != null && year > 1900) return year;
    }
    return 0;
  }

  factory DanmakuBangumiDetail.fromJson(Map<String, dynamic> json) {
    return DanmakuBangumiDetail(
      animeId: _asInt(json['animeId']),
      bangumiId: _asString(json['bangumiId']),
      animeTitle: _asString(json['animeTitle']),
      imageUrl: _asString(json['imageUrl']),
      typeDescription: _asString(json['typeDescription']),
      intro: _asString(json['intro']),
      summary: _asString(json['summary']),
      rating: _asDouble(json['rating']),
      isOnAir: _asBool(json['isOnAir']),
      titles: _asMapList(json['titles']).map(DanmakuTitle.fromJson).toList(),
      tags: _asMapList(json['tags']).map(DanmakuTag.fromJson).toList(),
      episodes:
          _asMapList(json['episodes']).map(DanmakuEpisodeRef.fromJson).toList(),
    );
  }

  /// 持久化用的扁平行（键与 [DanmakuBangumiDetail.fromJson] 一致，可直接读回）。
  ///
  /// 这份对象是**弹幕库详情缓存**的载荷：它只在用户点选某个库、或点「刷新」时
  /// 写一次，绝不跟着进度一起重写。
  Map<String, dynamic> toMap() => {
        'animeId': animeId,
        'bangumiId': bangumiId,
        'animeTitle': animeTitle,
        'imageUrl': imageUrl,
        'typeDescription': typeDescription,
        'intro': intro,
        'summary': summary,
        'rating': rating,
        'isOnAir': isOnAir,
        'titles': [for (final title in titles) title.toMap()],
        'tags': [for (final tag in tags) tag.toMap()],
        'episodes': [for (final episode in episodes) episode.toMap()],
      };
}

List<Map<String, dynamic>> _asMapList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<Map>().map(Map<String, dynamic>.from).toList();
}

String _asString(Object? value) => value is String ? value : '';

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    return int.tryParse(value) ?? double.tryParse(value)?.toInt() ?? 0;
  }
  return 0;
}

double _asDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

bool _asBool(Object? value) => value is bool ? value : false;
