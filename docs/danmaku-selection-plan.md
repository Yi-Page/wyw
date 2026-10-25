# 弹幕选择重构计划

> 状态：M0 / M1 / M2 / M4 / M5 已交付（M3 已并入 M1；旧匹配记忆层已删除）。
> 前置分析见 `docs/danmaku-analysis.md`（Kazumi 对照接入方案，M1–M5 已落地）。

## 0. 本次要解决的问题

现状：用户在播放页手选弹幕库后，**重新播放同一集时会退化成"未匹配"**，必须重新搜索选择。
根因见 §4（命中不显示 + 记忆 key 绑线路下标）。本次把"选择"这件事整体重做。

## 1. 口径（已与产品确认）

| 项 | 决定 |
|---|---|
| 持久化落点 | **进度记录**（`HistoryEntry.progress` 里的 `VideoPlaybackProgress`），不新开 Hive 箱 |
| 持久化内容 | **只有弹弹play 条目信息**：搜索拿到的 `imageUrl`/`animeTitle`，详情拿到的 `intro`/`summary`/`rating`/`bangumiId`/`episodeCount` |
| 刷新 | 卡片上的按钮 → 重新请求 `/bangumi/{id}` → 更新简介/封面/评分/集数并回写进度记录 |
| 分集匹配 | **不持久化**。只做"展示库的分集列表 → 点一集 → 作为当前集使用的弹幕"。**切集后需再点一次**（已确认接受） |
| 下载抓弹幕 | 保留为**设置选项**（`SettingsKeys.downloadDanmaku`，默认 true，此前无 UI 开关），抓取逻辑随本次一起重构（见 §5） |
| 旧匹配记忆层 | **删除**（`danmakuMatch` 箱、`DanmakuMatchRepository`、`remember/forget/loadFromMemory`）。磁盘上的旧箱文件保留不动 |

## 2. 明确不做

| 不做 | 实测理由 |
|---|---|
| `/api/v2/search/adv` | 现有 AppId（`sw7pmhj28t`）在**签名模式与凭证模式**下、所有参数组合都返回 `errorCode=11 验证用户权限失败`；`/search/adv/config` 可通但搜索本体被门禁 |
| `/api/v2/search/tmdb` | 可用（40 条，无 25 上限）但 `episodeCount` 恒为 1，且其命名空间的 `episodeId` 取弹幕为 **0 条**（实测 `/bangumi/tmdb-tv-30983` → `/comment/2030983010001` = 0 条）。混入候选会让"集数吻合度"信号失效并按选中取不到弹幕 |
| 自动匹配 | 无 bgm 条目体系；猜错代价是显示别人的弹幕 |
| 本地集↔库集映射表 | 本轮不做（扩展点见 §6） |

## 3. 接口能力矩阵（本机实测，AppId `sw7pmhj28t`）

| 接口 | 可用 | 条数 | 简介 | 指向弹幕库 |
|---|---|---|---|---|
| `/api/v2/search/anime?keyword=&v2=true&type=` | ✅ | **硬上限 25**，不可翻页 | ❌ | anidb ✅ |
| `/api/v2/search/episodes?anime=&v2=true` | ✅ | 57 部（`hasMore=true`） | ❌ | anidb ✅ —— **已不再使用**（M5 按反馈删掉「剧集搜索」兜底入口，条数多的优势抵不过"不带封面/年份/集数"） |
| `/api/v2/bangumi/{bangumiId}`（数字 animeId 或 `tmdb-tv-xxx`） | ✅ | 柯南 1372 集 / 226 KB | ✅ `intro`+`summary` | anidb ✅ |
| `/api/v2/comment/{episodeId}?withRelated=true` | ✅ | 288 KB / 4330 条（柯南第 1 话） | — | — |
| `/api/v2/search/adv` | ❌ errorCode 11 | — | 理论上有 | — |
| `/api/v2/search/tmdb` | ✅ | 40 | ❌ | TMDB ❌ 空库 |
| `/api/v2/search/tag?tags=` | ✅ | 6 | ✅ | anidb（但只能按数字标签搜） |

