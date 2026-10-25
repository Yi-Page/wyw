import 'package:flutter_test/flutter_test.dart';
import 'package:wyw/modules/danmaku/danmaku_shield_rule.dart';

void main() {
  group('isDanmakuShielded 普通文本', () {
    test('子串命中', () {
      expect(isDanmakuShielded('前方高能预警', ['前方高能']), isTrue);
      expect(isDanmakuShielded('前方高能', ['前方高能']), isTrue);
    });

    test('不命中时放行', () {
      expect(isDanmakuShielded('这条很正常', ['前方高能']), isFalse);
    });

    test('空文本与空规则都不算命中', () {
      expect(isDanmakuShielded('', ['前方高能']), isFalse);
      expect(isDanmakuShielded('前方高能', ['']), isFalse);
    });
  });

  group('isDanmakuShielded 正则', () {
    test('/正则/ 按正则匹配', () {
      expect(isDanmakuShielded('12345', [r'/^\d+$/']), isTrue);
      expect(isDanmakuShielded('abc123', [r'/^\d+$/']), isFalse);
    });

    test('不以斜杠包裹时按普通子串处理，不解释成正则', () {
      // `\d+` 作为子串并不出现在消息里，因此不命中；若被当成正则会命中。
      expect(isDanmakuShielded('12345', [r'\d+']), isFalse);
    });

    test('单个坏正则被跳过，不影响其它规则', () {
      // `/([/` 首尾都是斜杠 → 是正则规则，但 `([` 编译不过 → 该条被跳过，
      // 后面的普通规则仍然生效。
      expect(isDanmakuShielded('前方高能', ['/([/', '前方高能']), isTrue);
      expect(isDanmakuShielded('前方高能', ['/([/']), isFalse);
    });

    test('空正则（//）被跳过而不是匹配一切', () {
      expect(isDanmakuShielded('任意内容', ['//']), isFalse);
    });
  });

  group('validateDanmakuShieldRule', () {
    test('空串与纯空白不合法', () {
      expect(validateDanmakuShieldRule(''), DanmakuShieldRuleError.empty);
      expect(validateDanmakuShieldRule('   '), DanmakuShieldRuleError.empty);
    });

    test('超长不合法', () {
      final tooLong = 'a' * (kDanmakuShieldRuleMaxLength + 1);
      expect(validateDanmakuShieldRule(tooLong),
          DanmakuShieldRuleError.tooLong);
      expect(
        validateDanmakuShieldRule('a' * kDanmakuShieldRuleMaxLength),
        isNull,
      );
    });

    test('正则语法错误会被拦下', () {
      expect(validateDanmakuShieldRule('/([/'),
          DanmakuShieldRuleError.invalidPattern);
      expect(validateDanmakuShieldRule(r'/^\d+$/'), isNull);
    });

    test('普通文本（含斜杠但不构成正则包裹）合法', () {
      expect(validateDanmakuShieldRule('前方高能'), isNull);
      expect(validateDanmakuShieldRule('a/b'), isNull);
      expect(validateDanmakuShieldRule('//'), isNull);
    });
  });

  group('patternOf', () {
    test('剥掉正则的包裹斜杠', () {
      expect(patternOf(r'/^\d+$/'), r'^\d+$');
    });

    test('非正则原样返回', () {
      expect(patternOf('前方高能'), '前方高能');
    });
  });
}
