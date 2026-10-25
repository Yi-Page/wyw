#!/usr/bin/env node
'use strict';

/**
 * 插件命名链机械校验：文件名 = 索引键 = 类名 = 引擎槽位。
 *
 * 与 Dart 侧 `PluginSourceRule`（lib/plugins/plugin_source.dart）保持**同一套语义**：
 *   1. 先把注释与字符串 / 模板字面量掩成等长空白（行号不漂，字面量里的假类声明不误判）；
 *   2. 再在掩码结果上要求「恰好一处顶层类声明」，且类名与插件名逐字符相同。
 *
 * 用法：
 *   node tools/check_plugin_naming.js                 # 校验 assets/plugin/*.js
 *   node tools/check_plugin_naming.js path/to/a.js …  # 校验指定文件
 *   node tools/check_plugin_naming.js --self-test     # 只跑规则自检（含反例）
 *
 * 退出码：全部通过 0；有违规 1。
 */

const fs = require('fs');
const path = require('path');

// 第 1 列起、单行、基类写死 PluginSource
const CLASS_RE = /^class[ \t]+([A-Za-z_$][\w$]*)[ \t]+extends[ \t]+PluginSource\b/gm;

// `/` 出现在这些字符之后时，是**正则字面量的开头**而不是除号
const REGEX_ALLOWED_AFTER = new Set([
  '(', ',', ';', ':', '=', '[', '!', '&', '|', '?', '{', '}', '+', '-', '*',
  '%', '^', '~', '<', '>',
]);

// 这些关键字之后同样是正则字面量
const REGEX_PRECEDING_WORDS = new Set([
  'return', 'typeof', 'instanceof', 'in', 'of', 'new', 'delete', 'void',
  'case', 'do', 'else', 'yield', 'await', 'throw', 'default',
]);

const IDENT_CHAR = /[A-Za-z0-9_$]/;

/** 判断偏移 i（指向 `/`）处是正则字面量还是除号。 */
function regexStartsHere(source, i) {
  let j = i - 1;
  while (j >= 0 && /\s/.test(source[j])) j--;
  if (j < 0) return true;
  const prev = source[j];
  if (IDENT_CHAR.test(prev)) {
    let k = j;
    while (k >= 0 && IDENT_CHAR.test(source[k])) k--;
    return REGEX_PRECEDING_WORDS.has(source.slice(k + 1, j + 1));
  }
  if (prev === ')' || prev === ']') return false; // 表达式结束 → 除号
  return REGEX_ALLOWED_AFTER.has(prev);
}

/** 把注释、正则字面量与字符串 / 模板字面量掩成等长空白（换行保留）。 */
function maskCommentsAndLiterals(source) {
  const out = [];
  const n = source.length;
  let i = 0;

  while (i < n) {
    const ch = source[i];

    // 块注释
    if (ch === '/' && i + 1 < n && source[i + 1] === '*') {
      out.push('  ');
      i += 2;
      while (i < n) {
        if (source[i] === '*' && i + 1 < n && source[i + 1] === '/') {
          out.push('  ');
          i += 2;
          break;
        }
        out.push(source[i] === '\n' ? '\n' : ' ');
        i++;
      }
      continue;
    }

    // 行注释
    if (ch === '/' && i + 1 < n && source[i + 1] === '/') {
      while (i < n && source[i] !== '\n') {
        out.push(' ');
        i++;
      }
      continue;
    }

    // 正则字面量：/…/flags（引号 / 斜杠 / 大括号都在里面，必须整段掩掉）
    if (ch === '/' && regexStartsHere(source, i)) {
      let j = i + 1;
      let inClass = false;
      let closed = -1;
      while (j < n) {
        const c = source[j];
        // 正则字面量不能跨行：同一条语句里找不到结束符就按除号处理
        if (c === '\n') break;
        if (c === '\\' && j + 1 < n) {
          j += 2;
          continue;
        }
        if (c === '[') {
          inClass = true;
          j++;
          continue;
        }
        if (c === ']') {
          inClass = false;
          j++;
          continue;
        }
        if (c === '/' && !inClass) {
          closed = j;
          break;
        }
        j++;
      }
      if (closed > i) {
        for (let k = i; k <= closed; k++) {
          out.push(source[k] === '\n' ? '\n' : ' ');
        }
        i = closed + 1;
        while (i < n && /[A-Za-z]/.test(source[i])) {
          out.push(' '); // 标志位 gimsuy
          i++;
        }
        continue;
      }
      // 落到这里说明不是正则 → 按普通字符处理
    }

    // 字符串 / 模板字面量
    if (ch === '"' || ch === "'" || ch === '`') {
      out.push(' ');
      i++;
      while (i < n) {
        const inner = source[i];
        if (inner === '\\' && i + 1 < n) {
          const escaped = source[i + 1];
          out.push(' ');
          out.push(escaped === '\n' ? '\n' : ' ');
          i += 2;
          continue;
        }
        if (inner === ch) {
          out.push(' ');
          i++;
          break;
        }
        out.push(inner === '\n' ? '\n' : ' ');
        i++;
      }
      continue;
    }

    out.push(ch);
    i++;
  }

  return out.join('');
}