关键推论：

1. **25 条上限会把主系列挤出结果**。搜"柯南"不传 `type` → 25 条里只有 3 条 tvseries（其余 18 部剧场版），主系列 `animeId=266`（1220+ 集）**不在其中**；传 `type=tvseries` → 6 条，主系列在内。→ 类型筛选是必需功能，不是装饰。
2. 简介只能来自 `/bangumi/{id}`（`intro`/`summary`），而这次请求本就是拿 `episodeId` 的必经之路，不额外增加请求。
3. anidb 侧 `seasons` 恒为空（柯南 1372 集 `seasons=0`；TMDB 侧才有 seasons=2）→ 分集列表**不能**按季分组，只能长列表 + 筛选。
4. `episodeNumber` 可能含字母（`"1"` … `"C146"`），标题繁简混排 → 任何"按集号自动定位"只能作为**建议**，不得自动应用。
5. 详情响应体可达 226 KB → 必须按会话缓存，避免来回切条目重复请求（官方亦建议搜索结果缓存 2–6 小时）。

真实响应样本（用于单测 fixture）：`.danmaku-swagger/samples/`。

## 4. 现状缺陷（本次一并修掉）

1. **命中记忆后不显示**：`applyDanmakuLoad(enableDanmaku: GStorage.getSetting(danmakuEnabledByDefault))`，而该键默认 `false` 且**全项目没有任何 UI 能改**；只有手选那一次硬编码 `true`。→ 现象与"没记住"完全一致。
2. **记忆 key 绑线路下标**：`l|…|s{sourceIndex}` / `e|…|s{sourceIndex}`，换线路或插件重排集即失忆。
3. `forget()`（清除匹配）是死代码，选错无法清除。
4. `DanmakuBangumiDetail` / `DanmakuEpisodeRef` 把设计需要的字段全丢了（简介/评分/多语言标题/播出日期）。

## 5. 持久化设计

### 5.1 进度记录字段

在 `VideoPlaybackProgress`（`lib/services/storage/history_progress.dart`）上新增：

```dart
/// 当前作品选用的弹弹play 弹幕库条目（作品级）。分集选择刻意不持久化。
final DanmakuLibraryRef? danmaku;
```

`DanmakuLibraryRef`：`animeId` / `bangumiId` / `libraryTitle` / `imageUrl` / `intro` / `summary` / `rating` / `episodeCount` / `savedAtMs`，`toMap`/`fromMap` 容错（缺字段退化、不抛）。`toMap` 无该字段即视为"未选"，**旧记录天然兼容**。

- 写：用户**点定某一集**（那一下同时就是"确认用这个库"，没有独立的"使用这个库"按钮）或点「刷新」→ `VideoPageController.setDanmakuLibrary` 更新内存字段 → 立刻 `notifyProgressChanged()`（不等进度 tick），走既有 `onProgressChanged` → `setProgress`。没有进度记录可写时（下载入口反查不到记录 → `onProgressChanged` 为 null）只在本会话生效并记日志，不产生残缺记录。
- 读：`configure()` 已在读 `HistoryEntry`，在同一处取出并注入 `PlayerDanmakuController`。
- 边界：`writable == false`（下载入口反查不到进度记录，`onProgressChanged` 为 null）时，选择**只在本会话生效**并记日志，不产生残缺进度记录（与既有约定一致）。

### 5.2 下载抓弹幕的重构

删除记忆层后，下载抓弹幕改为**运行时按集号推导**，不引入新的持久化：

```
下载完成 → 开关开启（downloadDanmaku）
        → 读该作品进度记录里的 danmaku（库条目）
        → 请求 /bangumi/{id} 取分集列表（会话内缓存）
        → 用本地集名解析集号（utils/media.dart extractEpisodeNumber）
          与库集 episodeNumber 匹配 → 命中则抓弹幕写 danmaku.json
        → 未命中/解析不到 → 跳过并记日志（静默，不影响已完成的下载）
```

