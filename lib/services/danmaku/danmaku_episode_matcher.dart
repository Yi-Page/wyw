/// 本地集名 → 弹弹play 库分集的**保守**推导（纯函数，无 IO、无状态）。
///
/// 用途：下载完成后把弹幕缓存进剧集目录（离线播放用）。下载是后台行为、没有用户
/// 交互，所以必须在没有"用户手选"的情况下自己找一集；但这里**宁可找不到也不猜错**：
/// 返回 null 时调用方静默跳过，绝不会把隔壁集的弹幕写进这一集。
///
/// 与已被删除的"匹配记忆"的区别：这里不落任何盘，只是运行时按集号对一次位；
/// 用户手选出来的映射（本方案刻意不做持久化）若有，永远优先于本函数。
library;

import 'package:wyw/modules/danmaku/danmaku_episode_response.dart';

/// `第N集 / 第N话`：最明确的写法，优先于任何"扫第一个数字"的策略。
final RegExp _kChineseEpisode = RegExp(r'第\s*(\d{1,4})\s*[集话話]');

/// 纯数字短标题（可用作集号）：`1` / `01` / `1372`。
/// `12.5`（特别篇）、`C146`（柯南的客串集）这类**不参与**严格匹配。
final RegExp _kPureNumber = RegExp(r'^\d{1,4}$');

/// 「看起来像数字但不是集号」的噪声 token。
///
/// 实测插件给的集名长这样：`第03集 1080P`、`[Lilith-Raws] 进击的巨人 - 05 [1080p]`、
/// `名侦探柯南 S02 1024 WEB-DL`。若不做这层剔除，"1080" 会被当成第 1080 集。
final RegExp _kNoise = RegExp(
  r'\d{3,4}\s*[pPiI]' // 1080P / 720p / 480i
  r'|\d{3,4}\s*[xX]\s*\d{3,4}' // 1920x1080
  r'|[hHxX]\.?26[45]' // H264 / x265
  r'|[hH]\.?265'
  r'|(?:19|20)\d{2}' // 年份
  r'|WEB[- ]?DL|BluRay|BDRip|HEVC|AVC|AAC|FLAC|DDP?5\.?1|CHS|CHT|BIG5'
  r'|SEASON\s*\d{1,2}|S\d{1,2}\b',
  caseSensitive: false,
);

final RegExp _kDigits = RegExp(r'\d{1,4}');

/// 从本地集名里取"用户眼里的集号"；取不到返回 null。
///
/// 顺序刻意固定：先认 `第N集/话`，再退化为"剔除噪声后的第一个数字"。
/// 后者是启发式（`EVA 10` 这种写法只能这么认），因此调用方必须允许它失败。
int? localEpisodeNumber(String name) {
  final text = name.trim();
  if (text.isEmpty) return null;

  final chinese = _kChineseEpisode.firstMatch(text);
  if (chinese != null) {
    final value = int.tryParse(chinese.group(1)!);
    if (value != null && value > 0) return value;
  }

  final stripped = text.replaceAll(_kNoise, ' ');
  for (final match in _kDigits.allMatches(stripped)) {
    final value = int.tryParse(match.group(0)!);
    // 上限 999：四位以上且未被噪声规则吃掉的多半是年份/码率/时长，不是集号。
    if (value != null && value > 0 && value <= 999) return value;
  }
  return null;
}

/// 在库的分集列表里找与 [localName] 同号的那一集，返回下标；找不到返回 null。
///
/// 两条路径：
///   1. **严格**：库侧 `episodeNumber` 是纯数字且与本地集号相等（`"1"`/`"01"` 都算）；
///   2. **退位**：库侧**完全没有任何**纯数字短标题时才按"第 N 集 = 列表第 N 项"。
///      只要存在任何一条可比较的短标题就只走严格匹配——否则一半能对上的数据上
///      会整体错位（点进去是别人的弹幕，比没有弹幕更糟）。
int? matchLocalEpisodeToLibrary({
  required String localName,
  required List<DanmakuEpisodeRef> episodes,
}) {
  if (episodes.isEmpty) return null;
  final number = localEpisodeNumber(localName);
  if (number == null) return null;

  for (var i = 0; i < episodes.length; i++) {
    final raw = episodes[i].episodeNumber.trim();
    if (!_kPureNumber.hasMatch(raw)) continue;
    if (int.tryParse(raw) == number) return i;
  }

  final anyNumbered = episodes.any(
    (episode) => _kPureNumber.hasMatch(episode.episodeNumber.trim()),
  );
  if (!anyNumbered && number >= 1 && number <= episodes.length) {
    return number - 1;
  }
  return null;
}
