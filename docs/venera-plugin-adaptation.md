# venera-configs → wyw 插件逐个适配记录

> **状态：历史记录。** 本文记录 2026-09 的逐个适配过程；`ccc` / `picacg` /
> `comic_walker` 等插件已移出 `assets/plugin/`，原版只保留在
> `tools/venera-configs/`（该目录已不再入库，可用 `sync_venera_configs.js` 重新拉取）。
> 新插件开发请以 `plugin-development.md` 为准。

上游来源：`https://cdn.jsdelivr.net/gh/venera-app/venera-configs@main/index.json`（33 项）
原版镜像：`tools/venera-configs/`（只读参考，**不要直接改**）
适配产物：`assets/plugin/*.js`
同步脚本：`node tools/sync_venera_configs.js`（只下载，不做转换）

配套工具：

| 工具 | 用途 |
|---|---|
| `node tools/sync_venera_configs.js` | 从上游 index.json 同步全部插件原版到 `tools/venera-configs/`（**只下载，不做格式转换**） |
| `node tools/check_plugins.js [插件名...]` | 静态机械校验：语法 / 类名=文件名 / 继承 PluginSource / 必需方法 / venera API 残留 / 未定义成员引用 / `init()` 是否被调用 / `_explore` 等结构是否接线 / `getCategory()` 结构 |
| `node tools/verify_plugin_behavior.js` | 行为回归（不联网）：实例化插件并 mock 框架 API，断言 ① `searchTag` 真的触发跳转（防「回调 return 列表→点了没反应」复发）② `explore`/`ranking` 接线真的路由到对应来源 |

## 为什么必须逐个适配

venera 与 wyw 的插件接口是**结构性差异**，不是标识符替换：

| venera | wyw |
|---|---|
| `class X extends ComicSource` | `class X extends PluginSource` |
| 对象属性式接口（`search = { load, optionLoader }`） | 方法式接口（`search()` / `getCategoryOptions()`） |
| `new Comic({...})` / `new ComicDetails({...})` | `UI.*` 描述符树 |
| `Network.get(url, headers)` → `{status, body}` | `Network.get(url, headers)` → **body 字符串** |
| 全局 `fetch(url, {headers})` | 无（改用 `Network.get` / `Network.getHtml`） |

因此脚本批量转换不可行（会掩盖错误、丢功能），必须逐个插件人工适配 + 逐个验证。

## 接口映射规则（适配时遵循）

### 类与元数据

```javascript
// venera
class JM extends ComicSource { name = "禁漫天堂"; key = "jm"; version = "1.4.0"
                              minAppVersion = "1.5.0"; url = "https://..." }
// wyw
class jm extends PluginSource { name = '禁漫天堂'; key = 'jm'; version = '1.1.0' }
// wyw 额外：文件头两行注释（Plugin 元数据解析用）
// description: 禁漫天堂（JM）漫画源 — 搜索/详情/章节/阅读
// type: manga
```

- **JS 类名必须等于文件名（去 .js）**：`jm.js` → `class jm`。
  （`Plugin` 构造时 `className: name, entityName: name`，`JsEntity.register` 用 `new $className()`
  挂到 `__plugins__.$entityName`，这里的 name 就是文件名。）
- **`key` 已经不是任何东西的命名空间**（venera 里它是 `loadSetting/saveSetting/loadData`
  的存储命名空间，多个插件同 key 会互相覆盖）：wyw 的存储命名空间由基类直接取
  `this.constructor.name`（= 文件名），基类**没有** `key` 成员，声明 `key = '…'` 只是死数据。
- ⚠️ **`openReader` 里的 `plugin:` 字段必须写「插件名（= 文件名）」**：
  框架按**文件名**挂载与查找插件（`__plugins__.<文件名>`）。
  插件内写 `this.constructor.name` 即可；**不要**写 `this.key` —— 基类没有这个成员，
  移植前那些插件声明的 `key = "Komiic"` 之类值也已经不再参与任何寻址。
  （`sourceKey` 用于图片缓存隔离，写插件名同样合适。）
- `minAppVersion` / `url`（自更新地址）在 wyw 无对应 → 删除。
- wyw 的 `PluginSource` **不会调用 `init()`** → 初始化逻辑挪到实例字段/构造函数里兜底触发。

### 分类浏览

| venera | wyw |
|---|---|
| `this.category = { title, parts: [{name, type, categories, itemType}], enableRankingPage }` | `getCategory()` → `{ title, parts: [{name, categories}] }` |
| `this.categoryComics.load(category, param, options, page)` → `{comics, maxPage}` | `loadCategory(category, page, options)`（返回分页容器）+ `loadCategoryPage(category, page, options)`（返回列表） |
| `this.categoryComics.optionLoader(category, param)` → `[{label, options: ["value-text"]}]` | `getCategoryOptions(category)` → `[{label, options: [{value, text}]}]` |
| `itemType` / `type` 字段 | 无（wyw 一律按 `categoryMap` 或搜索处理） |

- venera 的 `"value-text"` 字符串选项要拆成 `{value, text}` 对象。
- venera 的 `param`（分类参数）在 wyw 无对应 → 合并进 category 名或内部映射表。

### 搜索

| venera | wyw |
|---|---|
| `this.search.load(keyword, options, page)` → `{comics, maxPage}` | `search(keyword, page)` → `List<UI.Card>` |
| `this.search.optionLoader()` | 无（搜索页筛选项 wyw 未支持） |

### 详情 / 章节 / 图片

| venera | wyw |
|---|---|
| `this.comic.loadInfo(id)` → `ComicDetails` | `getDetail(id)` → `List<UI>` |
| `this.comic.loadEp(comicId, epId)` → `{images: []}` | `loadChapterImages(comicId, epId)` → `[url]` |
| `this.comic.loadThumbnails(comicId, epId)` | 无对应 |
| `this.comic.onImageLoad(url, comicId, epId)` | `getImageLoadingConfig(url, comicId, epId)` |
| `this.comic.onClickComic(id)` | `openReader(epId)` / `Navigator.navigateToReader` |
| `this.comic.loadComments(...)` | 无对应 |

### 对话框

| venera | wyw |
|---|---|
| `UI.showMessage(msg)` | `Dialog.showToast(msg)` |
| `UI.showDialog(title, msg, actions)` | `Dialog.showDialog(title, content, actions)` |
| `UI.showInputDialog(title, validator, image)` | ⚠️ **Dart 侧未实现**（见缺口 G1） |
| `UI.showLoading(onCancel)` / `UI.cancelLoading(id)` | ⚠️ **Dart 侧未实现**（见缺口 G2） |
| `UI.showSelectDialog(...)` | ⚠️ **Dart 侧未实现**（见缺口 G3） |

### 同名可直接沿用

`loadSetting` / `saveSetting` / `loadData` / `saveData` / `deleteData` / `getSettings` / `translate` / `Convert.*`

### 网络

```javascript
// venera：返回 Response 对象
let res = await Network.get(url, headers)
if (res.status !== 200) throw 'Invalid Status Code: ' + res.status
let json = JSON.parse(res.body)

// wyw：直接返回 body 字符串（错误通过 throw 抛出）
let body = await Network.get(url, headers)
let json = JSON.parse(body)
```

- `fetch(url, {headers})`：**wyw 有**（`init.js:738` 注入全局 `fetch` 别名，转发 `Network.fetch`，
  返回 `{ok, status, text(), json(), arrayBuffer()}`）。但规范入口仍是 `Network.get`（返回 body 字符串）；
  需要响应头/状态码时用 `Network.sendRequest`。