共用纯函数 `matchLocalEpisodeToLibrary(localName, episodes)`，与 M3 的"分集列表默认定位建议"同源，便于单测。
风险：库集与源集号体系不一致时会抓错集；缓解是"仅当集号可解析且库侧存在同号集才抓"，且此行为受设置开关控制。

离线播放仍优先读 `danmaku.json`（下载产物，不是匹配记忆），这条链路不变。

> 已按此实现（M4）：纯函数在 `lib/services/danmaku/danmaku_episode_matcher.dart`，
> 调用点在 `DownloadController._cacheDanmakuForOffline`。

### 5.3 设置项

`downloadDanmaku` 默认 `true` 但**从无 UI**——本次在「弹幕设置」tab 补一行开关（放"弹幕库"分组）。

## 6. 后续扩展点（本轮不做）

想恢复"切集自动沿用"时，只需在同一个 `danmaku` 字段里加：

```dart
/// 本地集索引 → 库集索引（用户显式关联过才有）
final Map<int, int> episodeMap;
```

不改箱、不改读写路径、不动 UI 骨架。这就是本轮把持久化收进进度记录的价值。

## 7. 里程碑

### M0 面板拆两个 tab
- `SplitPanelTab` 增 `danmakuSettings('弹幕设置')`，顺序：`选集 / 弹幕 / 弹幕设置 / 画面 / 播放 / 更多`（`CapsuleTabStrip` 本就 `isScrollable`）。
- 原 `tab_danmaku.dart` → `tab_danmaku_settings.dart`（类 `DanmakuSettingsTab`），去掉「弹幕检索」行。
- 新 `tab_danmaku.dart`（类 `DanmakuTab`）= 选择页；M0 先显示当前库状态 + 「搜索弹幕库」入口（暂指向旧二级页，M1 换成内联搜索页后删除旧入口）。
- 验收：6 个 tab 可滚动切换，设置项无回归。

### M1 搜索 + 选分集（已交付）
- 接口/模型：`getBangumiDetail` 参数放宽为 `String`（数字 animeId 或 `tmdb-tv-xxx` 都收）；`DanmakuBangumiDetail` 补 `bangumiId`/`intro`/`summary`/`rating`/`isOnAir`/`titles`/`tags` 与 `displayIntro`；`DanmakuEpisodeRef` 补 `airDate`/`seasonId`/`lastWatched` 与 `airDateLabel`；`DanmakuSearchAnime` 补 `year`。
- 搜索页（内联在「弹幕」tab，`pages/player/danmaku_selection/`）：搜索框（预填剧名）+ **类型下拉**（全部/TV/剧场版/OVA/其它，走服务端过滤；M5 起与搜索框**同行**）+ 候选列表（封面/标题/类型·年份·集数·评分）+ **详情卡**（封面/多语言标题可点标题切换/简介可展开/评分/标签；与列表并存，可继续切条目）+ **25 条上限的显式提示** + 会话内缓存（按 `(关键词,类型)` 与 animeId）。
  > 候选列表**不显示匹配度**、也不按自算分重排（M1 时曾有，M5 后按反馈删除）：顺序就是弹弹play 自己的相关度排序。原因见 §M5。
- 分集列表：筛选框 + `ListView.builder`（实测柯南 1372 集），点一集即取该集弹幕并应用。
- 入口收敛：顶栏弹幕按钮（未匹配点击 / 已匹配长按）改为切到「弹幕」tab；删除 `danmaku_source_sheet.dart`、`widgets/danmaku_source_content.dart`、`SplitSubPage.danmakuSearch`、`DanmakuSearchSubPage`；`danmaku_source_sheet_models.dart` 更名 `danmaku_candidate_models.dart`。
- 顺手修掉 §4.1「命中记忆却不显示」：命中匹配记忆、命中离线缓存一律 `enableDanmaku: true`。
- 单测：`.danmaku-swagger/samples/` 的真实响应留档作参照，用例沿用仓库既有写法（手写 JSON，字段与取值抄自实测响应）：简介/评分/多语言标题/标签/季度/播出日期 + 脏数据回退 + 类型筛选枚举 + 年份解析。
- 验收：搜"柯南"默认 25 条并提示上限，切 TV 能搜到 `animeId=266`；点条目出详情卡；点分集立刻出弹幕；`flutter analyze` 无问题、`flutter test` 全绿（含 280×420 面板下新页签不溢出）。

