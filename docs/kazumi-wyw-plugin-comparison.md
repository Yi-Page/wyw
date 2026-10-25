# Kazumi 插件系统能力 ↔ wyw JS 插件能力对比

> 回答两个问题：
> **Q1**：`D:\development\AndroidStudioProjects\Kazumi` 的插件系统都有什么能力？
> **Q2**：wyw（本工作区）的插件系统，能否通过 JS + 已暴露的接口做到 Kazumi 插件能做的事？
>
> 证据约定：结论带 `文件:行号`；Kazumi 侧路径相对 Kazumi 仓库根（版本 `2.3.7+20307`，客户端 apiLevel=8），wyw 侧相对 wyw 仓库根。
> 交叉核验：本报告由 Lead 汇总，Kazumi/wyw 两侧清点与独立核查分别见
> `build/plugin-analysis/kazumi-inventory.md`（283 行）、`build/plugin-analysis/wyw-bridge.md`（516 行）、
> `build/plugin-analysis/verifier-probe.md`（345 行）、`build/plugin-analysis/verification-report.md`。
> 所有可验证断言已按对抗核验结论修正（8 条降级/更正、5 处计数与行号修正）。

---

## §0 结论速览

**Q1 一句话**：Kazumi 的插件是**纯声明式 JSON 规则**——宿主拿它跑固定流水线（搜索=1 次请求+3 个选择器，选集=1 次请求+2 个选择器），插件侧没有逻辑、没有条件、没有循环、没有多步请求；唯一「能执行 JS」的字段是反爬里的 `captchaScript`，而且只在验证码 WebView 页面内跑，不参与解析。

**Q2 一句话**：**能做到，而且是严格超集。** Kazumi 规则能表达的每一件事，wyw 插件都能表达；Kazumi 结构上做不到的（多步请求、签名计算、任意请求头、任意解析取值、插件自带 UI、插件设置项），wyw 都是默认能力。

**但要诚实地说清 9 个缺口**：4 个需改宿主 Dart 才能对齐 Kazumi（G1/G2/G3/G5），4 个是健壮性/一致性风险（G6/G7/G8/G9），1 个是可选（G4）。

| # | 缺口 | 方向 |
|---|---|---|
| G1 | 旧版 iframe 解析器（`useLegacyParser`）在 wyw **接口层无入口**（字段恒 false、无调用方） | 需改宿主 |
| G5 | **无法为最终媒体/下载请求声明 headers/referer/UA**（Kazumi 有 per-plugin `userAgent`/`referer`） | 需改宿主（防盗链刚需） |
| G2 | **无每插件广告过滤声明**（只有全局 `forceAdBlocker`） | 需改宿主 |
| G3 | **无在线插件仓库/订阅/版本更新**，且 `Plugin.toJson` 连 `version` 字段都没有 | 需改宿主（结构性） |
| G7 | **无脚本超时/内存栈上限/权限模型**，插件死循环可卡住宿主 | 风险 |
| G8 | **无 UA 对齐闭环**：headless WebView UA 与 Dio UA 各随机一次 → CF clearance cookie 易失配 | 风险 |
| G9 | 插件间 Cookie **默认共享**（Kazumi 按插件名分 jar） | 风险/可绕过 |
| G6 | JS 请求无取消、无 multipart/WS、**不走代理、不做证书放宽**（Kazumi 有代理） | 风险/可选 |
| G4 | 无框架级反爬工作流（wyw 是插件可编排的原语） | 可选，建议保持 |

---

## §1 Q1 · Kazumi 插件系统的能力

### 1.1 形态与 schema

