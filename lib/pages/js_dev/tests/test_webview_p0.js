/**
 * P0 WebView 条件等待 + 最终 URL 测试脚本
 *
 * 用法：
 *   1. 打开 App 的「JS 开发」页（lib/pages/js_dev 的测试台）
 *   2. 把本文件内容整体复制粘贴进上方编辑器，点 ▶ 运行
 *   3. 下方日志会逐条输出 [PASS]/[FAIL]，最后返回汇总 {total, passed, failed}
 *
 * 覆盖点：
 *   1. getHtml 旧签名（Network.getHtml(url, 秒数)）向后兼容 → 返回 string
 *   2. Network.webview 默认 → {html, finalUrl} 都非空
 *   3. waitFor selector：等 #chapter-items 出现，且 HTML 确含该选择器
 *   4. waitFor text：等 body 文本包含 Moby（httpbin/html，文本稳定），且 HTML 确含
 *   5. waitFor js：自定义表达式
 *   6. finalUrl 跳转：httpbin redirect-to 302 → 等 location.href 落到 /html 再返回
 *   7. 负测试：等一个永不出现的选择器 + 短超时 → 应 reject（超时路径）
 *
 * 注：检查 4/6 用 httpbin 验证机制本身，不硬编码站点文本/域名——
 * baozimh 的域路由（cn.dzmanga.com → www.baozimh.com 等）与 UI 文案会变。
 * 若某个域名连不上（网络/代理差异），可整体替换测试 URL。
 */

class Test {
  async run() {
    const results = [];
    const start = Date.now();

    const pass = (name, detail) => {
      const ms = Date.now() - start;
      log('[PASS] ' + name + (detail ? ' | ' + detail : '') + ' | ' + ms + 'ms', 'info');
      results.push({ name, ok: true, detail });
    };
    const fail = (name, err) => {
      log('[FAIL] ' + name + ' | ' + String(err && err.message || err), 'error');
      results.push({ name, ok: false, detail: String(err && err.message || err) });
    };

    const DETAIL_URL = 'https://cn.baozimhcn.com/comic/wuliandianfeng-pikapi';

    // ---- 1. getHtml 旧签名（超时秒数）→ 返回 string ----
    try {
      const html = await Network.getHtml(DETAIL_URL, 40);
      if (typeof html === 'string' && html.length > 0) {
        pass('1. getHtml 旧签名', '返回 string，长度=' + html.length);
      } else {
        fail('1. getHtml 旧签名', '返回值异常: ' + typeof html);
      }
    } catch (e) { fail('1. getHtml 旧签名', e); }

    // ---- 2. Network.webview 默认 → {html, finalUrl} ----
    try {
      const r = await Network.webview(DETAIL_URL, { timeout: 30 });
      if (r && typeof r.html === 'string' && r.html.length > 0 && typeof r.finalUrl === 'string' && r.finalUrl.length > 0) {
        pass('2. webview 默认', 'html长度=' + r.html.length + ' finalUrl=' + r.finalUrl);
      } else {
        fail('2. webview 默认', '返回结构异常: ' + JSON.stringify({ h: (r && r.html || '').length, f: r && r.finalUrl }));
      }
    } catch (e) { fail('2. webview 默认', e); }

    // ---- 3. waitFor selector ----
    try {
      const r = await Network.webview(DETAIL_URL, { timeout: 30, waitFor: 'selector:#chapter-items' });
      const ok = r.html.indexOf('chapter-items') >= 0;
      if (ok) {
        pass('3. waitFor selector', 'HTML 含 #chapter-items，长度=' + r.html.length);
      } else {
        fail('3. waitFor selector', 'HTML 不含 #chapter-items（条件未真正等待?）');
      }
    } catch (e) { fail('3. waitFor selector', e); }

    // ---- 4. waitFor text（用文本稳定的 httpbin/html 验证机制，不依赖站点文案） ----
    try {
      const r = await Network.webview('https://httpbin.org/html', { timeout: 30, waitFor: { type: 'text', value: 'Moby' } });
      const ok = r.html.indexOf('Moby') >= 0;
      if (ok) {
        pass('4. waitFor text', 'HTML 含 Moby，长度=' + r.html.length);
      } else {
        fail('4. waitFor text', 'HTML 不含 Moby');
      }
    } catch (e) { fail('4. waitFor text', e); }

    // ---- 5. waitFor js（自定义表达式） ----
    try {
      const r = await Network.webview(DETAIL_URL, { timeout: 30, waitFor: { type: 'js', value: 'document.querySelectorAll("a").length > 5' } });
      const ok = r.html.indexOf('<a') >= 0;
      if (ok) {
        pass('5. waitFor js', 'HTML 含 <a 链接，长度=' + r.html.length);
      } else {
        fail('5. waitFor js', 'HTML 不含 <a');
      }
    } catch (e) { fail('5. waitFor js', e); }

    // ---- 6. finalUrl 跳转（302 → 落地地址；用 httpbin redirect-to 保证确定性，不依赖站点域） ----
    try {
      const r = await Network.webview('https://httpbin.org/redirect-to?url=https%3A%2F%2Fhttpbin.org%2Fhtml', {
        timeout: 30,
        waitFor: 'js:location.href.indexOf("httpbin.org/html") >= 0',
      });
      const ok = r.finalUrl.indexOf('httpbin.org/html') >= 0 && r.html.indexOf('Moby') >= 0;
      if (ok) {
        pass('6. finalUrl 跳转', 'finalUrl=' + r.finalUrl + ' html长度=' + r.html.length);
      } else {
        fail('6. finalUrl 跳转', 'finalUrl 未落到 httpbin.org/html: ' + r.finalUrl);
      }
    } catch (e) { fail('6. finalUrl 跳转', e); }

    // ---- 7. 负测试：永不满足的条件 + 短超时 → 应 reject ----
    try {
      await Network.webview(DETAIL_URL, { timeout: 6, waitFor: 'selector:#no-such-element-12345' });
      fail('7. 超时负测试', '应当超时却成功返回了');
    } catch (e) {
      const msg = String(e && e.message || e);
      if (msg.indexOf('超时') >= 0) {
        pass('7. 超时负测试', '如预期 reject：' + msg);
      } else {
        fail('7. 超时负测试', 'reject 但不是超时信息: ' + msg);
      }
    }

    const failed = results.filter(x => !x.ok).length;
    log('----------------------------------------', failed ? 'error' : 'info');
    log('汇总: 通过 ' + (results.length - failed) + ' / ' + results.length, failed ? 'error' : 'info');
    return { total: results.length, passed: results.length - failed, failed };
  }
}
