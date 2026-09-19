/**
 * P2 请求模块测试脚本：Cookie 双向同步 + HTTP→WebView 级联降级
 *
 * 用法：同 P0/P1——复制进「JS 开发」页编辑器，点 ▶ 运行。
 *
 * 覆盖点：
 *   1. HTTP Set-Cookie 自动摄入（manual 302 上的 Set-Cookie → Network.cookies 查到）
 *   2. WebView 页面 Cookie → 请求侧同步（WebView 加载 /cookies/set 后，Dio 侧可查到）
 *   3. backend:'webview' 强制渲染（Network.get 返回 HTML；sendRequest 带 via/finalUrl）
 *   4. backend:'auto' 级联降级（HTTP 500 → 自动走 WebView 成功，via='webview'）
 *   5. backend:'auto' 非反爬错误不降级（DNS 失败原样返回 kind='dns'）
 *
 * 依赖 httpbin.org（上一轮已验证可达）；若不通可替换为其它可设 Cookie 的站点。
 */

class Test {
  async run() {
    // 构建检查：P2 新增的 Network.cookies 需要「完整重建并重启 app」才存在
    // （init.js 打包进 asset，热重载不会生效）。旧构建会在此直接给明确提示。
    if (typeof Network.cookies !== 'function') {
      log('[FAIL] 请先完整重建并重启 app：Network.cookies 不存在（P2 的 init.js 改动未生效）', 'error');
      return { total: 1, passed: 0, failed: 1, hint: 'stale build: Network.cookies missing' };
    }

    const results = [];
    const start = Date.now();
    const pass = (name, detail) => {
      log('[PASS] ' + name + (detail ? ' | ' + detail : '') + ' | ' + (Date.now() - start) + 'ms', 'info');
      results.push({ name, ok: true, detail });
    };
    const fail = (name, err) => {
      log('[FAIL] ' + name + ' | ' + String(err && err.message || err), 'error');
      results.push({ name, ok: false, detail: String(err && err.message || err) });
    };
    const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

    // ---- 1. HTTP Set-Cookie 自动摄入（manual 302 上的 Set-Cookie） ----
    try {
      // /cookies/set/{name}/{value} → 302 + Set-Cookie
      await Network.sendRequest('GET', 'https://httpbin.org/cookies/set/wyw_p2/hello', {}, null, { redirect: 'manual' });
      fail('1. Set-Cookie 摄入', '应当拿到 302 却成功');
    } catch (e) {
      const jar = await Network.cookies('https://httpbin.org/anything/xyz');
      if (e.status === 302 && jar.indexOf('wyw_p2=hello') >= 0) {
        pass('1. Set-Cookie 摄入', 'status=' + e.status + ' cookies=[' + jar + ']');
      } else {
        fail('1. Set-Cookie 摄入', 'status=' + e.status + ' 未见 wyw_p2=hello, cookies=[' + jar + ']');
      }
    }

    // ---- 2. WebView 页面 Cookie → 请求侧同步 ----
    try {
      // WebView 加载 httpbin 设 Cookie 页（302 后落到 /cookies，页面文本含 wyw_wv）
      const wv = await Network.webview('https://httpbin.org/cookies/set/wyw_wv/1', {
        timeout: 30,
        waitFor: { type: 'text', value: 'wyw_wv' },
      });
      const jar = await Network.cookies('https://httpbin.org/anything');
      if (wv.html.length > 0 && jar.indexOf('wyw_wv=1') >= 0) {
        pass('2. WebView→Dio Cookie 同步', 'finalUrl=' + wv.finalUrl + ' cookies=[' + jar + ']');
      } else {
        fail('2. WebView→Dio Cookie 同步', 'html=' + wv.html.length + ' 未见 wyw_wv=1, cookies=[' + jar + ']');
      }
    } catch (e) { fail('2. WebView→Dio Cookie 同步', e); }

    // ---- 3. backend:'webview' 强制渲染 ----
    try {
      const html = await Network.get('https://cn.baozimhcn.com/comic/wuliandianfeng-pikapi', {}, {
        backend: 'webview',
        webviewTimeout: 30,
        waitFor: 'selector:#chapter-items',
      });
      const ok = typeof html === 'string' && html.indexOf('chapter-items') >= 0;
      if (ok) {
        pass('3. backend=webview', 'Network.get 返回渲染 HTML 长度=' + html.length);
      } else {
        fail('3. backend=webview', 'HTML 不含 #chapter-items: ' + typeof html + ' len=' + (html || '').length);
      }
      // sendRequest 应带 via/finalUrl
      const full = await Network.sendRequest('GET', 'https://cn.baozimhcn.com/comic/wuliandianfeng-pikapi', {}, null, {
        backend: 'webview',
        webviewTimeout: 30,
      });
      if (full.via === 'webview' && full.finalUrl && full.body) {
        pass('3b. sendRequest via/finalUrl', 'via=' + full.via + ' finalUrl=' + full.finalUrl);
      } else {
        fail('3b. sendRequest via/finalUrl', JSON.stringify({ via: full.via, finalUrl: full.finalUrl, hasBody: !!full.body }));
      }
    } catch (e) { fail('3. backend=webview', e); }

    // ---- 4. backend:'auto' 级联降级（HTTP 500 → WebView 渲染成功） ----
    try {
      const full = await Network.sendRequest('GET', 'https://httpbin.org/status/500', {}, null, {
        backend: 'auto',
        webviewTimeout: 30,
        waitFor: 'text:500',
      });
      const ok = full.via === 'webview' && typeof full.body === 'string' && full.body.indexOf('500') >= 0;
      if (ok) {
        pass('4. auto 级联降级', 'HTTP 500 → via=' + full.via + ' body 长度=' + full.body.length);
      } else {
        fail('4. auto 级联降级', JSON.stringify({ via: full.via, hasBody: !!full.body, len: (full.body || '').length }));
      }
    } catch (e) { fail('4. auto 级联降级', e); }

    // ---- 5. backend:'auto' 非反爬错误不降级（DNS 失败原样返回） ----
    try {
      await Network.sendRequest('GET', 'https://no-such-host-abc.invalid/', {}, null, { backend: 'auto' });
      fail('5. auto 不误降级', '应当报错却成功');
    } catch (e) {
      if (e.kind === 'dns') {
        pass('5. auto 不误降级', '原样返回 kind=' + e.kind);
      } else {
        fail('5. auto 不误降级', 'kind 不符: ' + e.kind);
      }
    }

    const failed = results.filter(x => !x.ok).length;
    log('----------------------------------------', failed ? 'error' : 'info');
    log('汇总: 通过 ' + (results.length - failed) + ' / ' + results.length, failed ? 'error' : 'info');
    return { total: results.length, passed: results.length - failed, failed };
  }
}