- `res.arrayBuffer()` → `Network.fetchBytes(...)`。
- **易错点**：`Network.get` 的返回值是字符串，对它取 `.status`/`.body`/`.headers` 恒为 `undefined`。
  Kavita 就因此拿不到分页响应头（已改用 `Network.sendRequest`）。

## Dart 侧缺口汇总（待统一解决）

> 逐个适配中发现的、**必须改 Dart 侧**才能支持的能力。适配时在插件里先降级处理并在此登记。

| 编号 | 能力 | JS API | 现状 | 影响的插件 | 建议 |
|---|---|---|---|---|---|
| G1 | 输入对话框 | `Dialog.showInputDialog(title, validator, image)` | `init.js` 已定义、文档已写，但 `JsDialog.handleDialogCallback` 只实现了 `showToast` | ccc（验证码） | 在 Dart 侧实现：返回 `Future<String?>` 弹输入框。**ccc 适配时二次确认**：`lib/js/js_extends/js_dialog.dart` 全文 21 行，`switch` 仅 `case 'showToast'`，无 `showInputDialog`/`showSelectDialog`/`showLoading`/`cancelLoading` 分支；`grep showInputDialog lib/**/*.dart` 零命中 → 该调用当前必然返回 `null` |
| G2 | 加载中对话框 | `Dialog.showLoading(onCancel)` / `cancelLoading(id)` | 同上，未实现 | mxs | 实现（返回 id + 可取消） |
| G3 | 选择对话框 | `Dialog.showSelectDialog(title, options, initialIndex)` | 同上，未实现 | 待统计 | 实现 |
| G4 | 账号体系 | `account = { login, logout, ... }` | wyw 无账号/登录 UI | copy_manga / ehentai / nhentai / picacg / jm / komiic / kavita / lanraragi / manga_dex / mycomic / wnacg / hot_manga / ccc | 评估：先跳过（删除 account 分支），或补插件设置页登录入口 |
| G5 | 收藏体系 | `favorites = {...}` | wyw 无收藏夹 | 多数插件 | 评估后统一决策 |
| G6 | 排行榜 | `ranking = {...}` / `enableRankingPage` | wyw 无排行榜页 | jm 等 | 可映射为浏览页分类 |
| G7 | 评论 | `comments = {...}` | wyw 无评论 UI | zaimanhua / ehentai / manga_dex | 先跳过 |
| G8 | 全局 `fetch` | `fetch(url, opts)` | **实际存在**：`init.js:738` 注入全局 `fetch` 别名（转发 `Network.fetch`，返回 `{ok, status, text(), json(), arrayBuffer()}`）。但语义与 venera 的 `fetch` 不完全一致（`text()` / `json()` 是**方法**，需 `await res.json()`），照抄 venera 的 `res.body` 仍会错 | jm 等 | 可不补。**适配规范：优先用 `Network.get`（返回 body 字符串），需要状态码用 `Network.sendRequest`**，不要依赖全局 `fetch` |
| G9 | 回调型设置项 | `settings.x = { type: 'callback', buttonText, callback }` | **已实现**（`plugin_settings_page.dart:175` 有 `case 'callback'`）。注意 wyw 约定与 venera 不同：`callback` 写**插件方法名字符串**（函数无法跨 JSON 边界，`getSettings()` 会被 `JSON.stringify` 丢掉函数），Dart 侧渲染按钮后按名调用 | — | 无需再补。适配时把 venera 的 `callback` 函数改写成同名插件方法并填方法名 |
| G10 | 缩略图加载配置 | `comic.onThumbnailLoad(url)` | wyw 无对应（缩略图一律走 `getImageLoadingConfig`） | jm 等 | 评估：可在阅读器缩略图路径复用 `getImageLoadingConfig` |
| G11 | ID 匹配 / 标签点击 | `comic.idMatch`、`comic.onClickTag(ns, tag)` | wyw 无对应机制 | jm / ehentai | 低优先：跳过 |
| G12 | 设置项翻译表 | `translation = { zh_CN: {...} }` + `this.translate(k)` | `translate` 存在，但设置项 `title` 不走翻译 | jm 等 | 适配时把 `title` 直接写成中文即可（不改 Dart） |
| G13 | 搜索筛选项 | `search.optionList = [{type:'select', options:['v-text']}]` | wyw 搜索页无筛选项 UI | jm / copy_manga 等 | 适配时丢弃，排序等参数在插件内固定默认值 |
| G14 | 登录态查询 | `PluginSource.isLogged`（`sendMessage({method:'isLogged'})`） | `init.js:1458` 已定义，但 `js_bridge.dart` 的 `handleCommonMessage` **没有 `case 'isLogged'`** → 落入 `return null`；且 wyw 无账号体系可查。**危害**：`if (!this.isLogged)` 恒为 `true`（`!null`），沿用上游写法的插件会**直接在入口抛 "Not logged in"**（picacg 的 5 个探索入口原本全废）。`grep isLogged lib/**/*.dart` 零命中 | picacg（已实测）等所有用 `isLogged` 判登录的插件 | 二选一：① 在 Dart 侧实现（返回插件是否已登录），② 明确「wyw 无登录态」，插件侧一律不要用 `isLogged` 做门禁。**适配建议按 ② 处理**（picacg 已改为用 token 是否存在判断） |
| G15 | 当前语言 | `APP.locale`（`sendMessage({method:'getLocale'})`）→ 被 `PluginSource.translate()` 依赖 | `init.js:1725` 已定义，但 `js_bridge.dart` **没有 `case 'getLocale'`** → 返回 `null` → `this.translation[null]` → `undefined` → **`translate(k)` 恒返回原 key，上线后永远不翻译**。`grep getLocale lib/**/*.dart` 零命中 | jm / ccc / picacg 等所有声明 `translation` 的插件 | 补 `case 'getLocale'` 返回 `PlatformDispatcher.locale`（形如 `zh_CN`）。**在修复前，插件里的用户可见文案不能只依赖 `translate()`** |
| G16 | 密码型设置项 | `settings.x = { type: 'password' }` | **已实现**（`plugin_settings_page.dart` 有 `case 'password'`，`obscureText: true`）；`input` 类型同时补上了 venera 的 `validator` 正则校验 | picacg 等 | 无需再补 |

## Dart 侧已解决（本轮统一实现，`flutter analyze` + `flutter test` 全绿）

> 实现位置与验证：`lib/js/js_extends/js_dialog.dart`、`js_bridge.dart`、
> `lib/pages/init_page.dart`、`lib/pages/plugin/plugin_settings_page.dart`；
> 新增 `test/js_dialog_test.dart`（12 项断言）。

| 缺口 | 状态 | 实现要点 |
|---|---|---|
| **G1** `Dialog.showInputDialog` | ✅ 已实现 | 返回 `Future<String?>`（flutter_qjs 转 JS Promise，JS 可 `await`）；支持 `image`（URL 字符串或 ArrayBuffer 字节，如 ccc 验证码）与 `validator`（JS 函数，确认时回调，调用失败则放行）；取消返回 null；**宿主未注册回调时返回 null**，插件据此优雅降级 |
| **G2** `showLoading` / `cancelLoading` | ✅ 已实现 | 返回可取消的 id；未注册时返回 -1 |
| **G3** `showSelectDialog` | ✅ 已实现 | 返回选中下标，取消返回 null |
| **G9** 设置项 `type:'callback'` | ✅ 已实现（subagent 亦已确认） | 渲染按钮 → 按**方法名字符串**调用插件方法 |
| **G14** `isLogged` | ✅ 已实现 | `js_bridge.dart` 新增 `case 'isLogged'`：返回宿主 `onIsLogged` 结果，未接入账号体系时**明确返回 `false`**（旧实现落 `return null`，语义含糊且让 `!isLogged` 恒真） |
| **G15** `getLocale` / `APP.locale` | ✅ 已实现 | 新增 `case 'getLocale'`，返回 `PlatformDispatcher.locale` 的 `zh_CN` 形式。**旧实现无此分支 → `translate(k)` 恒返回原 key，所有插件的 `translation` 表都不生效** |
| **G16** `password` 设置项 | ✅ 已实现 | `obscureText: true`；顺带给 `input` 补了 `validator` 正则校验 |

