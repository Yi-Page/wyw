# 弹幕系统分析与接入方案

> 分析对象：Kazumi 2.3.6（`D:\development\AndroidStudioProjects\Kazumi`）
> 目标项目：wyw。文中所有「改动」均指 wyw 侧的改动。

## 0. 结论先行

1. **Kazumi 的弹幕只有一个数据源：弹弹play（DanDanPlay）开放 API**（`api.dandanplay.net`）。它没有自己接 B 站/巴哈的接口——弹弹play 侧是聚合库，返回的弹幕带 `BiliBili` / `Gamer` / `DanDan` 来源标签。
2. **bangumi 只参与一件事：「我是哪部番」的 ID 映射。** 渲染、时间轴、去重、屏蔽、缓存、设置项全部与 bangumi 无关。
3. **Kazumi 另有一条完全绕开 bangumi 的链路**：按番剧标题搜索弹幕库（手动检索面板）。这条链路对 wyw 才是有用的那条。
4. **弹幕渲染在 Flutter 层（画布覆盖），与 mpv / ffmpeg 完全无关**。不需要改播放器引擎，也不需要碰之前那套广告过滤补丁。
5. **wyw 的弹幕层是被「剥掉」的，不是没做过**：设置键（21 个）、`SettingGroup.danmaku`、`GStorage.shieldList` 箱、`DownloadEpisode.danmakuData` / `danDanBangumiID` 字段、快捷键 `toggledanmaku`、面板里的弹幕图标缓存字段，全都还在。因此本方案的性质是**恢复 + 替换匹配起点**，不是从零接入。

---

## 1. Kazumi 的实现

### 1.1 数据源与鉴权

| 项 | 值 | 位置 |
|---|---|---|
| 域名 | `https://api.dandanplay.net` | `lib/request/config/api_endpoints.dart:119` |
| 取弹幕 | `/api/v2/comment/{episodeId}?withRelated=true` | 同上 `:122` |
| 番剧搜索 | `/api/v2/search/episodes?anime={关键词}&v2=true` | 同上 `:125` |
| 番剧信息 | `/api/v2/bangumi/{animeId}` | 同上 `:128` |
| bgm 映射 | `/api/v2/bangumi/bgmtv/{bgmSubjectId}` | 同上 `:131` |

所有请求都要签名（`lib/request/clients/danmaku_client.dart:19-29`）：

```
X-Auth: 1
X-AppId:     <AppId>
X-Timestamp: <秒级时间戳>
X-Signature: base64( sha256( AppId + Timestamp + path + AppSecret ) )
```

`path` 是**请求路径**（不含域名与查询串），见 `lib/utils/crypto.dart:8-15`。

**AppId / AppSecret 不在仓库里**，靠构建期注入（`lib/utils/dandan_credentials.dart`）：

```dart
const Map<String, String> dandanCredentials = {
  'id':    String.fromEnvironment('DANDANAPI_APPID'),
  'value': String.fromEnvironment('DANDANAPI_KEY'),
};
```

→ CI 用 `--dart-define=DANDANAPI_APPID=... --dart-define=DANDANAPI_KEY=...` 注入。**这是 wyw 复用时第一道、也是最大的一道门槛**（见 §5.1）。

### 1.2 自动匹配：三级 ID 链

```
bangumi 条目 id（video_controller 的 bangumiItem.id，即 bgm.tv subject id）
  │  GET /api/v2/bangumi/bgmtv/{bgmId}
  ▼
弹弹play 的 animeId
  │  拼集号（padLeft(4,'0')）
  ▼
弹幕库 episodeId = animeId * 10000 + 集号
  │  GET /api/v2/comment/{episodeId}
  ▼
comments[] → DanmakuEntry
```

调用链：`lib/pages/player/controller/player_danmaku_controller.dart:270-295`（`_fetchDanDanmakuByBgmBangumiID`）→ `lib/request/apis/danmaku_api.dart:12-20`、`:52-75`。

两个已知坑（Kazumi 自己写在注释里）：

- `animeId * 10000 + 集号` 这条拼 ID 规则**是猜的**，官方文档没写，所以带 `withRelated=true` 兜底（`danmaku_api.dart:58`）。
- **集号从分集标题正则解析**（`extractEpisodeNumber`），解析失败退回列表索引（`lib/pages/video/video_controller.dart:845-862`）；离线模式直接用下载记录里的集号。

### 1.3 手动匹配：标题搜索链（不需要 bangumi）

`lib/pages/player/danmaku_source_sheet.dart` 的「选择弹幕源」三步面板：

