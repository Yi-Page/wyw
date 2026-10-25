# Pixiv 插件：pixiv-viewer 功能迁移说明

> 本文记录 `D:\code\java\pixiv-viewer`（Vue 版 Pixiv Viewer Kai）的功能盘点，以及
> 迁移到 wyw 后的落点：**哪些进搜索模块、哪些进浏览页、哪些只保留在详情/阅读器**。
>
> 实现文件：`assets/plugin/pixiv.js` · 出厂配置：`assets/plugin/index.json`

---

## 一、pixiv-viewer 的搜索能力盘点

### 1. 插画 / 漫画 / 动图（搜索主路径）

| 维度 | 支持值 | 说明 |
|---|---|---|
| 关键词 | 多词、空格分词、`-标签` 排除 | 与 Pixiv 搜索一致 |
| 匹配方式 | `partial_match_for_tags`（部分标签）/ `exact_match_for_tags`（完全标签）/ `title_and_caption`（标题与简介）/ `keyword`（关键词） | 默认部分标签 |
| 排序 | 最新 / 最早 | `date_desc` / `date_asc` |
| 内容类型 | 插画 + 漫画 + 动图 / 插画 + 动图 / 插画 / 动图 / 漫画 | `content_type` |
| 时间范围 | 近一天 / 近一周 / 近一月 / 近半年 / 近一年；自定义开始/结束日期 | `start_date` / `end_date` |
| R18 | 显示 / 隐藏 / 仅 R18 | 客户端拼 `R-18` / `-R-18` 并二次过滤 `x_restrict` |
| AI | 显示 / 隐藏 | `search_ai_type=1` + `illust_ai_type==2` 过滤 |
| 尺寸 | 3000px 以上 / 1000–2999px / 999px 以下 | 映射 `width_min/max`、`height_min/max` |
| 比例 | 横图 / 竖图 / 方图 | `ratio_pattern` |
| 作画工具 | SAI、Photoshop、CLIP STUDIO PAINT、Procreate 等数十种 | `tool` |
| 语言 | 仅漫画内容可选 | `lang` |
| 收藏数门槛 | `100/500/1000/5000/10000/30000 users入り` | 关键词追加 `N users入り` + 客户端按收藏数过滤 |
| 其他 | `include_potential_violation_works`、最低收藏数、屏蔽标签/用户、safe search | 客户端过滤 |
| 快速预览 | 关键词「热门预览」前 30 条（按收藏排序） | `/popular_preview` |
| 搜索热词 | 趋势标签（带封面） | `/tags` |
| 自动补全 | 标签自动补全 | `/search_autocomplete` |
| ID / URL 直达 | 纯数字 → 作品/小说/画师/特辑选择；粘贴作品/画师 URL 直接跳转 | 搜索页逻辑 |
| 以图搜图 | 上传图片 → SauceNAO | `/api/sauce/` |

### 2. 小说搜索

| 维度 | 支持值 |
|---|---|
| 关键词 | 多词、排除标签 |
| 匹配方式 | 部分标签 / 完全标签 / 正文 / 关键词 |
| 排序 | 最新 / 最早 |
| 时间 | 近一天/周/月 + 自定义日期 |
| R18 / AI | 显示、隐藏、仅 R18 |
| 阅读时长 | 10–59 分 / 60–179 分 / 180 分以上 |
| 文本长度 | <5000 / 5000–19999 / 20000–79999 / 80000+ 字 |
| 类型（genre） | 恋爱、异世界奇幻、现代奇幻、悬疑、恐怖、科幻、文学、生活、历史、BL、百合等 18 类 |
| 语言 | 日语、简中、繁中、英语、韩语等 |
| 热门预览 | 前 30 条 |

### 3. 用户 / 珍藏册

- 用户搜索：关键词 → 画师预览卡片（头像 + 近期作品）。
- 珍藏册搜索：按标签、安全模式检索合集。
- 用户详情：关注/取关、作品/漫画/小说/收藏/系列、系列列表、常用标签、相关画师、Twitter 媒体。

### 4. 排行榜与推荐

- 综合 / 插画 / 动图 / 漫画 / 小说排行。
- App 排行模式：日、周、月、新人、原创、男性向、女性向、R18、R18G。
- Web 排行可指定历史日期；小说排行单独接口。
- 推荐：推荐插画、推荐漫画、推荐小说、首页 Feed、最新作品、热门/发现、相关作品、相关画师、推荐画师、Pixivision 特辑、直播。

### 5. 作品页 / 阅读

- 多页插画逐页浏览、Ugoira 动图播放、标签、作者、浏览/收藏/评论数、简介。
- 收藏/取消收藏、关注作者、评论与回复、分享、源站链接、复制 ID。
- 多格式下载（Ugoira ZIP/GIF/WebM/APNG/MP4/AVIF）、漫画翻译、小说阅读器与翻译。

---

## 二、迁移到 wyw 的落点

### 2.1 搜索模块（`search(keyword, page)`）

只保留**纯关键词搜索**，和 pixiv-viewer 搜索框的默认行为一致：

