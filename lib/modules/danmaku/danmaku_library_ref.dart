import 'package:wyw/modules/danmaku/danmaku_episode_response.dart';

/// 「这部作品用弹弹play 的哪个库」——**作品级条目信息**。
///
/// 与已删除的"匹配记忆"（`DanmakuLibraryMatch` + `danmakuMatch` 箱）的关键区别：
/// 这里只记"用户选了哪个库"，**不记任何集映射**。分集选择按产品口径刻意不
/// 持久化（切集后需再点一次），所以这个对象足够小，可以直接放进进度记录
/// （`VideoPlaybackProgress.danmaku`）：跟随进度一起写盘、一起被历史/备份机制
/// 带走，不需要额外的 Hive 箱，也没有"箱与进度不同步"的可能。
///
/// 存的是**展示用快照**（封面/标题/简介/评分/集数/年份）：断网、接口改版或条目被
/// 删时，卡片仍能显示"当前使用的是哪一个"，只有 [refreshableId] 的刷新会失败。
///
/// **重数据不在这里**：分集列表（可达上千集）、多语言标题、标签都放进
/// `DanmakuLibraryCacheRepository`（按库 id 键的独立箱），这里只留能渲染卡片的
/// 那几项。原因是进度记录每 5–15 秒就被整体重写一次，把上千集塞进这个对象等于
/// 每次写都重新序列化一份大对象；而缓存是**可重建的派生数据**，丢了重拉一次即可。
/// `test/danmaku_library_ref_test.dart` 用键集断言把这条契约钉死了。
class DanmakuLibraryRef {
  const DanmakuLibraryRef({
    required this.animeId,
    this.bangumiId = '',
    required this.libraryTitle,
    this.imageUrl = '',
    this.intro = '',
    this.summary = '',
    this.rating = 0,
    this.episodeCount = 0,
    this.year = 0,
    required this.savedAtMs,
  });

  /// 弹弹play 作品编号。
  final int animeId;

  /// 字符串形式作品 id（数字串或 `tmdb-tv-30983` 这类）。
  final String bangumiId;

  /// 作品名，UI 上说明"当前用的是哪个库"。
  final String libraryTitle;

  /// 海报地址（详情卡与"当前使用"卡片用）。
  final String imageUrl;

  /// 短简介（Staff 或剧情简介）。
  final String intro;

  /// 长简介。
  final String summary;

  /// 综合评分 0-10。
  final double rating;

  /// 库的分集总数（来自详情接口的分集列表长度）。
  final int episodeCount;

  /// 上映年份（0 = **未知**，不是"确定没有"）。
  ///
  /// 来源优先级：搜索结果的 `startDate`（系列级，最准）> 详情首集 `airDate`
  /// （`DanmakuBangumiDetail.firstAirYear`）> 0。详情接口不返回 `startDate`，
  /// 所以"从搜索结果预览"时带进来的值要随快照持久化，否则卡片上的年份会在详情到手后
  /// 凭空消失；反过来，0 也会在下次点分集/刷新时用首集 `airDate` 补上（自愈），
  /// 因此老记录不会永远显示 `—`。
  final int year;

  /// 记录时间（毫秒）。
  final int savedAtMs;

  /// `libraryTitle` 为空视为无效记录：宁可当作"没选过"，也不要显示一个空白卡片。
  bool get isValid => animeId > 0 && libraryTitle.isNotEmpty;

  /// 刷新详情用的 id。
  ///
  /// 优先字符串形式 `bangumiId`：`/bangumi/{bangumiId}` 两种形式都接受，而字符串
  /// 形式是接口自己的规范 id（数字编号是它内部兼容用的）。
  String get refreshableId => bangumiId.isNotEmpty ? bangumiId : '$animeId';

  /// 卡片优先展示的简介：长简介为空时退回短简介（实测剧场版 `intro` 为空的条目）。
  String get displayIntro => summary.isNotEmpty ? summary : intro;

  /// 由接口详情构造：点选与刷新**共用同一条构造路径**，避免两处字段口径漂移。
  factory DanmakuLibraryRef.fromDetail(
    DanmakuBangumiDetail detail, {
    int? savedAtMs,
    int? year,
  }) {
    return DanmakuLibraryRef(
      animeId: detail.animeId,
      bangumiId: detail.bangumiId,
      libraryTitle: detail.animeTitle,
      imageUrl: detail.imageUrl,
      intro: detail.intro,
      summary: detail.summary,
      rating: detail.rating,
      // 集数取详情分集列表长度：搜索接口的 `episodeCount` 对 TMDB 源恒为 1，
      // 详情列表才是权威（实测柯南主系列 1372 集）。
      episodeCount: detail.episodes.length,
      // 年份优先级：调用方给的（来自搜索结果的 `startDate`）> 详情首集 `airDate` > 0。
      //
      // `0` 也要走兜底——进度记录里的 0 表示"当时没拿到"（老记录、或该条目接口没给
      // startDate），不是"确定没有年份"；这样下一次点分集/刷新就能把年份补回快照，
      // 卡片不会永远显示 `—`。
      year: (year ?? 0) > 0 ? year! : detail.firstAirYear,
      savedAtMs: savedAtMs ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toMap() => {
        'animeId': animeId,
        'bangumiId': bangumiId,
        'libraryTitle': libraryTitle,
        'imageUrl': imageUrl,
        'intro': intro,
        'summary': summary,
        'rating': rating,
        'episodeCount': episodeCount,
        'year': year,
        'savedAtMs': savedAtMs,
      };

  /// 容错解析：进度记录里存的是我们自己写的 Map，但字段可能来自旧版本或被外部
  /// 改写，因此数字字符串也接受、缺失退化，绝不抛异常（一条坏记录不该让播放页炸）。
  factory DanmakuLibraryRef.fromMap(Map<dynamic, dynamic> map) {
    return DanmakuLibraryRef(
      animeId: _asInt(map['animeId']),
      bangumiId: _asString(map['bangumiId']),
      libraryTitle: _asString(map['libraryTitle']),
      imageUrl: _asString(map['imageUrl']),
      intro: _asString(map['intro']),
      summary: _asString(map['summary']),
      rating: _asDouble(map['rating']),
      episodeCount: _asInt(map['episodeCount']),
      year: _asInt(map['year']),
      savedAtMs: _asInt(map['savedAtMs']),
    );
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

double _asDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

String _asString(Object? value) => value is String ? value : '';