- 插件 = JSON 对象（单对象 / 数组 / 一条或多条 `kazumi://` Base64 链接），字段全为字符串/布尔/嵌套配置：`Kazumi/lib/plugins/plugins.dart:80-119`（读）、`:150-182`（写）。
- **无 JS 引擎**：`pubspec.yaml` 不存在 `flutter_qjs`/`quickjs`/`flutter_js`/`dart_eval`；规则处理依赖 `xpath_selector`、`xpath_selector_html_parser`、`json_path`、`html`（`pubspec.yaml:51-53,79`）。
- 数据落在单一 `<appSupport>/plugins/v2/plugins.json`（`lib/plugins/plugins_controller.dart:104,111-150,304-318`）。

主要字段（完整表含嵌套字段见 `kazumi-inventory.md` §1）：

| 字段 | 语义 | 证据 |
|---|---|---|
| `api`/`type`/`name`/`version` | 最低客户端 API（`>8` 需升级）/ 站点类型（运行期无分支）/ 主键（同名去重）/ 版本（用于更新比对） | `plugins.dart:23-26,82-86,186` |
| `searchURL`/`searchList`/`searchName`/`searchResult` | 搜索 URL 模板（`@keyword`）+ 条目集合 / 名称（取 text）/ 链接（取 href） | `lib/services/plugin/xpath_rule_strategy.dart:50-145` |
| `chapterRoads`/`chapterResult` | 线路集合 / 剧集（名称取 text、地址取 href） | `xpath_rule_strategy.dart:160-212` |
| `usePost` | 把 `searchURL` 的 query 搬成表单 POST | `xpath_rule_strategy.dart:65-78` |
| `useLegacyParser` | 旧版（iframe src）vs 现代（拦截 m3u8/Range + hook XHR/Response.text + 监听 video/source）解析器 | `lib/webview/video/impl/video_webview_impl.dart:108,137-153,331,386` |
| `adBlocker` | 剔除 m3u8 广告分片（与全局 `forceAdBlocker` 取或） | `lib/utils/m3u8_ad_filter.dart:6-70` |
| `userAgent`/`referer` | **只用于播放/下载**，搜索与选集请求不用 | `plugins.dart:262-268`；`lib/pages/video/video_controller.dart:634-636` |
| `baseURL` | 拼相对 URL + 作为规则请求的 Referer 前缀 | `lib/utils/episode_url.dart:21-78`；`rule_engine.dart:310` |
| `searchMode`/`chapterMode` | `xpath`（默认）/`api` | `plugins.dart:101-102` |
| `searchApiConfig`/`chapterApiConfig` | API 模式请求模板与 JSONPath 映射（见 1.2） | `lib/plugins/api_rule_config.dart:72-232` |
| `antiCrawlerConfig` | 反爬（见 1.3） | `lib/plugins/anti_crawler_config.dart:25-133` |

**死字段**（编辑器/导入导出会透传，运行期无人读）：`useWebview`、`useNativePlayer`（源码注释即 legacy）、`muliSources`、`type`；`PluginInstallTimeTracker` 被 new 出来但全仓无读写（`plugin_install_time_tracker.dart:8-15`）。

### 1.2 规则引擎能写什么、不能写什么

| 能力 | XPath 模式 | API 模式 |
|---|---|---|
| 请求方法 | GET 或表单 POST | GET/POST（json/form body） |
| 自定义请求头 | **不能**（`xpath_rule_strategy.dart:66-78`） | 能（`api_rule_strategy.dart:129-137`） |
| 变量 | 仅 `@keyword`（URL 内，`Uri.encodeQueryComponent`） | `@keyword`/`@source`/`@episodeUrl`/0-based 与 1-based 索引/响应抓取的具名变量 |
| 取值 | 元素 **text** + **href**（硬编码；写 `@data-src` 无效） | JSONPath **白名单子集**：`.a.b`/`[0]`/`[*]`/`['k']`，无过滤器/切片/递归/函数 |
| 计算/拼接 | 无 | 只有 `@var` 替换，**无算术**（源码注释明写） |
| 正则 | 仅反爬检测用 | 同左 |
| 多步请求 / 动态 token | **不支持**（每次查询只发一次请求，`rule_engine.dart:36-181`） | 不支持 |
| 超时/重试/重定向/二进制 | 不支持（超时来自全局 12s；无重试） | 不支持 |
| 反爬验证 | 支持（仅搜索） | 不支持 |

