/// 弹弹play 开放 API 的响应模型（搜索类）。
///
/// 字段名与类型以官方 swagger 为准（`SearchAnimeDetails`、
/// `SearchEpisodesResponse`/`SearchEpisodesAnime`）。这是第三方接口：
/// `nullable: true` 的字段随时可能为 null，列表也可能是空数组或缺失，
/// 因此所有 `fromJson` 一律容错，缺失值退化为空串 / 0 / false，
/// 绝不让一个空字段炸掉整条候选匹配链路。
library;

/// `/api/v2/search/anime` 的单个作品。
///
/// 比 `/api/v2/search/episodes` 多了封面、上映日期、集数与评分——这些正是
/// 候选排序（封面相似度、年份、集数吻合度）依赖的字段。
class DanmakuSearchAnime {
  /// 作品编号（int64），后续 `/api/v2/bangumi/{bangumiId}` 可直接用数字形式。
  final int animeId;

  /// 作品ID（新），形如 `tmdb-movie-21832`。
  ///
  /// 注意：这不是 Bangumi.tv 的条目号，wyw 不做 bgm 条目映射。
  final String bangumiId;

  final String animeTitle;

  /// 作品类型枚举：`tvseries` / `movie` / `tmdbmovie` 等。
  final String type;

  /// 类型的中文描述。
  final String typeDescription;

  /// 海报图片地址，用于封面相似度比较；接口可能返回 null。
  final String imageUrl;

  /// 上映日期（date-time），接口可能返回 null。
  final String startDate;

  /// 剧集总数（int32），接口可能返回 null 或 0。
  final int episodeCount;

  /// 综合评分（0-10，decimal），接口可能返回 null 或 0。
  final double rating;

  /// 当前用户是否已关注；wyw 无登录态，恒为 false。
  final bool isFavorited;

  const DanmakuSearchAnime({
    required this.animeId,
    required this.bangumiId,
    required this.animeTitle,
    required this.type,
    required this.typeDescription,
    required this.imageUrl,
    required this.startDate,
    required this.episodeCount,
    required this.rating,
    required this.isFavorited,
  });

  factory DanmakuSearchAnime.fromJson(Map<String, dynamic> json) {
    return DanmakuSearchAnime(
      animeId: _asInt(json['animeId']),
      bangumiId: _asString(json['bangumiId']),
      animeTitle: _asString(json['animeTitle']),
      type: _asString(json['type']),
      typeDescription: _asString(json['typeDescription']),
      imageUrl: _asString(json['imageUrl']),
      startDate: _asString(json['startDate']),
      episodeCount: _asInt(json['episodeCount']),
      rating: _asDouble(json['rating']),
      isFavorited: _asBool(json['isFavorited']),
    );
  }

  /// 上映年份（取 `startDate` 前 4 位；长度不足或非数字时返回 null）。
  int? get year {
    if (startDate.length < 4) return null;
    return int.tryParse(startDate.substring(0, 4));
  }
}

/// `/api/v2/search/anime?keyword=&v2=true` 的响应（只取 `animes`）。
class DanmakuSearchResponse {
  final List<DanmakuSearchAnime> animes;

  const DanmakuSearchResponse({required this.animes});

  factory DanmakuSearchResponse.fromJson(Map<String, dynamic> json) {
    return DanmakuSearchResponse(
      animes: _asMapList(json['animes'])
          .map(DanmakuSearchAnime.fromJson)
          .toList(),
    );
  }
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
