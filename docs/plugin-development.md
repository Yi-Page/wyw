# Wyw 插件开发文档

> 本文档由现有代码库整理而成，是 wyw 插件开发（视频源 / 漫画源 / 小说源）的权威参考。
> 依据：`assets/js/init.js`（JS API 库）、`assets/plugin/*.js`（5 个示例插件）、`lib/js/**`（JS 桥 Dart 实现）、`lib/plugins/plugin.dart` 与 `lib/pages/plugin/plugin_controller.dart`（插件运行时）。

---

## 一、系统架构

wyw 是一个基于 Flutter 的聚合阅读/播放 App，通过 **JS 插件机制**扩展任意站点。JS 运行在 `flutter_qjs`（QuickJS）中，与 Dart 之间只有一条 **`sendMessage` 消息通道**。

```
┌─────────────────────────── Flutter App ───────────────────────────┐
│                                                                   │
│  插件文件 {appSupportDir}/plugins/*.js                             │
│        │ 扫描（PluginController）                                   │
│        ▼                                                          │
│  Plugin ── JsEntity.register ──▶ globalThis.__plugins__.<name>     │
│        │  invoke(method, args)（Promise 自动等待 + JSON 还原）      │
│        ▼                                                          │
│  BaseJsEngine（flutter_qjs 实例）                                   │
│     ├─ 注入 sendMessage 桥  →  JSEngineCommonApi.handleCommonMessage │
│     └─ 加载 assets/js/init.js（公共 API 库）                        │
│                                                                   │
│  UI 描述符（List<Map>，含 __type） → UiDescriptorRenderer → Widget   │
└───────────────────────────────────────────────────────────────────┘
```

### 1.1 关键文件

| 文件 | 作用 |
|---|---|
| `assets/js/init.js` | **JS API 库**，注入全局。提供 `Convert / Network / HtmlDocument / PluginSource / Dialog / APP / Navigator / UI / PluginBrowse` 等 |
| `lib/js/base_js_engine.dart` | `BaseJsEngine`：初始化引擎、注入 `sendMessage` 桥、加载 init.js |
| `lib/js/production_script_engine.dart` | `ProductionScriptEngine`：正式运行环境，初始化 `globalThis.__plugins__` 注册表 |
| `lib/js/script_engine.dart` | `ScriptEngine`：测试台（`runTest`，捕获 log + 异步结果） |
| `lib/js/entity/js_entity.dart` | `JsEntity`：插件类实例的注册 / 调用 / 热重载 / 卸载 |
| `lib/js/js_extends/js_bridge.dart` | `JSEngineCommonApi`：**JS→Dart 消息路由**（全部 `sendMessage` method） |
| `lib/js/js_extends/js_network.dart` | `JsNetwork`：HTTP 请求 + WebView 取页面 HTML |
| `lib/js/js_extends/js_codec.dart` | `JsCodec`：编码 / 加密 / 随机 / UUID |
| `lib/js/js_extends/js_descriptor.dart` | `UiType` 枚举 + `UiAction` + `UiNavigate` |
| `lib/js/js_extends/js_descriptor_renderer.dart` | UI 描述符 → Flutter Widget 渲染器 |
| `lib/js/js_extends/html/*.dart` | HTML 解析注册表（22 个 function：parse/query/extract/serialize） |
| `lib/plugins/plugin.dart` | `Plugin` 类：注册 / `invoke` / `invokeWidgets` / 热重载 / 删除 |
| `lib/pages/plugin/plugin_controller.dart` | 扫描 `{appSupportDir}/plugins/*.js`，管理插件列表 |
| `lib/pages/search/search_controller.dart` | 搜索页：`plugin.invokeWidgets('search', ...)` |
| `lib/pages/browse/` | 浏览页（分类浏览 Tab） |
| `lib/pages/descriptor/` | 详情页（descriptor，通过 `UI.Navigate` 进入） |
| `lib/pages/video/` | 视频播放页（`Navigator.navigateToVideo` 进入，自带资源嗅探） |
| `lib/pages/novel_reader/` | 小说阅读器（`Navigator.navigateToNovelReader` 进入） |
| `assets/plugin/*.js` | **5 个示例插件**：hanime / bmmdmm（视频）、hot_manga / jm / ehentai（漫画） |

### 1.2 插件生命周期

1. **放置**：把 `xxx.js` 复制到 `{appSupportDir}/plugins/`，重启 App 后在插件管理页刷新。
2. **注册**：`PluginController` 扫描该目录，`Plugin.fromFile` 读取源码；`JsEntity.register` 把源码包在 IIFE 中执行，创建 `new <ClassName>()` 实例挂载到 `globalThis.__plugins__.<name>`。
3. **调用**：页面调用 `plugin.invoke(method, args)` / `plugin.invokeWidgets(method, args)`。async 方法返回 Promise，框架自动等待；返回值 JSON 序列化还原。
4. **热重载**：修改源码后 `plugin.reload`（先 unload 再重新 register），无需重启 App。

> ⚠️ **硬性约定**：**类名必须等于文件名（去 `.js`）**，否则 `JsEntity.register` 找不到类。文件头元数据注释会被解析并展示：
> - `// description: ...` — 插件描述（展示在插件列表）
> - `// type: video|manga|novel` — 插件分类（可选，影响搜索页 tab 图标与分类筛选）。缺失时按插件实现的方法自动推断（`play`→视频、`openReader`→漫画、`openNovelReader`→小说），推断不出则归为「其他」。
>
> **插件管理（导入/禁用）**：删除 = 删文件；**禁用 = 不删文件但卸载**（插件不再出现在 App 中，文件保留在磁盘，管理页「已禁用」分区按名称可见），重新点「导入」即快速重新加载并恢复原排序位置。

---

## 二、JS API 全景（来自 init.js）

### 2.1 全局函数

| 全局 | 签名 | 说明 |
|---|---|---|
| `sendMessage` | `(message: Object) => any` | **唯一 JS→Dart 通道**。框架内部使用；插件一般不直接调用 |
| `setTimeout` | `(cb, ms)` | 延时回调（基于 Dart `delay` 实现） |
| `setInterval` | `(cb, ms)` | 周期回调，返回 `{cancel()}` 定时器对象 |
| `createUuid` | `() => string` | 基于时间的 UUID（每次调用生成新值，需持久化请自己存） |
| `randomInt` | `(min, max) => number` | 随机整数 |
| `randomDouble` | `(min, max) => number` | 随机浮点 |
| `log` | `(message, level?)` | 日志，`level ∈ info/warn/error`，输出到 App 日志 |
| `console` | `.log/.warn/.error` | 控制台别名 |
| `fetch` / `http` | 见 2.3 | 浏览器 fetch / axios 风格别名，转发到 `Network` |
| `setClipboard` | `(text) => Promise<void>` | 写剪贴板 |
| `getClipboard` | `() => Promise<string>` | 读剪贴板 |
| `compute` | `(func: string, ...args) => Promise<any>` | 把一段可求值为函数的代码放到引擎池（非主线程）执行，`args` 作为函数唯一参数 |