**仍需插件侧配合**：`G9` 的 `callback` 必须写方法名字符串（函数跨不了 JSON 边界）；
`G14` 修好后 `isLogged` 稳定为 `false`，依赖登录的功能仍需 `G4` 的账号 UI 才可用。

## 基线扫描结果（适配前，对本地已有适配产物）

工具：`node tools/check_plugins.js`（语法 / 类名 / 继承 / 必需方法 / venera 残留 / UI 类型 / getCategory 结构）

**39 个本地插件中 28 个通过、11 个失败** —— 失败项均为**之前脚本批量适配遗留的真实问题**：

| 插件 | 问题 | 性质 |
|---|---|---|
| copy_manga | 残留全局 `fetch(`；`res.status/res.body` 误用 | 真 bug |
| manga_dex | 残留全局 `fetch(` | 真 bug |
| wnacg | 残留全局 `fetch(`；`res.status/res.body` 误用 | 真 bug |
| nhentai | `Network.get` 结果被当 Response 用（`res.status`） | 真 bug（文件头注释自称"已改写"，与代码矛盾） |
| picacg | 同上 | 真 bug |
| ccc | 同上 | 真 bug |
| zaimanhua | 同上 | 真 bug |
| kavita / komga / lanraragi | 同上（且 `getCategory()` 返回空，自建服务器源可能本就无分类） | 待确认 |
| tinyavideo | `getCategory()` 返回值缺少 `parts` 数组 | 真 bug |

> 结论：脚本批量改写会留下「注释说改好了、代码没改」的隐蔽 bug，必须逐个核对。

### 复现的失效模式（后续适配重点排查）

1. **「注释声称已改写，代码没改」**：多个文件第 8 行左右写着
   `// - Network 调用已改写为 wyw 原生风格：Network.get/post 直接返回 body 字符串`
   但正文里仍写 `const res = await Network.get(...)` 然后 `if (res.status !== 200)`。
   wyw 的 `Network.get` 返回**字符串**，`res.status` 恒为 `undefined` → 判断恒真/恒假。
   已确认：nhentai、lanraragi（第 520-521 行，导致分类永远存空数组）、picacg、ccc、zaimanhua 等。
   **正确写法**：要么改用 `Network.sendRequest()`（它才返回 `{status, body}`），要么删掉状态判断、
   用 try/catch 捕获 wyw 抛出的结构化错误（`e.status` / `e.kind`）。

2. **`res.status/res.body` 与 `Network.get` 混用**：`tools/check_plugins.js` 会自动标记
   「文件内只用了 Network.get 却访问 res.status/res.body」的情况。

3. **`fetch(` 残留**：⚠️ 该条已修正 —— wyw **确实注入了全局 `fetch`**（`init.js:738`，转发
   `Network.fetch`）。但它的 `text()`/`json()` 是**方法**（`await res.json()`），与 venera 的
   `res.body` 语义不同，照抄仍会错。**适配规范：一律改用 `Network.get`（body 字符串）；
   需要状态码/响应头时用 `Network.sendRequest`**。`tools/check_plugins.js` 已不再把裸
   `fetch(` 判为残留，改为检测 `res.ok` / `await res.json()` 这类 venera Response 用法。
   已确认残留：copy_manga、manga_dex、wnacg（均已修复）。

5. **与主请求 `Promise.all` 并发的「附加信息」请求必须单独 try/catch**（copy_manga 适配发现）：
   wyw 的 `Network.get` 对非 2xx 会 **throw**，而 venera 下只是返回带 status 的 Response。
   因此 `getFavoriteStatus` / `isLogged` 这类与主请求并发的附加查询，在**未登录/受限**时会把
   整个 `Promise.all` 打挂 —— copy_manga 的详情页曾因此**在无账号时完全打不开**（picacg 的
   `isLogged` 门禁是同一根源，见 G14）。适配时务必把这类请求隔离到自己的 try/catch 里降级。

6. **`onClickTag`（G11）不必跳过 —— 有标准实现模式**（24 个上游插件都有它）：
   上游 `comic.onClickTag(ns, tag)` 返回两种形态：
   `{action:'search', keyword}`（跳搜索）或 `{page:'category', attributes:{category, param}}`（跳分类）。

   ⚠️ **关键约束**：`UI.Action` 的**返回值会被框架丢弃**
   （`lib/utils/plugin_action.dart:30` 只 `await plugin.invoke(...)`，不消费结果），
   所以**不能**让点击回调直接 `return` 卡片列表 —— 那样用户点了没有任何反应。

   正确模式（两个方法）：
   ```javascript
   // 1) 点击入口：只负责跳转（不返回内容）
   searchTag(namespace, tag) {
       const t = String(tag || '')
       if (!t) { Dialog.showToast('标签为空'); return }
       // plugin 参数必须写「文件名」
       Navigator.navigateToDescriptor('xxx', {
           method: 'loadTagResult',
           args: [String(namespace || ''), t],
           title: (namespace ? namespace + ': ' : '') + t,
       })
   }
   // 2) 结果页内容：返回 List<UI.Card>，由 descriptor 页渲染
   async loadTagResult(namespace, tag) {
       return await this['search'](tag, 1)   // 用 this['search'] 避免 checker 误判
   }
   ```
   详情页里把标签渲染成可点击按钮：
   `UI.Button({ label: text, style: 'text', onTap: UI.Action({ method: 'searchTag', args: [ns, text] }) })`

4. **异步 `getCategory()` 是合法的**：框架 `plugin.invoke` 会 await Promise，
   `async getCategory()` 可用（tinyavideo 即如此，校验脚本已支持）。

## 本轮修复记录

### 网络层误用（真 bug，运行必崩）

| 插件 | 问题 | 修法 |
|---|---|---|
| nhentai | `Network.get` 结果当 Response 用（`res.status`），文件头注释却自称"已改写" | 删状态判断，改用字符串 body |
| picacg / ccc / zaimanhua | 同上 | 同上 |
| wnacg | 同上 + 残留 `fetch(` 用法 | 同上 |
| manga_dex | 9 处 `Network.fetch` + `res.ok` / `await res.json()` 误用；`this.comic.languageLabel` 引用不存在的成员（取章节必抛 TypeError）；`loadEp` 硬编码 `uploads.mangadex.org`（图片 404）；全部请求无 headers | 改用 `Network.get` + `JSON.parse`；`this._comicApi.languageLabel`；用 at-home 返回的 `baseUrl`；补 `User-Agent`/`Accept` |
| kavita | `ensureOk()` 对字符串取 `.status`（无效）；`postJson` 用 `res.headers.pagination`（必然抛错，分页信息在响应头） | 删 `ensureOk`；改用 `Network.sendRequest` 读响应头 |
| komga | `ensureOk()` 同上 | 同上 |
| lanraragi | `init()` 里 `if (res.status !== 200)` → 分类永远存空数组 | 删状态判断 |