- 多词 / 排除标签原样传给 Pixiv。
- 纯数字：先尝试作品 ID 直达；失败再按关键词搜索。
- 粘贴 `pixiv.net/artworks/<id>`、`pixiv.net/users/<id>` 链接：直接打开对应详情。
- 自动附加插件设置里的 R18 排除词，并按设置过滤 R18 / AI / 最低收藏 / 屏蔽标签。
- 分页由 wyw 搜索页的「加载更多」驱动（`search(keyword, page)` 每次 30 条）。

### 2.2 浏览页（`getCategory` + `getCategoryOptions` + `loadCategory`）

这是本插件与 pixiv-viewer 差异最大的地方：**所有「非纯关键词」入口都收进浏览页**，
因为 wyw 搜索框没有筛选栏，而浏览页分类可以弹**下拉/输入筛选框**。

| 分组 | 分类 | 说明 |
|---|---|---|
| 快捷入口 | **ID 直达** | 下拉选作品 / 画师 / 小说 / 系列，输入纯数字 ID 直接打开详情（对应 pixiv-viewer 的纯数字弹窗和 URL 直达） |
| 快捷入口 | **画师作品** | 画师 ID + 插画/漫画，分页列出该画师作品 |
| 快捷入口 | **画师搜索** | 关键词 → 画师卡片 → 画师详情 |
| 快捷入口 | **相关作品** | 作品 ID → 相关推荐（接口不可用时按首个标签搜索兜底） |
| 发现 | **推荐插画** / **推荐漫画** | 对应「个性化推荐 / 热门推荐」；公共实例不可用时回退日榜 |
| 发现 | **热门预览** | 关键词语义下的前 30 条热门作品（按收藏排序），对应搜索页的「热门预览」 |
| 发现 | **热门标签** | 对应搜索页趋势标签墙；点标签直接打开搜索结果页 |
| 排行榜 | **综合 / 插画 / 漫画 / 小说排行** | 对应多维度排行；周期 + 历史日期可筛选 |
| 搜索 | **高级搜索** | 关键词 + 匹配方式 + 排序 + 内容类型 + R18 + AI + 时间范围 + 最低收藏（8 组筛选） |
| 搜索 | **更多筛选** | 关键词 + 起止日期 + 尺寸 + 比例 + 作画工具（20 个常用项）+ 语言 + 收藏数标签（8 组筛选） |
| 搜索 | **标签搜索** | 标签/关键词 + 排序 + R18 |
| 搜索 | **小说搜索** | 关键词 + 匹配方式 + 排序 + 类型 + 语言 |

> 公共 API 实例不支持高级查询参数时，插件会**退回纯关键词搜索并在本地过滤**
> （内容类型、日期、尺寸、比例、R18、AI、收藏数、完全标签/标题匹配），保证筛选仍有结果。
> 这是对公共实例限流/未授权的降级，不是接口语义的替代。

### 2.3 详情 / 阅读 / 历史

| pixiv-viewer | wyw 插件实现 |
|---|---|
| 作品详情（封面/标题/作者/浏览/收藏/尺寸/标签/简介） | `getDetail(id)` 描述符头部 + 元信息 + 标签按钮 + 简介 |
| 多页插画 / 漫画 | 一件作品 = 一个章节，多页图逐页进 wyw 漫画阅读器 |
| 系列作品 | 系列内每部作品 = 一个章节，详情页可「查看系列」并连续阅读 |
| 相关作品 | 详情页按钮 → `getRelatedWorks` 分页页 |
| 作者作品 | 详情页按钮 → `getUserWorks` 分页页（画师详情含最近作品） |
| 浏览历史 | `PluginBrowse.open` + `onOpenBrowseEntry` 回放 |
| 图片防盗链 | `getImageLoadingConfig` 附 `Referer: https://www.pixiv.net/` 与 UA |
| 小说 | `getNovelDetail` / `openNovelReader` / `loadChapterContent`（读纯文本正文） |
| Ugoira 动图 | 阅读器仅显示静态封面，详情页提示「打开源站看动图」 |
| 收藏 / 关注 / 评论 / 分享 / 下载 / 翻译 | 未迁移，见「不能迁移的部分」 |

### 2.4 插件设置

| 设置 | 默认 | 说明 |
|---|---|---|
| `api_base` | `https://api.cocomi.eu.org` | HibiAPI/PxveAPI 兼容实例；公共实例部分接口不可用，建议自建 |
| `image_proxy` | `i.pixiv.re` | 图片代理；也可填自建 PxveAPI 的 `https://<host>/pximg` |
| `quality` | `large` | `large` = 600×1200 自适应（快）；`master` = 1200px 全画面（需代理支持 `img-master`）；`original` = 原图（需代理支持） |
| `r18` | `0` | 隐藏 / 显示 / 仅 R18 |
| `ai` | `1` | 显示 / 隐藏 AI 作品 |
| `min_bookmarks` | `0` | 最低收藏数过滤 |
| `blocked_tags` | 空 | 逗号分隔的屏蔽标签 |

---

## 三、不能迁移 / 只保留在源站的部分

