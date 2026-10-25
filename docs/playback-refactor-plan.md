# 播放行为规范重构计划

> 目标：规范播放器**进入入口**（PlayIntentDecider + 选择播放方式弹窗）与**进入后的集数切换**（playEpisode）的行为，充分接入下载模块与进度历史模块，消除两套判定逻辑的漂移。
> 状态：**未实施**，方案备查；文中部分文件路径已随后续重构失效（如 `playback_classify.dart` 已不存在）。

## 1. 背景与已查验事实

### 1.1 下载三分类（用户定稿）

| 分类 | 判定 | 入口行为 |
|---|---|---|
| ① localFile | 集路径本身是本地文件，或 `getLocalVideoPath` 命中（status==completed 且文件存在） | 本地播放，不弹窗 |
| ② downloading | `findEpisodeByIdentity` 且 status ∈ {pending, resolving, downloading} | 弹窗（合流推荐，显示下载 %） |
| ③ none | 其余（什么都没有） | **必须弹窗** |

### 1.2 现状违例（本会话已查验）

1. **入口第③步**（`decide`：`cachedUrl.isNotEmpty → return online`）让"有缓存直链但没有本地文件、没有下载记录"的内容直接在线播、不弹窗 —— 违背"第三种必须弹窗"。
2. **弹窗**（`showPlayIntentDialog`）不接收、不展示"历史直链 + 续播进度"，只展示下载状态行。
3. **`isOfflineMode`** 曾是整页粘性标志（已修：切集在 `playEpisode` 开头复位，只反映当前集）。
4. **切集判定**在 `playEpisode` 内联五分支，与入口判定两套逻辑，语义易漂移。
5. **历史直链/续播位置**的获取散在 `init_page`（383-403）与播放页 `configure → _applyHistoryProgress`，无单一入口。

### 1.3 已经是现成的（重构不动的部分）

- **直链复用**：入口处 `cachedUrl` 已从插件 resolvedUrl + 历史合并；进页后 `_applyHistoryProgress` 合并进 sources，`playEpisode` 第一分支 `currentEp.resolvedUrl.isNotEmpty → 直接用`。
- **续播恢复**：入口 `offsetMs` 已传入 `VideoPageRouteArgs`；切集时 `_resolveResumeOffset(url, …)` 按直链查历史位置。
- **合流在 ③none 但有直链时**：`playEpisode` 先取 resolvedUrl，`downloadStructuredEpisode(resolvedUrl: playUrl)` 直接用缓存链接建任务，不重新解析。
- **切集入口**：选集面板 → `_onEpisodeTap` → `playEpisode`，每次切集五分支重算（含 `isOfflineMode` 复位）。

## 2. 核心设计：共享判定层（单一事实源）

新增 `EpisodePlaybackClassify`（建议放 `lib/pages/video/playback_classify.dart`），**入口与切集共用**。

```dart
enum PlaybackCategory { localFile, downloading, none }

class EpisodePlaybackState {
  PlaybackCategory category;
  String? localPath;          // 仅 localFile
  DownloadEpisode? activeTask; // 仅 downloading
  String? cachedUrl;          // 插件/历史直链（none 时可能有）
  int? resumeOffsetMs;        // 历史续播位置
  bool downloadAvailable;     // 「只下载」可用性
  String statusLine;          // 弹窗展示行（下载 % 或续播位置）
}
```

输入：`{sourceKey, videoId, sourceIndex, episodeIndex, path, resolvedUrl}`。
判定序：
1. `path.type == local` 或 `findLocalVideoPathByIdentity` 命中 → **localFile**
2. `findEpisodeByIdentity` 且 status 为进行中 → **downloading**
3. 其余 → **none**；`cachedUrl` = 集上 resolvedUrl 或历史直链，`resumeOffsetMs` = 历史位置

## 3. 入口决策层重构（PlayIntentDecider + 弹窗）

### 3.1 decide 决策表（替换现状 ①-⑤）

| 判定结果 | 行为 |
|---|---|
| localFile | 直接本地播放（不弹窗） |
| downloading | 弹窗（合流推荐；statusLine = 正在下载 %；「只下载」置灰） |
| none | **必须弹窗**；有直链+位置 → 弹窗内显示「可续播 · 上次看到 mm:ss」；无直链 → 普通四项 |

### 3.2 弹窗展示与选项语义（none 分类）

