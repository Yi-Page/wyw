/**
 * P1 请求模块测试脚本：extra 生效 + 结构化错误
 *
 * 用法：同 P0——复制进「JS 开发」页编辑器，点 ▶ 运行。
 *
 * 覆盖点：
 *   1. Network.get 正常 → 返回 string（无回归）
 *   2. 404 → 结构化错误：e.kind='http'、e.status=404、e.retryable=false
 *   3. DNS 失败 → e.kind='dns'、e.retryable=true
 *   4. 超时（extra.timeout 生效，connect 阶段）→ e.kind 为 timeout/connect、e.retryable=true
 *   5. Network.http 出错 → 也应抛结构化错误（修复回归）
 *   6. WebView 超时 → e.kind='webview'、e.retryable=true
 *   7. redirect:'manual' → 拿到 302 + e.headers.location（跳转目标）
 *
 * 若某个 URL 在你的环境不通，可替换。
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
    // 候选「确定返回 4xx」的 URL（baozimhcn 对任意路径都软 404 返回 200，不能用作 404 测试源）
    const CANDIDATE_404 = [
      'https://httpbin.org/status/404',
      'https://static-tw.baozimh.com/static/bzmh/img/definitely-not-exist-xyz.png',
      'https://s1.bzcdn.net/definitely-not-exist-xyz-12345.jpg',
    ];
    const REDIRECT_URL = 'https://cn.baozimhcn.com/user/page_direct?comic_id=wuliandianfeng-pikapi_lav8od&section_slot=0&chapter_slot=1';
    const fmt = (e) => e && { kind: e.kind, retryable: e.retryable, status: e.status, msg: e.message, headers: e.headers };

    // 依次请求候选 URL，返回第一个真实 4xx 的结构化错误；没有则 null
    const firstHttp4xx = async (useHttpApi) => {
      for (const u of CANDIDATE_404) {
        try {
          if (useHttpApi) { await Network.http(u); } else { await Network.get(u); }
        } catch (e) {
          if (e.kind === 'http' && e.status >= 400 && e.status < 600) return e;
        }
      }
      return null;
    };

    // ---- 1. 正常请求（无回归） ----
    try {
      const html = await Network.get(DETAIL_URL);
      if (typeof html === 'string' && html.length > 0) {
        pass('1. Network.get 正常', 'string 长度=' + html.length);
      } else {
        fail('1. Network.get 正常', '非字符串: ' + typeof html);
      }
    } catch (e) { fail('1. Network.get 正常', e); }

    // ---- 2. 真实 4xx → 结构化错误 ----
    {
      const e = await firstHttp4xx(false);
      if (e && e.retryable === false) {
        pass('2. 非2xx 结构化', JSON.stringify(fmt(e)));
      } else {
        fail('2. 非2xx 结构化', e ? '分类不符: ' + JSON.stringify(fmt(e)) : '候选 URL 均未返回 4xx');
      }
    }

    // ---- 3. DNS 失败 → e.kind='dns' ----
    try {
      await Network.get('https://no-such-host-abc.invalid/');
      fail('3. DNS 结构化', '应当报错却成功');
    } catch (e) {
      if (e.kind === 'dns' && e.retryable === true) {
        pass('3. DNS 结构化', JSON.stringify(fmt(e)));
      } else {
        fail('3. DNS 结构化', 'kind 不符: ' + JSON.stringify(fmt(e)));
      }
    }

    // ---- 4. 超时（extra.timeout 生效，10.x 不可达 → connect 超时）+ retries ----
    try {
      await Network.get('http://10.255.255.1:81/', {}, { timeout: 600, retries: 2 });
      fail('4. 超时+重试', '应当超时报错却成功');
    } catch (e) {
      if (e.retryable === true && (e.kind === 'timeout' || e.kind === 'connect')) {
        pass('4. 超时+重试', JSON.stringify(fmt(e)));
      } else {
        fail('4. 超时+重试', 'kind/retryable 不符: ' + JSON.stringify(fmt(e)));
      }
    }

    // ---- 5. Network.http 出错也抛结构化错误（回归修复） ----
    {
      const e = await firstHttp4xx(true);
      if (e) {
        pass('5. Network.http 错误', JSON.stringify(fmt(e)));
      } else {
        fail('5. Network.http 错误', '候选 URL 均未返回 4xx');
      }
    }

    // ---- 6. WebView 超时 → e.kind='webview' ----
    try {
      await Network.webview(DETAIL_URL, { timeout: 4, waitFor: 'selector:#no-such-element-xyz' });
      fail('6. webview 超时', '应当超时报错却成功');
    } catch (e) {
      if (e.kind === 'webview' && e.retryable === true) {
        pass('6. webview 超时', JSON.stringify(fmt(e)));
      } else {
        fail('6. webview 超时', 'kind/retryable 不符: ' + JSON.stringify(fmt(e)));
      }
    }

    // ---- 7. redirect:'manual' → 302 + location ----
    try {
      await Network.sendRequest('GET', REDIRECT_URL, {}, null, { redirect: 'manual' });
      fail('7. redirect manual', '应当报 302 却成功');
    } catch (e) {
      const loc = e.headers && (e.headers['location'] || e.headers['Location']);
      if (e.kind === 'http' && (e.status === 302 || e.status === 301 || e.status === 303) && loc) {
        pass('7. redirect manual', 'status=' + e.status + ' location=' + loc);
      } else {
        fail('7. redirect manual', '未拿到 302/location: ' + JSON.stringify(fmt(e)));
      }
    }

    const failed = results.filter(x => !x.ok).length;
    log('----------------------------------------', failed ? 'error' : 'info');
    log('汇总: 通过 ' + (results.length - failed) + ' / ' + results.length, failed ? 'error' : 'info');
    return { total: results.length, passed: results.length - failed, failed };
  }
}
