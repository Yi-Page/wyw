// wyw 插件静态/结构校验脚本（不联网、不做任何格式转换）。
//
// 用途：逐个适配 venera 插件时，对 assets/plugin/*.js 做统一的机械检查，
// 把「语法错 / 类名与文件名不一致 / 未继承 PluginSource / 缺少该类型必需方法 /
// 描述符里出现未知 UI 类型」这类问题一次性暴露出来。
//
// 用法：
//   node tools/check_plugins.js            # 校验全部
//   node tools/check_plugins.js jm ehentai # 只校验指定插件
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const PLUGIN_DIR = path.join(__dirname, '..', 'assets', 'plugin');

// ---- 最小框架 mock（只求能加载类定义，不触发真实逻辑）----
// 返回一个独立 sandbox，供 vm.createContext 使用；每个插件用全新 sandbox，
// 避免类声明在全局作用域互相冲突。
function createSandbox() {
  const uiTypes = new Set();
  const ui = (t) => (o) => ({ __type: t, ...(o || {}) });
  const sandbox = {
    __uiTypes: uiTypes,
    console,
    setTimeout: () => 0,
    setInterval: () => 0,
    clearTimeout: () => {},
    clearInterval: () => {},
    Date,
    Math,
    JSON,
    Map,
    Set,
    Promise,
    Number,
    String,
    Boolean,
    Array,
    Object,
    RegExp,
    Error,
    parseInt,
    parseFloat,
    isNaN,
    encodeURIComponent,
    decodeURIComponent,
  };
  sandbox.globalThis = sandbox;
  // 与 assets/js/init.js 的 PluginSource **保持同一份成员表**：只放机制 + 能力探测。
  // 能力方法（getCategory / getSettings / loadCategory / getImageLoadingConfig …）
  // 故意不在这里 —— 它们只有插件自己实现，宿主靠 implementsMethod 探测
  // （见「未定义成员引用」检查）。也没有 `key`：存储命名空间由基类直接取
  // `this.constructor.name`，插件读 `this.key` 就是引用了自己没有的成员，应当报出来。
  sandbox.PluginSource = class PluginSource {
    implementsMethod(name) {
      const owns = (obj) =>
        Object.prototype.hasOwnProperty.call(obj, name) &&
        typeof obj[name] === 'function';
      if (owns(this)) return true;
      let proto = Object.getPrototypeOf(this);
      while (proto && proto !== PluginSource.prototype) {
        if (owns(proto)) return true;
        proto = Object.getPrototypeOf(proto);
      }
      return false;
    }
    loadSetting() { return ''; }
    saveSetting() {}
    loadData() { return null; }
    saveData() {}
    deleteData() {}
    get isLogged() { return false; }
    init() {}
  };
  sandbox.UI = new Proxy(
    {
      Text: (arg) => ({ __type: 'text', ...(typeof arg === 'string' ? { content: arg } : arg) }),
      validate: () => [],
    },
    {
      get(target, prop) {
        if (prop in target) return target[prop];
        if (typeof prop === 'symbol') return undefined;
        // 其余 UI.X 一律当描述符构造器，并记录用到的类型名
        return (o) => {
          uiTypes.add(String(prop).toLowerCase());
          return { __type: String(prop).toLowerCase(), ...(o || {}) };
        };
      },
    },
  );
  sandbox.Dialog = {
    showToast() {}, showDialog() {}, showInputDialog: async () => null,
    showLoading: () => 0, cancelLoading() {}, showSelectDialog: async () => null,
  };
  sandbox.Navigator = {
    navigateToDescriptor() {}, navigateToReader() {}, navigateToNovelReader() {},
    navigateToVideo() {}, navigateToWebview() {},
  };
  sandbox.PluginBrowse = { open() {}, find: async () => null };
  sandbox.Network = {
    get: async () => '', post: async () => '', getHtml: async () => '',
    fetchBytes: async () => ({ body: new Uint8Array() }),
    sendRequest: async () => ({ body: '' }),
  };
  // Convert：已知方法给出可用返回值；未知方法（venera 新增的哈希等）一律
  // 返回空字节，避免「mock 不全」被误报成插件问题。
  const bytes = () => new Uint8Array([1, 2, 3, 4]);
  const convertKnown = {
    md5: bytes, sha1: bytes, sha256: bytes, sha512: bytes,
    hmac: bytes, hmacString: () => '00',
    encodeUtf8: () => new Uint8Array([1, 2, 3]), decodeUtf8: () => '',
    encodeBase64: () => 'AA==', decodeBase64: () => new Uint8Array([1, 2, 3]),
    hexEncode: () => '00112233', hexDecode: () => new Uint8Array([0, 17, 34, 51]),
    encryptAesEcb: bytes, decryptAesEcb: bytes,
    encryptAesCbc: bytes, decryptAesCbc: bytes,
    gzip: bytes, ungzip: bytes, randomBytes: bytes,
  };
  sandbox.Convert = new Proxy(convertKnown, {
    get(target, prop) {
      if (prop in target) return target[prop];
      if (typeof prop === 'symbol') return undefined;
      return () => new Uint8Array([1, 2, 3, 4]);
    },
  });
  sandbox.HtmlDocument = class {
    querySelector() { return null; }
    xpath() { return []; }
  };
  sandbox.APP = { version: '0', platform: 'android' };
  sandbox.Comic = ui('comic');
  sandbox.ComicDetails = ui('comicDetails');

  // init.js 注入的全局函数（wyw 的 JS API 全景，见 docs/plugin-development.md §2.1）
  sandbox.randomInt = (min = 0, max = 1) => Math.floor(Math.random() * (max - min + 1)) + min;
  sandbox.randomDouble = (min = 0, max = 1) => Math.random() * (max - min) + min;
  sandbox.createUuid = () => '00000000-0000-4000-8000-000000000000';
  sandbox.log = () => {};
  sandbox.compute = (fn, ...args) => (typeof fn === 'function' ? fn(...args) : undefined);
  sandbox.sendMessage = () => null;
  sandbox.setClipboard = () => {};
  sandbox.getClipboard = async () => '';
  sandbox.Image = { empty: () => ({ width: 0, height: 0 }) };
  sandbox.RSA = { encrypt: () => '', decrypt: () => '' };
  return sandbox;
}

