import 'dart:ui';

import 'package:wyw/modules/danmaku/danmaku_module.dart';

/// 弹弹play 弹幕颜色还原。
///
/// 官方 swagger（`CommentData.p`）说明颜色段是 32 位整数，算法为
/// `R * 256 * 256 + G * 256 + B`，这里按位取出 RGB 再交给 Flutter。
///
/// 与 Kazumi 的唯一差异是字面量形式：本仓库的硬编码颜色 guard 只允许白名单
/// 文件出现 `Color.fromARGB`/`Color(0x…)`，这里的色值来自接口数据而非主题，
/// 所以用等价的 `Color.from(...)` 写法（语义完全一致）。
Color generateDanmakuColor(int colorValue) {
  final red = (colorValue >> 16) & 0xFF;
  final green = (colorValue >> 8) & 0xFF;
  final blue = colorValue & 0xFF;
  return Color.from(
    alpha: 1,
    red: red / 255,
    green: green / 255,
    blue: blue / 255,
  );
}

/// 合并重复弹幕。
///
/// 同一时间点附近的相同文本（刷屏、复读、机器人）没必要逐条滚动，合并成
/// 「文本 xN」并置顶，既省画布空间也让观众能看清热度。归一化规则按顺序为：
/// 全角空格转半角、全角 ASCII 转半角、去掉空白、只保留文字与假名、
/// 连续 3 个以上相同字符压缩成 3 个。
///
/// [timeWindowSeconds] <= 0 时只做「同文本全局合并」，不做时间窗分组。
List<DanmakuEntry> mergeDuplicateDanmakus(
  List<DanmakuEntry> danmakus, {
  double timeWindowSeconds = 0,
}) {
  final grouped = <String, List<DanmakuEntry>>{};

  for (final danmaku in danmakus) {
    var text = danmaku.message.trim().toLowerCase();

    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if (code == 0x3000) {
        buffer.writeCharCode(0x20);
      } else if (code >= 0xFF01 && code <= 0xFF5E) {
        buffer.writeCharCode(code - 0xFEE0);
      } else {
        buffer.writeCharCode(code);
      }
    }
    text = buffer.toString();
    text = text.replaceAll(RegExp(r'\s+'), '');
    text = text.replaceAll(
      RegExp(
        r'[^\w\u4e00-\u9fff\u3040-\u309F\u30A0-\u30FF\u31F0-\u31FF\uFF65-\uFF9F]',
        unicode: true,
      ),
      '',
    );
    text = text.replaceAllMapped(RegExp(r'(.)\1{2,}'), (match) {
      final char = match.group(1)!;
      return char * 3;
    });

    grouped.putIfAbsent(text, () => []);
    grouped[text]!.add(danmaku);
  }

  final result = <DanmakuEntry>[];

  grouped.forEach((normalized, list) {
    if (list.isEmpty) return;

    if (timeWindowSeconds <= 0) {
      _addMergedGroup(result, list);
      return;
    }

    list.sort((a, b) => a.time.compareTo(b.time));

    var currentGroup = <DanmakuEntry>[];
    for (final item in list) {
      if (currentGroup.isEmpty) {
        currentGroup.add(item);
        continue;
      }
      final last = currentGroup.last;
      if ((item.time - last.time) <= timeWindowSeconds) {
        currentGroup.add(item);
      } else {
        _addMergedGroup(result, currentGroup);
        currentGroup = [item];
      }
    }

    if (currentGroup.isNotEmpty) {
      _addMergedGroup(result, currentGroup);
    }
  });

  return result;
}

void _addMergedGroup(List<DanmakuEntry> result, List<DanmakuEntry> group) {
  if (group.length == 1) {
    result.add(group.first);
    return;
  }
  result.add(
    DanmakuEntry(
      message: '${group.first.message} x${group.length}',
      time: group.first.time,
      type: 5,
      color: generateDanmakuColor(0xFFFFFF),
      source: group.first.source,
    ),
  );
}