证据：`xpath_rule_strategy.dart:54-57,126,132,180,187`；`api_rule_strategy.dart:19-57,410-420,515-531`。

宿主固定注入的请求头：`referer: <baseURL>/`、随机 UA、Cookie（搜索/API）；验证过的 UA 会**覆盖**规则 UA；非 2xx 一律失败（`rule_engine.dart:307-318`；`lib/request/clients/plugin_site_client.dart:37-44`）。

### 1.3 反爬 / 验证码（Kazumi 最强的一块）

- 三位一体：`captchaType` 1=图片验证码、2=自动点击按钮、3=注入自定义 JS；`captchaDetectType` 1=XPath、2=文本、3=正则（`lib/plugins/anti_crawler_config.dart:8-19`）。
- 真实流程（**WebView 是 headless 的**，用户只在对话框里看图填字，不是在浏览器里操作）：
  1. XPath 搜索响应命中验证页特征（或响应头 `cf-mitigated: challenge`）→ 抛 `CaptchaRequiredException`；
  2. 打开**无头** WebView 加载搜索页；加载前清空 WebView Cookie；
  3. 类型 1：页面内 canvas 抓验证码图 → 对话框展示 → 用户读数 → 宿主在**页面内**填写 input 并点击提交（`submitCaptchaInteract`），另有 MutationObserver 监听验证码消失；
  4. 类型 2：检测到按钮后自动点击；类型 3：把规则自带 JS 包 IIFE 注入页面，脚本调 `KazumiCaptcha.log/clicked/done/fail`；
  5. 通过后**收割页面 HTML 直接按同一套 XPath 规则解析**（省一次请求；仅 XPath 且非 POST 规则适用）；并保存 Cookie **与 `navigator.userAgent`**；后续请求强制用该 UA（clearance cookie 与 UA 绑定）。
  6. **只作用于 XPath 搜索**：API 搜索与选集解析都不触发验证流程。
- 证据：`lib/services/plugin/captcha_verification_service.dart:112-129,134-154,157-171,174-188,218-252`；`lib/webview/captcha/impl/captcha_webview_windows_impl.dart:11,22,150-158,161-187,284-310`；`lib/services/plugin/plugin_cookie_manager.dart:16-40,62-72`；`rule_engine.dart:103-128,216-262,301-318`。
- 边界：CookieJar 与 UA 都是**内存态**，重启后需重新验证（`plugin_cookie_manager.dart:11,16`）。

### 1.4 媒体解析 / 播放头 / 广告过滤

- 规则只产出**剧集页 URL**；最终媒体 URL 一定由宿主 Headless WebView 嗅探（`lib/pages/video/video_controller.dart:589-610`）。
- 现代解析器三路：native 拦截 `.m3u8` / `Range:` 媒体请求；页面内 hook `Response.prototype.text` 与 `XMLHttpRequest.open`（内容以 `#EXTM3U` 开头即上报，含 iframe 注入）；监听 `<video>/<source src>` + 每秒轮询兜底。旧版：监听 iframe src + 正则提取（`lib/webview/video/impl/video_webview_impl.dart:37-52`（native 拦截）、`:156-214`（XHR/Response hook）、`:291-328`（video/source + 轮询）、`:331+`（legacy））。
- 结果带 `format: auto|hls` 提示；WebView 实例池化（下载侧 `VideoSourceResolverPool` 1-5 worker 并行）；嗅探 WebView 走应用代理设置（`lib/services/video_source/video_source_format.dart:1-4`、`video_source_resolver_pool.dart:11-14`、`video_webview_impl.dart:477-511`）。
- 播放/下载请求头来自插件 `userAgent` + `referer`（`plugins.dart:262-268`）；广告过滤在 m3u8 层按 discontinuity group 剔除（`lib/utils/m3u8_ad_filter.dart:6-70`）。