| pixiv-viewer 功能 | 不迁移原因 | 替代 |
|---|---|---|
| 搜索自动补全 / 搜索历史 / 热词建议条 | wyw 搜索框只有关键词 + 历史，没有 suggestion 协议 | 热词做成浏览页「热门标签」；历史由宿主维护 |
| 以图搜图（SauceNAO） | 插件 JS API 没有文件选择/ multipart 上传 | 可在浏览器打开 SauceNAO（未内置） |
| RefreshToken / OAuth / Cookie 登录 | wyw 无账号中心；插件可存 token，但未做登录 UI | 自建带 `PIXIV_ACCOUNT_TOKEN` / `PIXIV_COOKIE` 的 API 实例 |
| 收藏 / 关注 / 评论 / 分享 | 依赖登录态与宿主账号 UI | 用源站网页版操作 |
| 个性化推荐（关注新作、推荐用户） | 需要登录 token；公共实例不可用 | 自建实例后由 `/illust_recommended` 等接口提供 |
| Ugoira 动图播放 | wyw 漫画阅读器只处理静态图片，没有帧时序播放能力 | 详情页跳源站 |
| 漫画翻译 / 小说富文本与翻译 / 多格式下载 | 属于宿主阅读器能力，不是数据源能力 | 保留在 pixiv-viewer / 源站 |
| 珍藏册 / 直播 / Pixivision 特辑 | Web 页面与专用接口，公共实例多不可用 | 可后续加 WebView 入口 |
| 多 API 实例 / 图床切换 / 主题 / 布局 / 云同步 | 宿主设置项，不属于单个插件 | wyw 全局设置 |

---

## 四、公共 API 实例的现状（重要）

默认实例 `https://api.cocomi.eu.org` 是 PxveAPI 的公开部署。PxveAPI 上游账号已被封禁，
公开实例目前**只有一部分匿名接口稳定**：

- ✅ 关键词搜索（`/search`，`word`/`page`）
- ✅ 排行（`/rank`）、热门标签（`/tags`）、用户搜索（`/search_user`）
- ✅ 作品详情（`/illust`）、画师详情（`/member`）
- ✅ 小说详情（`/novel_detail`）
- ❌ 小说正文（`/novel_text`、`/webview_novel`）：当前返回 400 `Not Accepted`（上游需要 `PIXIV_COOKIE`，公开实例被 ban）
- ⚠️ 高级搜索参数、推荐、最新、画师作品、相关作品、小说排行：时而 200、时而 400/500

插件已针对这些情况做降级：

1. 高级搜索失败 → 纯关键词 + 本地过滤；
2. 推荐接口失败 → 日榜；
3. 画师作品失败 → 按画师名搜索并过滤 `user.id`；
4. 相关作品失败 → 按作品首个标签搜索；
5. 小说正文 `/novel_text` 失败 → 尝试 `/webview_novel`；仍失败时提示自建 API（配置 `PIXIV_COOKIE`）或点「源站」阅读；
6. 都失败时显示可读的错误文案，不崩溃。

要恢复完整能力，自建一个带 Pixiv 登录态的 PxveAPI/HibiAPI，把 `api_base` 指向它即可：

```env
PIXIV_ACCOUNT_TOKEN=<refresh token>
PIXIV_COOKIE=<PHPSESSID=...>
```

---

## 五、验证方式

```bash
# 静态检查（类名 / 必需方法 / 未定义成员 / UI 类型）
node tools/check_plugins.js pixiv

# 小说阅读器参数 / 正文兜底回归（离线，不联网）
node tools/verify_pixiv_novel.js
```

实测结果（2026-10-24，公共实例）：

- `pixiv`：PASS 13 / FAIL 0（搜索 29–30 条、详情、单页图 600×600）
- 额外分支：ID 直达、排行、热门标签、推荐回退、画师搜索、小说搜索、小说详情、
  多页作品（2 页）、相关作品标签兜底均通过。
- 小说正文：`node tools/verify_pixiv_novel.js` 5/5 通过（离线 mock 章节参数、正文 ID、
  `/webview_novel` 兜底）；公共实例的 `/novel_text` 与 `/webview_novel` 均返回 400
  `Not Accepted`，需要自建实例才能读到正文。
- 公共实例上：`rank_novel`（小说排行）仍返回 500；`member_illust`（画师作品）
  不稳定，可能退化为「按画师名搜索」；推荐/相关已回退到日榜/标签搜索。
  需要完整能力时请自建实例。

---

## 六、出厂配置

`assets/plugin/index.json` 已追加：

```json
{
  "name": "pixiv",
  "enabled": false,
  "displayName": "Pixiv",
  "categoryId": "manga",
  "homepage": "https://www.pixiv.net/",
  "description": "Pixiv 插画/漫画/小说源 — 关键词搜索 / ID 直达 / 推荐与排行 / 参数化搜索 / 详情 / 阅读"
}
```

与其它内置插件一样默认禁用。全新安装时会作为「待导入」出现在插件管理页；
已有安装可把 `assets/plugin/pixiv.js` 复制到 `{appSupportDir}/plugins/`，
在插件管理页刷新/导入后启用。
