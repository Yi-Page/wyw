// wyw 插件行为回归验证（不联网）。
//
// 与 check_plugins.js（静态机械校验）互补：本脚本**实际实例化插件并调用方法**，
// mock 掉网络与框架 API，断言两类易回归的行为：
//
//   1. `searchTag` / `searchByTag`（onClickTag 的等价实现）必须**触发跳转**。
//      背景：`UI.Action` 的返回值会被框架丢弃（lib/utils/plugin_action.dart:30 只
//      `await plugin.invoke(...)`），所以点击回调若只是 `return` 卡片列表，用户点了
//      没有任何反应 —— copy_manga / wnacg 的初版都栽在这里。
//
//   2. `explore` / `ranking` 的接线必须真的路由到对应来源（而不是静默返回空）。
//
// 用法：node tools/verify_plugin_behavior.js
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const DIR = path.join(__dirname, '..', 'assets', 'plugin');

// 补了 searchTag 的插件 → [命名空间, 标签, 是否单参数签名]
const TAG_CASES = [
  ['hitomi', 'artists', 'some artist'],
  ['ykmh', '标签', '恋爱'],
  ['manhuagui', '作者', '某作者'],
  ['mxs', '作者', '某作者'],
  ['hcomic', '标签', '无修'],
  ['jcomic', '分類', '爱情'],
  ['happy', '作者', '某作者'],
  ['mycomic', '作者', '某作者'],
  ['ccc', '标签', '奇幻'],
  ['nhentai', 'tag', 'sole female'],
  ['picacg', 'Author', '某作者'],
  ['wnacg', '', '無修正', true], // searchByTag(tag) 单参数
  ['manga_dex', 'Tags', 'Action'],
  ['comick', '标签', 'Action'],
  ['copy_manga_multi_accounts', '作者', '某作者'],
  ['hot_manga', '作者', '某作者'],
  ['copy_manga', '作者', '某作者'],
];

function createSandbox() {
  const navigations = [];
  const toasts = [];
  const ui = (t) => (o) => ({ __type: t, ...(o || {}) });
  const sandbox = {
    __navigations: navigations,
    __toasts: toasts,
    console,
    setTimeout: () => 0,
    setInterval: () => 0,
    clearTimeout: () => {},
    clearInterval: () => {},
    Date, Math, JSON, Map, Set, Promise, Number, String, Boolean,
    Array, Object, RegExp, Error, parseInt, parseFloat, isNaN,
    encodeURIComponent, decodeURIComponent, encodeURI,
  };
  sandbox.globalThis = sandbox;
  // 与 assets/js/init.js 的 PluginSource 同一份成员表：只有机制（能力方法故意不 stub，
  // 它们只有插件自己实现）。**别在这里补真实基类已经删掉的成员** ——
  // 曾经 stub 过 `translate` / `getSettings`，那会让用到它们的插件在这个校验里"通过"、
  // 在真机上却崩。
  sandbox.PluginSource = class PluginSource {
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
    { get: (t, p) => (p in t ? t[p] : (typeof p === 'symbol' ? undefined : ui(String(p).toLowerCase()))) },
  );
  sandbox.Dialog = {
    showToast: (m) => toasts.push(String(m)),
    showDialog() {}, showInputDialog: async () => null,
    showLoading: () => 0, cancelLoading() {}, showSelectDialog: async () => null,
  };
  sandbox.Navigator = {
    navigateToDescriptor: (plugin, opts) => navigations.push({ plugin, opts }),
    navigateToReader() {}, navigateToNovelReader() {}, navigateToVideo() {}, navigateToWebview() {},
  };
  sandbox.PluginBrowse = { open() {}, find: async () => null };
  sandbox.Network = {
    get: async () => '', post: async () => '', getHtml: async () => '',
    fetchBytes: async () => ({ body: new Uint8Array() }),
    sendRequest: async () => ({ body: '' }),
  };
  const bytes = () => new Uint8Array([1, 2, 3, 4]);
  sandbox.Convert = new Proxy(
    {
      md5: bytes, sha1: bytes, sha256: bytes, sha512: bytes, hmac: bytes, hmacString: () => '00',
      encodeUtf8: () => new Uint8Array([1]), decodeUtf8: () => '',
      encodeBase64: () => 'AA==', decodeBase64: () => new Uint8Array([1]),
      hexEncode: () => '00', hexDecode: () => new Uint8Array([0]),
      encryptAesEcb: bytes, decryptAesEcb: bytes, encryptAesCbc: bytes, decryptAesCbc: bytes,
    },
    { get: (t, p) => (p in t ? t[p] : (typeof p === 'symbol' ? undefined : bytes)) },
  );
  sandbox.HtmlDocument = class {
    querySelector() { return null; }
    querySelectorAll() { return []; }
    xpath() { return []; }
    dispose() {}
  };
  sandbox.APP = { version: '0', locale: 'zh_CN', platform: 'android' };
  sandbox.Comic = ui('comic');
  sandbox.ComicDetails = ui('comicDetails');
  sandbox.randomInt = (a = 0) => a;
  sandbox.randomDouble = (a = 0) => a;
  sandbox.createUuid = () => '00000000-0000-4000-8000-000000000000';
  sandbox.log = () => {};
  sandbox.compute = (f, ...a) => (typeof f === 'function' ? f(...a) : undefined);
  sandbox.sendMessage = () => null;
  sandbox.setClipboard = () => {};
  sandbox.getClipboard = async () => '';
  sandbox.Image = { empty: () => ({ width: 0, height: 0 }) };
  return sandbox;
}