### 浏览页分类空白（自建服务器源）

`kavita` / `komga` / `lanraragi` 的 `getCategory()` 恒返回 null，根因是它们的
`_categoryData.parts` 全是 venera 的 **`type:'dynamic'` + `loader()`** 形态，
而适配层只认静态 `categories` 数组 → 全部被 filter 掉。

修法：新增 `_resolveCategoryParts()`，把 `loader()` 求值一次并缓存
「分类名 → venera param」映射（`_dynamicParamMap`），`getCategory()` 改为
`async`（框架会 await），`_fetchCategoryComics()` 用该映射还原 param。
三个插件的浏览页已从**完全空白**变为有分类（配置服务器后还会出现书库/合集/作者等动态分组）。

### 系统性观察（已在本轮全部处理）

`_explore`（venera 探索页）在 **22 个插件**里只定义未接线；`categoryComics.ranking` 与
`comic.onClickTag` 同样普遍缺失。wyw 没有「探索页 / 排行榜页 / 标签点击」这三种页面类型，
因此本轮把它们统一**回收**成 wyw 已有的入口：

| venera 能力 | wyw 落点 | 处理方式 |
|---|---|---|
| `explore = [{title, type, load}]` | 浏览页分类 | 回收成「首页 / 探索」分组（每个板块一个分类）。板块名静态的直接列出；**动态解析的**（manhuagui / mh1234 / goda / manhuaren / happy）用 `async getCategory()` 先跑一次 explore 拿板块名并缓存 |
| `categoryComics.ranking` | 浏览页分类 | 回收成「排行榜」分组（每个维度一个分类），`_fetchCategoryComics` 路由到 `ranking.load(option, page)` |
| `comic.onClickTag(ns, tag)` | 可点击标签 + 结果页 | 详情页标签改为 `UI.Button`；`searchTag(ns, tag)` 用 `navigator.navigateToDescriptor` 打开结果页，`loadTagResult` 返回卡片 |

**共补 `searchTag` 的插件（16 个）**：hitomi / ykmh / manhuagui / mxs / hcomic / jcomic /
happy / mycomic / ccc / nhentai / picacg / wnacg / manga_dex / comick /
copy_manga_multi_accounts / hot_manga。

> ⚠️ 实现 `onClickTag` 时最容易踩的坑：**`UI.Action` 的返回值会被框架丢弃**
> （`lib/utils/plugin_action.dart:30` 只 `await plugin.invoke(...)`）。
> copy_manga 与 wnacg 的初版都是「点击回调直接 `return` 卡片列表」→ 用户点了**毫无反应**。
> 已全部改为「跳转 + 结果页渲染」的两方法模式。

**行为验证**：用 Node + mock 全局对上述 16 个插件逐一断言
「调用 `searchTag` 后 `Navigator.navigateToDescriptor` 被调用、且目标方法为
`loadCategory`/`loadTagResult`」—— **32/32 通过**（临时脚本跑完已删）。

### 其他修复（本轮逐个核对时发现）

- **重复定义导致死代码**：`comic_walker` / `shonen_jump_plus` 各有一份引用未定义成员
  （`_categoryData`/`_categoryApi`）的 `getCategory`/`loadCategory`，被文件后段的定义覆盖 →
  已删除，避免误导与校验告警。
- **`ikmmh` 设置项从未生效**：上游 `settings.base_url` + `init()` 写回静态 `baseUrl`；
  本地构造函数虽调了 `this.init()`，但**本地没有实现 `init()`**（落到基类空实现）→
  用户填的站点地址永远不生效。已补 `settings` + `init()`。
- **`copy_manga_multi_accounts` 缺 `getImageLoadingConfig`**：单账号版有、多账号版漏了 → 已补。
- **`kavita` 的 `postJson`**：Kavita 的分页信息在响应头 `pagination`，而 `Network.post`
  只返回 body → 对字符串取 `.headers` 必然抛错。已改用 `Network.sendRequest`。
- **`nhentai` / `ikmmh` 的收藏态残留**：`this.isLogged` / `this.favorites` 在 wyw 不存在
  （取值为 `undefined`，或抛 TypeError 后被 try/catch 吞掉）→ 已清理为明确的「未收藏」。

## 适配进度

状态：`待适配` / `进行中` / `已适配` / `阻塞`

| # | 插件 | 文件 | 上游版本 | 本地版本 | 状态 | 问题记录 |
|---|---|---|---|---|---|---|
| 1 | 拷贝漫画 | copy_manga.js | 1.4.2 | 1.4.1 | 已适配 | 修复 `fetch`/`res.status` 误用、`init()` 无人调用等；explore→「首页推薦」；`searchTag` 修正为跳结果页 |
| 2 | 拷贝漫画(多账号) | copy_manga_multi_accounts.js | 1.4.1 | — | 已适配 | 新增文件；账号降级为 `account_tokens` 设置项；补 `getImageLoadingConfig`/`searchTag` |
| 3 | Komiic | komiic.js | 1.0.3 | 1.0.3 | 已适配 | explore（最近更新）接线为「探索」分组 |
| 4 | 包子漫画 | baozi.js | 1.1.6 | 1.1.8 | 已适配 | 核对通过（`page_direct` + 多页章节 + 动态 reader 域，优于上游） |
| 5 | Picacg | picacg.js | 1.0.6 | 1.0.6 | 已适配 | 8 处真 bug（登录恒失败、`isLogged` 门禁全废、分类 param 被当参数名…）；补 `searchTag` |
| 6 | nhentai | nhentai.js | 1.1.0 | 1.1.0 | 已适配 | `res.status` 误用、`this.isLogged` 残留已清理；补 `searchTag` |
| 7 | 紳士漫畫 | wnacg.js | 1.0.5 | 1.0.5 | 已适配 | 7 处 bug；`searchByTag` 修正为跳结果页（原返回值被框架丢弃） |
| 8 | ehentai | ehentai.js | 1.1.8 | 1.0.0 | 已适配 | 核对通过（页码占位 + 惰性取图 + 缩略图墙，均为文档推荐模式） |
| 9 | 禁漫天堂 | jm.js | 1.4.0 | 1.1.0 | 已适配 | 移植相关推荐/作品/角色/浏览量；保留「按ID直达」 |
| 10 | MangaDex | manga_dex.js | 1.2.0 | 1.1.1 | 已适配 | 9 处网络误用、`this.comic` 引用错误、硬编码图片域；补 `searchTag`（tag:/author:/artist: 前缀） |
| 11 | 爱看漫 | ikmmh.js | 1.0.6 | 1.0.5 | 已适配 | 清理 `this.favorites` 无效引用；补 `settings.base_url` + `init()`（原设置永远不生效） |
| 12 | 少年ジャンプ＋ | shonen_jump_plus.js | 1.1.1 | 1.1.1 | 已适配 | 删除被覆盖的死代码（引用未定义的 `_categoryData`） |
| 13 | hitomi.la | hitomi.js | 1.1.2 | 1.1.2 | 已适配 | explore→「探索」、ranking→「排行榜」（4 维度）；补 `searchTag`（命名空间→`artist:` 等前缀） |
| 14 | comick | comick.js | 1.2.0 | 1.2.0 | 已适配 | explore 4 板块→「首页」；补 `searchTag` |
| 15 | 优酷漫画 | ykmh.js | 1.0.0 | 1.0.0 | 已适配 | explore 2 板块→「首页」；补 `searchTag`（标签命中分类走分类页） |
| 16 | 再漫画 | zaimanhua.js | 1.0.2 | 1.0.2 | 已适配 | 整文件重写；105 项断言通过 |
| 17 | 漫画柜 | manhuagui.js | 1.2.1 | 1.2.1 | 已适配 | explore（动态板块）→「首页」；ranking 4 维度→「排行榜」；补 `searchTag` |
| 18 | 漫蛙吧 | manwaba.js | 1.0.2 | 1.0.3 | 已适配 | explore 4 板块→「首页」 |
| 19 | Lanraragi | lanraragi.js | 1.1.0 | 1.2.0 | 已适配 | `init` 里 `res.status` 导致分类恒空；补 `type:'dynamic'` 分类展开 |
| 20 | Komga | komga.js | 1.0.0 | 1.0.0 | 已适配 | 同上（含 `postJson` 读响应头改 `sendRequest`） |
| 21 | カドコミ | comic_walker.js | 1.0.1 | 1.0.0 | ⚠️ 已失效·已移出内置 | 适配本身已完成（删死代码、explore 已映射），但**站点端已关死**：搜索返回 `upgrade_required`、注册接口不可用 → 已移到 `assets/plugin-unavailable/`，不再作为内置插件，见下文「comic_walker 失效记录」 |
| 22 | 漫画1234 | mh1234.js | 1.0.0 | 1.0.0 | 已适配 | explore（动态板块）→「首页」 |
| 23 | CCC追漫台 | ccc.js | 1.0.1 | 1.0.1 | 已适配 | 5 处真 bug（付费判定恒假、`getImageLoadingConfig` 透传 Promise…）；补 `searchTag` |
| 24 | GoDa漫画 | goda.js | 1.2.1 | 1.2.1 | 已适配 | explore（动态板块）→「首页」 |
| 25 | 18漫画 | mh18.js | 1.0.0 | 1.0.0 | 已适配 | 核对通过（含相关推荐 + 空结果抛错） |
| 26 | 漫小肆 | mxs.js | 1.0.0 | 1.0.0 | 已适配 | explore 3 板块→「首页」；补 `searchTag`（作者→搜索、题材→分类） |
| 27 | 漫画人 | manhuaren.js | 1.0.0 | 1.0.0 | 已适配 | explore（动态板块）→「首页」 |
| 28 | H-Comic | hcomic.js | 1.0.0 | 1.0.0 | 已适配 | explore→「首页」；补 `searchTag` |
| 29 | jcomic.net | jcomic.js | 1.0.0 | 1.0.0 | 已适配 | explore（最近更新，可分页）→「首页」；补 `searchTag` |
| 30 | 热辣漫画 | hot_manga.js | 1.0.0 | 1.0.0 | 已适配 | explore 5 板块→「首页」；标签/作者改为可点击；补 `searchTag` |
| 31 | Kavita | kavita.js | 1.0.0 | 1.0.0 | 已适配 | `ensureOk` 误用 + 浏览页空白（dynamic 分类未展开） |
| 32 | 嗨皮漫画 | happy.js | 1.0.0 | 1.0.0 | 已适配 | explore（动态板块）→「首页」；ranking 8 维度→「排行榜」；补 `searchTag` |
| 33 | MYCOMIC | mycomic.js | 1.1.0 | 1.1.0 | 已适配 | explore 3 列表→「首页」；ranking 3 维度→「排行榜」；补 `searchTag` |

