import 'package:flutter_test/flutter_test.dart';
import 'package:wyw/modules/danmaku/danmaku_module.dart';
import 'package:wyw/pages/player/controller/player_danmaku_controller.dart';
import 'package:wyw/utils/danmaku.dart';

DanmakuEntry _entry(String message, double time, {int type = 1}) {
  return DanmakuEntry(
    message: message,
    time: time,
    type: type,
    color: generateDanmakuColor(0xFFFFFF),
    source: '1',
  );
}

void main() {
  group('DanmakuTimeline.resolveSourceSecond', () {
    test('无偏移时直接取整秒', () {
      expect(
        DanmakuTimeline.resolveSourceSecond(
          const Duration(milliseconds: 12900),
          0,
        ),
        12,
      );
    });

    test('正偏移表示弹幕比视频晚，需要往前找', () {
      expect(
        DanmakuTimeline.resolveSourceSecond(const Duration(seconds: 30), 5),
        25,
      );
    });

    test('负偏移表示弹幕比视频早，需要往后找', () {
      expect(
        DanmakuTimeline.resolveSourceSecond(const Duration(seconds: 30), -5),
        35,
      );
    });

    test('换算结果为负数时返回 null（该位置还没有弹幕）', () {
      expect(
        DanmakuTimeline.resolveSourceSecond(const Duration(seconds: 3), 5),
        isNull,
      );
    });

    test('恰好落在 0 秒仍然有效（不是 null）', () {
      expect(
        DanmakuTimeline.resolveSourceSecond(const Duration(seconds: 5), 5),
        0,
      );
    });
  });

  group('DanmakuTimeline.staggerDelayMilliseconds', () {
    test('总数非正时返回 0', () {
      expect(
        DanmakuTimeline.staggerDelayMilliseconds(index: 3, total: 0),
        0,
      );
    });

    test('第一条不延迟，后续严格递增且全部落在 1 秒内', () {
      const total = 7;
      final delays = [
        for (var i = 0; i < total; i++)
          DanmakuTimeline.staggerDelayMilliseconds(index: i, total: total),
      ];
      expect(delays.first, 0);
      for (var i = 1; i < delays.length; i++) {
        expect(delays[i], greaterThan(delays[i - 1]));
      }
      expect(delays.last, lessThan(1000));
    });

    test('只有一条时不产生延迟', () {
      expect(
        DanmakuTimeline.staggerDelayMilliseconds(index: 0, total: 1),
        0,
      );
    });
  });

  group('mergeDuplicateDanmakus', () {
    test('关闭时间窗时同文本全局合并为顶部 xN', () {
      final merged = mergeDuplicateDanmakus([
        _entry('哈哈', 1),
        _entry('哈哈', 2),
        _entry('哈哈', 3),
      ]);
      expect(merged, hasLength(1));
      expect(merged.single.message, '哈哈 x3');
      expect(merged.single.type, 5, reason: '合并结果置顶，避免继续刷屏');
    });

    test('不重复的弹幕原样保留', () {
      final merged = mergeDuplicateDanmakus([
        _entry('第一条', 1),
        _entry('第二条', 2),
      ]);
      expect(merged, hasLength(2));
      expect(merged.map((e) => e.message), containsAll(['第一条', '第二条']));
    });

    test('开启时间窗后，窗口外的同文本不会被合并到一起', () {
      final merged = mergeDuplicateDanmakus(
        [
          _entry('名场面', 1),
          _entry('名场面', 2),
          _entry('名场面', 60),
        ],
        timeWindowSeconds: 5,
      );
      expect(merged, hasLength(2));
      final messages = merged.map((e) => e.message).toList();
      expect(messages, contains('名场面 x2'));
      expect(messages, contains('名场面'));
    });

    test('全角与空白差异不影响合并判定', () {
      final merged = mergeDuplicateDanmakus([
        _entry('前方　高能', 1),
        _entry('前方 高能', 2),
      ]);
      expect(merged, hasLength(1));
      expect(merged.single.message, endsWith('x2'));
    });

    test('连续重复字符被压缩到 3 个后仍能合并', () {
      // 4 个与 5 个连续「哈」都会被归一化成 3 个，因此视为同一条。
      final merged = mergeDuplicateDanmakus([
        _entry('哈哈哈哈', 1),
        _entry('哈哈哈哈哈', 2),
      ]);
      expect(merged, hasLength(1));
    });
  });
}
