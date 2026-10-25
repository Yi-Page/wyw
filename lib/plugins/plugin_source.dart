/// 插件源码规范校验：**命名链** + **类声明形态** + **括号配平**。
///
/// ## 命名链（四环逐字符相同）
///
/// ```
/// 文件名  hanime.js
/// 索引键  index.json → plugins["hanime"]
/// 类名    class hanime extends PluginSource
/// 引擎槽位 __plugins__["hanime"]
/// ```
///
/// ## 校验项
///
/// | 项 | 级别 | 说明 |
/// |---|---|---|
/// | 非空 | 错误 | |
/// | 括号配平 `{}` `()` `[]` | 错误 | 在掩码后的源码上做，字面量 / 注释里的括号不参与 |
/// | 顶层 `class` 声明恰好 1 处 | 错误 | 数的是**所有**顶层 `class`，不只是 `extends PluginSource` 的 |
/// | 类名 = 插件名 | 错误 | JS 类名敏感、文件系统不敏感，必须逐字符相同 |
/// | 类声明之外还有代码 | **提示** | 合法 JS，但加载时会执行，且与顺序有关 |
///
/// 「类外有代码」只提示不拦截：存量插件里确实有这种写法，而且它是**能跑的**
/// —— 拦截会让它们直接注册失败。它是风格 / 健壮性问题（顶层副作用在类定义前执行），
/// 交给用户判断。
///
/// ## 只读校验
///
/// 本文件只做通过 / 不通过，**永不用于改写源码**。39 个内置插件里 7 个在类外有代码、
/// 2 个在类体内含第 1 列的 `}`、38/39 用模板字面量 —— 靠正则提取类体必然出错，
/// 所以类体边界只能用**括号配对**求（掩码后数字符），不能用正则找 `^}`。
library;

/// 一处顶层类声明的命中信息。
class PluginClassHit {
  const PluginClassHit({
    required this.className,
    required this.line,
    required this.offset,
  });

  /// 捕获到的类名
  final String className;

  /// 1 起的行号
  final int line;

  /// 在掩码后源码中的字符偏移
  final int offset;

  @override
  String toString() => '$className@$line';
}

/// 校验结果。[message] 是硬错误（不通过，可直接展示给用户）；
/// [warnings] 是提示，**不阻断注册**。
class PluginSourceCheck {
  const PluginSourceCheck._({
    this.hits = const [],
    this.message,
    this.warnings = const [],
  });

  /// 通过（且无提示）
  static const PluginSourceCheck pass = PluginSourceCheck._();

  /// 顶层类声明命中列表（用于诊断）
  final List<PluginClassHit> hits;

  /// 不通过的原因；通过时为 null
  final String? message;

  /// 能跑但不推荐的问题（例如类声明之外还有代码）
  final List<String> warnings;

  bool get ok => message == null;

  bool get hasWarnings => warnings.isNotEmpty;

  @override
  String toString() => ok
      ? 'PluginSourceCheck.ok${hasWarnings ? '(+${warnings.length} 提示)' : ''}'
      : 'PluginSourceCheck.fail($message)';
}

/// 插件名规则（字符集 / 保留名 / 大小写折叠）
abstract final class PluginNameRules {
  /// 合法插件名的字符集：**小写**字母或下划线开头，其余为小写字母 / 数字 / 下划线。
  ///
  /// 插件名同时是**文件名**（`{name}.js`）、**索引键**、**JS 类名**与
  /// **引擎槽位名**，所以必须满足 JS 标识符规则：不能以数字开头，不能含
  /// `-`、`.`、空格、`/` 等。`class my-rule {}` 在 JS 里根本不合法。
  ///
  /// **为什么强制小写**：文件系统大小写不敏感（Windows / macOS）而 JS 类名敏感，
  /// `hanime.js` 与 `Hanime.js` 是同一个文件却对应两个不同的类名。允许大写就永远
  /// 要做「折叠查重 + 拼写对齐」，而且外部放进来的文件随时可能制造折叠冲突。
  /// 把规则收在**准入**这一侧（[PluginNameRules.validate]），冲突就不可能产生。
  ///
  /// ⚠️ 这是**准入规则，不是存量规则**：已经存在的记录（含历史遗留的大写名字）
  /// 照常加载、照常可用，不由本规则判死 —— 见 `PluginController.rescan` 的扫描顺序。
  static final RegExp pattern = RegExp(r'^[a-z_][a-z0-9_]*$');