**当前进度：33/33 已适配**（其中 `comic_walker` 因**站点端变更**已失效，已移到
`assets/plugin-unavailable/` 不再作为内置插件，见下文；
`tools/check_plugins.js` 全量 **39/39 通过**；`flutter analyze` 无 issue；`flutter test` 50 项全绿）。

每个插件都经过：① 逐行核对上游接口与本地实现；② 修复 API 误用与逻辑 bug；
③ 把 `explore` / `ranking` 回收成浏览页分类入口（否则这些入口会静默丢失）；
④ 补 `onClickTag` 的等价实现（可点击标签 → 结果页）。

> 本地另有 7 个**不在上游 index.json** 里的自建视频源插件
> （bmmdmm / dushehub / fc_008nnn / hanime / pornhub / tinyavideo / ttdm8），
> 不涉及 venera 适配，仅纳入机械校验（均通过）。

## comic_walker 失效记录（2026-09 探测，已移出内置）

`assets/plugin-unavailable/comic_walker.js` 的**适配本身是完成的**，但该源在
**站点侧已经关死**，现标记为**不可用**并移出 `assets/plugin/`：只有该目录在
`pubspec.yaml` 里声明为资源，且 `PluginController` 的内置集合完全由
`AssetManifest` 中 `assets/plugin/` 前缀的条目决定，移出后既不打包也不再算内置。
插件头部 `// description:` 仍带 ⚠️ 标记，
原插件测试脚本 `test_plugin_comic_walker.js` 曾直接输出 SKIP 并附原因；该脚本已随测试骨架一并删除。

### 现象

搜索接口返回 HTTP 400：

```json
{ "message": "アプリのバージョンが古いため、アップデートをしてください", "code": "upgrade_required" }
```

### 排查结论（用带自定义 header 的直连探测逐项排除）

| 假设 | 结论 |
|---|---|
| 客户端版本号过旧 | **排除**。`init()` 已修好并正确把 `latestVersion` 更新到 App Store 最新版 `1.6.6`；直接用 UA `BookWalkerApp/9.9.9 (Android 13)` 探测同样**不会**触发 `upgrade_required` |
| UA 格式不对 | **部分成立，但不是本因**。站点确实解析 UA：改成 iOS 风格 `(iPhone; iOS 18.0)` 会返回「UserAgentの形式が不正です」；保持 `BookWalkerApp/x.y.z (Android NN)` 格式即可过这一层 |
| Environment-Key 失效 | **排除**。带旧 key 时站点不报 key 错误，只在缺 `Authorization` 时报「Authorizationヘッダが必要です」 |
| **缓存的旧 token 触发** | **命中**。不带 `Authorization` → 报「需要 Authorization 头」；带上插件里 `loadData('token')` 的旧 token → 变成 `upgrade_required`。即站点按 token 关联的客户端版本判定需要升级 |
| 重新注册拿新 token 可自救 | **不可行**。`POST /v1/users`（插件 `refreshToken()` 的匿名注册接口）实测**超时 / socket hang up**，站点侧已不可用 |

### 上游状态

`tools/venera-configs/comic_walker.js` 与线上 `venera-configs@main` 的同名文件
**SHA256 完全一致**（上游也未适配，仍是 `latestVersion = "1.4.13"` 的老实现）
→ 属**站点端变更导致的整源失效**，不是 wyw 适配引入的问题。

### 恢复路径

需从最新版カドコミ App 抓取可用的注册/鉴权接口与 `X-API-Environment-Key`，
再按新协议重写 `_searchApi` / `_comicApi`。在此之前建议在插件管理页保持「禁用」。

### 顺带修掉的通用问题（由本源暴露，与失效本身无关）

1. **`init()` 里读 `resp.status`**：wyw 的 `Network.get` 返回 body **字符串**，读 `.status`
   恒为 `undefined` → 版本号更新代码从未执行。已修（同类残留其它插件也要留意）。
2. **`request()` 里 `response.status === 204`**：同样的移植残留，恒为 false；
   已改用 `sendRequest` 拿真实状态码，让 204 分支真正生效。

## ccc 适配记录（2026-02 逐行核对）

上游 `tools/venera-configs/ccc.js` v1.0.1 → `assets/plugin/ccc.js`（**人工逐行**，非脚本转换）。

### 修复的真 bug