### M2 条目信息持久化 + 「当前使用」卡片 + 刷新（已交付）
- 新增 `DanmakuLibraryRef`（`modules/danmaku/danmaku_library_ref.dart`）：`animeId`/`bangumiId`/`libraryTitle`/`imageUrl`/`intro`/`summary`/`rating`/`episodeCount`/`savedAtMs`，含 `fromDetail`（点选与刷新共用一条构造路径）、`refreshableId`、`displayIntro`、`isValid` 与容错 `fromMap`。
- `VideoPlaybackProgress.danmaku`：跟随进度一起写盘；旧记录无此字段 → `null`；字段存在但为空壳/脏数据 → 也视作"没选过"（不显示空白卡片）。
- 写入：点定某一集后 `videoPageController.setDanmakuLibrary(ref)` **立即**写一次进度（不等 tick）；换作品时 `configure()` 先清零，避免控制器复用串台。
- 读回：`_applyHistoryProgress()` 从进度记录取出 → 「弹幕」tab 顶部状态行与「当前使用」卡片直接显示（断网也能显示，因为存的是展示快照）。
- 「当前使用」卡片：封面/标题/简介/评分/集数 + 「刷新」+「选择分集」；用户点了候选就换成候选详情卡（同一个顶部位置，窄面板才放得下列表）。
- 「刷新」：绕过会话缓存重请求 `/bangumi/{refreshableId}`，用新数据覆盖卡片并交回外壳回写进度；失败只 toast，不破坏已有快照。
- 单测：`DanmakuLibraryRef` 往返/脏数据/`fromDetail` 口径，`VideoPlaybackProgress` 含与不含 `danmaku` 的读写（`test/danmaku_library_ref_test.dart`）。

### M3 分集选择（已并入 M1）
原计划的"分集列表 + 点一集即用 + 修 `enableDanmaku`"三项都随 M1 落地。唯一没有做的是"当前集的库集高亮记忆"——按口径**刻意不持久化**：切集后回到"未选择"，需再点一次（已确认接受）。

### M4 清理旧记忆层 + 下载抓弹幕重构 + 设置项（已交付）
- **删除**：`GStorage.danmakuMatch` 箱、`repositories/danmaku_match_repository.dart`、`modules/danmaku/danmaku_match.dart`（`DanmakuMatch` / `DanmakuLibraryMatch`）、`DanmakuLibraryService` 的 `findMatch`/`findLibrary`/`remember`/`forget`/`loadFromMemory`/`loadEpisodes`、`DanmakuSourcePick`、`VideoPageController.applyDanmakuPick`/`danmakuSourceId`/`_loadDanmakuForCurrentEpisode`、`_danmakuSessions`。磁盘上的旧箱文件留在原处不动（不主动删用户数据）。
- **在线播放不再自动出弹幕**：`_playDirectUrl` 成功后改为 `PlayerDanmakuController.resetEpisodeSelection()`（清画布 + 清桶 + 关显示），否则上一集的弹幕会留在画布上继续跑。该复位方法刻意不是 `@action`（内部只组合两个已有 `@action`），避免为一行组合逻辑重跑代码生成。
- **离线播放只认下载缓存**：`_loadDanmakuForOfflinePlayback` 读 `danmaku.json`，读不到就复位；不再退回任何记忆表。
- **下载抓弹幕重构**：新增纯函数 `services/danmaku/danmaku_episode_matcher.dart`（`localEpisodeNumber` / `matchLocalEpisodeToLibrary`）。`_cacheDanmakuForOffline` 改为"进度记录里的库 → `loadDetail` 取分集 → 按集号对位 → 抓那一集写 `danmaku.json`"；**对不上就静默跳过**（下载是后台行为，宁可没缓存也不猜错集）。本地集名优先用下载记录的 `episodeName`，为空时退回进度记录里插件给的集名。带单测 `test/danmaku_episode_matcher_test.dart`（含 `1080P`/`x265`/年份/`S02` 噪声剔除、`C146`/`12.5` 不参与严格匹配、库侧无短标题才退位对号）。
- **设置项**：`SettingsKeys.downloadDanmaku`（默认 true、此前**从无 UI**）在「弹幕设置」tab 补上开关（新增「离线弹幕」分组）。