// wyw 描述符渲染器支持的 UI 类型（见 lib/js/js_extends/js_descriptor.dart）
const KNOWN_UI_TYPES = new Set([
  'card', 'column', 'row', 'stack', 'image', 'text', 'icon', 'button', 'iconbutton',
  'tag', 'spacer', 'divider', 'container', 'padding', 'sizedbox', 'center', 'align',
  'expanded', 'wrap', 'aspectratio', 'listview', 'singlechildscrollview', 'expansiontile',
  'pagination', 'action', 'navigate',
]);

// 各类型插件在 wyw 下的必需方法
const REQUIRED = {
  manga: ['search', 'getDetail', 'openReader', 'loadChapterImages'],
  novel: ['search', 'getDetail', 'openNovelReader', 'loadChapterContent'],
  video: ['play'],
};

function readHeaderType(src) {
  const head = src.split('\n').slice(0, 6).join('\n');
  const m = head.match(/^\s*\/\/\s*type:\s*(\w+)/m);
  return m ? m[1] : 'unknown';
}

// 剥掉「整行注释」，保留其余内容。
//
// 为什么不用逐字符的 stripComments：JS 的正则字面量里可能出现 `//`
// （如 `/https?:\/\//`），逐字符扫描会把它误判成行注释开头，导致后续状态错乱
// （把真实代码当注释剥掉、或把注释当代码检测）。这里只过滤整行注释，
// 简单可靠；代价是「行内注释里写 API 名」仍可能被检测到 —— 适配时避免即可。
function stripComments(src) {
  return src
    .split('\n')
    .filter((line) => !/^\s*(\/\/|\*|\/\*)/.test(line))
    .join('\n');
}