### 1.5 分发 / 编辑器 / 有效性

| 能力 | 事实 | 证据 |
|---|---|---|
| 导入 | JSON / JSON 数组 / 多条 `kazumi://` Base64 链接（兼容 URL-safe 与 percent-encoding） | `lib/services/plugin/plugin_import_parser.dart:28-143`；`lib/utils/encoding.dart:3-59` |
| 导出/分享 | `toJson()` → Base64 → `kazumi://` 链接 | `lib/pages/plugin_editor/rule_dialogs.dart:120-121` |
| 在线仓库/订阅 | `refreshPluginCatalog`（单飞）、启动检查更新、镜像（拦截器改写 URL）、目录缓存 5 分钟、批量更新并发 4 | `lib/plugins/plugins_controller.dart:87-90,320-358,476-555`；`lib/request/apis/plugin_catalog_api.dart:11-63` |
| 更新策略 | 版本比较；远程不高于本地则跳过（不降级）；名称必须与目录名一致 | `plugins_controller.dart:360-366,420-473` |
| 有效性 | 内存集合：本次启动内该规则成功返回过搜索 → 列表显示「搜索通过」 | `lib/services/plugin/plugin_validity_tracker.dart:1-16`；`plugin_search_service.dart:52,88` |
| 编辑器/测试 | 全字段 GUI（XPath/API 双模式 + 反爬）+ 保存前校验 + 规则测试页（原始响应/条目/diagnostics） | `lib/pages/plugin_editor/plugin_editor_page.dart:528-1131`；`plugin_test_page.dart:100-146` |

### 1.6 Kazumi 插件明确做不到的事（有代码证据）

1. 插件内不能写任何逻辑（无表达式/条件/循环）。2. 不能多步请求、动态 token、加密参数计算（连算术都没有）。3. 链接只能取 `href`、命名只能取元素 text。4. XPath 模式不能自定义 Cookie/Header，选集请求连 Cookie 都不带。5. XPath 线路名硬编码「播放线路N」。6. API 响应必须是合法 JSON。7. JSONPath 是收紧子集。8. 无每规则超时/重试/代理。9. 规则不能带资源/代码文件。10. 反爬只作用于 XPath 搜索。11. 最终媒体 URL 必经 WebView（`useWebview` 也关不掉）。12. 有效性/安装时间不落盘（后者还是死代码）。

---

## §2 Q2 · wyw 暴露给 JS 的接口面（对照基准）

- 引擎：`flutter_qjs` 0.3.7（fork）内编译 quickjs-ng 2024-02；`FlutterQjs()` **无参**创建 → 不限栈/内存/时间；Promise/async 可用（Dart Future↔JS Promise）。证据：`pubspec.yaml:56-58`；`lib/js/base_js_engine.dart:26-46`。
- **唯一注册原语是 `sendMessage`**：宿主只注入这一个全局函数，其余能力都在 `assets/js/init.js`（2428 行）用 JS 封装（`lib/js/base_js_engine.dart:31-36`）。
- 宿主侧共 **70 个可调用入口**：`sendMessage` 27 个 method（`lib/js/js_extends/js_bridge.dart:164-350`）+ `html` 子分派 22 个（`lib/js/js_extends/html/html_registry.dart:57-100`）+ `dialog` 6 + `plugin_history` 2 + `convert` 13（type）。
- JS 侧另有 27 个全局名 / 116 个具名成员（`Convert`/`Network`/`HtmlDocument`/`HtmlElement`/`Dialog`/`APP`/`Navigator`/`UI`/`PluginBrowse`/`PluginSource`/`Image`）。