### M5 版式重做 + 分集改走缓存引用（已交付）
反馈原话："持久化的应该要有剧集数据吧，这个也默认展示，搜索框放卡片下方，选中与展示的卡片为什么不一致？为什么还留一行显示当前使用？滚动为什么也只有搜索结果？"

- **持久化拆成"快照 + 缓存"**（不是把分集塞进进度记录）。用户否掉的方案是把上千集写进 `VideoPlaybackProgress.danmaku`：进度每 5–15 秒整体重写一次，那等于每次写都重新序列化一份大对象。改成：
  - 进度记录里仍只有**小快照**（`DanmakuLibraryRef`：id / 标题 / 封面 / 简介 / 评分 / 集数 / **年份**）＝"用户选了哪个库"的事实源；
  - 新增 `GStorage.danmakuLibraryCache` 箱 + `repositories/danmaku_library_cache_repository.dart`：按库 id 存 `DanmakuBangumiDetail`（分集列表 / 多语言标题 / 标签），**只在点选或点刷新时写一次**，上限 20 条按写入时间淘汰。它是**可重建的派生数据**，丢了重拉一次。
  - 于是"进场默认展示选集"成立：读进度记录拿引用 → 从缓存取分集 → 零请求、零额外写盘。缓存缺失时选集页签显示「取分集」按钮（例如本次重构前的老记录）。
  - `DanmakuLibraryRef` 新增 `year`：详情接口不返回 `startDate`，年份只有搜索结果有，所以由调用方带入并随快照持久化，否则卡片上的年份会在详情到手后消失。
- **版式：一页一滚动体**（`CustomScrollView`）：卡片（选中/持久化过才出现）→ **吸顶**「搜索 / 选集」切换行 → 内容。搜索框因此落在卡片下方；搜索结果与分集列表都不再各自 `Expanded + ListView`，整页一起滚。切换行用 **`bean/widget/connected_tabs.dart` 的 `ConnectedTabs`**（M3 connected-button 组，Kazumi 播放器弹幕设置弹窗用的就是它；wyw 里 `视频信息` 二级页的「概览/日志」同款）——它按可用宽度把剩余空间平摊给各段，所以天然"铺满整行"（左右各留 12 边距，与搜索框/筛选框对齐），标签放不下时自动横向滚动。吸顶行外层用 `Material` 而不是 `ColoredBox`（同 ListTile 断言的老问题：带色 ColoredBox 会吞掉水波纹）。
- **卡片统一成一个组件**：`widgets/library_card.dart`（`DanmakuLibraryCard`）同时承担"当前使用"和"刚选中"，只认一个数据源（快照），详情只作为"多给一点的补充"。旧的 `library_detail_card.dart` 删除——两张卡片长得不一样正是反馈里"选中与展示的卡片为什么不一致"的来源。卡片自带「使用中」标记，**顶部那行"当前使用：X"整行删除**（与卡片说的是同一件事）。
- **口径微调**：选用某库后**不自动**跳到「选集」页签（停在搜索结果，方便连续对比候选项）；持久化仍只在"这一集真的出弹幕了"之后发生，由面板发起（面板才知道展示的是哪份快照、年份是多少），外壳的 `onEpisodeSelected` 返回 `bool` 表示成功。
- 新增测试：`test/danmaku_library_cache_test.dart`（往返 / 损坏容错 / 上限淘汰）、`test/danmaku_search_panel_test.dart`（版式契约：卡片与「使用中」、选集引导、页签切换、`ConnectedTabs` 组件与边距）、`danmaku_library_ref_test.dart` 补 `year` 往返与**键集断言**（锁死"重数据不进进度记录"）。
- **删掉"匹配度"**（用户反馈"完全不准"）：候选条目上的百分比角标与「标题 92% · 封面 87% · 集数 88%」打分依据、以及按自算分的**重排**全部移除；列表保持弹弹play 自己的相关度顺序。删除 `danmaku_candidate_ranker.dart`（bigram Dice + 季号惩罚 + 集数相对差 + 加权归一化）、`cover_similarity_service.dart`（感知哈希，**只**被这个分数用）、`danmaku_candidate_models.dart`（`RankedDanmakuCandidate`）与三个对应测试文件，以及面板的 `localEpisodeCount`/`referenceCoverUrl` 入参。
  两条让它必须下线的理由：① **同一列里不可比**——封面分只给前 10 条算（要下载图片），没算到的按剩余权重归一化，于是有的行是三项加权、有的只是两项；② **信号本身是噪声**——`/search/anime` 的 `episodeCount` 是弹弹play 侧的系列总集数，本地集数是插件给的（TMDB 源恒为 1），封面又是插件图 vs 弹弹play 图（裁剪/水印都不同）。搜索接口自带相关度排序，"能认出是哪一部"比假精确的分数有用。
