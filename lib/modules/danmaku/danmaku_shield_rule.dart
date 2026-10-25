/// 弹幕屏蔽词的校验与匹配（纯函数，便于单测）。
///
/// 两种写法：
///   - 普通文本：按**子串**匹配（`前方高能` 命中 `前方高能预警`）；
///   - `/正则/`：首尾都是斜杠时按正则匹配，用于"某类刷屏"这种没法穷举的场景。
library;

/// 屏蔽词最大长度。太长既没有实际用途，也容易掩盖用户手滑粘进来的整段文本。
const int kDanmakuShieldRuleMaxLength = 64;

enum DanmakuShieldRuleError { empty, tooLong, invalidPattern }

/// 校验一条屏蔽词；合法返回 null。
DanmakuShieldRuleError? validateDanmakuShieldRule(String rule) {
  if (rule.trim().isEmpty) {
    return DanmakuShieldRuleError.empty;
  }
  if (rule.length > kDanmakuShieldRuleMaxLength) {
    return DanmakuShieldRuleError.tooLong;
  }
  if (_isRegexRule(rule) && !_canCompile(patternOf(rule))) {
    return DanmakuShieldRuleError.invalidPattern;
  }
  return null;
}

/// 是否命中任一屏蔽词。
///
/// 设计取舍：**单个规则写坏不影响其它规则**。正则编译失败时跳过这一条并继续，
/// 因为屏蔽词是用户随手维护的列表，不该因为一条手滑把整个弹幕功能弄停摆；
/// 同时调用方可以先用 [validateDanmakuShieldRule] 拒绝非法输入。
bool isDanmakuShielded(String message, Iterable<String> rules) {
  if (message.isEmpty) {
    return false;
  }
  for (final rule in rules) {
    if (rule.isEmpty) {
      continue;
    }
    if (_isRegexRule(rule)) {
      final pattern = patternOf(rule);
      if (pattern.isEmpty) {
        continue;
      }
      try {
        if (RegExp(pattern).hasMatch(message)) {
          return true;
        }
      } catch (_) {
        // 非法正则：跳过这条规则。
        continue;
      }
    } else if (message.contains(rule)) {
      return true;
    }
  }
  return false;
}

/// 取出正则规则的主体（去掉首尾斜杠）。非正则规则原样返回。
String patternOf(String rule) {
  if (!_isRegexRule(rule)) {
    return rule;
  }
  return rule.substring(1, rule.length - 1);
}

bool _isRegexRule(String rule) =>
    rule.length > 2 && rule.startsWith('/') && rule.endsWith('/');

bool _canCompile(String pattern) {
  if (pattern.isEmpty) {
    return false;
  }
  try {
    RegExp(pattern);
    return true;
  } catch (_) {
    return false;
  }
}