### 2.2 Convert — 编码 / 加密 / 哈希

```javascript
Convert.encodeUtf8(str) / decodeUtf8(bytes)      // UTF-8 ⇄ 字节
Convert.encodeGbk(str) / decodeGbk(bytes)        // GBK ⇄ 字节
Convert.encodeBase64(bytes) / decodeBase64(str)  // Base64 ⇄ 字节（注意方向）
Convert.md5(bytes) / sha1(bytes) / sha256(bytes) / sha512(bytes)   // 返回字节
Convert.hmac(key, value, hash)                   // HMAC（hash: md5/sha1/sha256/sha512）
Convert.hmacString(key, value, hash)             // 同上，返回 hex 字符串
Convert.encryptAesEcb(value, key) / decryptAesEcb(value, key)
Convert.encryptAesCbc(value, key, iv) / decryptAesCbc(value, key, iv)
Convert.encryptAesCfb(value, key, iv, blockSize) / decryptAesCfb(...)
Convert.encryptAesOfb(value, key, blockSize) / decryptAesOfb(...)
Convert.decryptRsa(value, key)
Convert.hexEncode(bytes) => string               // 字节 → hex 字符串
```

> 字节 = `ArrayBuffer` / `Uint8Array`。示例（jm.js）：
> ```javascript
> let token = Convert.md5(Convert.encodeUtf8(time + jmAuthKey));   // 字节
> let tokenHex = Convert.hexEncode(token);                          // hex 字符串
> let decrypted = Convert.decryptAesEcb(data, key);                 // 字节
> let text = Convert.decodeUtf8(decrypted);                         // 字符串
> ```

### 2.3 Network — HTTP 请求

| API | 返回 | 说明 |
|---|---|---|
| `Network.get(url, headers?)` | `Promise<string>` | GET，返回 body **字符串** |
| `Network.post(url, headers?, data?)` | `Promise<string>` | POST，返回 body 字符串 |
| `Network.put / patch / delete(url, headers?, data?)` | `Promise<string>` | 对应方法 |
| `Network.http(url, options?)` | `Promise<string>` | axios 风格，`options: {method, headers, body}` |
| `Network.sendRequest(method, url, headers, data, extra?)` | `Promise<{status, headers, body}>` | 完整响应 |
| `Network.fetchBytes(method, url, headers, data, extra?)` | `Promise<{status, headers, body}>` | body 为原始字节 |
| `Network.fetch(url, options?)` | `Promise<{ok, status, headers, arrayBuffer(), text(), json()}>` | 浏览器 fetch 风格 |
| `Network.getHtml(url, options?)` | `Promise<string>` | **经系统 WebView 加载页面**并返回渲染后 HTML（绕过 Cloudflare / JS 渲染 / 反爬）。`options` 可为旧式超时秒数（`getHtml(url, 30)`）或对象 `{timeout, waitFor}` |
| `Network.webview(url, options?)` | `Promise<{html, finalUrl}>` | 同 `getHtml`，额外返回**最终 URL**（跟随 302 / JS 跳转后的落地地址，如 page_direct 重定向目标域） |

> - **失败返回结构化错误**：非 2xx / 超时 / 断连 / DNS 失败时，`await` reject 一个带属性的 `Error`：
>   `e.kind`（`timeout` / `connect` / `dns` / `ssl` / `http` / `cancel` / `webview` / `other`）、
>   `e.retryable`（5xx/429/408/超时/断连 → true）、`e.status`（HTTP 状态码，非 HTTP 错误为 0）、
>   `e.headers`（失败响应头，`redirect:'manual'` 时读 `location` 用）。
> - `Network.get` 返回 body 字符串；JSON 接口要 `JSON.parse(res)`（见 hot_manga.js）。
> - 请求头可传防盗链 `Referer`、鉴权 `Authorization` 等（见 jm.js `baseHeaders`）。
> - **每请求 `extra` 参数**（`Network.get/post/...` 的第三参，透传到 Dart 侧已生效）：
>
>   ```javascript
>   Network.get(url, headers, {
>     timeout: 3000,                       // 超时毫秒数（覆盖全局，connect/send/receive 均生效）
>     retries: 2,                          // 失败重试次数 0-5（仅 e.retryable=true 时重试，带退避）
>     redirect: 'follow' | 'manual',       // 默认 follow；manual 时不跟随，从 e.headers.location 读跳转目标
>     backend: 'http' | 'webview' | 'auto', // 默认 http；webview 强制 WebView 渲染；auto 疑似反爬自动降级
>     webviewTimeout: 20,                  // webview / auto 的总超时秒数（5-90）
>     waitFor: 'selector:.x',              // webview / auto 的等待条件（同 getHtml）
>   });
>   ```
> - **Cookie 双向同步**：HTTP 响应的 `Set-Cookie` 自动摄入（含 302 跳转上的）；WebView 页面 Cookie
>   （登录态 / CF 验证）在 `getHtml`/`webview` 成功后自动导入请求侧，**同域名后续 `Network.get` 自动带 Cookie**；
>   可用 `await Network.cookies(url)` 手动查询 `"k1=v1; k2=v2"`（如给图片 CDN 请求拼 Cookie）。
> - **级联降级（`backend:'auto'`）**：HTTP 疑似反爬（403 / 429 / 5xx / 超时 / 断连）时自动改用 WebView 渲染，
>   成功返回 HTML 并带 `via='webview'`（`Network.get` 只返回 body，需要 `via`/`finalUrl` 用 `Network.sendRequest`）。
> - **WebView 模式有 15 秒空闲自动释放**，密集调用可复用；勿在 WebView 模式下高频创建。
> - **WebView `waitFor` 等待条件**（解决 SPA/慢加载抓取到半成品 HTML 的问题）：满足条件才返回渲染后的 HTML。
>
>   ```javascript
>   Network.getHtml(url, { waitFor: 'selector:.comic-contain amp-img' }); // 等选择器出现
>   Network.getHtml(url, { waitFor: { type: 'text', value: '寻找救援' } }); // 等 body 文本
>   Network.getHtml(url, { waitFor: { type: 'js', value: 'document.querySelectorAll("img").length > 0' } });
>   const { html, finalUrl } = await Network.webview(url, { waitFor: 'selector:.list-item' });
>   ```
>
>   `waitFor` 支持对象 `{type, value}`（type: `selector` / `text` / `js`）或字符串简写 `'selector:.x'` / `'text:xxx'` / `'js:<expr>'`；不传则等页面出现有意义内容（默认行为）。
> - **会话（`session`）隔离**：默认会话 `''` 之外，可用 `session` 键开独立会话
>   （`Network.getHtml(url, {session:'foo'})` / `Network.webview(url, {session})` / `extra.session`），
>   不同会话持有**独立的请求侧 Cookie 库**，且**串行化**执行 WebView 操作（并发安全，
>   多个 getHtml 并发不会互相踩踏）。`Network.cookies(url, session)` 指定会话查询。
>   注：WebView 侧因共享 WebView2 profile，多会话同域仍互通；请求侧 Cookie 隔离可靠。

