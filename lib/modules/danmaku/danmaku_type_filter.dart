/// `/api/v2/search/anime` 的**服务端**类型过滤档位。
///
/// 为什么必须有这一层：该端点硬上限 25 条且不可翻页（实测搜"柯南"与"高达"都
/// 恰好 25 条），而默认排序偏新上映作品——搜"柯南"时 25 条里 18 条是剧场版，
/// **主系列（1220+ 集）根本不在结果里**；加 `type=tvseries` 后 6 条里就能拿到。
/// 排序在客户端救不回被服务端截断的结果，只能用服务端过滤收窄。
///
/// `apiValue` 直接对应接口 `AnimeType` 枚举串；`null` 表示不过滤（"全部"）。
library;

enum DanmakuTypeFilter {
  all(null, '全部'),
  tv('tvseries', 'TV'),
  movie('movie', '剧场版'),
  ova('ova', 'OVA'),
  other('other', '其它');

  const DanmakuTypeFilter(this.apiValue, this.label);

  /// 传给接口 `type` 参数的值；`null` = 不传（不过滤）。
  final String? apiValue;

  /// 用户界面上显示的短标签。
  final String label;
}
