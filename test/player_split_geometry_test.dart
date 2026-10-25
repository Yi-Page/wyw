import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyw/pages/player/controller/player_split_geometry.dart';

void main() {
  group('splitAxisFor', () {
    test('宽大于高 → 左右分屏', () {
      expect(splitAxisFor(const Size(1920, 1080)), SplitAxis.horizontal);
    });

    test('高大于宽 → 上下分屏', () {
      expect(splitAxisFor(const Size(1080, 1920)), SplitAxis.vertical);
    });

    test('正方形按横屏处理（宽 >= 高）', () {
      expect(splitAxisFor(const Size(800, 800)), SplitAxis.horizontal);
    });
  });

  group('panelWidthRange（横屏，像素）', () {
    test('空间充足：上限取 640', () {
      expect(panelWidthRange(1920), const SplitPanelRange(280, 640));
    });

    test('空间中等：上限由视频区保底 420 反推', () {
      expect(panelWidthRange(900), const SplitPanelRange(280, 480));
    });

    test('刚好容得下视频区保底时区间收成一点', () {
      expect(panelWidthRange(700), const SplitPanelRange(280, 280));
    });

    test('窗口过窄：视频区保底退化到 240', () {
      expect(panelWidthRange(620), const SplitPanelRange(280, 380));
    });

    test('窗口极窄：视频区保底再退化到 160，并保证区间非空', () {
      final range = panelWidthRange(380);
      expect(range.min, 220);
      expect(range.max, 220);
      expect(range.isDegenerate, isTrue);
    });
  });

  group('defaultPanelWidth（横屏自动档）', () {
    test('取可用宽 1/3，并受 320~420 夹取', () {
      expect(defaultPanelWidth(1920), 420);
      expect(defaultPanelWidth(1200), 400);
      expect(defaultPanelWidth(900), 320);
    });

    test('窄窗口下默认值也被区间夹住', () {
      // 700/3 = 233 → 抬到 320 → 收进 [280, 280] → 280。
      expect(defaultPanelWidth(700), 280);
    });
  });

  group('resolvePanelWidth（横屏记忆值 = 像素）', () {
    test('记忆值为 0 走自动档', () {
      expect(resolvePanelWidth(availableWidth: 1200, storedWidth: 0), 400);
    });

    test('区间内原样使用', () {
      expect(resolvePanelWidth(availableWidth: 1200, storedWidth: 500), 500);
    });

    test('超出上限被夹到上限', () {
      expect(resolvePanelWidth(availableWidth: 900, storedWidth: 700), 480);
    });

    test('低于下限被夹到下限', () {
      expect(resolvePanelWidth(availableWidth: 900, storedWidth: 100), 280);
    });
  });

  group('panelWidthOutOfRange', () {
    test('自动档永远合法', () {
      expect(
        panelWidthOutOfRange(availableWidth: 900, storedWidth: 0),
        isFalse,
      );
    });

    test('区间内不越界', () {
      expect(
        panelWidthOutOfRange(availableWidth: 1200, storedWidth: 640),
        isFalse,
      );
    });

    test('窗口变小后旧的大值越界', () {
      expect(
        panelWidthOutOfRange(availableWidth: 900, storedWidth: 640),
        isTrue,
      );
    });

    test('小于下限也判为越界', () {
      expect(
        panelWidthOutOfRange(availableWidth: 900, storedWidth: 200),
        isTrue,
      );
    });
  });

  group('panelHeightRange（竖屏）', () {
    test('区间为容器高的 30% ~ 70%', () {
      expect(panelHeightRange(800), const SplitPanelRange(240, 560));
    });
  });

  group('defaultPanelHeight（竖屏）', () {
    test('取容器高 45%', () {
      expect(defaultPanelHeight(800), 360);
    });
  });

  group('resolvePanelHeight（竖屏记忆值 = 高度占比）', () {
    test('占比为 0 走默认值', () {
      expect(resolvePanelHeight(availableHeight: 800, storedFraction: 0), 360);
    });

    test('占比 0.45 原样换算为像素', () {
      expect(
        resolvePanelHeight(availableHeight: 800, storedFraction: 0.45),
        360,
      );
    });

    test('占比超过 70% 被夹到 70%', () {
      expect(
        resolvePanelHeight(availableHeight: 800, storedFraction: 0.9),
        560,
      );
    });

    test('占比低于 30% 被夹到 30%', () {
      expect(
        resolvePanelHeight(availableHeight: 800, storedFraction: 0.1),
        240,
      );
    });

    test('占比是相对容器高的，随容器变化', () {
      expect(
        resolvePanelHeight(availableHeight: 1000, storedFraction: 0.5),
        500,
      );
    });
  });

  group('panelHeightFractionOutOfRange', () {
    test('占比为 0 视为自动，永远合法', () {
      expect(
        panelHeightFractionOutOfRange(
          availableHeight: 800,
          storedFraction: 0,
        ),
        isFalse,
      );
    });

    test('30%~70% 内不越界', () {
      expect(
        panelHeightFractionOutOfRange(
          availableHeight: 800,
          storedFraction: 0.45,
        ),
        isFalse,
      );
    });

    test('超出 70% 越界', () {
      expect(
        panelHeightFractionOutOfRange(
          availableHeight: 800,
          storedFraction: 0.9,
        ),
        isTrue,
      );
    });
  });

  group('clampDouble', () {
    test('把值收进闭区间', () {
      expect(clampDouble(5, 0, 10), 5);
      expect(clampDouble(-1, 0, 10), 0);
      expect(clampDouble(11, 0, 10), 10);
    });
  });
}