### 2.4 HtmlDocument / HtmlElement — HTML 解析

```javascript
const doc = new HtmlDocument(html);   // 解析 HTML 字符串
doc.dispose();                        // 用后释放（可选）
```

**文档级查询**（`HtmlDocument`）：

| 方法 | 说明 |
|---|---|
| `doc.querySelector(sel)` | 取第一个匹配元素（CSS 选择器或 `//` 前缀的 XPath），无匹配返回 `null` |
| `doc.querySelectorAll(sel)` | 全部匹配元素（数组） |
| `doc.xpath(expr)` | XPath 查询，返回数组 |
| `doc.xpathQuery(expr)` / `doc.xpathQueryAll(expr)` | XPath 别名 |
| `doc.getElementById(id)` | 按 id 取元素 |

**元素级 API**（`HtmlElement`）：

| 属性/方法 | 说明 |
|---|---|
| `el.querySelector(sel)` / `el.querySelectorAll(sel)` | 子级查询 |
| `el.children` | 子元素数组 |
| `el.childrenInfo` | 结构化子节点：`{type: 'element'|'text'|'comment', text, elementKey?}` |
| `el.parent` / `el.previousElementSibling` / `el.nextElementSibling` | 树导航（可 null） |
| `el.text` | 文本内容 |
| `el.attributes` | 属性对象（`el.attributes.href`） |
| `el.getAttribute(name)` | 取单个属性 |
| `el.classNames` / `el.id` / `el.localName` | 类名数组 / id / 标签名 |
| `el.innerHTML` | 内部 HTML 字符串 |

> 懒加载封面图常用优先级：`data-original` > `data-src` > `src`（见 hot_manga / 老版本 maccms 主题）。

### 2.5 PluginSource — 插件基类（必须继承）

`assets/js/init.js` 定义基类，**所有插件必须 `extends PluginSource`**。字段与方法：

```javascript
class myplugin extends PluginSource {
    name = '站点名'          // 显示名
    key = 'myplugin'        // 数据存储 key（load/save 使用）
    version = '1.0.0'
    settings = { ... }      // 设置项 schema（见 4.4）
    translation = {}        // 多语言：{locale: {key: text}}

    // 存储：按 key 隔离，跨会话持久化
    loadData(dataKey)        // 读数据（任意 JSON）
    saveData(dataKey, data)  // 写数据
    deleteData(dataKey)      // 删数据
    loadSetting(key)         // 读设置
    saveSetting(key, value)  // 写设置

    getSettings()            // 返回 this.settings（框架自动调用，无需覆写）

    // 图片加载定制（阅读器每张图调用，见 4.5）
    getImageLoadingConfig(url, comicId, epId) { return {} }

    // 分类浏览（浏览页 Tab，见 4.2）
    getCategory() { return null }         // {title, parts:[{name, categories}]} 或 null
    getCategoryOptions(category) { return null }  // [{label, options:[{value, text}]}] 或 null
    loadCategory(category, page = 1, options = []) { return [] }
    loadCategoryPage(category, page = 1, options = []) { return [] }

    translate(key)           // 按当前 locale 翻译（不覆写）
    init() { }               // 可选初始化
    get isLogged() { ... }   // 登录态（需 Dart 侧支持）
}
```

> ⚠️ 引擎**不会调用 `init()`**（注释说明 wyw 引擎不调用 init，直接实例字段），初始化请直接写在实例字段 / 构造函数里（见 hot_manga.js）。

### 2.6 Dialog — 对话框

```javascript
Dialog.showToast(message)                              // 轻提示
Dialog.showDialog(title, content, actions)             // actions: [{text, callback, style}]
Dialog.showLoading(onCancel)                           // 返回 id
Dialog.cancelLoading(id)                               // 关闭 loading
Dialog.showInputDialog(title, validator?, image?)      // → Promise<string|null>
Dialog.showSelectDialog(title, options[], initialIndex?) // → Promise<number|null>
```

### 2.7 APP — 应用信息

```javascript
APP.version   // 应用版本
APP.locale    // 当前语言，如 "zh_CN"
APP.platform  // "android" | "ios" | "windows" | "macos" | "linux"
```

### 2.8 Navigator — 页面导航

```javascript
// 视频：进入 wyw 视频播放页（结构化对象）
Navigator.navigateToVideo({
    videoId, title, cover?, sourceKey?,
    initialSource?, initialEpisode?,
    sources: [{ name, episodes: [{ name, url, type }] }]
})
//   type: 'direct'（直链）| 'page'（播放页嗅探）| 'local'（本地文件）
//        或 'resolve'（惰性：{plugin, method, args}，播放页按需调用取直链）

// 通用 WebView 页（一般不用）
Navigator.navigateToWebview(url)

// 漫画：进入漫画阅读器
Navigator.navigateToReader({
    comicId, comicTitle,
    chapters,               // [{id, title, images:[...]}] 预加载，或
                            // [{id, title, plugin, method, args}] 惰性加载（切章时调插件方法取图片）
    sourceKey?,             // 源标识（图片缓存隔离）
    initialChapter = 1, initialPage = 1,
})

// 小说：进入小说阅读器
Navigator.navigateToNovelReader({
    novelId, novelTitle,
    chapters,               // [{id, title, content}] 预加载，或
                            // [{id, title, plugin, method, args}] 惰性加载（切章时调插件方法取正文）
    sourceKey?, initialChapter = 1,
})

// 详情页（descriptor）
Navigator.navigateToDescriptor(plugin, { method, args?, title?, actions? })
```

### 2.9 PluginBrowse — 浏览历史桥

```javascript
PluginBrowse.open(pluginName, { id, title, cover = '', kv = {} })  // 记录一条浏览历史（进入详情页时调）
PluginBrowse.find(pluginName, id)                                   // 查询 → data 或 null
```