```
输入番剧名 → GET /api/v2/search/episodes   （选番剧）
          → GET /api/v2/bangumi/{animeId} （拿分集列表，带 episodeId）
          → GET /api/v2/comment/{episodeId}（直接用 episodeId 取弹幕）
```

三个步骤的代码位置：`:143`（搜索番剧）、`:174`（拿分集）、`:196`（按 `episodeId` 取弹幕，走 `getDanDanmakuByEpisodeID`）。

注意 `danmaku_api.dart:33-39` 的注释：官方 `/api/v2/search/anime` 最多 25 条且不能翻页（柯南有 48 条会被截断），所以改用不限条数的 `/api/v2/search/episodes`。

**这条链路完全不依赖 bangumi**，是 wyw 应该采用的起点。

### 1.4 弹幕数据格式

弹弹play 标准 `p` 串（`lib/modules/danmaku/danmaku_module.dart:23-36`）：

```json
{ "m": "弹幕文本", "p": "时间秒,类型,颜色十进制,来源" }
```

- 类型：`1` 滚动 / `4` 底部 / `5` 顶部（`player_item.dart:1028-1036` 映射到 `DanmakuItemType`）
- 颜色：`generateDanmakuColor(int)` 拆 RGB（`lib/utils/danmaku.dart:4-9`）
- 来源：`BiliBili` / `Gamer` / `DanDan`，仅作为过滤开关的依据

### 1.5 渲染与时间轴

渲染用 pub 上的 **`canvas_danmaku: ^0.3.3`**（纯 Flutter `CustomPainter` 画布，与播放器无耦合）：

- 挂载：`lib/pages/player/player_item.dart:1400-1426`，`DanmakuScreen` 作为 `Positioned.fill` 覆盖在视频表面之上、控制面板之下；`createdController` 回调里把 `DanmakuController` 存进 `playerController.danmaku.canvasController`。
- 选项：`DanmakuOption(hideTop/hideScroll/hideBottom/area/opacity/fontSize/duration/lineHeight/strokeWidth/fontWeight/massiveMode/fontFamily)`，全部来自设置。

时间轴（`player_danmaku_controller.dart:314-335` + `player_item.dart:1038-1081`）：

- 弹幕按**整秒**分桶：`Map<int 秒, List<DanmakuEntry>>`（`addDanmakus`，`:322-325`）
- 播放器有 1 秒周期定时器（`player_item.dart:1083-1088` 的 `getPlayerTimer`），每秒调 `_emitDanmakusForCurrentPosition()`
- 同一秒的多条弹幕用 `staggerDelayMilliseconds` 在 0~999 ms 内错开发送（`:1056-1059`）
- 发送前四道闸门：`mounted` / `playerPlaying` / `!playerBuffering` / `danmakuOn`
- `danmakuTimeOffset`（秒）做时间轴偏移：`源秒 = 播放位置 - offset`，负数直接不出（`:113-118`）
- **`scheduledDanmakuGeneration` 失效计数器**：seek / 清屏时 +1，把所有已排队未发出的延迟任务作废（`:133-136`、`:1060-1068`），防止跳转后旧弹幕串场
- 播放暂停 / 恢复：`player_controller.dart:340`、`:358` 调 `canvasController.pause()/resume()`
- 倍速：`updateDanmakuSpeed` 在「跟随倍速」开启时把 `duration` 除以播放速度（`:328-335`）

### 1.6 内容处理

- **去重合并**（`lib/utils/danmaku.dart:11-98`）：文本归一化（全角→半角、去空白与标点、叠字压缩到 3 个）后按 5 秒窗口合并，合并结果为 `原文本 xN` 并**强制顶部弹幕**（`:89-97`）。开关：`danmakuDeduplication`。
- **屏蔽词**（`lib/pages/my/my_controller.dart:82-101`）：普通词走 `contains`；`/xxx/` 形式当正则（编译失败只记日志、跳过）。规则存在 `GStorage.shieldList`。
- **来源开关**：`danmakuBiliBiliSource` / `danmakuGamerSource` / `danmakuDanDanSource`，在 `player_item.dart:1018-1026` 判定。

### 1.7 离线缓存 / 屏蔽词同步 / 发送弹幕

- **离线缓存**：弹幕不存 Hive，写成下载目录下的独立 JSON 文件，内容为 `{danDanBangumiID, danmakus[]}`（`lib/pages/download/download_controller.dart:408-458`）。离线播放先读缓存，缓存空再联网补并回写（`player_danmaku_controller.dart:191-245`）。开关：`downloadDanmaku`。
- **屏蔽词同步**：WebDAV（`webDavEnableDanmakuShield` + 设备 ID + 双向合并 sync state），`lib/repositories/danmaku_shield_repository.dart`、`lib/services/sync/danmaku_shield_sync_service.dart`。
- **发送弹幕**：面板「发送到」有两个选项（`danmaku_destination_sheet.dart`），但**只有「一起看聊天室」实现**；「发送至远程弹幕库」没有任何 POST 实现（全局无发送弹幕的 API）。本地发的弹幕只进画布。