  /// Windows 保留设备名（大小写不敏感）：`con.js` 这类文件在 Windows 上不可用。
  static const Set<String> _reserved = {
    'con', 'prn', 'aux', 'nul',
    'com1', 'com2', 'com3', 'com4', 'com5', 'com6', 'com7', 'com8', 'com9',
    'lpt1', 'lpt2', 'lpt3', 'lpt4', 'lpt5', 'lpt6', 'lpt7', 'lpt8', 'lpt9',
  };

  /// 大小写折叠键：用于「必须大小写不敏感唯一」的查重。
  static String fold(String name) => PluginNameFold.of(name);

  /// 校验插件名；合法返回 null，否则返回可直接展示给用户的错误信息。
  static String? validate(String name) {
    if (name.isEmpty) return '插件名不能为空';
    if (!pattern.hasMatch(name)) {
      if (_looksLikeUppercaseOnly(name)) {
        return '插件名必须全小写：`$name` 含大写字母'
            '（它同时是文件名、索引键与 JS 类名；文件系统大小写不敏感，'
            '允许大写就无法保证唯一）';
      }
      return '插件名只能以小写字母或下划线开头，且仅含小写字母、数字、下划线'
          '（它同时是文件名、索引键与 JS 类名）';
    }
    if (_reserved.contains(name.toLowerCase())) {
      return '插件名不能是系统保留名（$name）';
    }
    return null;
  }

  /// 名字是否「仅因含大写字母」而不合法（用于给出更准确的提示）。
  static bool _looksLikeUppercaseOnly(String name) {
    if (!name.contains(RegExp(r'[A-Z]'))) return false;
    return RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name);
  }

  /// 存量记录的名字是否仍是大写形态（准入规则管不到它，只能提示）。
  ///
  /// 只用于日志 / 提示，**不参与任何判定** —— 历史遗留的大写插件必须继续可用。
  static bool isLegacyName(String name) =>
      name.contains(RegExp(r'[A-Z]')) && !pattern.hasMatch(name);
}

/// 插件名的大小写折叠（文件系统不敏感，写盘前必须用它查重）。
abstract final class PluginNameFold {
  static String of(String name) => name.trim().toLowerCase();
}

/// 源码形态校验器（只读）。
abstract final class PluginSourceRule {
  /// 顶层类声明：**必须从第 1 列开始**，且 `extends PluginSource` 与类名同行。
  ///
  /// 列 0 的要求是免费收益：顺带排除「方法内部嵌套的类」，也挡住大部分被 IIFE
  /// 包住的情况（那种情况即使正则通过，注册时 `new NAME()` 也会抛
  /// `ReferenceError`）。基类写死 `PluginSource`，不写通配，换取精确性。
  static final RegExp classDeclaration = RegExp(
    r'^class[ \t]+([A-Za-z_$][\w$]*)[ \t]+extends[ \t]+PluginSource\b',
    multiLine: true,
  );

  /// **任何**顶层类声明（不要求 `extends PluginSource` 同行）。
  ///
  /// 用来数「一共几个类」：只数 [classDeclaration] 的话，
  /// 文件里再放一个 `class Helper {}` 是查不出来的。
  static final RegExp anyClassDeclaration = RegExp(
    r'^class[ \t]+([A-Za-z_$][\w$]*)',
    multiLine: true,
  );