> `pluginName` 必须通过 `this.name`（即插件 key）显式传入，不能用全局变量。
> 浏览历史回放：实现 `onOpenBrowseEntry(entry)` 方法（见 4.6）。

### 2.10 UI — 描述符构造

`UI.X({...})` 返回**普通 JS 对象**（含 `__type` 字段），框架递归渲染为 Flutter Widget。**返回 List 描述符的插件方法**（`search` / `getDetail` / `loadCategory` 等）都会交给渲染器。

**完整原语列表**（与 `lib/js/js_extends/js_descriptor.dart` 的 `UiType` 一一对应，27 种）：

| 类型 | 字段 | 说明 |
|---|---|---|
| `card` | `child, padding, elevation, color, shapeRadius` | 卡片容器 |
| `column` | `children, mainAxisAlignment, crossAxisAlignment, mainAxisSize` | 纵向布局 |
| `row` | `children, mainAxisAlignment, crossAxisAlignment, mainAxisSize` | 横向布局 |
| `stack` | `children, alignment` | 重叠布局 |
| `image` | `src, width, height, fit, type, headers` | 网络图片（src 为空走占位图；**可传 headers 做图片防盗链**，见 jm.js） |
| `text` | `content, style, maxLines, overflow` | 文本；`UI.Text('str')` 简写 |
| `icon` | `name, size, color` | Material Icon |
| `button` | `label, onTap, style` | 按钮；`onTap` 必须是 `UI.Action` 或 `UI.Navigate` |
| `iconButton` | `icon, onTap, tooltip, color, size` | 图标按钮（AppBar / 卡片操作） |
| `tag` | `text, color, textColor` | 徽章 |
| `spacer` | `flex` | 弹性空间 |
| `divider` | `thickness, color, indent, endIndent` | 分隔线 |
| `container` | `child, padding, margin, color, width, height, alignment, decoration` | 多功能容器 |
| `padding` | `padding, child` | 内边距 |
| `sizedBox` | `width, height` | 固定尺寸 / 间距 |
| `center` | `child, widthFactor` | 居中 |
| `align` | `alignment, child` | 对齐 |
| `expanded` | `flex, child` | Flex 撑开 |
| `wrap` | `children, direction, spacing, runSpacing, alignment` | 流式布局 |
| `aspectRatio` | `aspectRatio, child` | 比例容器 |
| `listView` | `children, direction, padding` | 滚动列表 |
| `singleChildScrollView` | `child, direction, padding` | 单子滚动（详情页 body） |
| `expansionTile` | `title, subtitle, children, initiallyExpanded, shapeRadius` | **可折叠面板**（章节分组） |
| `pagination` | `page, maxPage, pageMethod, pageArgs` | 分页容器（见 4.3） |
| `action` | `plugin, method, args, payload, icon` | 动作描述符（不进渲染树，作为 onTap） |
| `navigate` | `page, method, args, title, actions` | 导航描述符（不进渲染树，作为 onTap） |

**动作 / 导航**：

```javascript
// 点击回调当前插件的某方法（plugin='__self__' 表示当前搜索/详情所属插件）
UI.Action({ method: 'play', args: [url, title, cover] })

// 跳转详情页 + 自动调用 plugin 方法拿内容
UI.Navigate({
    page: 'descriptor',
    method: 'getDetail',
    args: [id],
    title: title,
    actions: [{ __type: 'action', icon: 'favorite', method: 'favorite', args: [id] }],
})
```

> - `UI.validate(node)` 可在开发期校验描述符树（未知类型 / 深度 > 32 / 非法 onTap 会抛错）。
> - `Button.onTap` 传非 Action/Navigate 会被降级为不可点击并 console.warn。
> - `expansionTile.children`、`column/row.children` 必须是**数组**；单个也要包 `[UI.X({...})]`。

---

## 三、插件类型与接口约定

插件按内容类型分三类，**接口约定（方法签名）是框架与插件之间的契约**，必须实现对应方法：

### 3.1 视频源插件（示例：hanime.js、bmmdmm.js）

```javascript
class myvideo extends PluginSource {
    name = '站点名'; key = 'myvideo'; version = '1.0.0'

    async search(keyword, page = 1)   // → List<UI.Card>（搜索结果卡片）
    async getDetail(id)               // → List<UI>（详情页描述符）
    async play(url, title?, cover?)   // → Navigator.navigateToVideo({...}) 结构化进入
    getCategory() / getCategoryOptions(category) / loadCategory(...) / loadCategoryPage(...)  // 可选：分类浏览
}
```

**播放核心原则：交给 wyw 播放器嗅探，不要自己解析**。

`Navigator.navigateToVideo` 使用**结构化对象**传参，一次传入整部剧的播放源列表（含线路 + 每集），播放页内可自由选集/切线路：

```javascript
async play(url, title, cover) {
    // 有整部剧缓存（getDetail 里构建 _playSources）时，直接传完整 sources：
    Navigator.navigateToVideo({
        videoId: this._playSources.videoId,
        title: title,
        cover: cover || '',
        sourceKey: this.key,
        initialSource: 0,
        initialEpisode: 0,
        sources: this._playSources.sources,   // [{ name:'线路名', episodes:[...] }]
    });
}
```

**单集的结构**（`sources[].episodes[]`）：

```javascript
{
    name: '第 1 集',
    url: '播放页网址 / 直链 / 本地路径',   // 预加载形态
    type: 'direct' | 'page' | 'local'
}
// 或惰性 resolve 形态（播放页真正要播该集时才调用插件方法取直链）：
{
    name: '第 1 集',
    type: 'resolve',
    plugin: this.key,          // 插件 key
    method: 'resolvePlayUrl', // 插件暴露的方法，返回 { url, type }
    args: ['/vod-play/1-1-1/']
}
```

**推荐：getDetail 缓存整部剧 sources**（在详情页解析多线路剧集时构建），`play()` 里据此定位当前集并整体传入；同时提供 `async resolvePlayUrl(url)` 供播放页按需取直链。