**插件的另一半契约是宿主会调用的方法**：`search(keyword,page)`、`getDetail(id)`、`play(url,…)`、`resolvePlayUrl`（播放源 `type:'resolve'` 时）、`openReader`/`loadChapterImages`、`openNovelReader`/`loadChapterContent`、`getCategory*`、`getSettings`/`loadSetting`/`saveSetting`、`getImageLoadingConfig`、`getUrl`、`implementsMethod`、`onOpenBrowseEntry`。

**wyw 侧的边界（本次核查确认，含「文档有代码无」）**：

- `compute()`：JS 有定义，宿主 dispatch **没有该分支** → 落到 `return null`，调用恒得 `null`（同类的 `Image.*` 只在漫画图片还原的独立隔离引擎里可用）。
- 元素级 XPath 是**死代码**：`init.js` 同名方法重复定义（后者覆盖），`dom_xpathQuery*` 不可达；`doc.querySelector('//x')` 不识别 XPath——只有 `querySelectorAll`/`xpathQueryAll`/`xpathQuery` 走 XPath（`query_handler.dart` 的注释声称会自动识别，**注释是错的**）。
- `PluginSource.get isLogged` 恒 `false`（`onIsLogged` 全仓无赋值点）；`APP.version` 恒 `''`（宿主从不注入 `appVersion`）；`plugin_browse_entry` 是 no-op。
- `UI.Image` 的 `headers` 被 `init.js` 解构丢弃（渲染器其实支持，需手写 `__type:'image'`）；`UI.Action` 的返回值被宿主丢弃（要展示结果必须跳 descriptor 页）；`UI.Navigate.page` 字段被忽略。
- UI 描述符：24 个可渲染原语（`UiType` 27 项 = 24 渲染 + action/navigate/unknown），**没有输入框/下拉/Tab/表单类原语**（输入只能借 `Dialog.showInputDialog/showSelectDialog`），渲染深度上限 32、每容器最多 200 子元素。
- 插件存储只在两个硬编码前缀内（`plugin_data:<类名>:*`、`plugin_setting:<类名>:*`），读写不到宿主设置；未设置的设置项返回 `null`。
- 网络：无请求取消（`kind:'cancel'` 只是分类，没有触发路径）、无 multipart/上传进度、无 WebSocket/SSE、**不走代理**、**不忽略证书**（`allowBadCertificates` 无赋值点）；Cookie 请求侧为进程内存、显式忽略 `max-age/expires`。
- **无脚本超时/中断/沙箱**：90s 超时只属于测试台；生产引擎同步评估，插件死循环会卡住。

---

## §3 逐项映射（核心交付）

判定：**✅ 可达**（现有 JS+宿主即可，且多为更强）；**⚠️ 部分/需插件编排**；**❌ 缺口**（必须改 Dart）。