- **又一轮版式微调**（同一批反馈）：
  1. **两个页签各自的搜索框都挂顶**（`_pinnedHeaderDelegate` 里两行：切换行 + 当前页签的搜索/筛选框）。长结果或上千集的分集列表滚到一半时，改关键词/筛分集不用先滚回顶部。选集页签没有分集时不挂第二行（面板最窄只有 ~280，白占高度）。
  2. **类型筛选从"搜索框下方一排 chips"改成与搜索框同行的下拉**（`SelectField`，与相邻 `TextField` 同款 M3 outlined 外观）。宽度 **118 是量出来的**：触发内容 = contentPadding(12×2) + 最宽类型名「剧场版」(3 CJK ≈ 42) + ▾ 的交互宽度 48 = 114 才不溢出，实测 110 当场 `RenderFlex overflow`。
  3. **删掉「剧集搜索」兜底**（`/search/episodes`）：同时删掉 `DanmakuApi.searchEpisodes`、`DanmakuLibraryService.searchEpisodes`、`DanmakuEpisodeSummary` 模型与相关用例。保留它的唯一理由是条数多（57 vs 25），但它不带封面/年份/集数、也没有类型过滤，25 条上限的真实解法是**服务端类型筛选**。
  4. **卡片封面照 Kazumi 详情页（Android 形态）的做法**：`AspectRatio(0.65)`（海报 2:3 一档）+ **由高度决定宽度**，而不是写死一个小尺寸。那边卡片高 300、封面约 150×230；这里是 280px 宽的分屏面板，高度取 **120（≈ 78 宽）**——再高会把标题那列挤成一条缝、也让卡片占满整面板。此前是写死的 `46×62` → `56×80`，两次都被反馈偏小，根因就是"给固定小尺寸"这个思路本身。
  5. **修掉"点标题切换没生效"**：原因是 `_resolveTitleIndex` 每次 build 都优先选与快照同名的标题，把用户点出来的 `_titleIndex` 覆盖掉了；改成只在"详情刚到 / 换库"时定位一次（`_syncTitleIndex`），并按反馈删掉「语言 · 点标题切换（i/n）」那一行提示。
  6. **卡片指标从拼接字符串改成指标格**（"这里单纯做成字符串不好看"）：原来是
     `TV动画 · 2024 年 · 12 集 · 评分 7.5 · 连载中` 一行 `join(' · ')`，扫读差、尾巴还会被省略号切掉。照 Kazumi 详情页信息块改成**标签在上、值在下**（值加粗主色，未知显示 `—`），2×2 四格：类型/年份/集数/评分（评分带一颗星）；「连载中」是**状态**不是数值，做成标题右侧的徽标。封面高度因此提到 120（与四格 + 标题的总高相当，封面仍决定行高）。
  7. **面板补齐设置项**（反馈："设置里面的弹幕设置有重复合并等，为什么播放器面板里没有？"）：
     根因是**共用件的插槽设计**——`DanmakuDisplaySection` 当初给播放器弹层留了
     `leadingTiles`/`trailingTiles`，设置页把「简繁转换 / 海量弹幕 / 弹幕去重」经插槽
     塞进同一张卡；弹层退场后插槽没了消费者，面板只拿到共用件本体。而「描边 / 描边粗细 /
     弹幕颜色 / 字体字重」干脆还内联在设置页里。
     改法（照仓库"全共用内容件"的口径）：三项插槽行**收进共用件内置**（插槽参数删除），
     样式组抽成新的 `DanmakuStyleSection`，两端都用同一份；设置页因此只剩页面专有的
     来源/屏蔽/恢复默认。
     生效路径分三类，都做了：
     - 描边 / 描边粗细 / 字重 / 海量 → 进画布 `DanmakuOption`，播放循环每秒比对的选项签名
       已包含它们，约 1 秒内自己生效（无需外壳接线）；
     - 弹幕颜色 → 发送每条弹幕时现读，下一条即刻生效；
     - **弹幕去重** → 合并发生在**写入桶**时，所以控制器新增"保留去重前原始列表 +
       `reapplyDanmakuDeduplication()` 就地重跑分桶"，面板开关直连它，不必换集、不必联网。
       （`DanmakuDisplayProperty` 相应补 `massive`/`deduplication`。）
     - 简繁转换维持原样：那行自己的说明就是"下次联网加载弹幕时生效"。
     **只剩「恢复默认设置」留在设置页**（页面级动作，带确认框）。
     测试：`player_split_tabs_test.dart` 新增两条——面板是否覆盖设置页那 22 项、
     改「弹幕去重」后 `danmakuCount` 从 4 变 2（就地重跑，不联网）。
  8. **年份显示为 `—` 的修复**（反馈："弹幕库信息的年份存储后在此展示为一个-"）：
     详情接口不返回 `startDate`，年份只能从**搜索结果**带进来；而进度记录里的
     `year == 0` 表示"当时没拿到"（老记录、或该条目接口没给 `startDate`），四个写快照的
     地方又都原样传递 0，于是会一直显示 `—`。
     改法两条：① `DanmakuBangumiDetail.firstAirYear`——详情里每集都有
     `airDate`（实测 `"airDate":"2023-01-06T00:00:00"`），用它推作品年份；
     ② `DanmakuLibraryRef.fromDetail` 的年份优先级改为
     **调用方给的（搜索结果）> 首集 airDate > 0**，且 `0` 也走兜底（0 是"未知"而不是
     "确定没有"）。于是**自愈**：下一次点分集或刷新就会把年份写回快照；卡片侧也做同样
     兜底，所以老记录只要详情在（含磁盘缓存）就立刻显示年份，不必等自愈。
  9. **默认页签跟随状态**（反馈："下方默认 tab 页，如果有已选择的弹幕库就是选集，否则就是搜索"）：
     `TabController(initialIndex: widget.current == null ? 0 : 1)`，选过库时直接落在
     「选集」（用户要的多半是"这一集用库里的哪一集"），没选过才从「搜索」开始。
     只在**进场时**决定一次：之后用户自己切到哪就停在哪，选完库/换集不会把页签抢走。
     （测试注意：同一用例里二次 `pumpWidget` 会复用 State、`initState` 不再跑，
     两个默认态必须分成两个用例。）
  新增测试：`test/danmaku_library_card_test.dart`（标题轮换真的切换了、提示行不再出现、封面比例与高度、指标格取代拼接串、连载中徽标、年份兜底与优先级）与面板测试里的"搜索框/下拉挂顶且同行""类型下拉可选中最宽项不溢出""默认页签的两个分支"。
