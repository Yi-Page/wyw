import 'package:wyw/modules/danmaku/danmaku_ch_convert.dart';
import 'package:wyw/modules/danmaku/danmaku_module.dart';
import 'package:wyw/modules/danmaku/danmaku_episode_response.dart';
import 'package:wyw/modules/danmaku/danmaku_search_response.dart';
import 'package:wyw/request/clients/danmaku_client.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/services/storage/storage.dart';
import 'package:wyw/utils/dandan_credentials.dart';

export 'package:wyw/request/clients/danmaku_client.dart'
    show DandanNotConfiguredException;

/// 弹弹play 开放 API 端点（只读）。
///
/// 全部路径都不含域名与查询串：它们既是请求路径，也是签名覆盖的 `Path`。
class DanmakuApi {
  DanmakuApi._();

  static final DanmakuClient _client = DanmakuClient.instance;

  static const String _searchAnimePath = '/api/v2/search/anime';
  static const String _bangumiPathPrefix = '/api/v2/bangumi/';
  static const String _commentPathPrefix = '/api/v2/comment/';

  /// 未配置凭证时为 false，调用方据此跳过整块弹幕 UI（静默降级）。
  static bool get isConfigured => isDandanConfigured;

  /// 按关键词搜索作品。
  ///
  /// `v2=true` 走新版搜索引擎：旧版会把关键词塌缩成单个作品，
  /// 且 `/search/anime` 本身不带分页参数，`v2=true` 是拿到完整候选列表的前提。
  ///
  /// [type] 是可选的**服务端**类型过滤（AnimeType：`tvseries` / `movie` /
  /// `ova` / `tvspecial` / `web` …）。它不是装饰：本端点硬上限 25 条且不可翻页，
  /// 实测搜"柯南"不传 type 时 25 条里只有 3 条剧集、主系列（1220 集）**根本不在
  /// 结果里**，传 `type=tvseries` 后 6 条里就能拿到主系列。排序在客户端救不回被
  /// 服务端截断的结果，只能用服务端过滤收窄。
  static Future<DanmakuSearchResponse> searchAnime(
    String keyword, {
    String? type,
  }) async {
    final json = await _get(
      _searchAnimePath,
      queryParameters: {
        'keyword': keyword,
        'v2': 'true',
        if (type != null && type.isNotEmpty) 'type': type,
      },
    );
    if (_isFailed(json, _searchAnimePath)) {
      return const DanmakuSearchResponse(animes: []);
    }
    final response = DanmakuSearchResponse.fromJson(json);
    WywLogger().i(
      '${LogTag.danmaku} 搜索作品完成 keyword=$keyword type=${type ?? '(全部)'} '
      '候选数=${response.animes.length}',
    );
    return response;
  }

  /// 获取作品详情，用于拿权威的分集 `episodeId`，同时是**简介的唯一来源**。
  ///
  /// [bangumiId] 支持两种形式：数字形式 `animeId`（如 `266`）或字符串形式
  /// `bangumiId`（如 `tmdb-tv-30983`）——接口文档明确两者都接受，因此刷新时
  /// 优先用详情里回带出来的字符串形式。
  ///
  /// 接口对未收录作品会返回 `bangumi: null`，此时返回 null 而不是空对象，
  /// 让调用方显式走降级分支。
  static Future<DanmakuBangumiDetail?> getBangumiDetail(
    String bangumiId,
  ) async {
    final trimmed = bangumiId.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final path = '$_bangumiPathPrefix$trimmed';
    final json = await _get(path);
    if (_isFailed(json, path)) {
      return null;
    }
    final bangumi = json['bangumi'];
    if (bangumi is! Map) {
      WywLogger().w('${LogTag.danmaku} 作品详情为空 bangumiId=$trimmed');
      return null;
    }
    final detail = DanmakuBangumiDetail.fromJson(
      Map<String, dynamic>.from(bangumi),
    );
    WywLogger().i(
      '${LogTag.danmaku} 获取作品详情 bangumiId=$trimmed 剧集数=${detail.episodes.length} '
      '简介=${detail.displayIntro.length}字 标题数=${detail.titles.length}',
    );
    return detail;
  }

  /// 按弹幕库编号取弹幕。
  ///
  /// `withRelated=true` 才会带上第三方关联网址的弹幕（推荐值）；
  /// `chConvert` 按设置的简繁转换档位传给接口，由服务端做转换。
  /// 该响应没有 `success` 字段（swagger `CommentResponseV2` 只含
  /// `count`/`comments`），所以不做失败判定，解析出多少就返回多少。
  static Future<List<DanmakuEntry>> getComments(int episodeId) async {
    // 凭证检查前置：未配置时直接抛，不去读存储（本地构建常常连存储都没初始化）。
    if (!isConfigured) {
      WywLogger()
          .d('${LogTag.danmaku} 未配置弹弹play 凭证，跳过请求 path=$_commentPathPrefix$episodeId');
      throw const DandanNotConfiguredException();
    }
    final conversion = DanmakuChConvert.fromValue(
      GStorage.getSetting(SettingsKeys.danmakuChConvert),
    );
    final json = await _get(
      '$_commentPathPrefix$episodeId',
      queryParameters: {
        'withRelated': 'true',
        'chConvert': conversion.value.toString(),
      },
    );
    final entries = DanmakuEntry.listFromJson(json['comments']);
    WywLogger().i(
      '${LogTag.danmaku} 获取弹幕 episodeId=$episodeId 接口计数=${json['count']} '
      '解析条数=${entries.length}',
    );
    return entries;
  }

  static Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    if (!isConfigured) {
      // 凭证缺失是本地构建的预期状态而非故障，调用方靠异常静默降级，
      // 所以记为 debug 级别，不落盘、不打扰用户。
      WywLogger().d('${LogTag.danmaku} 未配置弹弹play 凭证，跳过请求 path=$path');
      throw const DandanNotConfiguredException();
    }
    return _client.get(path, queryParameters: queryParameters);
  }

  /// 外层统一带 `success`/`errorCode`/`errorMessage`，失败时只记警告并把
  /// 空结果交给调用方（例如关键词没命中），不升级成硬错误。
  static bool _isFailed(Map<String, dynamic> json, String path) {
    if (json['success'] != false) {
      return false;
    }
    WywLogger().w(
      '${LogTag.danmaku} 接口返回失败 path=$path errorCode=${json['errorCode']} '
      'errorMessage=${json['errorMessage']}',
    );
    return true;
  }
}