### 1.8 一次播放的完整调用链

```
VideoPageController.changeEpisode
  → PlaybackInitParams(bangumiId, pluginName, danmakuEpisodeNumber, ...)   video_controller.dart:512-530 / :622-635
  → _loadPlaybackDanmaku()                                                 video_controller.dart:541-576
      → PlayerDanmakuController.fetchDanmaku(bangumiId, pluginName, ep)     player_danmaku_controller.dart:139-155
          ├─ 离线：读本地弹幕文件 → 命中即返回
          └─ 在线：bgmtv 映射 → animeId → comment → List<DanmakuEntry>
      → applyDanmakuLoad(result, enableDanmaku: danmakuEnabledByDefault)
  → （每秒）PlayerItem.getPlayerTimer → _emitDanmakusForCurrentPosition
      → danmakusForPlaybackPosition(当前位置)
      → myController.isDanmakuBlocked(文本) ? 丢弃 : canvasController.addDanmaku(...)
```

---

## 2. wyw 现状：残骸清单（证明这是「恢复」而非「新建」）

| 残留物 | 位置 | 现状 |
|---|---|---|
| `SettingGroup.danmaku` | `lib/services/storage/settings_keys.dart:3` | 枚举值在，无页面 |
| 21 个弹幕设置键 | 同上 `:82-186`（`danmakuEnhance` … `danmakuFollowSpeed`） | 已注册、有默认值、在 `_SettingBoxKey` 与 `values` 列表里（`:424-444`、`:513-533`），**但无人读取** |
| `downloadDanmaku` 设置键 | 同上 `:343` | 同上 |
| `GStorage.shieldList` | `lib/services/storage/storage.dart:23`、`:39` | **箱子已打开**，无人使用 |
| `DownloadEpisode.danmakuData` | `lib/modules/download/download_module.dart:89-91` | Hive 字段在（`@HiveField(14)`），仅在 `download_controller.dart:288-289` 被原样复制，无实际读写 |
| `DownloadEpisode.danDanBangumiID` | 同上 `:93-95` | Hive 字段在（`@HiveField(15)`），同上 |
| 快捷键 `toggledanmaku`（D 键） | `lib/utils/constants.dart:208`、`:243` | 已声明映射与名称，**无处理函数** |
| `cachedDanmakuOnIcon` / `OffIcon` | `lib/pages/player/player_item_panel.dart:90-91`、`smallest_player_item_panel.dart:79-80` | 字段在，无赋值无使用 |
| 设置页注释 | `lib/pages/settings/settings_page.dart:43` | 明写「弹幕相关设置（SettingGroup.danmaku）尚无对应页面」 |
| `dio` / `crypto` 依赖 | `pubspec.yaml:40-41` | **已在**，签名所需的 sha256 + base64 可直接用 |
| `DioFactory.apiDio` | `lib/request/core/dio_factory.dart:13` | **已在**，与 Kazumi 同构 |
| `canvas_danmaku` 依赖 | `pubspec.yaml` | **缺失**，需新增 |

结论：设置、持久化、网络、加密四项基础设施 wyw 都有；缺的是 **画布依赖 + 弹幕控制器 + 数据层 + 匹配层 + UI**。

---

## 3. 接入方案

### 3.1 总体架构

```
┌─ 展示层（与播放器弱耦合，只依赖「当前播放秒数」）
│    DanmakuScreen（canvas_danmaku）  ←  PlayerDanmakuController  ←  播放位置
├─ 加工层（纯数据，可单测）
│    分桶 / 去重 / 屏蔽词 / 时间轴偏移 / 来源过滤
├─ 匹配层（wyw 特有，替换 Kazumi 的 bangumi 链路）
│    (sourceKey, videoId, sourceIndex, episodeIndex, 集标题)
│        ↕ 匹配记忆表（Hive）
│    (dandan animeId, dandan episodeId, 匹配标题)
└─ 数据层（弹弹play）
     DanmakuApi（签名 + 三个端点） → DanmakuEntry
```

**核心设计点**：把「弹幕属于哪一集」抽成一个显式的 `DanmakuMatchKey`，让展示层/加工层完全不关心它来源于 bangumi 还是标题搜索。这样以后换源（换弹幕库）只改匹配层。

### 3.2 数据层改动