```javascript
async getDetail(id) {
    // ...解析出多线路剧集 panelEls...
    this._playSources = { videoId: String(id), title: title, cover: cover, sources: [] }
    for (每个线路 panel) {
        const sourceEpisodes = []
        for (每个集 a) {
            const href = a.attributes.href || ''
            sourceEpisodes.push({ name: 集名, type: 'resolve', plugin: this.key, method: 'resolvePlayUrl', args: [href] })
        }
        this._playSources.sources.push({ name: 线路名, episodes: sourceEpisodes })
    }
    // ...仍渲染每个集的 UI.Button(onTap: play(href, title, cover))...
}

async resolvePlayUrl(url) {
    // 执行固定逻辑取直链：请求播放页 / iframe 内页，提取 m3u8/mp4...
    // 返回 { url, type }，type 为 'direct'（直链）或 'page'（需播放器嗅探）
    return { url: 'https://.../index.m3u8', type: 'direct' }
}

async play(url, title, cover) {
    // 从 this._playSources 定位 currentSource/currentEpisode 后整体传入
    Navigator.navigateToVideo({
        videoId: this._playSources.videoId, title, cover,
        sourceKey: this.key, initialSource, initialEpisode,
        sources: this._playSources.sources,
    })
}
```

### 3.2 漫画源插件（示例：hot_manga.js、jm.js、ehentai.js）

```javascript
class mycomic extends PluginSource {
    name = '站点名'; key = 'mycomic'; version = '1.0.0'

    async search(keyword, page = 1)              // → List<UI.Card>
    async getDetail(id)                          // → List<UI>（头部 + 简介 + 章节）
    async openReader(epId)                       // → Navigator.navigateToReader（章节惰性加载）
    async loadChapterImages(comicId, epId)       // → [图片URL...]（阅读器切章时调用）
    getImageLoadingConfig(url, comicId, epId)    // → {headers, modifyImage} 可选
    async onOpenBrowseEntry(entry)               // → 浏览历史回放（可选）
    getCategory() / getCategoryOptions / loadCategory / loadCategoryPage  // 可选
}
```

**章节惰性加载**（推荐，避免一次传大量图片 URL）：

```javascript
async openReader(epId) {
    // this._chapters 在 getDetail 时已缓存 [{id, title}]
    let chapters = this._chapters.map((ep) => ({
        id: ep.id,
        title: ep.title,
        plugin: 'mycomic',          // 必须 = 插件 key
        method: 'loadChapterImages',
        args: [this._comicId, ep.id],
    }));
    Navigator.navigateToReader({
        comicId: this._comicId,
        comicTitle: this._comicTitle,
        chapters: chapters,
        sourceKey: 'mycomic',
        initialChapter: initialChapter,
        initialPage: 1,
    });
}
```

### 3.3 小说源插件（框架已支持 `Navigator.navigateToNovelReader`）

```javascript
class mynovel extends PluginSource {
    async search(keyword, page)       // → List<UI.Card>
    async getDetail(id)               // → List<UI>
    async openNovelReader(epId)       // → Navigator.navigateToNovelReader
    async loadChapterContent(novelId, epId)  // → 章节正文 string（惰性加载时调用）
}
```

```javascript
Navigator.navigateToNovelReader({
    novelId, novelTitle,
    chapters: [{ id, title, plugin: 'mynovel', method: 'loadChapterContent', args: [novelId, epId] }],
    sourceKey: 'mynovel',
    initialChapter: 1,
});
```

---

## 四、进阶功能

### 4.1 分类浏览（浏览页 Tab）

实现 `getCategory()` 返回**非 null** 后，插件会出现在浏览页 Tab 中：

```javascript
getCategory() {
    return {
        title: '站点名',           // 浏览页标题
        parts: [
            { name: '分组名', categories: ['分类A', '分类B'] },
        ],
    };
}
```

- `getCategoryOptions(category)`：分类的筛选选项（`[{label, options:[{value, text}]}]`），无则返回 `null`。
- `loadCategory(category, page, options)`：返回**分页容器**（`[UI.Pagination({...})]`）。
- `loadCategoryPage(category, page, options)`：返回**单纯的结果列表**（`UI.Pagination` 换页时调用）。

### 4.2 分页（UI.Pagination）

```javascript
async loadCategory(category, page = 1, options = []) {
    const { maxPage } = await this._fetchCategoryComics(category, page, options);
    return [
        UI.Pagination({
            page: page,
            maxPage: maxPage,
            pageMethod: 'loadCategoryPage',      // 获取某页内容的方法名（返回单纯结果列表）
            pageArgs: [category, 1, options],    // 页码位于 args[1]，换页时自动更新
        }),
    ];
}
async loadCategoryPage(category, page = 1, options = []) {
    const { comics } = await this._fetchCategoryComics(category, page, options);
    return comics;  // 单纯结果列表
}
```

### 4.3 详情页（descriptor）

**两种进入方式**：

1. 搜索结果卡片按钮 → `UI.Navigate({page:'descriptor', method:'getDetail', args:[id], title, actions})`
2. JS 主动跳转 → `Navigator.navigateToDescriptor('plugin', {method:'getDetail', args:[id], title})`

详情页 `descriptor_controller` 调用 `plugin.invokeWidgets(method, args)` 渲染描述符树；页面内按钮点击 → `plugin.invoke(action.method, action.args)`。

**详情页标准结构**（参见 hot_manga / jm）：

```javascript
async getDetail(id) {
    let items = [];
    // 1) 头部卡片：封面 + 标题 + 元信息
    items.push(UI.Card({ padding: 12, shapeRadius: 8,
        child: UI.Row({ crossAxisAlignment: 'start', children: [
            UI.Image({ src: cover, width: 110, height: 150 }),
            UI.SizedBox({ width: 12 }),
            UI.Expanded({ child: UI.Column({ crossAxisAlignment: 'start', children: [
                UI.Text({ content: title, style: { fontSize: 16, weight: 'bold' }, maxLines: 2 }),
                ...metaLines.map(m => UI.Text({ content: m, style: { fontSize: 12, color: '#888888' }, maxLines: 1 })),
            ]})}),
        ]}),
    }));
    // 2) 简介卡片
    if (description) items.push(UI.Card({ padding: 12, shapeRadius: 8,
        child: UI.Text({ content: description, style: { fontSize: 13, color: '#555555' }, maxLines: 6 })}));
    // 3) 章节（ExpansionTile 折叠面板 + Wrap 流式按钮）
    items.push(UI.ExpansionTile({
        title: UI.Text({ content: `章节（${chapters.length} 话）`, style: { fontSize: 14, weight: 'bold' }, maxLines: 1 }),
        initiallyExpanded: true,
        shapeRadius: 0,
        children: [
            UI.Container({ padding: 8, child: UI.Wrap({ spacing: 6, runSpacing: 6,
                children: chapters.map(ep => UI.Button({
                    label: ep.title, style: 'text',
                    onTap: UI.Action({ method: 'openReader', args: [ep.id] }),
                }))})}),
        ],
    }));
    // 4) 记录浏览历史
    PluginBrowse.open(this.key, { id, title, cover, kv: { id } });
    return items;
}
```