| # | 位置 | 问题 | 修法 |
|---|---|---|---|
| 1 | `_comicApi.loadEp` | `Network.get(...)` 的返回值是 **body 字符串**，却对其取 `res.status == 403` 判付费章节 → 恒为 `undefined == 403` → **永远不成立**，付费章节会继续 `JSON.parse` 一个 HTML/错误体而抛错 | 改用 `Network.sendRequest('GET', ...)` 拿 `{status, body}`；同时 catch `e.status == 403`（wyw 对非 2xx 会抛结构化异常），两种形态都兜住；非 2xx 抛带状态码的可读异常 |
| 2 | 适配层 `search()` | 调用 `_searchApi.load(keyword, [], page)` 传**空数组**，而上游 `load()` 无条件 `options[0] = "&sort_by=" + options[0]` → URL 拼出 `&sort_by=undefined`（且 `&type=undefined` 等），搜索请求非法 | 新增 `_defaultSearchOptions()` 固定上游 optionList 首项默认值（`updated_at` + 6 个 `""`），传满 7 项 |
| 3 | `_searchApi.load` | 上游**原地改写** `options[i]` 为 `"&k=v"`；同一数组复用时二次前缀成 `&sort_by=&sort_by=updated_at`（options 污染） | 改为局部 `p` 数组非破坏性拼接，并对缺项兜底 `opts[0] \|\| "updated_at"`；`keyword` 补 `encodeURIComponent` |
| 4 | 适配层 `getImageLoadingConfig` | 未 `await` 上游的 `async onImageLoad` → 把 **Promise 对象**交给 Dart（`init_page.dart` 里 `if (raw is Map)` 判定失败）→ 配置静默丢弃 → **图片解密链完全失效、图片显示为密文/失败** | 改为 `async getImageLoadingConfig` + `await this._comicApi.onImageLoad(...)`（Dart 侧 `fetchImageLoadingConfig` 本就 `await plugin.invoke`） |
| 5 | `_explore[0].load` | 上游 `result[curTitle] = result[curTitle].concat(comics)`：若首个模板无 `title`，`curTitle` 仍为 `null` → `result[null].concat` 抛 TypeError，**整页空白** | 加 `curTitle != null` 守卫 + `(result[curTitle] \|\| [])` 兜底 |

> 第 1 条即 `check_plugins.js` 报的 `res.status/res.body 疑似误用`。修复后脚本对该行降级为
> 提示「需确认来源是 Network.sendRequest（合法）」——现确实来自 `Network.sendRequest`。

### 补齐/接线的功能

| 上游功能 | 落地方式 |
|---|---|
| 探索页 `explore`（首頁模板 `/public/home_v2`） | 原先只定义未接线（死代码）。现借「分类按钮」承载为浏览页 **「首頁 › 首頁推薦」** 入口：`getCategory()` 注入该分组，`_fetchExploreComics()` 调用 `explore[0].load()` 并把 `singlePageWithMultiPart` 的多组合并为单列表（`id` 统一 `String()`，首頁的 `c["value"]` 可能是数字） |
| 付费章节提示（上游 596 行 `UI.showDialog("提示","該章節需付費后閲讀",[...])`） | `ccc._showPaidChapterDialog(comicId)`：`Dialog.showDialog(title, content, actions)` 带「取消 / 去購買」两个回调；「去購買」用 `Dialog.openExternalBrowser` 打开 `creative-comic.tw/zh/book/{id}/content`（对应上游 `UI.launchUrl`），老版本无该 API 时降级 toast |
| 详情页点赞数 `likesCount` | 头卡补「推薦: N」（上游 `ComicDetails.likesCount` = `like_count_only_uuid`） |
| 付费章节 `[付費]` 标题标记 | 已有，核对 `freeRead()` 已正确改写为 `this._comicApi.freeRead(c)`（上游是 `this.comic.freeRead`）——**该处转换正确，无需改** |

### 跳过的功能（含 Dart 缺口对应）

| 上游功能 | 跳过原因 | 缺口 |
|---|---|---|
| `account`（账密登录 + 验证码） | wyw 无账号/登录 UI；且登录必需验证码输入框 | **G4 + G1** |
| `account.loginWithWebview` / `checkStatus` / `onLoginSuccess` | wyw 无 WebView 登录态回传与 `_localStorage` 注入 | **G4** |
| `favorites`（`addOrDelFavorite` / `loadComics`） | wyw 无收藏夹体系 | **G5** |
| `loadComments` / `sendComment` / `likeComment` | wyw 无评论 UI | **G7** |
| `onClickTag`（标签点击转搜索） | wyw 无标签点击回调机制 | **G11** |
| `search.optionList`（7 组筛选） | wyw 搜索页无筛选项 UI → 固定为默认值 | **G13** |
| `minAppVersion` / `url`（自更新） | wyw 无对应字段 | 规范 |

`_account` 对象**保留**（含完整验证码流程），以便 Dart 侧补齐 G1/G4 后直接可用；
但公开入口 `login()` 当前只 toast + 抛可读异常，不会让上层崩。

### 相关 Dart 侧需求（重点）

1. **G1 —— `Dialog.showInputDialog` 必须实现**（ccc 登录的**硬阻塞**）。
   - 现状：`assets/js/init.js`（`Dialog.showInputDialog`，返回 `Promise<string|null>`）与
     `docs/plugin-development.md` §2.6 均已声明；但 `lib/js/js_extends/js_dialog.dart`
     的 `handleDialogCallback` `switch` 只有 `case 'showToast'` → 该调用必然返回 `null`。
   - 影响：ccc 的账号登录链路完全不可用（验证码无法输入）。
   - 建议实现：`case 'showInputDialog'` → 弹 `AlertDialog` + `TextField`，
     支持 `image`（`string` URL 或 `ArrayBuffer` 图片，ccc 传的是 `Convert.decodeBase64` 的字节）；
     确认返回文本、取消返回 `null`；`validator` 返回非空字符串时在框内显示错误。
   - ccc 侧的降级已就绪：`showInputDialog` 返回 `null` 时抛
     `「当前版本不支持验证码输入（Dart 缺口 G1…）」` 并 toast，**不崩**。
2. **G4 —— 账号体系**：即使 G1 补齐，仍需要插件设置页的登录入口（`account.login/logout` 的调用方）
   才能实际使用 ccc 登录。
3. 无其他新增 Dart 需求（ccc 未用到 G2/G3/G9）。

### 验证

- `node tools/check_plugins.js ccc` → `ok ccc [manga] methods=29`，**0 问题**（1 条提示：`res.status` 来自合法的 `Network.sendRequest`）
- `node --check assets/plugin/ccc.js` → 通过
- 行为自检（`vm` + mock 全局，临时脚本置于 `build/`，跑完已删）→ **19/19 通过**：
  覆盖类名/继承、`getCategory`/`getCategoryOptions` 结构（`"-全部"`→`value=""`、`"2-劇情"`→`value="2"`）、
  `search` URL 无 `undefined` 且二次调用无二次前缀、`parseComics` 字段与 `maxPage`、
  `loadEp` 403 付费弹窗 + actions 回调 + 外链、`loadEp` 200 解析、`loadChapterImages` 空结果抛错、
  账号 G1 降级（含 `/recaptcha` 仍被请求）、`getImageLoadingConfig` 返回已解析对象（非 Promise）、
  `getDetail` 描述符类型白名单 + 浏览历史 + `[付費]` 标记、`openReader` 的 `initialChapter`/惰性章节格式、
  `logout` 清理、`onOpenBrowseEntry` 边界。

## picacg 适配记录（逐行核对）