| # | Kazumi 能力 | wyw 路径 | 判定 |
|---|---|---|---|
| M1 | 搜索（1 请求+3 选择器） | `Network.get` + `new HtmlDocument(html)`；`querySelectorAll`（CSS，或 `//` 前缀转 XPath）/`xpathQuery*`；结果用 UI 描述符渲染 | ✅ 更强（可多步、可签名、可任意取值） |
| M2 | 选集/线路 | 任意方法 + `sources:[{name,episodes[]}]`，线路名可自定义 | ✅ 更强 |
| M3 | API 模式/JSONPath | 任意 JS：`JSON.parse` + 取值（无白名单） | ✅ 更强 |
| M4 | 剧集页→媒体直链 | `PlayResourcePath{direct｜page｜local｜resolve}`：可给直链、可给播放页交宿主无头嗅探、可先跑插件 resolve 再多步解析 | ✅ 更强（Kazumi 只能给页面 URL 后必嗅探） |
| M5 | 请求定制 | headers/method/body/bytes/每请求 timeout/retries 0-5/manual redirect/session；结构化错误 `{kind,retryable,status,headers,body}` | ✅ 更强（Kazumi 无超时/重试/重定向/二进制） |
| M6 | Cookie | HTTP `Set-Cookie` 自动摄入 + WebView 页面 Cookie 自动导入请求侧 + `get_cookies` 可读 + `session` 可隔离 | ✅ 能力更强，但**默认不按插件隔离**（Kazumi 按插件名分 jar）；两侧插件 Cookie 都不落盘 |
| M7 | 反爬类型1（图片验证码） | `Dialog.showInputDialog(title, validator, image)` 能显示图片并收输入 | ⚠️ 部分：`_buildDialogImage` 用 `Image.network(url)`，**不带 headers**（防盗链图可能白屏且失败静默）；**无页面内填写/提交接口**（`CaptchaWebviewController` 只有 init/parseHtml/getCookieString/unloadPage/dispose）、**无「验证通过」信号**；插件只能自己取图、自己构造提交请求 |
| M8 | 反爬类型2（自动点击按钮） | 把点击塞进 `waitFor:{type:'js',value:"(document.querySelector('.x').click(), document.querySelector('.ok')!=null)"}`：该表达式被**在页面内反复求值**（Windows：页面内 watcher 每 150ms 自轮询，Dart 侧每 300ms 重注入；Android/iOS/macOS：Dart 侧每 250ms `evaluateJavascript`） | ⚠️ 机械可行：这是**等待条件**通道，非脚本通道；无返回值、无日志回传、表达式重复执行（须写成幂等）；换条件只能靠 `unloadPage`（失败是静默吞的） |
| M9 | 反爬类型3（自定义 JS） | 同 M8 的注入点；**没有** `KazumiCaptcha.done/log` 这类协议，也没有「注入脚本读回结果」的接口 | ⚠️ 部分（可注入副作用，拿不回结果） |
| M10 | 反爬「检测→验证→回灌」框架 | 逐条可拼：`backend:'auto'`（403/429/5xx/超时/断连自动降级无头 WebView）+ `webview_html` + 图片输入框 + 等待条件注入 + Cookie 自动同步 | ⚠️ 能实现但全由插件编排；宿主无「挑战页检测→来源标记→引导验证→HTML 回灌」流程（**「来源标记」在 wyw 侧未证实**） |
| M11 | 每插件 `adBlocker` | 只有全局 `forceAdBlocker`，过滤在播放引擎 `hls_ad_filter` | ❌ G2 |
| M12 | `useLegacyParser` | 双解析器实现仍在，但**接口层无入口**：`loadUrl`/`resolve` 均无该参数、`video_webview_impl.dart:14` 字段无赋值点、唯一带该参数的 `VideoSourceResolverPool` 全仓无调用方且 worker 内丢弃 | ❌ G1（Kazumi 真透传：`video_controller.dart:606-609`） |
| M13 | 播放/下载请求头（`userAgent`/`referer`） | 四条通道全堵：`PlayResourcePath`/`fromResolveResult` 无 headers；直链播放写死 `{'user-agent': getRandomUA()}`+`referer:''`；代理与下载写死默认头；插件入口不收 headers | ❌ G5 |
| M14 | 导入/导出/分享 | 本地 bundle（`{format,version,plugins:[{name,content}]}`，容忍裸数组/单对象）+ 文件多选导入 + 剪贴板导入/导出 + 野文件认领 | ⚠️ 部分：无 `kazumi://` 链接、**无在线订阅/更新**，且 `Plugin.toJson` 不含 `version` → 无版本比较的数据基础 |
| M15 | 编辑器/测试 | 插件管理页（导入/启停/排序/分类/改源码/管理属性）+ 真引擎测试台（预载 `assets/plugin/*.js`，async，90s 超时） | ✅ 更强 |
| M16 | 有效性 | `PluginPresence{loaded,disabled,failed,missing,deleted}` + `loadError`/`fileMissing` + 能力探测缓存 | ✅（语义不同：判文件与注册结果，不判「本次启动搜索成功过」） |
| M17 | 插件设置项（Kazumi 无） | `getSettings()`/`settings` schema → 宿主表单（select/input/password/switch/callback）→ 持久化 | ✅ wyw 独有 |
| M18 | 插件私有数据（Kazumi 无） | `loadData/saveData/deleteData` | ✅ wyw 独有 |

