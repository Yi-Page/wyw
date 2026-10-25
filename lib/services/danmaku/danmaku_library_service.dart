import 'package:wyw/modules/danmaku/danmaku_module.dart';
import 'package:wyw/modules/danmaku/danmaku_episode_response.dart';
import 'package:wyw/modules/danmaku/danmaku_search_response.dart';
import 'package:wyw/request/apis/danmaku_api.dart';

/// 弹幕库访问的唯一入口：接口调用与凭证可用性判断收在一处。
///
/// 历史上这里还兼管"匹配记忆"（把用户手选写进 `danmakuMatch` 箱、下次播放按偏移
/// 推导）。现在两者都换了位置：
///   - **作品级选择**（用哪个库）存在进度记录里（`VideoPlaybackProgress.danmaku`），
///     跟随进度一起写盘；
///   - **分集映射**按产品口径刻意不持久化（切集后需再点一次）。
/// 于是匹配记忆层整体退场，这里只剩纯接口封装——不持有任何状态，也没有第二个
/// 事实源。
class DanmakuLibraryService {
  DanmakuLibraryService();

  static final DanmakuLibraryService instance = DanmakuLibraryService();

  /// 是否已配置弹弹play 凭证；未配置时整块弹幕功能静默关闭。
  bool get isConfigured => DanmakuApi.isConfigured;

  /// 按关键词搜索候选作品（不含分集，分集要另调 [loadDetail]）。
  ///
  /// [type] 透传给接口做**服务端**类型过滤（`tvseries`/`movie`/`ova`…）：
  /// 该端点硬上限 25 条且不可翻页，泛关键词（实测"柯南"）会把主系列挤出结果，
  /// 客户端排序救不回被截断的结果，只有服务端过滤能救。
  Future<List<DanmakuSearchAnime>> searchAnime(
    String keyword, {
    String? type,
  }) async {
    final response = await DanmakuApi.searchAnime(keyword, type: type);
    return response.animes;
  }

  /// 取作品完整详情（分集 + 简介/评分/多语言标题/标签）。
  ///
  /// [bangumiId] 优先用详情回带出来的字符串形式（如 `tmdb-tv-30983`）；
  /// 数字 `animeId` 也可，接口两种都接受。
  Future<DanmakuBangumiDetail?> loadDetail(String bangumiId) {
    return DanmakuApi.getBangumiDetail(bangumiId);
  }

  /// 按弹幕库编号取弹幕。
  Future<List<DanmakuEntry>> loadComments(int episodeId) {
    return DanmakuApi.getComments(episodeId);
  }
}