上游 `tools/venera-configs/picacg.js` v1.0.6 → `assets/plugin/picacg.js`（**人工逐行**，非脚本转换）。
上游结构：`account` / `explore`(5 项) / `category`+`categoryComics` / `search` / `favorites` /
`comic`(loadInfo/loadEp/onImageLoad/onThumbnailLoad/comments) / `settings` / `translation`。

### 修复的真 bug

| # | 位置（修复前） | 问题 | 修法 |
|---|---|---|---|
| 1 | `_ensureToken()` L957/L964 | `res` 来自 **`Network.post`（返回 body 字符串）**，却写 `if (res.status === 200)` → 恒为 `undefined === 200` → **自动登录 100% 失败**，并抛 `'哔咔登录失败: HTTP undefined'`。即 `check_plugins.js` 报的 `res.status` 误用 | 登录改为直接读 body：`const body = await Network.post(...)` → `JSON.parse(body)` → 取 `json.data.token`；非 2xx 由 wyw 抛结构化 Error（`e.status`）兜住 |
| 2 | `_explore[*].load` L452/487/522/557/592，共 5 处 | `if (!this.isLogged) throw 'Not logged in'`。wyw **未实现** `isLogged`（**缺口 G14**），恒返回 `null` → `!null === true` → **5 个探索入口全部直接抛错**，功能完全不可用 | 去掉 `isLogged` 门禁，改为「有 token 就带、没有就自动登录」（`_ensureToken()`）；`isLogged` 语义在 wyw 不成立，插件侧不该用它做门禁 |
| 3 | `_fetchCategoryComics()` L130-154 | 分类参数解析错误：上游 `load(category, param, ...)` 里 `param ?? 'c'` 才是**参数名**，而适配层在 `parts` 里找不到映射时写 `param = category`，再 `type = param ?? 'c'` → 实际 URL 变成 `comics?page=1&全彩=全彩&s=dd`（**把分类名当成了 query 参数名**），接口必然返回空/报错 | 新增 `_resolveParam(category)`：探索类目 → `'explore'`，其余主题分类统一 → `'c'`。URL 现为 `comics?page=2&c=%E5%85%A8%E5%BD%A9&s=ld` |
| 4 | `_comicApi.loadInfo` catch 分支 L875 | `if (e === 'Invalid status code: 401')` 是**死代码**：wyw 抛的是 `Error` 对象（`e.status`），永远不等于该字符串 → 401 后不会重登 | 统一由 `_request()` 在 `catch` 里判 `e.status === 401` → `deleteData('token')` + 重新登录 + **重试一次**（等价上游 `res.status === 401` 分支） |
| 5 | `_comicApi.loadEp` L914-927 / `epsLoader` L837-849 | 分页 `while(true)` 用上游的 `pages === i` 作终止条件；当响应缺 `pages`（或为 0）时**永不相等 → 死循环**，且每轮都发请求 | 改为 `if (!pages \|\| pages <= i) break`（正常单调序列下与上游等价，异常时安全退出） |
| 6 | `_comicApi.loadEp` L911 | 适配层传 `realEp = epId === '__all__' ? null : epId`，但 `getDetail` 从不产生 `'__all__'` 章节（picacg 必有 eps）→ 该分支是**无效的"画廊"兜底**，若真传入则拼出 `/order/null/pages` | 删除；章节恒为真实 epId |
| 7 | `search(keyword, page)` L74 | 调 `_searchApi.load(keyword, [], page)` 传空 options → body 里 `sort: undefined`，精排参数非法（同 ccc 第 2 条的同类问题） | 固定上游 `optionList[0]` 首项默认值 `'dd'`（`static searchSort`）；wyw 搜索页无筛选项（G13），排序在插件内固定 |
| 8 | `getImageLoadingConfig` L364 | 直接把上游 `onImageLoad` 的返回值透传；上游该函数在本文件里是 `async` → 返回 **Promise**。虽然 picacg 的 `onImageLoad` 无 `await`、`async` 只让结果包了一层 Promise，Dart 侧 `if (raw is Map)` 判 Promise 会失败 → **配置静默丢弃**（与 ccc 第 4 条同一失效模式） | 改为**同步**方法直接 `return {url, headers: {'user-agent': 'okhttp/3.8.1'}}`（Dart 侧 `fetchImageLoadingConfig` 会 `await plugin.invoke`，同步返回值同样安全） |

> 另清理：适配层构造函数里 `Promise.resolve(this.init())` —— wyw 的 `PluginSource.init()` 是空实现，
> 该调用纯属噪音（上游并无 `init`），且会在构造期触发异步。已删除。
> 死代码 `_explore`（5 项，从未接线）已回收进 `getCategory()`，不再留有未使用字段。

### 补齐/接线的功能

| 上游功能 | 落地方式 |
|---|---|
| 探索页 `explore` 5 项（Random / Latest / H24 / D7 / D30） | 上游在 wyw 无探索页 → 回收成浏览页「**探索**」分组（`getCategory()` 的 5 个分类按钮）：哔咔随机 `/comics/random`、哔咔最新 `/comics?page={p}&s=dd`、日/周/月榜 `/comics/leaderboard?tt=H24\|D7\|D30&ct=VC`。**这是 G6 排行榜的降级落地**（与 manga_dex/ccc 的做法一致） |
| 主题分类 40 项（`category.parts[0].categories`） | 原样保留进 `getCategory()` 的「**主题**」分组，走 `comics?c=<分类>&s=<排序>` |
| `categoryComics.optionList` 排序（dd/da/ld/vd） | `getCategoryOptions()` 返回 `[{label:'排序', options:[{value,text}×4]}]`，把上游 `"value-text"` 拆成 `{value,text}`；用户选择经 `loadCategory/loadCategoryPage` 的 `options[0]` 进入 `&s=` |
| `search.load`（进阶搜索）+ 排序 | `search(keyword, page)` → `POST /comics/advanced-search?page={p}`，body `{keyword, sort}` |
| `comic.loadInfo` 的 info / eps / **recommend** | `getDetail()` 并发拉 info + 全量 eps，推荐单独拉且**失败不阻塞主流程**（上游 `Promise.all` 一处失败全挂，这里放宽为推荐可缺） |
| 详情标签分组（`ComicDetails.tags`：Author / Chinese Team / Categories / Tags） | 渲染成「作者 / 汉化组 / 分类 / 标签」四组 `UI.Tag` 流式布局 |
| 详情元信息 | 头卡显示 作者 / 汉化 / 上传者 / 更新时间（`updated_at` → `Y-M-D`）/ 点赞·评论·页数 |
| `ComicDetails.recommend` 相关推荐 | 渲染为可点击按钮 → `UI.Navigate({method:'getDetail'})` |
| `comic.loadEp` 章节图片 | `loadChapterImages(comicId, epId)` 逐页拉全，拼 `fileServer + '/static/' + path` |
| `comic.onImageLoad` 图片请求头 | `getImageLoadingConfig()` 返回 `{url, headers:{'user-agent':'okhttp/3.8.1'}}`（防盗链） |
| `buildHeaders` 的签名链 | 保留上游算法：`Convert.encodeUtf8` + `Convert.hmacString(key, value, 'sha256')`。**已在 `init.js` 确认两个方法都真实存在**（L32 / L181），无需 Dart 改动 |
| 设置项 `base_url` / `imageQuality` / `appChannel` | 保留，并补 `get` 兜底（`loadSetting` 未设置返回空串）；`title` 按 G12 直接写中文 |

### 跳过的功能（含 Dart 缺口对应）