function lineOf(text, offset) {
  let line = 1;
  for (let i = 0; i < offset && i < text.length; i++) {
    if (text.charCodeAt(i) === 0x0a) line++;
  }
  return line;
}

/** 返回 { ok, hits, message } —— 与 Dart 侧文案一致。 */
function check(source, pluginName) {
  if (source.trim() === '') {
    return { ok: false, hits: [], message: '插件源码为空' };
  }
  const masked = maskCommentsAndLiterals(source);
  const hits = [];
  CLASS_RE.lastIndex = 0;
  let m;
  while ((m = CLASS_RE.exec(masked)) !== null) {
    hits.push({ className: m[1], line: lineOf(masked, m.index), offset: m.index });
    if (hits.length > 8) break;
  }

  if (hits.length === 0) {
    return {
      ok: false,
      hits,
      message: '未找到顶层的 `class <插件名> extends PluginSource` 声明。'
        + '要求：类声明从第 1 列开始，且 `extends PluginSource` 与类名同一行',
    };
  }
  if (hits.length > 1) {
    const where = hits.map((h) => `${h.className}（第 ${h.line} 行）`).join('、');
    return {
      ok: false,
      hits,
      message: `发现 ${hits.length} 处顶层类声明，只允许 1 处：${where}`,
    };
  }

  const hit = hits[0];
  if (hit.className !== pluginName) {
    const reason = hit.className.toLowerCase() === pluginName.toLowerCase()
      ? '（仅大小写不同；JS 类名大小写敏感，文件系统不敏感，必须逐字符相同）'
      : '';
    return {
      ok: false,
      hits,
      message: `JS 类名 \`${hit.className}\` 与插件名 \`${pluginName}\` 不一致`
        + `${reason}（第 ${hit.line} 行）。`
        + '文件名、索引键、类名、引擎槽位必须逐字符相同',
    };
  }
  return { ok: true, hits, message: null };
}

// ===== 规则自检（含反例）=====