/** 把变量名转义成可安全拼进正则的字面量（`this.foo` 里的点也要转义）。 */
function escapeRegExp(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

async function checkOne(file) {
  const name = file.replace(/\.js$/, '');
  const full = path.join(PLUGIN_DIR, file);
  const src = fs.readFileSync(full, 'utf8');
  const code = stripComments(src); // 所有「残留 API」检测只看真实代码，不看注释
  const problems = [];
  const notes = [];
  // 1) 语法
  try {
    new vm.Script(src, { filename: file });
  } catch (e) {
    return { name, problems: ['语法错误: ' + e.message], notes, methods: [], type: 'unknown' };
  }

  // 2) 类名 == 文件名
  const classNames = [...src.matchAll(/^\s*class\s+([A-Za-z_$][\w$]*)\s+extends\s+([\w$.]+)/gm)];
  if (classNames.length === 0) {
    problems.push('未找到 `class X extends PluginSource` 声明');
  } else {
    const [cls, base] = [classNames[0][1], classNames[0][2]];
    if (cls !== name) problems.push(`类名(${cls}) != 文件名(${name})`);
    if (base !== 'PluginSource') problems.push(`继承自 ${base}，应为 PluginSource`);
  }

  // 3) 加载实例，检查方法
  let instance = null;
  let uiTypes = new Set();
  try {
    const sandbox = createSandbox();
    uiTypes = sandbox.__uiTypes;
    const ctx = vm.createContext(sandbox);
    const cls = classNames[0] ? classNames[0][1] : 'undefined';
    vm.runInContext(src + `\n;globalThis.__cls = ${cls};`, ctx, { filename: file });
    if (typeof sandbox.__cls === 'function') instance = new sandbox.__cls();
  } catch (e) {
    problems.push('实例化失败: ' + e.message);
  }

  const methods = [];
  const members = new Set();
  if (instance) {
    let proto = Object.getPrototypeOf(instance);
    const seen = new Set();
    while (proto && proto !== Object.prototype) {
      for (const k of Object.getOwnPropertyNames(proto)) {
        if (k === 'constructor' || seen.has(k)) continue;
        seen.add(k);
        const desc = Object.getOwnPropertyDescriptor(proto, k);
        if (!desc) continue;
        // 方法
        if (typeof desc.value === 'function') {
          methods.push(k);
          members.add(k);
          continue;
        }
        // getter / setter（如 `get baseUrl()` / `get headers()`）也算已定义成员
        if (typeof desc.get === 'function' || typeof desc.set === 'function') {
          members.add(k);
        }
      }
      proto = Object.getPrototypeOf(proto);
    }
    // 实例字段（含构造函数里赋值的箭头函数）
    for (const k of Object.keys(instance)) {
      members.add(k);
      if (typeof instance[k] === 'function') methods.push(k);
    }
    methods.sort();
  }

  // 4) 必需方法
  const type = readHeaderType(src);
  const required = REQUIRED[type];
  if (required) {
    const missing = required.filter((m) => !methods.includes(m));
    if (missing.length) problems.push(`缺少 ${type} 必需方法: ${missing.join(', ')}`);
  } else {
    notes.push(`文件头未声明 // type:（当前="${type}"），跳过必需方法检查`);
  }

  // 5) 是否残留 venera 专有 API（只看真实代码，不看注释）
  // 注意：wyw 的 init.js 确实注入了全局 `fetch` 别名（转发 Network.fetch），
  // 所以裸 `fetch(` 不算错；真正要拦的是 venera 的 `res.ok` / `await res.json()` 用法。
  const veneraLeftovers = [];
  if (/\bnew\s+ComicDetails\s*\(/.test(code)) veneraLeftovers.push('new ComicDetails(');
  if (/\bUI\.showMessage\s*\(/.test(code)) veneraLeftovers.push('UI.showMessage(');
  if (/\bthis\.categoryComics\b/.test(code)) veneraLeftovers.push('this.categoryComics');
  if (/\bthis\.comic\b/.test(code)) veneraLeftovers.push('this.comic');
  if (/\bthis\.search\b/.test(code)) veneraLeftovers.push('this.search');
  if (/\bres\.ok\b/.test(code)) veneraLeftovers.push('res.ok（venera Response 用法）');
  if (/await\s+res\.json\s*\(/.test(code)) veneraLeftovers.push('await res.json()（venera Response 用法）');
  if (veneraLeftovers.length) problems.push('疑似残留 venera API: ' + veneraLeftovers.join(', '));

  // res.status / res.body 只在「来源是 Network.get（wyw 返回 body 字符串）」时才是错的；
  // 若来自 Network.sendRequest（wyw 确实返回 {status, body}）则合法 → 降级为待确认。
  // 这条按变量名 `res` 的粗筛只是**兜底提示**：精确判断交给下面 5b) 的变量级检查
  // （同名变量可能在不同函数里来自不同 API，粗筛容易误报，故不再计入 problems）。
  if (/\bres\.(status|body)\b/.test(code)) {
    notes.push('出现 res.status/res.body —— 请确认来源是 Network.sendRequest（合法）还是 Network.get（误用，见下方变量级检查）');
  }

  // 5b) 「返回值形态」移植残留（**精确到变量**，比上面那条按变量名 `res` 的粗筛可靠得多）。
  //
  //   venera: Network.get/post/... → axios Response（可读 .status/.body/.headers）
  //   wyw   : Network.get/post/... → **body 字符串**
  //   venera: Network.fetchBytes   → 字节
  //   wyw   : Network.fetchBytes   → {status, headers, body}
  //
  // 这类误用**语法与静态检查全过、只有真跑才炸**，且已实际造成故障：
  //   - comic_walker 的 init() 读 resp.status → 版本号更新代码从未执行 → 站点 400；
  //   - hitomi 的 get_index_version 读 resp.status → 搜索直接失败（0 条）；
  //   - hitomi 的 get_url_at_range / get_nozomi 把 fetchBytes 的响应对象当字节
  //     → new Uint8Array(res) 得到空数组 → DataView.getInt32 越界。
  // 变量级检查的已知局限：按**变量名**而非作用域匹配。同名变量在不同函数里
  // 可能来自不同 API（hitomi 的 `res` 一处来自 get、一处来自 fetchBytes），
  // 因此这里收集「每个变量名的所有来源形态」：只有全部来源都是 body 字符串
  // 才算确定问题；来源混合时降级为待确认，避免误报。
  const OBJ_RETURNING = new Set(['sendRequest', 'fetchBytes', 'fetch', 'webview']);
  const varSources = new Map();
  const addSource = (name, kind) => {
    if (!varSources.has(name)) varSources.set(name, new Set());
    varSources.get(name).add(kind);
  };
  for (const m of code.matchAll(
    /\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:await\s+)?Network\.(\w+)\s*\(/g,
  )) {
    addSource(m[1], OBJ_RETURNING.has(m[2]) ? 'obj' : 'string');
  }
  for (const m of code.matchAll(
    /\bthis\.([A-Za-z_$][\w$]*)\s*=\s*(?:await\s+)?Network\.(\w+)\s*\(/g,
  )) {
    addSource('this.' + m[1], OBJ_RETURNING.has(m[2]) ? 'obj' : 'string');
  }
  // 非 Network 来源的赋值（JSON 结果、对象字段、函数返回…）→ 标 other。
  // 有 other 来源就说明该变量名不只承载「HTTP 响应」，降级为待确认，避免误报：
  // 例如 copy_manga_multi_accounts 的 `comicData` 一处来自 `results.comic`（JSON 对象，
  // `comicData.status.display` 是漫画连载状态，合法），另一处才是 Network.get。
  for (const m of code.matchAll(
    /\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?!\s*(?:await\s+)?Network\.)[^=]/g,
  )) {
    addSource(m[1], 'other');
  }
  for (const m of code.matchAll(
    /\bthis\.([A-Za-z_$][\w$]*)\s*=\s*(?!\s*(?:await\s+)?Network\.)[^=]/g,
  )) {
    addSource('this.' + m[1], 'other');
  }

  for (const [v, kinds] of varSources) {
    const props = [];
    for (const p of ['status', 'body', 'headers', 'ok']) {
      if (new RegExp('\\b' + escapeRegExp(v) + '\\.' + p + '\\b').test(code)) props.push(p);
    }
    if (!props.length) continue;
    const list = props.join('/');
    if (kinds.size === 1 && kinds.has('string')) {
      problems.push(
        `${v} 来自 Network.get/post（wyw 返回 **body 字符串**），却读了 .${list} —— ` +
        '恒为 undefined（venera 返回 axios Response，属移植残留；需要状态码/响应头请改用 Network.sendRequest）',
      );
    } else if (kinds.has('string')) {
      notes.push(
        `${v} 同时被 Network.get 与 Network.sendRequest/fetchBytes 赋值过，却读了 .${list} —— ` +
        '请确认读的那处来源是 sendRequest/fetchBytes（合法），否则恒为 undefined',
      );
    }
  }

  const fetchBytesVars = new Set();
  for (const m of code.matchAll(
    /\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:await\s+)?Network\.fetchBytes\s*\(/g,
  )) {
    fetchBytesVars.add(m[1]);
  }
  for (const v of fetchBytesVars) {
    const e = escapeRegExp(v);
    const misused =
      new RegExp('new\\s+Uint8Array\\s*\\(\\s*' + e + '\\s*\\)').test(code) ||
      new RegExp('new\\s+DataView\\s*\\(\\s*' + e + '[\\s,)]').test(code) ||
      new RegExp('\\b' + e + '\\.byteLength\\b').test(code) ||
      new RegExp('\\b' + e + '\\.slice\\s*\\(').test(code);
    if (misused) {
      problems.push(
        `${v} 来自 Network.fetchBytes（wyw 返回 **{status, headers, body}**），却被当字节用 —— ` +
        `应改用 ${v}.body（venera 的 fetchBytes 直接返回字节，属移植残留）`,
      );
    }
  }
  if (/new\s+(?:Uint8Array|DataView)\s*\(\s*await\s+Network\.fetchBytes/.test(code)) {
    problems.push(
      'Network.fetchBytes(...) 的结果被直接当字节用 —— 应取 .body（wyw 返回 {status, headers, body}）',
    );
  }

  // 6) 未知 UI 类型
  const unknownUi = [...uiTypes].filter((t) => !KNOWN_UI_TYPES.has(t));
  if (unknownUi.length) problems.push('未知 UI 描述符类型: ' + unknownUi.join(', '));

  // 9) 未定义成员引用：`this.xxx` 从未在本类上定义过 —— 典型如把 venera 的
  //    `this.comic` 改名成 `_comicApi` 后漏改调用点（manga_dex 的取章节必崩 bug）。
  //
  //    判定不需要白名单：上面已经把**整条原型链**（含基类 PluginSource.prototype）
  //    与实例自有字段反射进 members 了。所以这里引用了、members 里又没有的，
  //    就是「引用了自己没有的成员」—— 真 bug，必须报。
  //    （旧版本用一张手写白名单替桩基类补漏，代价是把 `this.getCategory` 这种
  //      「其实没实现」的引用一起放过了。）
  if (instance) {
    // 方法体内动态赋值的字段也算已定义
    for (const m of code.matchAll(/\bthis\.([A-Za-z_$][\w$]*)\s*=/g)) members.add(m[1]);
    const referenced = new Set(
      [...code.matchAll(/\bthis\.([A-Za-z_$][\w$]*)/g)].map((m) => m[1]),
    );
    const missing = [...referenced].filter((k) => !members.has(k)).sort();
    if (missing.length) {
      problems.push('引用了未定义的成员: this.' + missing.join(', this.'));
    }
  }

  // 8) 接线检查：定义但没被用到的 venera 结构 = 上游功能静默丢失
  // 8a) init()：wyw 引擎**不会**调用 init()（见 docs/plugin-development.md），
  //     插件自己定义了 init 却没有调用点 → 初始化逻辑永远不会执行。
  const definesInit = /\n\s*(async\s+)?init\s*\([^)]*\)\s*\{/.test(code);
  const callsInit = /this\.init\s*\(/.test(code);
  if (definesInit && !callsInit) {
    problems.push('定义了 init() 但无人调用 —— wyw 引擎不调 init()，初始化会丢失（应在构造函数里兜底调用）');
  }

  // 8b) venera 内部结构只定义未使用
  const countOf = (re) => (code.match(re) || []).length;
  if (countOf(/_explore/g) === 1) {
    notes.push('_explore 仅定义未使用（venera 探索页未映射到浏览页分类）');
  }
  if (countOf(/_categoryData/g) === 1) {
    notes.push('_categoryData 仅定义未使用（venera 分类结构未接线）');
  }
  if (countOf(/_searchApi/g) === 1) {
    notes.push('_searchApi 仅定义未使用');
  }

  // 7) getCategory 结构（允许 async：框架 plugin.invoke 会 await Promise）
  if (instance && typeof instance.getCategory === 'function') {
    try {
      let cat = instance.getCategory();
      if (cat && typeof cat.then === 'function') cat = await cat;
      if (cat === null || cat === undefined) {
        notes.push('getCategory() 返回空（不参与浏览页）');
      } else if (typeof cat !== 'object' || !Array.isArray(cat.parts)) {
        problems.push('getCategory() 返回值缺少 parts 数组');
      } else {
        notes.push(`getCategory(): ${cat.parts.length} 个分组`);
      }
    } catch (e) {
      problems.push('getCategory() 调用抛错: ' + e.message);
    }
  }

  return { name, problems, notes, methods, type };
}

const only = process.argv.slice(2);

// 插件构造函数里可能自己调 init()（venera 风格）并触发异步逻辑；mock 不全时
// 会产生 unhandledRejection，这属于「检查脚本的 mock 不够」，不是插件问题。
process.on('unhandledRejection', () => {});
const files = fs
  .readdirSync(PLUGIN_DIR)
  .filter((f) => f.endsWith('.js'))
  .filter((f) => only.length === 0 || only.some((o) => f === o || f === o + '.js'))
  .sort();

(async () => {
  let bad = 0;
  for (const f of files) {
    let r;
    try {
      r = await checkOne(f);
    } catch (e) {
      // 检查脚本自身出错（如插件在实例化时抛出未捕获异常）不应中断全量检查
      r = { name: f.replace(/\.js$/, ''), problems: ['检查脚本异常: ' + e.message], notes: [], methods: [], type: 'unknown' };
    }
    if (r.problems.length) {
      bad++;
      console.log(`FAIL  ${r.name}  [${r.type}]`);
      for (const p of r.problems) console.log('        - ' + p);
    } else {
      console.log(`ok    ${r.name}  [${r.type}]  methods=${r.methods.length}`);
    }
    for (const n of r.notes) console.log('        · ' + n);
  }

  console.log(`\n${files.length - bad}/${files.length} 通过`);
  process.exit(bad ? 1 : 0);
})();