**快速验证过的关键链路**（可直接重放）：
- JS→播放：`assets/js/init.js:1749-1771` → `js_bridge.dart:207-232` → `lib/pages/init_page.dart:352-379` → `lib/services/storage/video_play_model.dart:161-188` → `lib/services/video_source/resolution_service.dart:43-65` → `webview_video_source_service.dart:79-141`。
- 反爬取页：`init.js:680-717` → `js_bridge.dart:205-206` → `js_network.dart:369-412` → `lib/webview/captcha/**`；现有插件已在用（`assets/plugin/hanime.js:50-55` 明确注释「用 Network.getHtml 绕过 Cloudflare」）。

---

## §4 缺口清单

### 4.1 需改宿主才能对齐 Kazumi（按优先级）

| 编号 | 缺口 | 证据 | 建议 |
|---|---|---|---|
| G1 | `useLegacyParser` 接口层无入口 | `lib/webview/video/video_webview_controller.dart:86`；`webview_video_source_service.dart:28-32,101-104`；`video_source_resolver_pool.dart:6,110-125,145-156`（无调用方 + 丢弃参数）；`video_webview_impl.dart:14`（恒 false） | 有站点需要 legacy 时接通「每插件/每集」开关；否则删死代码 |
| G5 | 无法为最终媒体/下载请求声明 headers/referer/UA | `video_play_model.dart:33-75,84-97`；`lib/pages/video/video_controller.dart:748-750,771`；`playback_proxy_service.dart:165-166`；`lib/pages/video/video_entry_launcher.dart:50-55` | 在 `PlayResourcePath`/`VideoPlaySource` 加 headers 透传到播放与下载（对有防盗链的源是刚需） |
| G2 | 无每插件广告过滤声明 | `lib/pages/download/download_controller.dart:569,869-878`；`video_controller.dart:696-703` | 资源描述或插件设置里加 per-plugin 开关 |
| G3 | 无在线分发，且缺 `version` 字段 | `lib/plugins/**` 检索 `shop/catalog/subscription/needUpdate` 零命中；`lib/plugins/plugin.dart:438-445`（toJson 只 6 字段） | 远程目录 + 版本比对前，先把 `version` 存进索引（Kazumi 参考：`plugin_catalog_api.dart:11-63`、`plugins_controller.dart:360-366`） |

### 4.2 健壮性/一致性风险（wyw 自身）

| 编号 | 风险 | 证据 | 影响 |
|---|---|---|---|
| G7 | 无脚本超时/内存栈上限/权限模型；插件加载即拥有全部接口 | `lib/js/base_js_engine.dart:28`（`FlutterQjs()` 无参）；`lib/js/entity/js_entity.dart:94-151`（无 timer）；`js_network.dart:56`（任意 URL） | 死循环/大分配可卡住宿主；无域名白名单 |
| G8 | **无 UA 对齐闭环**（反爬最易踩） | headless WebView UA 随机（`lib/webview/captcha/impl/captcha_webview_inappwebview_impl.dart:27`）；Dio UA 另一次随机（`lib/request/core/dio_factory.dart:15-19`）；全仓无 `getUserAgent` | WebView 过墙拿到的 clearance cookie 与 UA 绑定，后续 Dio 请求 UA 不同 → 可能被再次挑战（Kazumi 专门做了闭环） |
| G9 | 插件间 Cookie 默认共享 | `lib/js/js_extends/js_bridge.dart:159`（`JsNetwork` 是引擎级单例）+ `js_network.dart:359-367`（默认会话 `''`） | 插件 A 的同域 Cookie 会漏给插件 B；可让插件显式传 `session` 规避 |
| G6 | 无请求取消、不走代理、不忽略证书 | `lib/js/js_extends/js_network.dart:298`（`cancel` 仅分类）；`lib/request/core/network_config.dart:5-58`（无 proxy 字段、`allowBadCertificates` 无赋值点） | Kazumi 有代理 + 代理下放宽证书；wyw 的 JS 网络层两者皆无 |

