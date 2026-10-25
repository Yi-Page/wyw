// pixiv 插件小说阅读器离线回归测试（不联网）。
//
// 覆盖曾经出现过的线上问题：
//   - 章节 args 只传了 novelId，loadChapterContent(novelId, epId) 里用 epId，
//     导致请求 /novel_text?id=undefined；
//   - /novel_text 不可用时没有 /webview_novel 兜底。
//
// 用法：node tools/verify_pixiv_novel.js
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const SRC = fs.readFileSync(path.join(__dirname, '..', 'assets', 'plugin', 'pixiv.js'), 'utf8');

function load(handler) {
  const urls = [];
  const navs = [];
  const ui = (t) => (o) => ({ __type: t, ...(o || {}) });
  const sb = {
    console: { log() {}, error() {}, warn() {} },
    setTimeout: () => 0, setInterval: () => 0, clearTimeout() {}, clearInterval() {},
    Date, Math, JSON, Map, Set, Promise, Number, String, Boolean,
    Array, Object, RegExp, Error, parseInt, parseFloat, isNaN,
    encodeURIComponent, decodeURIComponent, encodeURI,
    PluginSource: class {
      loadSetting() { return ''; }
      saveSetting() {}
      loadData() { return null; }
      saveData() {}
      deleteData() {}
      get isLogged() { return false; }
      init() {}
    },
    UI: new Proxy(
      { Text: (x) => ({ __type: 'text', ...(typeof x === 'string' ? { content: x } : x) }), validate: () => [] },
      { get: (t, p) => (p in t ? t[p] : (typeof p === 'symbol' ? undefined : ui(String(p).toLowerCase()))) },
    ),
    Dialog: { showToast() {}, showDialog() {}, showInputDialog: async () => null, showLoading: () => 0, cancelLoading() {}, showSelectDialog: async () => null },
    Navigator: {
      navigateToDescriptor() {}, navigateToReader() {},
      navigateToNovelReader(opts) { navs.push(opts); },
      navigateToVideo() {}, navigateToWebview() {},
    },
    PluginBrowse: { open() {}, find: async () => null },
    Network: {
      async get(url) { urls.push(String(url)); return handler(String(url)); },
      post: async () => '', getHtml: async () => '',
      fetchBytes: async () => ({ body: new Uint8Array() }),
      sendRequest: async () => ({ body: '' }),
    },
    Convert: new Proxy({}, { get: () => () => '00' }),
    HtmlDocument: class { querySelector() { return null; } querySelectorAll() { return []; } xpath() { return []; } dispose() {} },
    APP: { version: '0', locale: 'zh_CN', platform: 'android' },
    Comic: ui('comic'), ComicDetails: ui('comicDetails'),
    randomInt: (a = 0) => a, randomDouble: (a = 0) => a,
    createUuid: () => '00000000-0000-4000-8000-000000000000',
    log() {}, compute: (f, ...a) => (typeof f === 'function' ? f(...a) : undefined),
    sendMessage: () => null, setClipboard() {}, getClipboard: async () => '',
    Image: { empty: () => ({ width: 0, height: 0 }) },
  };
  sb.globalThis = sb;
  vm.runInContext(SRC + '\n;globalThis.__cls = pixiv;', vm.createContext(sb), { filename: 'pixiv.js' });
  return { inst: new sb.__cls(), urls, navs };
}

let pass = 0;
let fail = 0;
function check(name, ok, extra) {
  if (ok) { pass++; console.log('PASS  ' + name); }
  else { fail++; console.log('FAIL  ' + name + (extra ? '  | ' + extra : '')); }
}

(async () => {
  {
    const { inst, navs } = load(() => JSON.stringify({}));
    await inst.openNovelReader('29456460');
    const args = navs[0] && navs[0].chapters && navs[0].chapters[0] && navs[0].chapters[0].args;
    check(
      'openNovelReader 章节 args = [novelId, epId]',
      Array.isArray(args) && args[0] === '29456460' && args[1] === '29456460',
      JSON.stringify(args),
    );
  }

  {
    const { inst, urls } = load((url) =>
      url.includes('/novel_text')
        ? JSON.stringify({ novel_text: '正文A' })
        : JSON.stringify({ error: 'unexpected' }));
    const text = await inst.loadChapterContent('29456460', undefined);
    check(
      'loadChapterContent(novelId, undefined) 使用 novelId',
      text === '正文A' && urls.length === 1 && urls[0].includes('novel_text?id=29456460'),
      JSON.stringify(urls),
    );
  }

  {
    const { inst, urls } = load((url) => {
      if (url.includes('/novel_text')) return JSON.stringify({ error: 'Not Accepted' });
      return JSON.stringify({ text: '<p>正文B</p>' });
    });
    const text = await inst.loadChapterContent('29456460');
    check(
      '/novel_text 失败时回退 /webview_novel 并去 HTML',
      text === '正文B' && urls.some((u) => u.includes('/webview_novel?id=29456460')),
      JSON.stringify(urls),
    );
  }

  {
    const { inst, urls } = load(() => JSON.stringify({ error: 'Not Accepted' }));
    let msg = '';
    try { await inst.loadChapterContent('29456460'); } catch (e) { msg = String((e && e.message) || e); }
    check(
      '两个接口都失败时提示自建 API / PIXIV_COOKIE',
      msg.includes('PIXIV_COOKIE') && urls.every((u) => !u.includes('undefined')),
      msg + ' ' + JSON.stringify(urls),
    );
  }

  {
    const { inst, urls } = load(() => JSON.stringify({}));
    let msg = '';
    try { await inst.loadChapterContent(); } catch (e) { msg = String((e && e.message) || e); }
    check('缺少 ID 时直接报错且不发请求', msg.includes('缺少小说 ID') && urls.length === 0, msg);
  }

  console.log(`\n通过 ${pass} / 失败 ${fail}`);
  process.exit(fail ? 1 : 0);
})();