function selfTest() {
  const cases = [
    {
      title: '类名与插件名一致',
      source: 'class hanime extends PluginSource {\n  name = "H"\n}\n',
      plugin: 'hanime',
      ok: true,
    },
    {
      title: '类名不一致',
      source: '// 头部\nclass other extends PluginSource {}\n',
      plugin: 'hanime',
      ok: false,
      contains: '第 2 行',
    },
    {
      title: '仅大小写不同',
      source: 'class Hanime extends PluginSource {}\n',
      plugin: 'hanime',
      ok: false,
      contains: '大小写',
    },
    {
      title: '两处顶层类声明',
      source: 'class a extends PluginSource {}\nclass b extends PluginSource {}\n',
      plugin: 'a',
      ok: false,
      contains: '2 处',
    },
    {
      title: '未继承 PluginSource',
      source: 'class hanime {\n}\n',
      plugin: 'hanime',
      ok: false,
      contains: '未找到',
    },
    {
      title: 'extends 换行（要求单行）',
      source: 'class hanime\n  extends PluginSource {}\n',
      plugin: 'hanime',
      ok: false,
    },
    {
      title: '缩进的嵌套类不计入',
      source: 'class hanime extends PluginSource {\n'
        + '  make() { class helper extends PluginSource {} }\n}\n',
      plugin: 'hanime',
      ok: true,
    },
    {
      title: '注释里的假类声明不计入',
      source: '// class fake extends PluginSource {}\n'
        + 'class hanime extends PluginSource {}\n',
      plugin: 'hanime',
      ok: true,
    },
    {
      title: '模板字面量里的假类声明不计入',
      source: 'const inject = `\nclass fake extends PluginSource {}\n`;\n'
        + 'class hanime extends PluginSource {}\n',
      plugin: 'hanime',
      ok: true,
    },
    {
      title: '字符串里的转义引号不会提前结束掩码',
      source: 'const s = "\\" class fake extends PluginSource {}";\n'
        + 'class hanime extends PluginSource {}\n',
      plugin: 'hanime',
      ok: true,
    },
    {
      // ikmmh.js 的真实形态：正则字面量里的奇数个双引号
      title: '正则字面量里的引号不会吃掉后面的类声明',
      source: 'const re = /document\\.cookie\\s*=\\s*"([^"]+)"/;\n'
        + 'function f() { return 1 }\n'
        + 'class hanime extends PluginSource {}\n',
      plugin: 'hanime',
      ok: true,
    },
    {
      title: '字符类里的斜杠不会提前结束正则',
      source: 'const re = /[/"]+/g;\nclass hanime extends PluginSource {}\n',
      plugin: 'hanime',
      ok: true,
    },
    {
      title: '除号不被误判为正则（表达式后）',
      source: 'const a = (b) / 2;\nconst c = d[0] / 3;\n'
        + 'class hanime extends PluginSource {}\n',
      plugin: 'hanime',
      ok: true,
    },
    {
      title: '关键字后的正则被正确识别',
      source: 'function f() { return /"/.test(s) }\n'
        + 'const g = typeof /x/ === "object";\n'
        + 'class hanime extends PluginSource {}\n',
      plugin: 'hanime',
      ok: true,
    },
  ];

  let failed = 0;
  for (const c of cases) {
    const masked = maskCommentsAndLiterals(c.source);
    if (masked.length !== c.source.length) {
      failed++;
      console.log(`✗ ${c.title} —— 掩码长度变化：${c.source.length} → ${masked.length}`);
      continue;
    }
    const r = check(c.source, c.plugin);
    const okMatch = r.ok === c.ok;
    const containMatch = !c.contains || (r.message || '').includes(c.contains);
    if (okMatch && containMatch) {
      console.log(`✓ ${c.title}`);
    } else {
      failed++;
      console.log(`✗ ${c.title} —— 期望 ok=${c.ok}${c.contains ? ` 且含「${c.contains}」` : ''}，`
        + `实际 ok=${r.ok} message=${r.message}`);
    }
  }
  console.log(`\n规则自检：${cases.length - failed}/${cases.length} 通过`);
  return failed === 0;
}

// ===== 存储命名空间派生语义自检 =====

/**
 * 复刻 `PluginSource`（assets/js/init.js）的字段模型，验证三件事：
 *
 *   1. 基类**没有**任何「宿主属性字段」（name / version / homepage）与 `key` 成员；
 *   2. 存储命名空间 = `this.constructor.name` = 插件名 —— 基类各方法直接用类名，
 *      **不经过任何插件可声明的属性**，所以插件写 `key = '…'` 也改不了它；
 *   3. 现存 22/39 个插件在构造函数里就调 `init()` → 同步 `loadSetting()`，
 *      而类名在 `new` 的那一刻就已确定，所以时序天然成立。
 */
