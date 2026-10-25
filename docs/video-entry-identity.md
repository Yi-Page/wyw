# 播放作品身份（code）与进播放页编排层

> 状态：已落地（`lib/services/storage/video_code.dart`、
> `lib/pages/video/video_entry_launcher.dart`、`lib/services/history/video_progress_merge.dart`）。
> 本文是该部分的契约，改代码前先读这里。

## 1. 解决的问题

改造前同一部作品有**两套作品级 key**，两边互相找不到：

| | 作品级 key | 产生方式 |
|---|---|---|
| 进度历史 | `'$sourceKey:$videoId'` | [init_page]、[video_controller] 各自拼（4 处） |
| 下载记录 | `'${pluginName}_$mediaId'`，`mediaId = videoId.hashCode` | [download_controller] |

后果：

- **正向**（进度/播放身份 → 下载）能用，因为两边都从同一对插件参数派生；
- **反向**（下载 → 进度）断了：`hashCode` 不可逆，下载页只能拿
  `record.mediaId.toString()` 当 `videoId` 拼出 `plugin:<hashCode>`，与进度记录的
  `plugin:<真实videoId>` 不是同一条 → 读不到续播、也写不进进度；
- `String.hashCode` 还有碰撞风险（不同作品可能落进同一条下载记录）。

## 2. 身份规则（唯一构造点）

```dart
code = pluginName.isEmpty ? videoId : '$pluginName:$videoId'
```

- 规则实现：[VideoCode.of]。**唯一的构造调用点是
  `VideoEntryLauncher.openFromPlugin`**（插件入口）。
- 其余入口一律**读取记录里已有的 code**，不得再拼接：
  - 进度入口：`HistoryEntry.sourceId` 就是 code；
  - 下载入口：`DownloadRecord.code`（老记录用 `DownloadRecord.effectiveCode`
    从 `sourceKey`/`videoId` 派生）。
- 页面与写回只读 `VideoPageRouteArgs.historySourceId`
  （= 显式 `code`，缺省时才按旧规则从 `sourceKey`/`videoId` 派生，兼容手动播放）。
  `VideoPageController.videoCode` 是页内唯一身份字段，进度回填、写回、下载查询、
  弹幕匹配全部只读它。
- `videoId` 为空 ⇒ `code` 为空 ⇒ **入口必须拒绝进入播放**（不再静默回退成
  `videoUrl`，那正是"同一作品两个 code"的主要来源）。
- `pluginName` 为空 ⇒ 拒绝（否则 code 退化成裸 id，与手动播放/其他来源混在一起）。
  非空但未注册只告警，因为 js 控制台测试脚本与热重载时序上可能查不到插件。

## 3. 数据模型与引用方向

```
进度记录 HistoryEntry{ sourceId = code, type=video, progress: VideoPlaybackProgress }
    └─ progress.sources[] ─ VideoPlaySource.episodes[] ─ VideoPlayEpisode
下载记录 DownloadRecord{ code, videoId, sourceKey, pluginName, mediaId,
                         episodes: Map<episodeNumber, DownloadEpisode> }
```

- 引用是**单向存字段**：下载记录存 `code`（`@HiveField(8)`），由它反查进度记录；
  进度记录不存下载 id。反向由"进度 code → `findRecordByCode`"完成。
- **物理 key 保持不变**：下载 box 的 key 仍是 `'${pluginName}_$mediaId'`。
  这是刻意的——它带来三个好处：
  1. 老数据零迁移（`code` 字段用 `defaultValue: ''` + `effectiveCode` 派生兜住）；
  2. 不需要把 key 改成 `sha256(code)`（Hive String key 上限 255 的问题不存在，
     因为 key 基于 int `mediaId`）；
  3. 磁盘目录名 `<mediaId>_<pluginName>/<episodeNumber>` 不用动。
  ⇒ 想"把 key 也换成 code"时请先读本节：那会把上面三件事一次性变成迁移工程。
- `mediaId`/`videoId`/`sourceKey`/`pluginName` 仍然保留：前者用于物理 key 与目录，
  后三者用于老记录派生 code 与（未来的）数据管理模块。

## 4. 三个入口 → 统一中间体 → 公共流程