  /// 校验 [source] 是否符合本文件的全部规则（见库文档的表格）。
  static PluginSourceCheck check({
    required String source,
    required String pluginName,
  }) {
    if (source.trim().isEmpty) {
      return const PluginSourceCheck._(message: '插件源码为空');
    }
    final masked = maskCommentsAndLiterals(source);

    // ① 括号配平：先查它 —— 括号乱了后面的类声明定位也不可信
    final unbalanced = _checkBalanced(masked);
    if (unbalanced != null) return PluginSourceCheck._(message: unbalanced);

    // ② 顶层类声明：先数「所有类」，再确认那一个是不是 extends PluginSource
    final hits = <PluginClassHit>[];
    for (final match in classDeclaration.allMatches(masked)) {
      hits.add(PluginClassHit(
        className: match.group(1)!,
        line: _lineOf(masked, match.start),
        offset: match.start,
      ));
      if (hits.length > 8) break; // 畸形文件保护
    }
    final allClasses = <PluginClassHit>[];
    for (final match in anyClassDeclaration.allMatches(masked)) {
      allClasses.add(PluginClassHit(
        className: match.group(1)!,
        line: _lineOf(masked, match.start),
        offset: match.start,
      ));
      if (allClasses.length > 8) break;
    }

    if (allClasses.length > 1) {
      final where =
          allClasses.map((h) => '${h.className}（第 ${h.line} 行）').join('、');
      return PluginSourceCheck._(
        hits: allClasses,
        message: '发现 ${allClasses.length} 处顶层类声明，只允许 1 处：$where',
      );
    }
    if (hits.isEmpty) {
      final found = allClasses.isEmpty
          ? ''
          : '（第 ${allClasses.single.line} 行找到 `class ${allClasses.single.className}`，'
              '但它不是 `extends PluginSource`，或 `extends` 与类名不在同一行）';
      return PluginSourceCheck._(
        message: '未找到顶层的 `class $pluginName extends PluginSource` 声明$found。'
            '要求：类声明从第 1 列开始，且 `extends PluginSource` 与类名同一行',
      );
    }

    final hit = hits.single;
    if (hit.className != pluginName) {
      final reason = hit.className.toLowerCase() == pluginName.toLowerCase()
          ? '（仅大小写不同；JS 类名大小写敏感，文件系统不敏感，必须逐字符相同）'
          : '';
      return PluginSourceCheck._(
        hits: hits,
        message: 'JS 类名 `${hit.className}` 与插件名 `$pluginName` 不一致'
            '$reason（第 ${hit.line} 行）。'
            '文件名、索引键、类名、引擎槽位必须逐字符相同',
      );
    }

    // ③ 类声明之外还有代码？只提示，不拦截（存量插件里有，而且能跑）
    return PluginSourceCheck._(
      hits: hits,
      warnings: _outerCodeWarnings(masked, hit),
    );
  }

  /// 括号配平：把 `{}` `()` `[]` 按栈配对。
  ///
  /// 在**掩码后**的源码上做，所以字符串 / 模板字面量 / 注释 / 正则字面量里的括号
  /// 已经被抹成空格，不会干扰计数。返回配平失败的原因，配平则返回 null。
  static String? _checkBalanced(String masked) {
    const openOf = {'}': '{', ')': '(', ']': '['};
    final stack = <(String, int)>[];

    for (var i = 0; i < masked.length; i++) {
      final ch = masked[i];
      if (ch == '{' || ch == '(' || ch == '[') {
        stack.add((ch, i));
      } else if (openOf.containsKey(ch)) {
        if (stack.isEmpty || stack.last.$1 != openOf[ch]) {
          return '第 ${_lineOf(masked, i)} 行的 `$ch` 没有对应的 `${openOf[ch]}`'
              '（括号不配对）';
        }
        stack.removeLast();
      }
    }
    if (stack.isNotEmpty) {
      final (ch, at) = stack.last;
      return '第 ${_lineOf(masked, at)} 行的 `$ch` 没有闭合（括号不配对）';
    }
    return null;
  }