### 4.4 设置项（settings）

插件声明 `settings` 字段，插件管理页会自动读取并渲染设置界面（`lib/pages/plugin/plugin_settings_page.dart`）：

```javascript
settings = {
    image_quality: {
        title: '图片质量',
        type: 'select',                 // select / input（validator 正则可选）
        options: [
            { value: '800', text: '低 (800)' },
            { value: '1200', text: '中 (1200)' },
            { value: '1500', text: '高 (1500)' },
        ],
        default: '1500',
    },
    base_url: {
        title: 'API地址',
        type: 'input',
        validator: '^...$',             // 可选：输入校验正则
        default: 'api.example.com',
    },
};
```

读取：`this.loadSetting('image_quality')`，未设置时返回空，需兜底默认值：

```javascript
get imageQuality() {
    return this.loadSetting('image_quality') || '1500';
}
```

### 4.5 图片加载定制（getImageLoadingConfig + modifyImage）

阅读器为每张图调用 `getImageLoadingConfig(url, comicId, epId)`，可返回：

- `url` — 覆盖请求地址
- `method` — 覆盖请求方法（大写）
- `data` — 请求体
- `headers` — 自定义请求头（如鉴权 token / referer，见 jm.js `getImgHeaders`）
- `onResponse` — `(ArrayBuffer) => ArrayBuffer` 修改响应数据
- `modifyImage` — **JS 脚本字符串**，在独立 Isolate 中执行，脚本需定义 `function modifyImage(image) {...}`，用于切片打乱还原
- `onLoadFailed` — 加载失败回调

```javascript
getImageLoadingConfig(url, comicId, epId) {
    return {
        headers: this.getImgHeaders(),
        modifyImage: `...`,   // 可选：图片还原脚本
    };
}
```

**Image API**（仅 `modifyImage` 脚本内可用）：

```javascript
image.width / image.height          // 尺寸
Image.empty(width, height)          // 创建空白图
image.copyRange(x, y, w, h)         // 复制区域 → 新 Image
image.copyAndRotate90()             // 复制并旋转 90°
res.fillImageAt(x, y, image)        // 把 image 填充到 (x,y)
res.fillImageRangeAt(x, y, image, srcX, srcY, w, h)  // 区域填充
```

**惰性取原图**（ehentai.js 模式）：`loadChapterImages` 返回**页码占位列表**，真实 URL 在 `getImageLoadingConfig` 中按页调用 API 获取并缓存，避免数百页全量预取。

### 4.6 浏览历史回放（onOpenBrowseEntry）

插件管理页点击历史条目时，框架调用 `plugin.invoke('onOpenBrowseEntry', [entry])`：

```javascript
async onOpenBrowseEntry(entry) {
    if (!entry || !entry.kv || !entry.kv.id) {
        Dialog.showToast('浏览历史无效');
        return;
    }
    Navigator.navigateToDescriptor(this.key, {
        method: 'getDetail',
        args: [entry.kv.id],
        title: entry.title || '',
    });
}
```

### 4.7 反爬 / 特殊站点技巧

- **Cloudflare 反爬 / JS 渲染**：`Network.getHtml(url, 50)` 走系统 WebView 加载（hanime.js）。
- **请求头伪装**：`User-Agent` / `Referer` / `X-Requested-With` / `Sec-Fetch-*`（jm.js `baseHeaders`）。
- **加密响应**：`Convert.md5 + hexEncode + decryptAesEcb + decodeUtf8`（jm.js `convertData`）。
- **访问频率限制**：检测提示后 `setTimeout` 等待重试（hot_manga.js `loadChapterImages` 最多重试 5 次）。
- **动态域名**：运行时从远端拉取域名列表 + 本地兜底（jm.js `refreshApiDomains`）。

### 4.8 实战案例：baozimh（包子漫画）章节加载 + 图片防盗链

> 完整可参考实现：`assets/plugin/baozi.js`（assets/plugin 下的工作示例，含 UA/headers 伪装、page_direct 跳转、AMP 图解析、Referer 防盗链）。

**1) 章节请求 403 的根因 —— 站点用跳转保护章节页**

- 详情页章节目录里的链接是**跳转中间页**，不是章节页本身：
  `/user/page_direct?comic_id=<完整slug>&section_slot=0&chapter_slot=<N>` → 302 → 真实章节页
  `https://<lang>.dzmanga.com/comic/chapter/<完整slug>/0_<N>.html`
- **坑 1**：`comic_id` 必须用**完整 slug**（含站点后缀，如 `wuliandianfeng-pikapi_lav8od`），详情页 URL 里的短 slug 不能直接用于 page_direct。
- **坑 2**：不能把章节页域名/路径硬编码（不同站点不同），必须**请求 page_direct 让 Dio 跟随 302**，且请求带浏览器 UA + Referer，否则 403。
- **坑 3**：章节 `id` 必须从链接提取 **`chapter_slot`**（或 `/0_<slot>.html`），**列表索引 ≠ slot**，否则会请求到不存在的 `0_0.html`。

```javascript
// 章节链接两种格式都要兼容
const extractSlot = (href) => {
    let m = href.match(/chapter_slot=(\d+)/); if (m) return m[1];
    m = href.match(/\/(\d+)_(\d+)\.html/); if (m) return m[2];
    return null;
};
```

**2) 章节页是 SSR/AMP 结构 —— 图片在 `<amp-img>` 里**

- 章节页没有 `<img>`，图片全在 `<amp-img>` 内，容器是 `.comic-contain` / `.comic-contain__item`（**没有 `.chapter-img`**）。
- 用 `doc.querySelectorAll('.comic-contain amp-img')` 收集，属性按 `src` / `data-src` / `data-original` 依次读取；内容区取不到时再兜底全页 `amp-img`（避免把 logo/图标混进来）。
- **务必用 console 打印选择器命中数**（`.chapter-img` / `.comic-contain` / `amp-img` / `img` 各命中几个），一眼看出结构是否匹配。

**3) 图片 CDN 防盗链 —— 返回 200 但图被替换**

- 图片 CDN（`*.bzcdn.net`）校验 **reader 域 Referer**（如 `https://cn.dzmanga.com/`）+ 浏览器 UA，缺 Referer 时返回**被替换的拦截图**（HTTP 200 但不是原图）。
- 通过 `getImageLoadingConfig` 返回 headers 补上：

```javascript
getImageLoadingConfig(url, comicId, epId) {
    return { headers: { 'User-Agent': this.ua,
        'Referer': 'https://' + this.lang + '.dzmanga.com/', } };
}
```