process.on('unhandledRejection', () => {});

let pass = 0;
let fail = 0;
const check = (name, cond, extra) => {
  if (cond) { pass++; console.log('  PASS  ' + name); }
  else { fail++; console.log('  FAIL  ' + name + (extra ? '  | ' + extra : '')); }
};

function load(name) {
  const src = fs.readFileSync(path.join(DIR, name + '.js'), 'utf8');
  const sb = createSandbox();
  vm.runInContext(src + `\n;globalThis.__cls = ${name};`, vm.createContext(sb), { filename: name + '.js' });
  return { inst: new sb.__cls(), sb };
}

const fakeComic = (id) => ({ id: String(id), title: 'T' + id, subTitle: '', cover: '', tags: [], description: '' });

(async () => {
  console.log('=== 1) searchTag 必须触发跳转（返回值会被框架丢弃）===\n');
  for (const [name, ns, tag, singleArg] of TAG_CASES) {
    let loaded;
    try {
      loaded = load(name);
    } catch (e) {
      check(name, false, '实例化失败: ' + e.message);
      continue;
    }
    const { inst, sb } = loaded;
    const fn = typeof inst.searchTag === 'function' ? 'searchTag'
      : (typeof inst.searchByTag === 'function' ? 'searchByTag' : null);
    if (!fn) { check(name, false, '未实现 searchTag/searchByTag'); continue; }
    try {
      const ret = singleArg ? inst[fn](tag) : inst[fn](ns, tag);
      if (ret && typeof ret.then === 'function') await ret;
    } catch (e) {
      check(name + ' ' + fn + '()', false, '抛错: ' + e.message);
      continue;
    }
    const nav = sb.__navigations;
    const ok = nav.length === 1 && nav[0].plugin === name &&
      nav[0].opts && ['loadCategory', 'loadTagResult'].includes(nav[0].opts.method);
    check(`${name}.${fn}() 触发跳转（目标 ${nav[0] ? nav[0].opts.method : '—'}）`, ok, JSON.stringify(nav));
  }

  console.log('\n=== 2) explore / ranking 接线必须真的路由 ===\n');

  {
    const { inst } = load('hitomi');
    inst._explore[0].load = async (page) => ({ comics: [fakeComic('E' + page)], maxPage: 9 });
    const r1 = await inst._fetchCategoryComics('最新', 2, []);
    check('hitomi 探索分类 → _explore[0].load（透传页码）', r1.comics[0] && r1.comics[0].id === 'E2' && r1.maxPage === 9, JSON.stringify(r1));
    inst._categoryApi.ranking = { load: async (opt, page) => ({ comics: [fakeComic('R' + opt + page)], maxPage: 3 }) };
    const r2 = await inst._fetchCategoryComics('今日排行', 1, []);
    check('hitomi 排行榜分类 → ranking.load(option=today)', r2.comics[0] && r2.comics[0].id === 'Rtoday1', JSON.stringify(r2));
  }

  {
    const { inst } = load('manhuagui');
    inst._explore[0].load = async () => ([
      { title: '热门漫画最新更新', comics: [fakeComic('A')] },
      { title: '经典完结漫画', comics: [fakeComic('B')] },
    ]);
    const cat = await inst.getCategory();
    const home = cat.parts.find((p) => p.name === '首页');
    check('manhuagui 动态解析出首页板块名', !!home && home.categories.includes('经典完结漫画'), JSON.stringify(home));
    const r = await inst._fetchCategoryComics('经典完结漫画', 1, []);
    check('manhuagui 首页板块 → 取对应板块', r.comics[0] && r.comics[0].id === 'B', JSON.stringify(r));
    check('manhuagui 排行榜分组（4 维度）', cat.parts.some((p) => p.name === '排行榜' && p.categories.length === 4), JSON.stringify(cat.parts.map((p) => p.name)));
  }

  {
    const { inst } = load('hot_manga');
    let called = 0;
    inst._fetchHomeSections = async () => { called++; return { '推荐漫画': [fakeComic('H')] }; };
    const r = await inst._fetchCategoryComics('推荐漫画', 1, []);
    check('hot_manga 首页板块 → _fetchHomeSections', called === 1 && r.comics[0] && r.comics[0].id === 'H', JSON.stringify(r));
    const r2 = await inst._fetchCategoryComics('推荐漫画', 2, []);
    check('hot_manga 首页板块单页（第 2 页为空）', r2.comics.length === 0 && r2.maxPage === 1, JSON.stringify(r2));
  }

  {
    const { inst } = load('jcomic');
    inst._explore[0].load = async (page) => ({ comics: [fakeComic('J' + page)], maxPage: 7 });
    const r = await inst._fetchCategoryComics('最近更新', 3, []);
    check('jcomic 首页分类 → explore（透传页码）', r.comics[0] && r.comics[0].id === 'J3' && r.maxPage === 7, JSON.stringify(r));
  }

  {
    const { inst } = load('mycomic');
    inst._explore[0].load = async () => ({ comics: [fakeComic('M0')], maxPage: 2 });
    inst._explore[2].load = async () => ({ comics: [fakeComic('M2')], maxPage: 2 });
    const r0 = await inst._fetchCategoryComics('最新上架', 1, []);
    const r2 = await inst._fetchCategoryComics('最高人气', 1, []);
    check('mycomic 各列表路由到对应 _explore[i]', r0.comics[0] && r0.comics[0].id === 'M0' && r2.comics[0] && r2.comics[0].id === 'M2', JSON.stringify([r0.comics[0] && r0.comics[0].id, r2.comics[0] && r2.comics[0].id]));
  }

  {
    const { inst } = load('komiic');
    inst._explore[0].load = async (page) => ({ comics: [fakeComic('K' + page)], maxPage: 5 });
    const r = await inst._fetchCategoryComics('最近更新', 2, []);
    check('komiic 探索分类 → explore', r.comics[0] && r.comics[0].id === 'K2' && r.maxPage === 5, JSON.stringify(r));
  }

  {
    const { inst } = load('happy');
    inst._categoryApi.ranking = { load: async (opt, page) => ({ comics: [fakeComic('P' + opt)], maxPage: 1 }) };
    const r = await inst._fetchCategoryComics('日阅读', 1, []);
    check('happy 排行榜分类 → ranking.load(option=day)', r.comics[0] && r.comics[0].id === 'Pday', JSON.stringify(r));
  }

  console.log(`\n通过 ${pass} / 失败 ${fail}`);
  process.exit(fail ? 1 : 0);
})();