| 动作 | 文件 | 说明 |
|---|---|---|
| 新增 | `lib/modules/danmaku/danmaku_entry.dart` | `DanmakuEntry`（`m` / `p` 解析、`toJson`），照搬 Kazumi `lib/modules/danmaku/danmaku_module.dart` |
| 新增 | `lib/modules/danmaku/danmaku_responses.dart` | `DanmakuEpisode` / `DanmakuEpisodeResponse` / `DanmakuSearchAnime` / `DanmakuSearchResponse` |
| 新增 | `lib/utils/danmaku_credentials.dart` | `String.fromEnvironment('DANDANAPI_APPID'/'DANDANAPI_KEY')` |
| 新增 | `lib/utils/dandan_signature.dart` | `sha256(appId + ts + path + secret)` → base64（用已有 `crypto` 包） |
| 新增 | `lib/request/clients/danmaku_client.dart` | dio 客户端，注入 `X-Auth/X-AppId/X-Timestamp/X-Signature`，复用 `DioFactory.apiDio` + `NetworkErrorMapper` |
| 新增 | `lib/request/apis/danmaku_api.dart` | 四个方法：`searchAnimes(title)`、`getEpisodesByAnimeId(animeId)`、`getDanmakuByEpisodeId(episodeId)`、`getDanmakuByAnimeIdAndEpisode(animeId, ep)` |
| 修改 | `lib/services/logging/log_tags.dart` | 新增 `static const danmaku = '[Danmaku]';` |
| 修改 | `lib/request/core/dio_factory.dart` | 仅当需要独立的超时/重试策略时加一个 `danmakuDio`；否则不动 |

> 注意：wyw **不要**移植 `getDanDanBangumiIDByBgmBangumiID`——wyw 没有 bgm id。

### 3.3 匹配层改动（wyw 特有，工作量最大的一块）

**匹配记忆表**（新增 `lib/modules/danmaku/danmaku_match.dart` + `lib/repositories/danmaku_match_repository.dart`）：

- 新开 Hive 箱 `danmaku_match`（在 `storage.dart` 里与 `shieldList` 并列打开）
- key：`'${historySourceId}|s${sourceIndex}|e${episodeIndex}'`（`historySourceId` 已有：`VideoPageRouteArgs.historySourceId` = `sourceKey:videoId`）
- value：`{animeId, episodeId, animeTitle, episodeTitle, savedAt}`

**自动匹配**（新增 `lib/services/danmaku/danmaku_matcher.dart`）：

1. 取 `videoPageController.videoTitle`（已有）+ `VideoPlayEpisode.name`（已有）作为关键词
2. `searchAnimes(title)` → 候选番剧列表
3. 标题归一化打分（去季号/年份/标点后比较，可复用 `lib/utils/format.dart` 附近的能力或新写）：取最高分且超过阈值者
4. `getEpisodesByAnimeId(animeId)` → 分集列表
5. 用 `VideoPlayEpisode.name` 里的集号（可参考 Kazumi 的 `extractEpisodeNumber` 思路）在分集列表里定位 `episodeId`；定位不到则用列表序号
6. 写入匹配记忆表；低于阈值不自动应用，直接提示「可手动检索」

**手动检索**（新增 `lib/pages/player/danmaku_source_sheet.dart`）：照搬 Kazumi 的三步面板（搜索番名 → 选番剧 → 选分集），完成后同样写入匹配记忆表。

### 3.4 渲染层改动

| 动作 | 文件 | 说明 |
|---|---|---|
| 修改 | `pubspec.yaml` | 新增 `canvas_danmaku: ^0.3.3`（与 Kazumi 同版本，保证行为一致） |
| 新增 | `lib/pages/player/controller/player_danmaku_controller.dart` | MobX Store：`danDanmakus`、`danmakuOn`、`danmakuLoading`、`canvasController`、`scheduledDanmakuGeneration`、`resolveDanmakuSecond`、`danmakusForPlaybackPosition`、`addDanmakus`、`clearAndInvalidateScheduledDanmakus`、`updateDanmakuSpeed` |
| 修改 | `lib/pages/player/player_controller.dart` | 加 `late final PlayerDanmakuController danmaku`；`dispose()` 清理；暂停/恢复时 `canvasController.pause()/resume()` |
| 修改 | `lib/pages/player/player_item.dart` | ① 在视频层 `Stack`（`:1117`）里、`PlayerScreenshotFeedbackOverlay`（`:1128`）之前插入 `Positioned.fill(child: DanmakuScreen(...))`；② `getPlayerTimer`（`:797`）的每秒回调里加 `_emitDanmakusForCurrentPosition()`；③ seek / 换集 / 切换源时调 `clearAndInvalidateScheduledDanmakus()` |
| 新增 | `lib/utils/danmaku.dart` | `generateDanmakuColor` + `mergeDuplicateDanmakus`（照搬，含叠加 xN 与 5 秒窗口） |