- reader 域做成 `input` 设置（`reader_domain`），不同站点可改。
- **reader 域动态检测（v1.1.8 起）**：章节页 `canonical` 的 host 才是真实 reader 域
  （站点域路由会变，如 `dzmanga.com` → `www.baozimh.com`），`loadChapterImages` 里把
  `_extractHost(canonical)` 记到 `this._readerHost`，`getImageLoadingConfig` 优先用它，
  设置项仅作「未打开过章节」时的兜底——避免站点换域后防盗链失效。
- ⚠️ **注意区分「防盗链拦截图」与「站点自带的引流图」**：个别章节会插入引流/广告图，浏览器里也照样显示——那不是 bug，别花时间"修复"。
- **不要擅自改写图片 URL**（如插入 `/w640` 质量参数）：除非在浏览器里验证过真实格式，否则默认原样返回 URL，仅在显式配置 `cdn_domains` 时替换域名。

**4) 空结果的诊断姿势**

`loadChapterImages` 解析为空时**不要静默返回 `[]`**（会导致阅读器 `maxPage=0` 崩溃），应 `console.error` 打印诊断 + `throw` 带上下文的异常（`url`、HTML 长度、选择器命中数、首章节信息），阅读器会显示错误文案，用户可直接回贴。

---

## 五、测试与调试

1. **JS 开发测试台（App 内置页面）**：App 里的「JS 开发」页（`lib/pages/js_dev/`）——上方是脚本编辑器，下方是彩色日志面板（info/warn/error 分级、`RET` 返回值、异常堆栈）。它跑的是完整 `ScriptEngine`（加载 `assets/js/init.js` 全部 API + `sendMessage` 桥），是**写插件前验证/调试代码最直接的地方**：

   - **脚本协议**：必须定义 `class Test { run() { ... } }`；`run()` 返回普通值或 `Promise`（异步，90s 上限）。每次运行 `new Test()`，方法间无状态残留。默认编辑器里有 hello-world 示例。
   - **日志**：`log(msg, 'info'|'warn'|'error')` 与 `console.*` 都会进面板；`run()` 的返回值 JSON 序列化后以 `RET` 高亮展示（对象自动缩进格式化）。
   - **能力**：`Network.get / getHtml / webview / cookies / sendRequest`、`HtmlDocument`、`Convert`、`Dialog`、`UI` 等全部可用。WebView 首次调用有初始化成本；单次默认 50s 超时、15s 空闲自动释放。
   - **内置回归测试**（`lib/pages/js_dev/tests/`，复制进编辑器点 ▶ 即跑）：
     - `test_webview_p0.js` — WebView `waitFor` + `finalUrl`（7 项）
     - `test_network_p1.js` — `extra`（timeout/retries/redirect）+ 结构化错误（7 项）
     - `test_network_p2.js` — Cookie 双向同步 + HTTP→WebView 级联降级（6 项）
     - `test_network_p3.js` — 会话池并发安全 + 会话 Cookie 隔离（4 项）
     - `test_plugin_hanime.js` — 对真实 hanime1.me 验证插件同款 waitFor
   - **注意**：`init.js` 与内置插件打包进 asset，改动后需**完整重建重启**（热重载不生效）；测试台报「not a function」多半是没重建。测试站选稳定可达的（如 httpbin.org、cn.baozimhcn.com），别硬编码易变的站点文本/域名。
2. **运行时测试**：插件管理页添加插件 → 粘贴 JS → 重启 → 在搜索 / 浏览 / 详情页测试。
3. **日志（强规则：尽可能多地用 console 打印插件信息用于调试）**：`console.log/warn/error` 经 `WywLogger` 输出到 App 日志，是排查解析问题的最快手段。**开发插件时应主动、大量打印关键调试信息，不要只在出错时才打**：

   ```javascript
   // 建议打印：请求 URL、HTML 长度、解析数量、前几条关键数据、选择器命中数
   console.log('[plugin]', '请求:', url, '页长:', html.length);
   console.log('[plugin]', '链接数:', links.length, '前3:', links.slice(0, 3).map(x => x.href));
   console.log('[plugin]', '选择器命中:', doc.querySelectorAll('.chapter-img').length,
       'amp-img:', doc.querySelectorAll('amp-img').length);
   console.error('[plugin]', '解析失败:', e);
   ```

   约定：
   - 统一加 `[插件key]` 前缀，便于在 App 日志里过滤定位。
   - 打印**请求 URL + HTML 长度**（判断请求是否被反爬返回错误页/空页）、**解析数量 + 前 N 条样本**（确认解析结果对得上）、**选择器命中数**（确认 HTML 结构与选择器匹配）。
   - 解析结果为空时：`console.error` 打印诊断信息，并**直接抛带上下文的异常**（`throw '解析为空：url=... 页长=... 命中数=...'`）——阅读器/详情页会把异常显示成错误文案，用户可直接回贴日志，省去来回排查。
   - 日志开销很小，正式环境保留即可；但避免打印会拖慢热路径的巨型对象（超大 HTML 全文、数百页图片列表）。

4. **Toast 提示**：`Dialog.showToast('未找到结果，请检查关键词')` 让用户在 UI 上看到错误。

---

## 六、常见陷阱

| ⚠️ 陷阱 | 正确做法 |
|---|---|
| 手动解析播放页找 iframe/m3u8 | 交给播放器嗅探：结构化 `Navigator.navigateToVideo({sources:[{name,episodes:[{name,url,type:'page'}]}]})` |
| 类名与文件名不一致 | 类名 = 文件名去 `.js`，否则注册失败 |
| 引擎不调用 `init()` | 初始化逻辑放实例字段 / getter / 构造 |
| 封面只读 `src` | 懒加载：`data-original` > `data-src` > `src` |
| `Network.get` 结果当 JSON 用 | 它是 body 字符串，需 `JSON.parse` |
| 章节一次传全部图片 URL | 用惰性加载：`{id, title, plugin, method, args}` |
| 图片 403（防盗链） | `UI.Image({..., headers: ...})` 或 `getImageLoadingConfig` 返回 headers |
| `ExpansionTile.children` 传单个对象 | 必须是数组：`[UI.X({...})]` |
| `Button.onTap` 传普通函数 | 必须是 `UI.Action` / `UI.Navigate` 描述符 |
| `HtmlDocument` 不释放 | 用后 `doc.dispose()`（Map 有 GC 兜底） |
| 请求被 Cloudflare 拦截 | `Network.getHtml(url)` 走 WebView 渲染 |

---

## 七、完整模板

### 7.1 视频源模板