| 上游功能 | 跳过原因 | 缺口 |
|---|---|---|
| `account`（`login` / `logout` / `reLogin` / `registerWebsite`） | wyw 无账号/登录 UI。**部分降级为可用**：保留 `settings.email` / `settings.password`，由插件用 `Network.post /auth/sign-in` 换 token 并缓存（`_ensureToken`），401 自动重登 → **不需要 Dart 改账号体系即可用**（代价：密码存在插件设置里） | **G4** |
| `favorites`（`addOrDelFavorite` / `loadComics`） | wyw 无收藏夹体系 | **G5** |
| `categoryComics.ranking` + `category.enableRankingPage:true` | wyw 无排行榜页；榜单能力已改由「探索」分组的日/周/月榜承载 | **G6** |
| `comic.loadComments` / `sendComment` / `likeComment` | wyw 无评论 UI | **G7** |
| `comic.likeComic`（点赞） | 无点赞 UI/状态回流 | G4 相关 |
| `comic.onThumbnailLoad` | wyw 无对应；缩略图统一走 `getImageLoadingConfig`（本插件该处返回的 headers 对缩略图同样适用） | **G10** |
| `comic.onClickTag(namespace, tag)`（作者/分类/标签点击 → 转分类或搜索） | wyw 无标签点击回调机制。标签以 `UI.Tag` 只读展示 | **G11** |
| `search.optionList`（排序筛选） | wyw 搜索页无筛选项 UI → 固定 `'dd'` | **G13** |
| `translation` 表的实际生效 | `translate()` 当前恒返回原 key（**新发现缺口 G15**） | **G15** |
| `minAppVersion` / `url`（自更新） | wyw 无对应字段 | 规范 |

### 相关 Dart 侧需求（重点）

1. **G14 —— `PluginSource.isLogged` 必须实现，或在规范里明确禁用**（本次新发现）。
   - 现状：`assets/js/init.js:1458` 定义了 `get isLogged()`（发 `sendMessage({method:'isLogged'})`），
     但 `lib/js/js_extends/js_bridge.dart` 的 `handleCommonMessage` 里**没有 `case 'isLogged'`**，
     落到末尾 `return null`。
   - 危害：**这是"静默恒真"型陷阱**——`if (!this.isLogged)` 在 JS 里 `!null === true`，
     所以任何照抄上游 `if (!this.isLogged) throw ...` 的插件，其功能会**整体不可用但语法/静态检查全过**
     （picacg 的 5 个探索入口原本 100% 抛 "Not logged in"，`check_plugins.js` 也扫不出来）。
   - 建议：① 若要支持登录态，补 `case 'isLogged'`；② 若 wyw 不做账号，则**在 `docs/plugin-development.md`
     的陷阱表里明确写「不要用 `isLogged`」**，并在 `check_plugins.js` 里加一条规则把 `this.isLogged`
     标为"潜在恒真门禁"（建议 ②，成本最低且能防住同类问题复发）。
2. **G15 —— `APP.locale` / `sendMessage({method:'getLocale'})` 未实现**（本次新发现）。
   - 现状：`init.js:1725` 定义 `APP.locale` → `sendMessage({method:'getLocale'})`，
     但 `js_bridge.dart` 没有 `case 'getLocale'` → 返回 `null`。
   - 危害：`PluginSource.translate(key)` 内部是 `this.translation[APP.locale]?.[key] ?? key`，
     locale 为 `null` → 查表必失败 → **所有插件的 `translation` 表上线后一律不生效**（静默降级为英文原文）。
   - 建议：补 `case 'getLocale': return ...`（`zh_CN` / `zh_TW` 形式，与 `translation` 表的键一致）。
   - **picacg 侧的降级已就绪**：`getCategoryOptions()` 不再只依赖 `translate()`，
     改用 `_t(中文, key)` —— `translate()` 可用就用它，不可用则回退写死的中文，
     保证在 G15 修复前后 UI 文案**始终是中文**（自检里有专门一条断言覆盖 locale=null 的场景）。
3. **G4 部分可绕开**：picacg 不需要 `account` API 也能登录（插件内 `settings.email/password` + `/auth/sign-in`）。
   若后续要给用户更好的体验，可考虑「插件设置项支持 `type:'password'`（掩码输入）」——
   当前 `plugin_settings_page.dart` 只区分 `select`/`switch`/`input`，密码框会**明文显示**。这是一个**新登记的小缺口（G16）**。

### 验证

- `node --check assets/plugin/picacg.js` → 通过（无输出）
- `node tools/check_plugins.js picacg` → `ok picacg [manga] methods=34`，**0 问题**（提示：`getCategory(): 2 个分组`）
- 行为自检（`build/picacg_selfcheck.js`，`vm` 加载**真实的 `assets/js/init.js`** 后再注入插件；
  mock 掉 `Network`/`Dialog`/`Navigator`/`sendMessage`（含 `load_data`/`save_data`/`load_setting`/`convert`），
  跑完已删）→ **32/32 通过**。覆盖：
  - 实例化不触发网络与 `init()`；`name`/`key`/`version`
  - `getCategory()` 结构合法（`parts[].{name,categories}`），45 个分类 = 探索 5 + 主题 40
  - `getCategoryOptions()` 结构合法（`{label, options:[{value,text}]}`）、`translate()` 生效时=中文、
    **`locale=null`（G15 现状）时仍为中文**
  - `search()` 返回 `UI.Card` 列表；URL/方法/`signature` 头/`authorization` 头/`sort=dd` 均正确
  - 分类：URL 为 `c=<分类>`（**回归断言 #3**）、`page`/`s` 透传、`loadCategory` 的 `maxPage` 取自响应、
    `pageMethod`/`pageArgs` 正确
  - 探索 5 个分类各自的 URL（random / latest / H24 / D7 / D30）
  - `getDetail()` 描述符类型与顺序（card,card,card,**expansionTile**,card）、章节按 order 排序且 id 为 `1..n`、
    缓存 `_comicId`/`_chapters`、相关推荐可跳转
  - `loadChapterImages()` URL 拼接与分页 URL
  - `getImageLoadingConfig()` 返回**同步对象**且含 `user-agent`（**回归断言 #8**）
  - 鉴权：无 token → 自动登录 → token 缓存 → 业务请求带 token；**401 → 清 token → 重登 → 重试成功**
    （**回归断言 #1/#4**）；未配置账号 → 可读异常且不抛穿
  - `openReader()` 章节惰性加载形态（`{id,title,plugin,method,args}`）与 `initialChapter` 定位
  - `onOpenBrowseEntry()` 正常/无效 entry
  - 源码（剔除注释）无 `res.status`/`res.body`/`fetch(`/`new Comic(`/`new ComicDetails(`/`UI.showMessage(`/`this.isLogged` 残留
  - 插件用到的 `Convert.*` 方法在 `init.js` 中确实存在；用到的 16 个 `UI.*` 原语在 `init.js`
    的 `__ui_wrap_` 字面量与 Dart `UiType` 枚举里**都存在**

> 自检脚本踩到的两个 `vm` 陷阱（供后续插件复用该手法时参考）：
> ① `vm.createContext(sandbox)` **之后**再改 `sandbox.X` 不会影响 context 内的全局绑定；
> ② `let Network = {...}` / `let Dialog = {...}` / `class PluginSource` 在全局词法作用域建立绑定，
> `globalThis.X = ...` 覆盖不掉 —— 必须在 context **内部**用 `vm.runInContext` 就地替换方法
> （`Network.get = ...`），否则 mock 不生效、测试会得出假结论。


