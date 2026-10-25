#!/usr/bin/env node
/**
 * 生成**出厂插件配置** `assets/plugin/index.json`。
 *
 * 与运行时 `index.json` **同格式**（数组、六字段），随应用打包；只在「一个插件都没有」
 * 时被当作要读的配置写进 `index.json`，之后再也不读。
 *
 * 元数据来源（从内置插件里一次性抽取）：
 *   - `// description:` 头部注释 → `description`
 *   - `// type:`        头部注释 → `categoryId`
 *   - 类字段 `name = '…'`        → `displayName`（与插件名相同或缺失时留空，界面回落插件名）
 *
 * 全部写成 `enabled: false`：内置插件复制进用户目录后默认禁用，等用户自己导入。
 * 顺序 = 插件名字典序，因此出厂列表的顺序是确定的。
 *
 * 用法：node tools/gen_plugin_seed.js
 */

const fs = require('fs');
const path = require('path');

const PLUGIN_DIR = path.join(__dirname, '..', 'assets', 'plugin');
const OUT_FILE = path.join(PLUGIN_DIR, 'index.json');

/** 读头部注释里的 `// key: value`（只认行首注释） */
function headerValue(source, key) {
  const re = new RegExp('^//[ \\t]*' + key + ':[ \\t]*(.+)$', 'm');
  const m = source.match(re);
  return m ? m[1].trim() : '';
}

/** 读类体里的字符串字面量类字段 `key = '…'`（缩进 2–8 空格，单双引号都认） */
function classField(source, key) {
  const re = new RegExp(
    '^[ \\t]{2,8}' + key + "[ \\t]*=[ \\t]*([\"'])([^\"']*)\\1",
    'm',
  );
  const m = source.match(re);
  return m ? m[2].trim() : '';
}

const files = fs
  .readdirSync(PLUGIN_DIR)
  .filter((f) => f.endsWith('.js'))
  .sort();

/**
 * 插件顺序 = 数组位置 = 列表展示顺序（见 docs/plugin-storage-spec.md），
 * 所以这里**保留 index.json 里已有的顺序**，只把新出现的插件按名字序追加在后面。
 * 若每次都按名字重排，维护者定好的展示顺序会被重跑冲掉。
 */
function existingOrder() {
  try {
    const raw = JSON.parse(fs.readFileSync(OUT_FILE, 'utf8'));
    if (!Array.isArray(raw)) return [];
    return raw
      .map((r) => (r && typeof r.name === 'string' ? r.name : ''))
      .filter(Boolean);
  } catch (e) {
    return [];
  }
}

const names = files.map((f) => f.replace(/\.js$/, ''));
const ordered = [];
for (const name of [...existingOrder(), ...names]) {
  if (names.includes(name) && !ordered.includes(name)) ordered.push(name);
}

const records = [];
for (const name of ordered) {
  const source = fs.readFileSync(path.join(PLUGIN_DIR, `${name}.js`), 'utf8');

  // 显示名与插件名相同就没必要写：界面本来就会回落到插件名
  const declared = classField(source, 'name');
  const displayName = declared && declared !== name ? declared : '';

  records.push({
    name,
    enabled: false,
    displayName,
    categoryId: headerValue(source, 'type'),
    homepage: '',
    description: headerValue(source, 'description'),
  });
}

const missing = records.filter((r) => !r.categoryId || !r.description);
if (missing.length) {
  console.error(
    '有插件缺少 description / type 注释：' +
      missing.map((r) => r.name).join(', '),
  );
  process.exit(1);
}

fs.writeFileSync(OUT_FILE, JSON.stringify(records, null, 2) + '\n', 'utf8');

const withName = records.filter((r) => r.displayName).length;
console.log(`已写出 ${path.relative(path.join(__dirname, '..'), OUT_FILE)}`);
console.log(`  插件 ${records.length} 个（全部 enabled: false）`);
console.log(`  带展示名 ${withName} 个，其余靠插件名回落`);
console.log(
  '  分类分布 ' +
    JSON.stringify(
      records.reduce((acc, r) => {
        acc[r.categoryId] = (acc[r.categoryId] || 0) + 1;
        return acc;
      }, {}),
    ),
);
