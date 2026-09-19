/**
 * hanime 插件集成验证：对真实 hanime1.me 搜索页使用与插件相同的
 * waitFor（等结果渲染 / 明确无结果），确认新版 Network.getHtml 能拿到完整 HTML。
 *
 * 用法：复制进「JS 开发」页编辑器，点 ▶ 运行。
 * 若 hanime1.me 在你的网络不可达，会得到结构化错误（kind=timeout/connect 等），
 * 那也说明结构化错误生效；正常应返回 watch 链接数 > 0。
 */

class Test {
  async run() {
    const results = [];
    const pass = (n, d) => { log('[PASS] ' + n + (d ? ' | ' + d : ''), 'info'); results.push({ name: n, ok: true, detail: d }); };
    const fail = (n, e) => { log('[FAIL] ' + n + ' | ' + String(e && e.message || e), 'error'); results.push({ name: n, ok: false, detail: String(e && e.message || e) }); };

    const keyword = 'test';
    const url = 'https://hanime1.me/search?query=' + encodeURIComponent(keyword) + '&page=1';
    // 与 hanime.js _waitSearchSettled() 相同的等待条件（JS 表达式）
    const waitFor = {
      type: 'js',
      value: 'document.querySelectorAll("a[href*=\\\"/watch?v=\\\"]").length > 0 '
        + '|| /(沒有找到|没有找到|找不到|無結果|无结果|no result|nothing found)/i.test(document.body ? document.body.innerText : "")',
    };

    try {
      const html = await Network.getHtml(url, { timeout: 40, waitFor });
      const watchCount = (html.match(/\/watch\?v=\d+/g) || []).length;
      const hasContainer = html.indexOf('video-item-container') >= 0;
      if (html.length > 0) {
        pass('hanime 搜索渲染', 'HTML长度=' + html.length + ' watch链接=' + watchCount + ' 含video-item-container=' + hasContainer);
      } else {
        fail('hanime 搜索渲染', '空 HTML');
      }
    } catch (e) {
      fail('hanime 搜索渲染', e);
    }

    const failed = results.filter(x => !x.ok).length;
    log('----------------------------------------', failed ? 'error' : 'info');
    log('汇总: 通过 ' + (results.length - failed) + ' / ' + results.length, failed ? 'error' : 'info');
    return { total: results.length, passed: results.length - failed, failed };
  }
}