**插入点注意事项**：弹幕层必须在视频表面之上、控制面板之下（与 Kazumi 的层序一致），否则弹幕会盖住控制条。

### 3.5 UI 层改动

| 动作 | 文件 | 说明 |
|---|---|---|
| 修改 | `lib/pages/player/player_item_panel.dart` | 接上已存在的 `cachedDanmakuOnIcon/OffIcon` 字段，加弹幕开关按钮、弹幕设置入口、弹幕源切换入口 |
| 修改 | `lib/pages/player/smallest_player_item_panel.dart` | 同上（迷你面板） |
| 修改 | `lib/utils/constants.dart` + 按键处理 | 把已声明的 `toggledanmaku`（D 键）接到实际处理函数 |
| 新增 | `lib/pages/settings/danmaku/danmaku_settings_page.dart` 等 | 显示设置（透明度/字号/行高/描边/区域/滚动顶底/海量/字体/颜色/时长/跟随倍速/时间轴偏移）、来源开关、去重开关、默认开关 |
| 修改 | `lib/pages/settings/settings_page.dart` | 在「播放」组加「弹幕设置」分类（`:43` 的注释可删） |
| 新增 | `lib/repositories/danmaku_shield_repository.dart` + 屏蔽词编辑页 | 读写已打开的 `GStorage.shieldList`；匹配函数 `isDanmakuBlocked(text)`（含 `/正则/` 支持） |
| 可选 | WebDAV 屏蔽词同步 | 最后做，可延后 |

### 3.6 持久化与离线

| 动作 | 文件 | 说明 |
|---|---|---|
| 修改 | `lib/modules/download/download_module.dart` | `danmakuData` / `danDanBangumiID` 字段**已存在**，无需迁移；建议按 Kazumi 做法改存独立 JSON 文件（`danmakuData` 留空），避免 Hive 膨胀 |
| 修改 | `lib/services/download/download_manager.dart` | 下载完成时若 `downloadDanmaku` 开，抓一次弹幕写入下载目录 |
| 修改 | `lib/pages/video/video_controller.dart` | 离线播放先读本地弹幕文件；未命中再联网补 |
| 修改 | `lib/pages/player/controller/player_models.dart` | `PlaybackInitParams` 目前注释明写「no bangumi/episode metadata」，需补弹幕所需身份：建议传 `danmakuMatchKey`（或 `danmakuEpisodeNumber` + `sourceIndex`/`episodeIndex`），不要重新引入 bangumi 概念 |

---

## 4. 关键决策与风险

### 4.1 签名是硬门槛（P0 风险）

`api.dandanplay.net` 全部接口需 `X-AppId` + `X-Signature`。Kazumi 的密钥由 CI 注入，仓库内为空。wyw 有三个选择：

| 方案 | 代价 | 说明 |
|---|---|---|
| A. 自行申请弹弹play 开放平台 AppId/Secret | 需注册与审核 | **推荐**；合规、稳定 |
| B. 复用 Kazumi 的密钥 | 不合规 | Kazumi 的密钥绑定其 AppId，属于他人凭证，且随时可能失效 |
| C. 走第三方转发/无签名代理 | 可用性不可控 | 非官方，随时可能挂；仅适合临时验证 |

**在拿到 AppId 之前，M1（渲染层 + 假数据）可以先做**，整条链路用内置测试弹幕跑通，不受签名阻塞。

### 4.2 匹配准确率（P1 风险）

wyw 没有 bgm 条目，唯一的匹配输入是**番剧标题 + 分集标题**。风险：

- 同名前传/续作/剧场版会误匹配 → 用「标题归一化 + 年份/季号 + 分集数量接近度」综合打分，低于阈值不自动应用
- 集号解析失败 → 退回列表序号，并把「已应用但可能不准」这件事在 UI 上显式暴露（可一键换源）
- 匹配记忆表是**纠错手段**：用户手动选一次后永久生效，不再自动匹配

### 4.3 与播放器完全解耦（好消息）

弹幕只依赖「当前播放秒数」这一个输入。因此：

- 三种播放模式（在线直链 / 本地代理 / 离线本地）**共用同一套弹幕代码**，无需分别适配
- 不需要碰 mpv、ffmpeg、`hls_ad_filter` 补丁、分片、播放列表
- 也不需要像广告过滤那样区分列表格式

### 4.4 与广告过滤的交互（必须专门验证）

广告过滤补丁在跳过广告时会**补正 mpv 的 PTS 偏移**，使 mpv 报告的时间轴依然连续。因此「按 mpv 播放位置取弹幕桶」的理论结果是仍然对齐（弹幕跟着内容走，不会因为广告被剔除而整体前移 25.7 秒）。