| 入口 | 方法 | 骨架（结构权威） | `(s,e)` | writable |
|---|---|---|---|---|
| ① 插件调用 | `openFromPlugin` | 插件给的 `sources`（最新结构） | 插件指定 | **总是 true** |
| ② 进度记录 | `openFromHistory` | 记录里的 `sources`（自带状态） | 记录里的 last* 或面板选择 | true |
| ③ 下载记录 | `openFromDownload` | 反查到的进度记录的 `sources` | 下载记录的真实 `(sourceIndex, episodeIndexOf)` | **有骨架 true / 无骨架 false** |

公共流程 `_open`：决策（`PlayIntentDecider.decide`：本地短路 / 弹窗 / 只下载）
→ 构造 `VideoPageRouteArgs(code: ...)` → `pushNamed('/video/')`。

**写回口径（关键不变量）**

- `onProgressChanged` **只在拿到进度记录（骨架）时挂上**。
- ③ 反查不到进度记录时（「只下载」从没进过播放页 / 历史被删 / 私人模式）
  **只播本地文件、不写任何记录**——绝不用"只有一集"的 sources 去整表替换，
  否则会把整部剧的源/集列表削成单集。
- ③ 有骨架时**不要改写骨架里那一集的 `path`**：本地文件由播放页
  `playEpisode` 的"已下载 → 本地播放"短路（按 code + `(s,e)` 查）自动挑中。
  把本地路径写进 `path` 会让之后从 ② 进入时那一集变成 `local` 型，
  文件一删就播不了、也不会回退解析。

## 5. 集级身份：下标 + 二级校验

集级仍是下标 `(sourceIndex, episodeIndex)`（`VideoPlayEpisode` 没有集 id），
但合并时过一道校验（[mergeVideoProgressState]）：

- 线路名一致（任一侧为空则视为未知 → 放行）；
- 集标识一致：优先 `path.args[0]`（插件传的集参数，resolve 型集都带），
  其次 `path.url`，最后集名；任一侧为空 → 放行。

即**只在"两侧都有标识且不同"时拒绝合并**，宁可保留进度也不误丢。
被拒绝时按 `i` 级日志留痕，便于排查"进度没回填"的反馈。

防的是：插件换线路顺序、线路数量变化、同线路插集/重排导致进度串到别的集上
（下载侧同一风险由 `episodeNumber` 编码决定，回显会跟着错位）。

**插件契约**：`sources` 的顺序必须稳定，只允许在末尾追加集；重排/插入中间集
会使历史进度与下载状态错位。

## 6. 回归防线

`test/video_identity_and_merge_test.dart`：

- `VideoCode` 构造/拆分/记录侧派生（含空值拒绝语义）；
- `DownloadRecord.effectiveCode`：新记录读 code、老记录派生、极老记录空串、
  物理 key 与 code 解耦；
- `mergeVideoProgressState`：一致则回填；线路名不一致 / 集标识不一致则跳过；
  标识缺失则保守合并；无历史原样返回；只回填状态不改 `name`/`path`。

另外这些测试仍在守护周边不变量：`hive_type_id_test`（typeId 唯一）、
`download_episode_key_test`（集号编码互逆）、`player_no_navigation_test`、
`player_no_duplicate_entries_test`。
`lib/pages/player/` 内不得出现跳转他页的调用——所以编排层放在
`lib/pages/video/`，不要放进 player 目录。

## 7. 已知边界（有意为之，不是 bug）

- **手动播放**（我的页 → 手动播放）未纳入本次改造：它不带插件名，`code` 就是
  URL。它能播、能写进度，但下载命名空间走 `'wyw'`。该入口计划重做时一并收敛。
- **v2/迁移后的旧进度记录**：`sources` 为空、只剩 `videoUrl`，历史页点进去
  现在会提示"该记录没有可用的播放结构，请从插件详情页重新进入"（以前是 push
  进去再落到「无可播放资源」错误页）。清理由后续"应用数据管理模块"负责。
- **插件 id 的稳定性由插件保证**：宿主只能保证"同一个 id 一致"，无法保证
  "同一部作品恒等 id"。插件把作品 id 换成播放页 URL 会分裂成两个 code。
- **③ 的骨架可能过时**：骨架取自进度记录，站点改版后里面的 resolve 描述可能
  失效；失败时应有"重新解析/回详情页"的出口（与 ② 同）。
- **删除语义**：删进度记录后下载记录的 code 悬空 → ③ 走"无骨架"分支（可播、
  不写）；删下载记录不影响进度；私人模式下下载仍建、进度不写，属正常态。