function derivedKeySelfTest() {
  let failed = 0;
  const expect = (title, actual, wanted) => {
    const ok = JSON.stringify(actual) === JSON.stringify(wanted);
    if (ok) {
      console.log(`✓ ${title}`);
    } else {
      failed++;
      console.log(`✗ ${title} —— 期望 ${JSON.stringify(wanted)}，实际 ${JSON.stringify(actual)}`);
    }
  };

  // 与 assets/js/init.js 的 PluginSource 同形（只保留与字段模型相关的部分）。
  // 注意：基类**没有** `key` 成员 —— 存储命名空间由基类直接取 `this.constructor.name`，
  // 不经过任何插件可声明的属性（所以插件写 `key = '…'` 也影响不到命名空间）。
  class PluginSource {
    // 模拟同步 JS 桥：loadSetting 立即返回
    loadSetting(k) { return `[${this.constructor.name}]${k}`; }
  }

  // 清洗过的插件：类体里不声明任何宿主字段
  class Clean extends PluginSource {
    constructor() { super(); this.init(); }
    init() { this.seenAtInit = this.loadSetting('base_url'); }
  }

  // 旧写法：类体里声明了 key / name / version（会生成自有数据属性）
  class Legacy extends PluginSource {
    name = 'Komiic 显示名';
    key = 'Komiic';
    version = '1.0.1';

    constructor() { super(); this.init(); }
    init() { this.seenAtInit = this.loadSetting('base_url'); }
  }

  const hostFields = ['name', 'version', 'homepage'];
  expect(
    '基类没有 name / version / homepage 数据字段',
    hostFields.filter(
      (k) => Object.getOwnPropertyDescriptor(PluginSource.prototype, k) !== undefined,
    ),
    [],
  );
  expect(
    '基类没有 key 成员（命名空间不经过可被插件遮蔽的属性）',
    Object.getOwnPropertyDescriptor(PluginSource.prototype, 'key'),
    undefined,
  );

  const clean = new Clean();
  expect('清洗过的插件：构造期命名空间即类名（= 插件名）',
    clean.seenAtInit, '[Clean]base_url');
  expect('清洗过的插件：实例上没有 name / version / homepage 字段',
    hostFields.filter((k) => k in clean), []);

  const legacy = new Legacy();
  expect('旧写法：声明了 key 字段也改变不了存储命名空间（仍取类名）',
    legacy.seenAtInit, '[Legacy]base_url');
  expect('旧写法：实例上只有它自己声明的字段',
    ['name', 'key', 'version'].filter((k) => Object.prototype.hasOwnProperty.call(legacy, k)),
    ['name', 'key', 'version']);

  const storageFailed = failed;
  console.log(`\n存储命名空间派生自检：${storageFailed === 0 ? '全部通过' : `${storageFailed} 项失败`}`);

  // ===== 能力探测自检 =====
  //
  // 直接 eval `assets/js/init.js` 里的**真实基类**（不是另抄一份），锁住两条不变量：
  //   1. 基类**不许**给能力方法留空实现 —— 留了，能力探测对每个插件都为真；
  //   2. `implementsMethod` 只认「插件自己写的可调用成员」。
  const realSource = realPluginSource();
  const CAPABILITIES = [
    'getCategory', 'getCategoryOptions', 'loadCategory',
    'getImageLoadingConfig', 'getSettings',
  ];
  const MECHANISMS = [
    'implementsMethod', 'loadData', 'saveData', 'deleteData',
    'loadSetting', 'saveSetting', 'isLogged', 'init',
  ];

  expect(
    '基类没有能力方法（留了空实现，能力探测就永远为真）',
    CAPABILITIES.filter(
      (k) => Object.getOwnPropertyDescriptor(realSource.prototype, k) !== undefined,
    ),
    [],
  );
  expect(
    '基类保留机制成员（缺一不可）',
    MECHANISMS.filter(
      (k) => Object.getOwnPropertyDescriptor(realSource.prototype, k) === undefined,
    ),
    [],
  );
  expect(
    '基类没有 static sources（死字段）',
    Object.getOwnPropertyDescriptor(realSource, 'sources'),
    undefined,
  );
  expect(
    '基类没有 key 成员（存储命名空间只取 this.constructor.name）',
    Object.getOwnPropertyDescriptor(realSource.prototype, 'key'),
    undefined,
  );

  class ImplementsIt extends realSource {
    getCategory() { return null; }
  }
  class NotImplements extends realSource {}
  class FieldStyle extends realSource {
    search = async () => [];
  }
  class ExplicitlyOff extends realSource {
    getCategory = null;
  }

  expect('插件实现了的能力方法 → true',
    new ImplementsIt().implementsMethod('getCategory'), true);
  expect('插件没实现 → false',
    new NotImplements().implementsMethod('getCategory'), false);
  expect('字段式（箭头函数）也算实现',
    new FieldStyle().implementsMethod('search'), true);
  expect('同名但不是函数（显式关掉）→ false',
    new ExplicitlyOff().implementsMethod('getCategory'), false);
  expect('基类自己的机制成员不算「插件实现」',
    new NotImplements().implementsMethod('loadSetting'), false);
  expect('未定义的名字 → false',
    new NotImplements().implementsMethod('nope'), false);

  const capabilityFailed = failed - storageFailed;
  console.log(`\n能力探测自检：${capabilityFailed === 0 ? '全部通过' : `${capabilityFailed} 项失败`}`);
  return failed === 0;
}

