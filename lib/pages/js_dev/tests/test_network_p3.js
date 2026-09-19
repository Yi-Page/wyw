/**
 * P3 请求模块测试脚本：WebView 会话池（并发安全串行化）+ 会话 Cookie 隔离
 *
 * 用法：同 P0/P1/P2——复制进「JS 开发」页编辑器，点 ▶ 运行。
 *
 * 覆盖点：
 *   1. 并发串行化：同一默认会话里并发 3 个 getHtml/webview（不同 URL）
 *      → 全部返回各自正确内容（无并发踩踏）
 *   2. 会话 Cookie 隔离：s1/s2 两个会话各自摄入 Set-Cookie，
 *      互不可见；后续同会话 HTTP 请求自动带上各自 Cookie
 *   3. 默认会话不被 s1/s2 污染
 *
 * 依赖 httpbin.org 与 cn.baozimhcn.com（前几轮已验证可达）。
 */

class Test {
  async run() {
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

    const DETAIL_URL = 'https://cn.baozimhcn.com/comic/wuliandianfeng-pikapi';

    // ---- 1. 并发串行化：同一会话 3 个并发 WebView 调用 ----
    try {
      const [a, b, c] = await Promise.all([
        Network.webview(DETAIL_URL, { timeout: 40, waitFor: 'selector:#chapter-items' }),
        Network.webview('https://httpbin.org/html', { timeout: 40, waitFor: { type: 'text', value: 'Moby' } }),
        Network.getHtml(DETAIL_URL, 40), // 旧签名 + 并发
      ]);
      const aOk = a.html.indexOf('chapter-items') >= 0;
      const bOk = b.html.indexOf('Moby') >= 0;
      const cOk = c.indexOf('chapter-items') >= 0;
      if (aOk && bOk && cOk) {
        pass('1. 并发串行化', '3 个并发调用各自内容正确（a.len=' + a.html.length + ' b.len=' + b.html.length + ' c.len=' + c.length + '）');
      } else {
        fail('1. 并发串行化', JSON.stringify({ aOk, bOk, cOk, aLen: a.html.length, bLen: b.html.length, cLen: c.length }));
      }
    } catch (e) { fail('1. 并发串行化', e); }

    // ---- 2. 会话 Cookie 隔离（HTTP Set-Cookie 按会话摄入 + 注入） ----
    try {
      // s1 摄入 s1c=1；s2 摄入 s2c=2
      for (const [sess, name] of [['s1', 's1c'], ['s2', 's2c']]) {
        try {
          await Network.sendRequest('GET', 'https://httpbin.org/cookies/set/' + name + '/1', {}, null, { session: sess, redirect: 'manual' });
        } catch (e) { /* 302 属预期 */ }
      }
      const jar1 = await Network.cookies('https://httpbin.org/anything', 's1');
      const jar2 = await Network.cookies('https://httpbin.org/anything', 's2');
      const isolated = jar1.indexOf('s1c=1') >= 0 && jar1.indexOf('s2c') < 0 &&
                       jar2.indexOf('s2c=1') >= 0 && jar2.indexOf('s1c') < 0;
      if (isolated) {
        pass('2. 会话 Cookie 隔离', 'jar1=[' + jar1 + '] jar2=[' + jar2 + ']');
      } else {
        fail('2. 会话 Cookie 隔离', 'jar1=[' + jar1 + '] jar2=[' + jar2 + ']');
      }

      // 后续同会话 HTTP 请求自动带上各自 Cookie（httpbin /cookies 回显收到的 Cookie）
      const b1 = await Network.get('https://httpbin.org/cookies', {}, { session: 's1' });
      const b2 = await Network.get('https://httpbin.org/cookies', {}, { session: 's2' });
      const injected = b1.indexOf('s1c') >= 0 && b1.indexOf('s2c') < 0 &&
                       b2.indexOf('s2c') >= 0 && b2.indexOf('s1c') < 0;
      if (injected) {
        pass('2b. 会话 Cookie 注入', 's1 带 s1c，s2 带 s2c，互不串');
      } else {
        fail('2b. 会话 Cookie 注入', 'b1含s1c=' + (b1.indexOf('s1c') >= 0) + ' b1含s2c=' + (b1.indexOf('s2c') >= 0) + ' b2含s2c=' + (b2.indexOf('s2c') >= 0));
      }
    } catch (e) { fail('2. 会话 Cookie 隔离', e); }

    // ---- 3. 默认会话不被 s1/s2 污染 ----
    try {
      const jar0 = await Network.cookies('https://httpbin.org/anything');
      if (jar0.indexOf('s1c') < 0 && jar0.indexOf('s2c') < 0) {
        pass('3. 默认会话未污染', 'jar0=[' + jar0 + ']');
      } else {
        fail('3. 默认会话未污染', 'jar0=[' + jar0 + '] 混入了 s1/s2 的 Cookie');
      }
    } catch (e) { fail('3. 默认会话未污染', e); }

    const failed = results.filter(x => !x.ok).length;
    log('----------------------------------------', failed ? 'error' : 'info');
    log('汇总: 通过 ' + (results.length - failed) + ' / ' + results.length, failed ? 'error' : 'info');
    return { total: results.length, passed: results.length - failed, failed };
  }
}
