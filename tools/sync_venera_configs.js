// venera-configs 上游插件同步脚本。
//
// 用途：把 https://cdn.jsdelivr.net/gh/venera-app/venera-configs@main 的
// index.json 与其中列出的全部插件原样下载到本目录（tools/venera-configs/），
// 作为逐个适配到 wyw 格式的**只读参考**（适配产物写在 assets/plugin/）。
//
// 用法：node tools/sync_venera_configs.js
//
// 注意：本脚本只做「下载原版」，不做任何格式转换 —— venera → wyw 的适配
// 必须逐个插件人工进行（见 docs/venera-plugin-adaptation.md）。
const fs = require('fs');
const path = require('path');
const https = require('https');

const BASE = 'https://cdn.jsdelivr.net/gh/venera-app/venera-configs@main/';
const OUT = path.join(__dirname, 'venera-configs');

function fetchBuffer(url, redirects = 0) {
  return new Promise((resolve, reject) => {
    https
      .get(url, { headers: { 'User-Agent': 'wyw-plugin-sync' } }, (res) => {
        if (
          res.statusCode >= 300 &&
          res.statusCode < 400 &&
          res.headers.location &&
          redirects < 5
        ) {
          res.resume();
          return resolve(
            fetchBuffer(new URL(res.headers.location, url).toString(), redirects + 1),
          );
        }
        if (res.statusCode !== 200) {
          res.resume();
          return reject(new Error('HTTP ' + res.statusCode));
        }
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => resolve(Buffer.concat(chunks)));
      })
      .on('error', reject);
  });
}

(async () => {
  fs.mkdirSync(OUT, { recursive: true });

  const indexRaw = await fetchBuffer(BASE + 'index.json');
  fs.writeFileSync(path.join(OUT, 'index.json'), indexRaw);
  const list = JSON.parse(indexRaw.toString('utf8'));
  console.log('index.json: ' + list.length + ' 项');

  const failed = [];
  for (const item of list) {
    const file = item.fileName;
    try {
      const buf = await fetchBuffer(BASE + file);
      fs.writeFileSync(path.join(OUT, file), buf);
      console.log('OK   ' + file + '  ' + buf.length + ' bytes');
    } catch (e) {
      failed.push(file);
      console.log('FAIL ' + file + '  ' + e.message);
    }
  }

  console.log('\n完成: ' + (list.length - failed.length) + '/' + list.length);
  if (failed.length) {
    console.log('失败: ' + failed.join(', '));
    process.exit(1);
  }
})();