### 4.3 wyw 自身的「文档有、代码无」

`compute()`（`init.js:1885-1891` vs 宿主无分支）；`Image.*` 在插件引擎不可用（只在 `lib/pages/comic_reader/image/image_utils.dart:130-207` 的隔离引擎）；`isLogged` 恒 false；`APP.version` 恒 `''`；`UI.Image.headers` 被解构丢弃；元素级 XPath 死代码；`UI.Action` 返回值被丢弃。`docs/venera-plugin-adaptation.md` 还把 `getLocale`/`APP.locale` 标为「已实现」，而代码里根本不存在（该文件自身前后矛盾）。

---

## §5 wyw 更强的部分（一句话汇总）

任意逻辑与多步请求、签名/加解密（utf8/gbk/base64/md5/sha1/sha256/sha512/hmac/aes-ecb/cbc/cfb/ofb/rsa 解密/hex）、任意请求头与每请求超时/重试/重定向策略、结构化网络错误、`backend:'auto'` 自动降级、文档级 XPath+CSS+树导航+属性/文本/innerHTML 提取、播放资源四态契约、插件自带 UI（24 原语+分页+详情页）、插件设置项与私有存储、真引擎测试台、搜索分页（Kazumi 无）。

---

## §6 落地建议：把 Kazumi JSON 规则迁成 wyw JS 插件

机械映射表（`usePost` → `httpMethod:'POST'`；API/JSONPath → `JSON.parse`；反爬 → `backend:'auto'` + `showInputDialog{image}` + `waitFor{type:'js'}` 等），唯一需要宿主先补的是 **G1/G2/G3/G5** 四项。

若短期不想动宿主，可用 JS 侧绕过的部分：
- **G2**：插件在返回播放源前自行拉一次 m3u8 并剔除广告分片——但 wyw 过滤在播放引擎侧，插件只能改地址或干脆不处理（建议还是补宿主开关）。
- **G5**：插件可用 `resolve` 方法在播放前把带 Referer 的媒体请求"验活"或转成自身可控的直链，但**无法改变播放器最终拉的请求头**——不要用这个当长期方案。
- **G8**：插件在 `webview_html` 之后自行用 `webView UA` 无法取得（无接口）→ 只能依赖站点不绑定 UA；有绑定倾向的站点建议优先用 `type:'page'`（交宿主嗅探）而不是 WebView 取 HTML 后 Dio 直连。
- **G4**：建议保持「插件自负其责」——wyw 原语组合比 Kazumi 的三固定类型更通用。

---

## §7 证据与可信度

- 三条独立证据链：`kazumi-inventory.md`（Kazumi 侧，283 行，全部带 file:line）、`wyw-bridge.md`（wyw 侧，516 行，70 入口逐项 + 负证据检索清单）、`verifier-probe.md`（独立核查 7 项高风险能力，345 行，附可重放命令）。
- 对抗核验（`verification-report.md`）：25 条结论中 21 条「代码确证」、1 条「间接推断」（wyw headless WebView 与宿主可见 WebView 共享 profile cookie——依赖第三方包与 WebView2 语义，未实机验证）、2 条「未证实」（「可覆盖 Kazumi 三种验证类型」「wyw 有验证来源标记」）、1 条已降级（M7）。
- 本报告已按核验结论修正 8 条断言与 5 处计数/行号。

**仍待实机验证的 3 点**：① wyw headless WebView 与宿主可见 WebView 的 Cookie 共享（影响"登录态复用"结论）；② G8 的 UA 失配在真实 Cloudflare 站点上的实际影响；③ 用 `waitFor{type:'js'}` 做自动点击在真实站点上的成功率（无现成插件示例）。