/** 取出 `assets/js/init.js` 里真实的 `PluginSource` 类（用于能力探测自检） */
function realPluginSource() {
  const file = path.join(__dirname, '..', 'assets', 'js', 'init.js');
  const src = fs.readFileSync(file, 'utf8');
  const start = src.indexOf('class PluginSource {');
  if (start < 0) throw new Error('init.js 里找不到 class PluginSource');
  let depth = 0;
  const open = src.indexOf('{', start);
  let end = open;
  for (; end < src.length; end++) {
    if (src[end] === '{') depth++;
    else if (src[end] === '}') {
      depth--;
      if (depth === 0) break;
    }
  }
  const body = src.slice(open, end + 1);
  return new Function(`return class PluginSource ${body}`)();
}

// ===== 扫描文件 =====

// 宿主附加属性：按 docs/plugin-storage-spec.md 不该出现在插件代码里
const LEGACY_CLASS_FIELD_RE = /^[ \t]*(name|key|version)[ \t]*=[ \t]*['"]/gm;

function pluginNameOf(filePath) {
  const base = path.basename(filePath);
  return base.endsWith('.js') ? base.slice(0, -3) : base;
}

/** 收集「能跑但应该清理」的写法（非致命）。 */
function collectWarnings(source) {
  const warnings = [];

  const legacy = new Set();
  LEGACY_CLASS_FIELD_RE.lastIndex = 0;
  let m;
  while ((m = LEGACY_CLASS_FIELD_RE.exec(source)) !== null) legacy.add(m[1]);
  if (legacy.size > 0) {
    warnings.push(
      '类字段 ' + [...legacy].sort().join(' / ') +
      ' —— 插件代码里只该有代码：这些字段没有任何读取者、也不落盘' +
      '（宿主台账在 index.json 里）。清理掉即可。' +
      '注意 `key` 现在是纯死数据（存储命名空间由基类直接取 this.constructor.name），' +
      '删字段前先把插件里 `this.key` 的引用改成 `this.constructor.name`（或插件名），' +
      '否则那些引用会变成 undefined',
    );
  }

  return warnings;
}

function scan(files) {
  let bad = 0;
  let warned = 0;
  for (const file of files) {
    const source = fs.readFileSync(file, 'utf8');
    const name = pluginNameOf(file);
    const masked = maskCommentsAndLiterals(source);
    if (masked.length !== source.length) {
      bad++;
      console.log(`✗ ${name} —— 掩码长度变化（${source.length} → ${masked.length}），行号会漂`);
      continue;
    }
    const r = check(source, name);
    if (r.ok) {
      console.log(`✓ ${name} —— 第 ${r.hits[0].line} 行 class ${r.hits[0].className}`);
    } else {
      bad++;
      console.log(`✗ ${name} —— ${r.message}`);
    }
    const warnings = collectWarnings(source);
    if (warnings.length > 0) {
      warned++;
      for (const w of warnings) console.log(`  ⚠ ${w}`);
    }
  }
  console.log(`\n扫描 ${files.length} 个文件：命名链违规 ${bad} 个，`
    + `可清理的旧写法 ${warned} 个（不影响运行）`);
  return bad === 0;
}

// ===== 入口 =====

const args = process.argv.slice(2);

if (args.includes('--debug')) {
  const target = args.filter((a) => !a.startsWith('--'))[0];
  if (!target) {
    console.error('用法: node tools/check_plugin_naming.js --debug <file.js>');
    process.exit(1);
  }
  const raw = fs.readFileSync(target, 'utf8');
  const masked = maskCommentsAndLiterals(raw);
  const count = (text, needle) => text.split(needle).length - 1;
  console.log(`文件: ${target}`);
  console.log(`长度: raw=${raw.length} masked=${masked.length} (差 ${masked.length - raw.length})`);
  console.log(`换行: raw=${count(raw, '\n')} masked=${count(masked, '\n')}` +
    `  CRLF=${count(raw, '\r\n')}  单独CR=${count(raw, '\r') - count(raw, '\r\n')}`);
  console.log(`引号: '=${count(raw, "'")} "=${count(raw, '"')} \`=${count(raw, '`')}`);
  console.log(`裸正则匹配 raw: ${(raw.match(CLASS_RE) || []).length} 处`);

  CLASS_RE.lastIndex = 0;
  const m = CLASS_RE.exec(raw);
  if (m) {
    const line = lineOf(raw, m.index);
    console.log(`raw 命中: class ${m[1]} 第 ${line} 行`);
    const before = maskCommentsAndLiterals(raw.slice(0, m.index));
    console.log(`该处掩码后残留: ${JSON.stringify(before.slice(-80))}`);
    console.log(`掩码结果同位置: ${JSON.stringify(masked.slice(m.index - 20, m.index + 40))}`);
  } else {
    const at = raw.indexOf('class ');
    console.log(`raw 未命中。首个 "class " 在偏移 ${at}（第 ${lineOf(raw, at)} 行）`);
    console.log(`掩码结果同位置: ${JSON.stringify(masked.slice(at - 20, at + 40))}`);
  }
  process.exit(0);
}

let ok;
if (args.includes('--self-test')) {
  ok = selfTest();
  console.log('');
  ok = derivedKeySelfTest() && ok;
} else {
  const explicit = args.filter((a) => !a.startsWith('--'));
  let files = explicit;
  if (files.length === 0) {
    const dir = path.join(__dirname, '..', 'assets', 'plugin');
    files = fs.readdirSync(dir)
      .filter((f) => f.endsWith('.js'))
      .sort()
      .map((f) => path.join(dir, f));
  }
  if (files.length === 0) {
    console.error('没有找到待校验的插件文件');
    process.exit(1);
  }
  ok = selfTest();
  console.log('');
  ok = derivedKeySelfTest() && ok;
  console.log('');
  ok = scan(files) && ok;
}
process.exit(ok ? 0 : 1);