但这是**推论，不是实测结论**。接入后必须测：同一集在
① 广告过滤关闭 ② 广告过滤开启
两种情况下，广告位之后的弹幕时间点是否一致。若不一致，说明 mpv 时间基准与源时间轴之间还有偏差，需要在 `timelineOffsetSeconds` 之外增加一层「广告补偿」——**这是本方案唯一可能被广告过滤影响的点**。

### 4.5 明确不做的事

- 不引入 bangumi 条目体系（wyw 的 `PlaybackInitParams` 注释已明确这是有意为之）
- 不实现「发送弹幕到远程弹幕库」（Kazumi 自己也没实现）
- 不做 WebDAV 屏蔽词同步（可选，最后评估）

---

## 5. 分阶段实施

| 阶段 | 内容 | 依赖 | 验收 |
|---|---|---|---|
| **M1** | 加 `canvas_danmaku` 依赖；`PlayerDanmakuController` + `DanmakuScreen` 挂载；用内置假弹幕跑通分桶 / 错峰 / 清屏失效 / 暂停恢复 / 倍速 | 无 | 三种播放模式下都能看到假弹幕按时间出现；seek 不串场 |
| **M2** | 数据层（签名 client + 三个端点 + 模型）；**先用手动检索面板**验证接口连通 | AppId/Secret | 手动搜索一部番、选一集，弹幕正确显示 |
| **M3** | 匹配记忆表 + 自动匹配 + 手动检索回写 | M2 | 打开一集自动出弹幕；匹配错时手动换源后不再重复匹配 |
| **M4** | 显示设置页 + 开关按钮 + D 键 + 来源过滤 + 去重 + 时间轴偏移 | M1 | 21 个已注册的设置键全部可用；`settings_page.dart:43` 注释删除 |
| **M5** | 屏蔽词（读写已有 `shieldList` 箱）+ 离线弹幕缓存 + 下载时抓取 | M2 | 离线播放无网也能出弹幕；屏蔽词生效 |

**先做 M1 的理由**：它不依赖 AppId，且能立刻暴露渲染层的层序、定时器、生命周期问题；同时 M1 完成后，即使弹幕源最终不可用，这部分代码也不白写（换源只换数据层）。

---

## 6. 证据清单

### Kazumi（分析依据）

| 主题 | 位置 |
|---|---|
| 端点常量 | `lib/request/config/api_endpoints.dart:118-131` |
| 签名算法 | `lib/utils/crypto.dart:8-15` |
| 密钥注入 | `lib/utils/dandan_credentials.dart` |
| dio 客户端与请求头 | `lib/request/clients/danmaku_client.dart:13-42` |
| 四个 API 方法 | `lib/request/apis/danmaku_api.dart` |
| 数据模型 | `lib/modules/danmaku/danmaku_module.dart`、`danmaku_episode_response.dart`、`danmaku_search_response.dart` |
| 加载编排 / 分桶 / 时间轴 | `lib/pages/player/controller/player_danmaku_controller.dart` |
| 渲染挂载 | `lib/pages/player/player_item.dart:1400-1426` |
| 每秒发送与错峰 | `lib/pages/player/player_item.dart:1038-1088` |
| 手动检索面板 | `lib/pages/player/danmaku_source_sheet.dart` |
| 屏蔽词匹配 | `lib/pages/my/my_controller.dart:82-101` |
| 去重合并 | `lib/utils/danmaku.dart` |
| 离线缓存 | `lib/pages/download/download_controller.dart:408-458` |
| 播放参数与集号来源 | `lib/pages/video/video_controller.dart:512-530`、`:845-888` |

### wyw（改动落点依据）

| 主题 | 位置 |
|---|---|
| 弹幕设置键残骸 | `lib/services/storage/settings_keys.dart:3`、`:82-186`、`:343`、`:424-444` |
| 屏蔽词箱 | `lib/services/storage/storage.dart:23`、`:39` |
| 下载弹幕字段 | `lib/modules/download/download_module.dart:89-95` |
| 快捷键声明 | `lib/utils/constants.dart:208`、`:243` |
| 面板图标字段 | `lib/pages/player/player_item_panel.dart:90-91` |
| 设置页注释 | `lib/pages/settings/settings_page.dart:43` |
| 播放参数 | `lib/pages/player/controller/player_models.dart` |
| 视频层 Stack / 每秒定时器 | `lib/pages/player/player_item.dart:1117-1137`、`:797-798` |
| 集身份 | `lib/pages/video/video_controller.dart:48-60`、`lib/services/storage/video_play_model.dart:104-119` |
| dio 工厂 | `lib/request/core/dio_factory.dart:13` |