  /// 类声明之外是否还有代码。返回可读的提示列表（空 = 干净）。
  static List<String> _outerCodeWarnings(String masked, PluginClassHit hit) {
    final body = _classBodySpan(masked, hit.offset);
    if (body == null) {
      // 括号配平已通过，走到这里说明类体结构没找到（例如类声明后直接跟了表达式）
      return const ['无法定位类声明的 `{…}` 类体，请检查类声明本身'];
    }

    final details = <String>[];
    final before = _firstCodeLine(masked, 0, hit.offset);
    if (before != null) {
      details.add('之前（第 ${before.line} 行）：${before.text}');
    }
    final after = _firstCodeLine(masked, body.end + 1, masked.length);
    if (after != null) {
      details.add('之后（第 ${after.line} 行）：${after.text}');
    }
    if (details.isEmpty) return const [];

    return ['类声明之外还有代码（加载时就会执行，且顺序依赖类定义）：'
        '${details.join('；')}'];
  }

  /// 类体 `{…}` 的区间：从类声明往后找第一个 `{`，再按括号配对找它的 `}`。
  ///
  /// 不能靠正则找 `^}` 收尾 —— 内置插件里就有类体内含第 1 列 `}` 的写法。
  static ({int start, int end})? _classBodySpan(String masked, int classOffset) {
    final start = masked.indexOf('{', classOffset);
    if (start < 0) return null;
    var depth = 0;
    for (var i = start; i < masked.length; i++) {
      final ch = masked[i];
      if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0) return (start: start, end: i);
      }
    }
    return null;
  }

  /// [from, to) 里第一行有内容的代码（掩码后的文本，注释 / 字面量已是空白）。
  static ({int line, String text})? _firstCodeLine(
    String masked,
    int from,
    int to,
  ) {
    var line = _lineOf(masked, from);
    for (final raw in masked.substring(from, to).split('\n')) {
      final text = raw.trim();
      if (text.isNotEmpty) {
        return (
          line: line,
          text: text.length > 40 ? '${text.substring(0, 40)}…' : text,
        );
      }
      line++;
    }
    return null;
  }

  /// 把注释、正则字面量与字符串 / 模板字面量替换成**等长空白**（换行保留）。
  ///
  /// 两个作用：
  ///   1. 行号与字符偏移都不变 → 报错能精确指到行；
  ///   2. 注释或字面量里的 `class X extends PluginSource` 不再造成误判
  ///      （现有 38/39 个内置插件含模板字面量，且每个文件都有头部注释块）。
  ///
  /// **正则字面量必须单独处理**：`ikmmh.js` 第 13 行
  /// `/document\.cookie\s*=\s*"([^"]+)"/` 里有**奇数个双引号**，只按引号配对会让
  /// 掩码一路吃掉后面的类声明，把合法插件误判为不可用。
  ///
  /// 只在源码规范校验里使用；**不用于改写源码**。
  static String maskCommentsAndLiterals(String source) {
    final out = StringBuffer();
    final length = source.length;
    var i = 0;

    while (i < length) {
      final ch = source[i];

      // 块注释
      if (ch == '/' && i + 1 < length && source[i + 1] == '*') {
        out.write('  ');
        i += 2;
        while (i < length) {
          if (source[i] == '*' && i + 1 < length && source[i + 1] == '/') {
            out.write('  ');
            i += 2;
            break;
          }
          out.write(source[i] == '\n' ? '\n' : ' ');
          i++;
        }
        continue;
      }

      // 行注释
      if (ch == '/' && i + 1 < length && source[i + 1] == '/') {
        while (i < length && source[i] != '\n') {
          out.write(' ');
          i++;
        }
        continue;
      }

      // 正则字面量：/…/flags（引号、斜杠、大括号都在里面，必须整段掩掉）
      if (ch == '/' && _regexStartsHere(source, i)) {
        var j = i + 1;
        var inClass = false;
        var closed = -1;
        while (j < length) {
          final c = source[j];
          // 正则字面量不能跨行：同行找不到结束符就按除号处理
          if (c == '\n') break;
          if (c == '\\' && j + 1 < length) {
            j += 2;
            continue;
          }
          if (c == '[') {
            inClass = true;
            j++;
            continue;
          }
          if (c == ']') {
            inClass = false;
            j++;
            continue;
          }
          if (c == '/' && !inClass) {
            closed = j;
            break;
          }
          j++;
        }
        if (closed > i) {
          for (var k = i; k <= closed; k++) {
            out.write(source[k] == '\n' ? '\n' : ' ');
          }
          i = closed + 1;
          while (i < length && _asciiLetter.hasMatch(source[i])) {
            out.write(' '); // 标志位 gimsuy
            i++;
          }
          continue;
        }
        // 落到这里说明不是正则 → 按普通字符处理
      }

      // 字符串 / 模板字面量
      if (ch == '"' || ch == "'" || ch == '`') {
        out.write(' ');
        i++;
        while (i < length) {
          final inner = source[i];
          // 转义：连同被转义的字符一起掩掉，但换行必须保留
          if (inner == '\\' && i + 1 < length) {
            final escaped = source[i + 1];
            out.write(' ');
            out.write(escaped == '\n' ? '\n' : ' ');
            i += 2;
            continue;
          }
          if (inner == ch) {
            out.write(' ');
            i++;
            break;
          }
          out.write(inner == '\n' ? '\n' : ' ');
          i++;
        }
        continue;
      }

      out.write(ch);
      i++;
    }

    return out.toString();
  }

  /// 1 起的行号：统计 [offset] 之前的换行数。
  static int _lineOf(String masked, int offset) {
    var line = 1;
    for (var i = 0; i < offset && i < masked.length; i++) {
      if (masked.codeUnitAt(i) == 0x0A) line++;
    }
    return line;
  }

  // ===== 私有：正则字面量识别 =====

  /// `/` 出现在这些字符之后时，是**正则字面量的开头**而不是除号。
  static const Set<String> _regexAllowedAfter = {
    '(', ',', ';', ':', '=', '[', '!', '&', '|', '?', '{', '}', '+', '-', '*',
    '%', '^', '~', '<', '>',
  };

  /// 这些关键字之后同样是正则字面量。
  static const Set<String> _regexPrecedingWords = {
    'return', 'typeof', 'instanceof', 'in', 'of', 'new', 'delete', 'void',
    'case', 'do', 'else', 'yield', 'await', 'throw', 'default',
  };

  static final RegExp _identChar = RegExp(r'[A-Za-z0-9_$]');
  static final RegExp _asciiLetter = RegExp(r'[A-Za-z]');
  static final RegExp _whitespace = RegExp(r'\s');

  /// 判断 [i]（指向 `/`）处是正则字面量还是除号。
  ///
  /// 用「前一个有效 token」判断（JS 词法的经典歧义）：表达式结束后是除号，
  /// 语句 / 运算符位置则是正则。判断错也不会掩盖代码 —— 正则分支还要求
  /// **同一行内**能找到结束斜杠，否则退回按普通字符处理。
  static bool _regexStartsHere(String source, int i) {
    var j = i - 1;
    while (j >= 0 && _whitespace.hasMatch(source[j])) {
      j--;
    }
    if (j < 0) return true;
    final prev = source[j];
    if (_identChar.hasMatch(prev)) {
      var k = j;
      while (k >= 0 && _identChar.hasMatch(source[k])) {
        k--;
      }
      return _regexPrecedingWords.contains(source.substring(k + 1, j + 1));
    }
    if (prev == ')' || prev == ']') return false; // 表达式结束 → 除号
    return _regexAllowedAfter.contains(prev);
  }
}