```javascript
// description: <站点名> 视频源（搜索 + 详情 + 播放）
class myvideo extends PluginSource {
    name = '<站点名>'
    key = 'myvideo'
    version = '1.0.0'
    baseUrl = 'https://<domain>'

    _abs(href) {
        if (!href) return '';
        if (href.startsWith('http://') || href.startsWith('https://')) return href;
        if (href.startsWith('//')) return 'https:' + href;
        if (href.startsWith('/')) return this.baseUrl + href;
        return this.baseUrl + '/' + href;
    }

    _buildCard({ cover, title, epInfo, id }) {
        return UI.Card({
            elevation: 0, shapeRadius: 16, color: '@theme:surfaceContainerLow', padding: 4,
            child: UI.Row({ crossAxisAlignment: 'start', children: [
                cover ? UI.Image({ src: cover, width: 80, height: 116 }) : null,
                UI.SizedBox({ width: 12 }),
                UI.Expanded({ child: UI.Column({ crossAxisAlignment: 'start', mainAxisAlignment: 'start', children: [
                    UI.Text({ content: title, style: { fontSize: 14, weight: 'bold' }, maxLines: 2 }),
                    epInfo ? UI.Text({ content: epInfo, style: { fontSize: 12, color: '#888888' }, maxLines: 2 }) : null,
                ].filter(x => x != null) }) }),
                UI.SizedBox({ width: 8 }),
                UI.IconButton({
                    icon: 'play_circle_filled', tooltip: '播放', color: '#e53935', size: 20,
                    onTap: UI.Action({ method: 'play', args: [`${this.baseUrl}/watch?v=${id}`, title] }),
                }),
            ].filter(x => x != null) }),
        });
    }

    async search(keyword, page = 1) {
        const url = `${this.baseUrl}/search?query=${encodeURIComponent(keyword)}&page=${page}`;
        let html;
        try {
            html = await Network.get(url, this._headers());
        } catch (e) {
            Dialog.showToast('搜索请求失败: ' + e);
            return [];
        }
        if (!html) return [];
        const doc = new HtmlDocument(html);
        const items = [];
        for (const item of doc.querySelectorAll('.video-item')) {
            // ... 解析标题 / 封面 / 剧集信息
            items.push(this._buildCard({ cover, title, epInfo, id }));
        }
        doc.dispose();
        if (items.length === 0 && page <= 1) Dialog.showToast('未找到结果');
        return items;
    }

    async play(url, title, cover) {
        // 结构化进入：有 getDetail 缓存的整部剧 sources 时整体传入
        Navigator.navigateToVideo({
            videoId: this._playSources?.videoId || url,
            title: title || url,
            cover: cover || '',
            sourceKey: this.key,
            initialSource: 0,
            initialEpisode: 0,
            sources: this._playSources?.sources || [{
                name: '默认线路',
                episodes: [{ name: title || url, url: url, type: 'page' }],
            }],
        });
    }
}
```

### 7.2 漫画源模板

```javascript
// description: <站点名> 漫画源 — 搜索/详情/阅读
class mycomic extends PluginSource {
    name = '<站点名>'
    key = 'mycomic'
    version = '1.0.0'

    _comicId = ''
    _comicTitle = ''
    _chapters = []

    async search(keyword, page = 1) { /* ...返回 List<UI.Card>... */ }

    async getDetail(id) { /* ...返回 List<UI>，最后 PluginBrowse.open(this.key, {id,title,cover,kv})... */ }

    async openReader(epId) {
        let chapters = this._chapters.map(ep => ({
            id: ep.id, title: ep.title,
            plugin: 'mycomic', method: 'loadChapterImages', args: [this._comicId, ep.id],
        }));
        Navigator.navigateToReader({
            comicId: this._comicId, comicTitle: this._comicTitle,
            chapters, sourceKey: 'mycomic',
            initialChapter: 1, initialPage: 1,
        });
    }

    async loadChapterImages(comicId, epId) {
        // 返回该章图片 URL 数组
        const res = await Network.get(`${this.apiUrl}/chapter?id=${epId}`, this.headers);
        return JSON.parse(res).images.map(e => this.getImageUrl(epId, e));
    }
}
```

### 7.3 小说源模板

```javascript
// description: <站点名> 小说源 — 搜索/详情/阅读
class mynovel extends PluginSource {
    name = '<站点名>'
    key = 'mynovel'
    version = '1.0.0'

    async search(keyword, page = 1) { /* ... */ }
    async getDetail(id) { /* ... */ }

    async openNovelReader(epId) {
        Navigator.navigateToNovelReader({
            novelId: this._novelId, novelTitle: this._novelTitle,
            chapters: this._chapters.map(c => ({
                id: c.id, title: c.title,
                plugin: 'mynovel', method: 'loadChapterContent', args: [this._novelId, c.id],
            })),
            sourceKey: 'mynovel',
            initialChapter: 1,
        });
    }

    async loadChapterContent(novelId, epId) {
        const res = await Network.get(`${this.apiUrl}/chapter?id=${epId}`, this.headers);
        return JSON.parse(res).content;  // 返回正文 string
    }
}
```

---

## 八、调试速查表

| 现象 | 排查方向 |
|---|---|
| 插件列表不显示 | 文件是否在 `{appSupportDir}/plugins/`；是否重启；类名是否 = 文件名 |
| "Class xxx not found" | 类名 ≠ 文件名（去 .js） |
| 搜索结果空 | `console.log` 输出 HTML 片段检查选择器；`Dialog.showToast` 看错误 |
| 封面占位图 | 懒加载属性 `data-original` 没读 |
| 图片 403 | 加 Referer / token headers（`UI.Image` headers 或 `getImageLoadingConfig`） |
| 图片 200 但不是原图（被替换/拦截图） | CDN 防盗链：`getImageLoadingConfig` 补 reader 域 Referer + UA；个别章节是站点自带的引流图，非 bug |
| 解析出空列表 / 数量对不上 | console 打印选择器命中数与 HTML 片段；确认图片容器是 `<img>` 还是 `<amp-img>`、属性是 `src`/`data-src`/`data-original` |
| 播放无反应 | 确认 `Navigator.navigateToVideo({sources})` 传参正确（sources 非空、每集含 url+type 或 resolve） |
| 章节打不开 | `openReader` 的章节是否用惰性加载格式 `{plugin, method, args}` |
| 按钮点击无效 | `onTap` 必须 `UI.Action` / `UI.Navigate` |
| JSON 解析失败 | `Network.get` 返回字符串，先 `JSON.parse`；检查是否被 gzip/加密 |

---

**文档版本**：2026-07 整理重写（依据当前代码库）
**代码位置**：`assets/js/init.js` · `assets/plugin/*.js` · `lib/js/**` · `lib/plugins/plugin.dart`