---

## 7. 落地状态（实现记录）

M1–M5 全部实现完毕。`flutter analyze` 零问题，`flutter test` 全绿（298 个用例，其中弹幕相关 102 个）。

> **2026-10 后续重构（选择动线重做）**：上表 M3 里的"两级匹配记忆"（`danmaku_match*.dart`
> + `danmakuMatch` 箱）与"手动检索弹层/二级页"**已整体删除**。作品级选择改存进**进度
> 记录**（`VideoPlaybackProgress.danmaku`，只放小快照 + 引用），分集映射按产品口径刻意
> 不持久化（切集后需再点一次）；重数据（分集列表/多语言标题/标签）另存
> `danmakuLibraryCache` 箱，按库 id 引用——进度记录每 5–15 秒整体重写一次，塞不下也不该
> 塞上千集。搜索 / 类型筛选 / 卡片 / 选分集内联在分屏面板的「弹幕」tab（一页一滚动体：
> 卡片 → 吸顶「搜索/选集」→ 内容），与「弹幕设置」tab 拆开。下载抓弹幕改为"进度记录里
> 的库 + 按集号对位"。**M3 的"封面感知哈希排序"也一并删除**（`danmaku_candidate_ranker.dart`、
> `cover_similarity_service.dart`、`danmaku_candidate_models.dart` 及其测试）：候选列表上的
> 匹配度百分比与自算分重排都被拿掉，顺序交给弹弹play 自己的相关度。见
> `docs/danmaku-selection-plan.md`。

| 阶段 | 交付 | 关键文件 |
|---|---|---|
| M1 渲染层 | 画布挂载、按秒分桶、错峰发送、失效计数器、跳转清屏、暂停/恢复、倍速跟随 | `player_danmaku_controller.dart`、`utils/danmaku.dart`、`player_item.dart` |
| M2 数据层 | `dart-define` 凭证、签名、dio 客户端、四个端点、容错模型 | `lib/request/clients/danmaku_client.dart`、`lib/request/apis/danmaku_api.dart`、`lib/modules/danmaku/danmaku_{entry,responses}.dart` |
| M3 检索与记忆 | 手动检索面板（标题预填）、封面感知哈希排序、两级匹配记忆 | `danmaku_source_sheet.dart`、`danmaku_library_service.dart`、`cover_similarity_service.dart`、`danmaku_candidate_ranker.dart`、`danmaku_match*.dart` |
| M4 设置与 UI | 弹幕设置页（21 个键）、屏蔽词入口、面板按钮、D 键、画布设置热同步 | `lib/pages/settings/danmaku/`、`player_item_panel.dart` |
| M5 屏蔽词与离线 | 纯函数匹配/校验、`shieldList` 仓库、管理页、播放过滤；下载时抓弹幕、离线优先读本地缓存 | `lib/modules/danmaku/danmaku_shield.dart`、`danmaku_shield_repository.dart`、`danmaku_cache_service.dart` |

### 7.1 与初版方案的偏差（都是实现中发现的更好做法）

1. **匹配记忆做成两层**（初版只有集级）。只记集级意味着 24 集的剧要手选 24 次。现在作品级记「选中的作品 + 全部分集 + 集号偏移」，同源其它集按偏移推导；集级记录用于个别集的覆盖。推导依据是**用户自己的那次点选**，不是猜标题；推导越界（源比库多/少集）时返回 null 让用户重选，绝不取邻集弹幕。
2. **不做自动匹配**（按用户要求）。面板打开时把当前剧名填进输入框，但必须由用户点选。
   > **后已删除**：曾按「标题 bigram + 封面感知哈希 + 集数接近度」加权重排，并在条目上显示
   > 「标题 92% · 封面 87% · 集数 100%」。该分数实测"完全不准"，且同一列内不可比
   > （封面分只算前 10 条，没算到的按剩余权重归一化），现已连同打分器、封面相似度服务与
   > 三个测试文件一起删除，列表改为保持弹弹play 自己的相关度顺序。见 `danmaku-selection-plan.md` §M5。
