import 'package:flutter/material.dart';
import 'package:wyw/utils/danmaku.dart';

/// 单条弹幕。
///
/// 对应 `GET /api/v2/comment/{episodeId}` 的 `comments[]`（swagger
/// `CommentData`）：`cid` / `m` / `p`，其中 `p` 的格式为
/// `出现时间,模式,颜色,用户ID`。
/// 颜色还原（`generateDanmakuColor`）与 Kazumi 一样放在 `utils/danmaku.dart`。
class DanmakuEntry {
  /// 弹幕内容（`m`）。
  String message;

  /// 出现时间，单位秒（`p` 第 1 段，形如 `12.34`，精确到小数点后两位）。
  double time;

  /// 弹幕模式（`p` 第 2 段）：1-普通，4-底部，5-顶部。
  int type;

  /// 弹幕颜色（`p` 第 3 段）。
  Color color;

  /// `p` 第 4 段。官方定义是「用户ID」——字符串形式的用户标识，通常是数字，
  /// 不含特殊字符。
  ///
  /// 注意：Kazumi 把这个字段注释成「弹幕来源（BiliBili/Gamer）」，与官方
  /// swagger 不符（那是历史误读）。wyw 只消费 time/type/color；这里原样保留
  /// 是为了排障，也是去重/复用弹幕时唯一能区分发布者的字段。
  String source;

  DanmakuEntry({
    required this.message,
    required this.time,
    required this.type,
    required this.color,
    required this.source,
  });

  /// 第三方数据容错：`m`/`p` 缺失、或 `p` 的段数不足时退化为安全默认值，
  /// 不让单条脏弹幕炸掉整条链路。
  factory DanmakuEntry.fromJson(Map<String, dynamic> json) {
    final parts = ((json['p'] as String?) ?? '').split(',');
    return DanmakuEntry(
      message: (json['m'] as String?) ?? '',
      time: double.tryParse(_partAt(parts, 0)) ?? 0,
      type: int.tryParse(_partAt(parts, 1)) ?? 1,
      color: generateDanmakuColor(int.tryParse(_partAt(parts, 2)) ?? 0xFFFFFF),
      source: _partAt(parts, 3),
    );
  }

  /// 解析 `comments` 数组：`comments` 缺失/为 null/不是数组时返回空列表，
  /// 单个非法元素跳过而不是让整批弹幕失败。
  static List<DanmakuEntry> listFromJson(Object? comments) {
    if (comments is! List) return const [];
    final entries = <DanmakuEntry>[];
    for (final item in comments) {
      if (item is Map) {
        entries.add(DanmakuEntry.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    return entries;
  }

  /// 序列化回与接口一致的形状（缓存/转发弹幕时用）。
  Map<String, dynamic> toJson() {
    // 只写回 RGB：接口的颜色段不含透明度。
    return {
      'm': message,
      'p': '$time,$type,${color.toARGB32() & 0xFFFFFF},$source',
    };
  }
}

String _partAt(List<String> parts, int index) {
  if (index >= parts.length) return '';
  return parts[index].trim();
}