- 新入参：`hasCachedUrl`、`resumeText`（`formatHistoryPosition` 格式化）
- 展示行位置：标题/集名下方、选项上方，仅在有直链时出现
- 选项：
  - 直接播放 → `online, allowProxyPlayback=false`（有直链时复用直链）
  - 合流播放 → `merge`（有直链时用它建任务，不重新解析）
  - 只下载 → prepare → resolve（有直链免解析）→ 建任务
  - 暂不播放 → none
- **删掉现状第③步**（`cachedUrl.isNotEmpty → return online`）

### 3.3 改动文件

- `lib/pages/video/play_intent.dart`：decide 改走判定器；dialog 加入参与展示行
- `lib/pages/init_page.dart`：传 `hasCachedUrl` / 续播文本给弹窗（`cachedUrl`/`offsetMs` 计算收敛到 ResumeContext，见 §5）

## 4. 切集行为规范（playEpisode 重构）

`playEpisode` 改为调用同一判定器，按分类 + 页内 `playMode` 执行（保持"整页模式"语义：进入时一次性决定，切集沿用）。

| 目标集分类 | 行为 |
|---|---|
| localFile | 本地播放（无视页模式；已完成不重复建任务/合流） |
| downloading + 页 merge | 直用任务 `networkM3u8Url`（免解析）；无直链则 prepare+解析建任务 |
| downloading + 页 online | 无视下载任务，正常在线解析播放（文档化为预期行为） |
| none + 页 merge | 有直链复用；否则解析 → `downloadStructuredEpisode` 建任务 |
| none + 页 online | 有直链复用；否则在线解析 |

- `isOfflineMode` 由判定器结果设置：`localFile → true`，其余 `→ false`（保持"当前集本地文件播放"语义）。
- 续播恢复沿用 `_resolveResumeOffset`（按直链查历史位置），不新增逻辑。

### 4.1 边界情况（文档化为预期）

| 情况 | 行为 |
|---|---|
| 暂停/失败任务 | 归入 none（弹窗「只下载」可用；合流页 prepare 幂等重解析建任务） |
| 已删除文件的 completed 记录 | `getLocalVideoPath` 不命中 → none（合流页重建任务） |
| 切回当前集 | `_onEpisodeTap` 直接关面板，不重播 |

## 5. 进度历史模块集成：ResumeContext

新增单一查询（收敛 init_page 与播放页的历史读取）：

```dart
class ResumeContext {
  final String cachedUrl;   // 插件 resolvedUrl 兜底，历史直链覆盖
  final int positionMs;
  static ResumeContext forEpisode({
    sourceKey, videoId, sourceIndex, episodeIndex, fallbackResolvedUrl,
  });
}
```

- **入口**（init_page）：`ResumeContext.forEpisode(...)` 结果给弹窗展示 + `offsetMs` 传入播放页。
- **播放页**：`configure → _applyHistoryProgress` 保持（把历史直链/位置合并进 sources 供切集复用）。
- **弹窗展示**、**直链复用**、**续播恢复**全部读同一来源。

## 6. 下载模块集成

- 判定器统一调用：`findLocalVideoPathByIdentity`、`findEpisodeByIdentity`、`hasActiveDownloadByIdentity`（并入判定序）。
- 合流生命周期保持：`downloadStructuredEpisode`（幂等）、`prepareStructuredEpisode`、`maybeStartProxyForPlaybackByIdentity`。
- 「只下载」统一：有直链免解析（现状已支持，收敛入口）。

## 7. 测试计划

- **判定器单测**：三分类；下载各状态；completed 但文件缺失；直链有无；历史位置有无。
- **入口**：none+直链 → 弹窗且显示续播行；localFile 不弹窗；downloading 弹窗合流推荐 + 「只下载」置灰。
- **切集**：已下载 → 本地播放；进行中+merge → 直用直链；进行中+online → 在线播；`isOfflineMode` 随切集正确翻转。
- **回归**：现有 399 用例不回归。

## 8. 实施顺序（建议）

- **P1**：判定器 + decide 重构（删第③步、分类化、传参）→ 切集接入判定器
- **P2**：弹窗展示直链 + 续播进度
- **P3**：ResumeContext 收敛历史查询
- **P4**：测试 + 全量回归 + 真机验证（入口各分类、切集各分类、窄屏菜单、离线/在线互切）

## 9. 明确不改的范围

- 切集**不走** PlayIntentDecider（那是"从外部进播放页"的决策层）；切集是页内 playEpisode 直接决策。
- "整页模式"（进入时一次决定的直接播放/合流播放）语义保持，不引入逐集重决策（除非后续另行拍板）。
- 弹窗选项集（直接播放/合流播放/只下载/暂不播放）不变。