3. **封面只算前 10 个候选**。排在后面的不会被点，全量算等于为列表末尾多下载几十张图；实时重排前先取候选快照，避免重排后下标错位漏算。
4. **`bangumiId` 不是 bgm 条目号**（swagger 澄清）。它是新体系作品 ID，形如 `tmdb-movie-21832`。bgm 映射必须走 `/api/v2/bangumi/bgmtv/{bgmtvSubjectId}`，而官方明说该映射由**人工维护**、可能错/缺/延迟——这也是不引入 bangumi 的依据之一。
5. **`/api/v2/comment/{episodeId}` 挂在 302 重定向下**（跳转弹幕加速服务），且响应只有 `count`/`comments`，没有 `success` 字段，因此不做失败判定，按解析条数返回。
6. **`/search/episodes` 不返回集号与封面**：`episodeNumber` 只有 `/bangumi/{id}` 详情才有；因此面板走 `/search/anime`（有封面/年份/集数）→ `/bangumi/{id}`（有权威 `episodeId`）。（该端点作为"剧集搜索"兜底的用法后来被删除，见 `danmaku-selection-plan.md` §M5。）
7. **字重设置存的是 `FontWeight.values` 下标**，画布包按 `values[i]` 取值，越界会抛 `RangeError` → 读写两侧都 clamp。
8. **画布设置热同步**：`DanmakuScreen` 只在创建时读一次 `option`，因此播放器每秒比对一次设置签名并仅在变化时 `updateOption`（该调用内部会做大量差异处理，不能每秒无脑调）。
9. **离线弹幕落成剧集目录里的文件**（`danmaku.json`）而不是写 Hive：随「删除下载」一起清掉，不产生孤儿数据，也不会撑大下载记录箱。

### 7.2 凭证与合规

- 凭证由构建期注入：`--dart-define=DANDANAPI_APPID=... --dart-define=DANDANAPI_KEY=...`；**不入库**（与 Kazumi 一致）。
- 未配置时：不发出任何请求，弹幕整块静默关闭，其余功能不受影响。
- 弹弹play 使用约定：弹幕功能必须**免费**开放，且**不得商用**。

---

## 8. 真机验证清单

构建：

```
flutter run --dart-define=DANDANAPI_APPID=xxx --dart-define=DANDANAPI_KEY=yyy
```

| # | 场景 | 预期 | 观察方式 |
|---|---|---|---|
| 1 | 不传凭证启动 | 长按弹幕按钮 → 面板显示「未配置弹弹play 凭证」；日志无任何网络请求 | 日志 `[Danmaku] 未配置弹弹play 凭证，跳过请求` |
| 2 | 传凭证，首次播放某集 | 弹幕按钮为「未匹配」态；点击直接打开检索面板且**剧名已预填** | 面板输入框内容 |
| 3 | 面板搜索 | 候选列表出现，条目下显示「标题 x% · 封面 x% · 集数 x%」，几秒内顺序会按封面分重排 | 视觉 |
| 4 | 选中某集 | 弹幕立刻出现；提示「已切换到「XXX」」 | 日志 `[Danmaku] 应用弹幕 episodeId=... 总条数=...` |
| 5 | 换到同一源的另一集 | **不再要求手选**，直接出弹幕（作品级偏移推导） | 日志同上；无「尚无弹幕匹配记录」 |
| 6 | 换到集数与弹幕库不一致的集（如源多出花絮） | 提示需手动检索，**不会**取到邻集弹幕 | 日志 `作品级记录按偏移推导越界` |
| 7 | 跳转（进度条/按键/手势） | 画布立刻清空，跳转后不出现旧位置弹幕 | 视觉 |
| 8 | 暂停/恢复播放 | 弹幕随播放暂停/恢复 | 视觉 |
| 9 | 倍速播放（开/关「跟随倍速」） | 开启时弹幕速度同步变化 | 视觉 |
| 10 | 设置页改字号/透明度/描边/区域/字重 | **播放中立即生效**（后台/画中画场景也生效） | 视觉 |
| 11 | 关闭「滚动弹幕」等类型开关 | 对应类型立刻消失 | 视觉 |
| 12 | 加屏蔽词（普通词与 `/^\d+$/`） | 命中弹幕不显示；坏正则只被跳过 | 视觉 + 日志无异常 |
| 13 | 离线（飞行模式）播放已下载且匹配过的集 | 仍出弹幕（读本地 `danmaku.json`） | 日志 `离线播放使用本地缓存的弹幕` |
| 14 | 下载一集（开「下载弹幕」，且该集已匹配） | 剧集目录出现 `danmaku.json` | 日志 `已缓存弹幕供离线播放`；文件管理器 |
| 15 | 三种播放模式（直链/代理/离线） | 同一集弹幕一致、时间轴一致 | 对比观察 |
| 16 | **广告过滤开启 vs 关闭** | 广告位之后的弹幕时间点应一致（补丁会补正 PTS 偏移）。若不一致，说明需要额外的广告补偿 | 同一集两种设置下比对 |
| 17 | D 键 | 切换弹幕开关 | 桌面端按键 |
| 18 | 删除下载 | `danmaku.json` 随目录一起被删除 | 文件管理器 |

> 第 16 项是本方案唯一可能被广告过滤影响的点，务必实测。
