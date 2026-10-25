# 播放器分屏面板 · 重做计划（v2）

> **状态：待拍板，未实施。**
> v1（提交 `7562f8a`…`94ac4bc`，7 个提交 / 17 个文件 / +2164 −157）因代码质量不达标已回滚，
> 完整存档于分支 `backup/player-split-panel`（含回滚前未提交的设置同步 WIP，见 `34134fe`）。
> **基线 = 回滚后的 `main`（`ac743ed`）**：`flutter analyze` 无问题，**409 个测试全绿**。
> v1 存档分支上同样 analyze 干净、**425 例全绿**——所以回滚理由是**设计与契约**，不是"编译不过/测试红"。
>
> **契约以本文档 §1.3 为准（5 个 tab）。**
> `docs/player-split-panel-mockup.html` / `.png` 是 **4 tab 历史稿**，与 §1.3 不一致，P0 内必须同步为 5 tab——
> v1 的返工正是从"计划写 5 tab、实现与设计稿做 4 tab"的漂移开始的。
> 与 Kazumi#1916 的对照见 `docs/kazumi-wyw-player-panel-comparison.md`。

## 实施进度

| 切片 | 状态 | 结果 |
|---|---|---|
| **P0 共用原语** | ✅ 完成 | 见下方落地记录；`flutter analyze` 干净，测试 409 → **451** 全绿 |
| **P1 布局壳** | ✅ 完成 | 分屏可用：拖动/夹取/双击复位/开合动画/比例持久化/顶栏 ⚙ |
| **P2 选集 tab** | ✅ 完成 | 面板「选集」tab 与视频页选集面板**同一份 widget**、同一套语义；含自动定位当前集与逐集下载状态 |
| **P1.5 视频区尺寸口径** | ✅ 完成 | seek 灵敏度 / HUD 判据 / 弹幕 `compactLayout` 改用视频区实测尺寸 |
| **P3 弹幕 tab** | ✅ 完成 | 总开关 + 来源开关 + 共用显示组 + 三个二级页；顺带抽出 `DanmakuSourceContent` / `DanmakuTimeOffsetContent` 两个无头件 |
| **P4 画面 tab** | ⏳ 收尾中 | 画面调节（含预设 CRUD 内嵌）/ 超分 / 比例 / 视频信息二级页 |
| **P5 播放 tab** | ✅ 完成 | 倍速/音量/跳过/定时关闭（含自定义）/PiP/投屏/外部播放/截图 |
| **P6 更多 tab + 旧入口退场** | ✅ 完成 | 调试/刷新；旧入口全部退场（下详） |
| **用户反馈修复** | ✅ 完成 | 分界线改为面板边框 + 拖动跟手 + 去掉黑色分隔（下详） |

### 分界线（用户反馈后的最终形态）

用户连续报了两个问题，都改掉了，也都在 v1 存档里找到了对照：

| | v1（已回滚） | 中间版本（错） | 现在 |
|---|---|---|---|
| 拖动基准 | State 字段，`setState` 内同步写回 | 构建时传入的 `extent`（一帧前快照）→ **丢增量**（鼠标走两份、线走一份） | State 字段 `_dragExtent`，同步累加 |
| 可见的线 | 贴面板前沿（`Alignment.centerLeft`） | 自绘一条线，浮在热区中央（距面板边 ~4px） | **面板前沿边框**（线就是面板的边） |
| 热区 | 12px，叠在面板内容上（竖屏吃掉页签条 8px） | 独占 8px 槽位 → 露出容器底色成**黑色分隔** | 8/12px 叠在交界线上（各半：不吃内容、不留缝） |

教训：**热路径（拖动）上的累加必须同步**——把权威值收进 controller 之后仍不能用"构建时快照"当拖动基准；v1 这点原本是对的。

### 最终形态：几何与拖动改用成熟组件 `multi_split_view`

用户实测后判定：**渲染速度没问题，是手搓的交互逻辑不够成熟**。因此把几何/拖动整套交出去，只保留本项目特有的契约。

| | 手搓（已废弃） | 现在（`multi_split_view` 3.6.2） |
|---|---|---|
| 拖动/热区/坐标 | 自写 `GestureDetector` + 增量累加 + clamp | 组件内部负责（`resizable` + `dividerHandleBuffer`） |
| 鼠标光标 | 自写 `MouseRegion` | 组件按轴向给 `resizeColumn/resizeRow` |
| 双击复位 | 自写双击判定 | 组件 `onDividerDoubleTap` |
| 尺寸夹取 | 自写 clamp | `Area(min:, max:)`（clamp 值仍由本项目纯函数算） |
| 可见的线 | 自绘浮在热区中央 | **布局槽位就是那条线**：`dividerThickness: 1` + 线自身绘制，零空隙 |

迁移时踩到并修掉的两个**真机运行时异常**（都已写成回归测试）：

1. `Cannot interpolate between finite constraints and unbounded constraints`：悬停加粗用了 `AnimatedContainer`，横竖屏切换时它在「有限/无界」宽高之间补间 `BoxConstraints` → 框架断言。改为 `TweenAnimationBuilder<double>` 补间**一个 double**。
2. 开合动画期间面板被按**动画中的尺寸**布局（小到 0.6px）→ 页签条 `Row` 溢出 39px、二级页 `Column` 溢出。改为面板内容**按目标尺寸布局 + `ClipRect` 只裁剪可见部分**（顺带让面板在动画期间完全不重排）。
3. 另修：`Area` 的写入一律延后到 build 之后（`didUpdateWidget` 处于 build 阶段，直接写会触发 `MultiSplitView` 的 `setState() called during build`）。

### P5 / P6 落地记录（旧入口退场）

- `player_item_panel.dart` **1359 → 约 650 行**：底栏宽屏 MenuAnchor 簇（超分/倍速/比例）、顶栏「更多」菜单全部项、顶栏下载按钮及其 6 个私有辅助方法、一个无调用者的死代码 `showSetSpeedSheet`、16 个 import 全部删除。
- 承载方逐项对照（完整表见提交信息）：超分/比例 → 画面 tab；倍速/定时关闭/画中画/投屏/外部播放/截图 → 播放 tab；弹幕设置 → 弹幕 tab；选集+下载 → 选集 tab；视频详情/画面调节 → 画面 tab 的二级页；重新解析 → 更多 tab；窄屏弹幕开关 → **顶栏常驻**（去掉 `if (!compact)`，菜单没了不能丢入口）。
- 定时关闭**保留了「自定义」**（v1 曾在这里漏掉，属功能回归），剩余时间走 `remainingSecondsNotifier` 实时刷新。
- `player_panel_hold.dart` **不能整删**：`PlayerPanelHold` 的 lease 仍被 `player_item.dart` 与保留的顶栏/底栏使用；只删掉已零引用的 `PlayerPanelHoldMenuAnchor`，并在文件头写明。
- 收尾时清掉的死接口：`PlayerItemPanel.handleSuperResolutionChange` / `showVideoInfo` / `toggleEpisodePanel`（顶栏选集按钮随之不再渲染）、`player_item.dart` 的 `showVideoInfo()`、以及因此**不可达**的 `video_details_sheet.dart`（文件已删除；内容件 `VideoDetailsContent` 保留给二级页）。
- 把 `PlayerPlaybackController.playerDebugMode` / `buttonSkipTime` 补成 `@observable`（并按项目约定用 `--build-filter` 重新生成 mobx 代码），删掉两个 tab 里为绕开"非 observable"而加的私有 `ValueNotifier` 重建信号；两个 tab 因此回到无状态。

### 新增测试

| 文件 | 覆盖 |
|---|---|
| `test/player_split_geometry_test.dart` | 29 条：clamp/默认档/越界判定（纯函数） |
| `test/player_split_layout_test.dart` | 15 条：可见性与轴向、记忆值夹取、拖动方向与单位、**拖动不丢增量**、饱和值、双击复位、开合动画、**视频+面板=容器宽（无空隙）** |
| `test/split_panel_scaffold_test.dart` | 6 条：页签渲染/切换回调、**切走再切回不重建（保活）**、二级页头部与返回、关闭、窄面板不溢出 |
| `test/player_split_tabs_test.dart` | 面板级窄宽度体检：280×420 下渲染各 tab / 二级页 |
| `test/player_no_navigation_test.dart` | 守卫：`lib/pages/player` 内不得出现跳转他页的调用（剥注释口径） |
| `test/player_no_duplicate_entries_test.dart` | 守卫：已退场的旧入口标识符不得再出现（禁止双入口，v1 的返工原因） |

### 死外壳清理（面板接管后）

面板承载了对应功能后，两个播放器弹层已**零调用者**，按 §2.3「外壳删除」一并删掉：

| 文件 | 原行数 | 现在的承载方 |
|---|---|---|
| `lib/pages/player/widgets/video_filter_sheet.dart` | 64 | 画面 tab → 「画面调节」二级页（`FilterSubPage`，内嵌 `FilterPresetsBody`） |
| `lib/pages/settings/danmaku/danmaku_settings_sheet.dart` | 157 | 弹幕 tab（共用 `DanmakuDisplaySection` + 三个二级页） |

同样因不可达而删除的还有 `lib/pages/player/video_details_sheet.dart`（承载方：画面 tab 的「视频信息」二级页）。

### 面板架构（P2 定型）

- **`SplitTabHost`**（`lib/pages/player/split_tabs/split_tab_host.dart`）：把面板需要的一切收成一个值对象。v1 把 13 个必填回调摊在 tab 构造参数上，每加一项都要改两处签名。
- **装配点唯一**：`buildSplitPanelTabs(host)` / `buildSplitSubPage(host, page)`（`split_tabs/player_split_tabs.dart`），页签与二级页各一个文件，便于并行开发与评审。
- **二级页用类型分派**（`SplitSubPage` enum），不是字符串——改名不会静默变成空 body。
- **状态**：可见性 / 页签 / 二级页 / 两方向比例全在 mobx `PlayerPanelController`；切页签自动退回列表层。

### 旧入口退场的顺序调整（与 v1 计划不同，已生效）

原计划把「顶栏选集/下载按钮退场」放在 P2。实际执行时发现：这两个按钮牵连视频页的
`_toggleTabBodyAnimated` → `_showPortraitEpisodeSheet` → `_episodePanelKey` →
`_revealCurrentEpisode` 一整串私有方法，以及底栏 MenuAnchor 簇与「更多」菜单里
`_buildDownloadButton` 的 4 个辅助方法。**半拆会留下死代码**（`unused_element`），
且此时面板的对应 tab 尚未全部就位、无法验证"无重复入口"。

因此改为：**所有旧入口退场集中在 P6 一次完成**，验收方式为
「点面板各入口后路由栈不变」测试 + `git grep pushNamed lib/pages/player` 为空 +
无重复入口清单核对。P2 只负责把「选集」tab 做成功能对等（同一份
`EpisodeSelectionPanel`、同一套下载语义），不动旧入口。

### P2 落地记录

- `split_tabs/tab_episodes.dart`：与视频页选集面板**同一份 widget**（`EpisodeSelectionPanel`），参数语义照抄 `video_page.dart` 的两处调用；两处**关键差异**按契约修正：
  - `isOffline` 用 `isCachedOnlyPlayback`（"整季可离线"），**不是** `isOfflineMode`（那只是"当前这一集是本地文件"，会让整季在线剧集错误显示"已缓存"并抑制逐集标签——`video_controller.dart` 有明确注释）；
  - `isPlaying` 用视频页判据（`playing && !playback.loading && !videoPageController.loading`）。
  - `onDownload` 与 `downloads` 都接上了（v1 是 `downloads: const {}` + 不给 `onDownload`，按钮恒禁用）。
- 进入本页自动定位当前集（`revealCurrentEpisode()`，post-frame）。
- 视频页 → 播放器页新增两条回调：`onEpisodeSelected`（0 基，与 `_onEpisodeTap` 同语义）、`onDownloadEpisode`。
- **PiP 联动**：`mobx.reaction` 监听 `videoPageController.isPip`，进入画中画自动收起面板（退出不恢复）。
- **Esc（桌面）**：先退二级页，再收面板；面板没开时不拦截按键。

### P1.5 落地记录

新增 `_videoRegionKey`（挂在视频区 `MouseRegion` 上），以**视频区 RenderBox 实测尺寸**替代整窗 `MediaQuery`：

| 位置 | 改动 |
|---|---|
| 水平拖动 seek 灵敏度 | `180000 / 视频区宽`（原来用窗口宽：面板占掉一部分后灵敏度不再对应视频内比例） |
| 控制栏显隐判据 | 指针坐标先 `globalToLocal` 到视频区，再与视频区高度比较（原来用整窗坐标） |
| 弹幕 `compactLayout` | 用视频区 `shortestSide`（原来用整窗最短边） |

首帧拿不到 RenderBox 时回落到整窗值；弹幕侧另有每秒 `syncCanvasOptionIfChanged` 自校正。

### P0 落地记录

- **`CapsuleTabStrip` / `CapsuleTab`**（`lib/bean/settings/capsule_tab_strip.dart`）：收藏页改为使用共用件，页面内 45 行手抄 TabBar 删除；`indicatorAnimation: TabIndicatorAnimation.elastic` 全仓**只剩共用件一处**。
- **`DanmakuDisplaySection`**（`lib/pages/settings/danmaku/danmaku_display_section.dart`）：设置页与播放器 sheet 的**两套滑杆实现合并为一份**（删重复 317 行，换单份 270 行；两宿主文件净 −266 行）。副作用（**验收时需确认**）：
  1. 设置页的「字体大小 / 不透明度」由「弹幕样式」卡移入共用卡（其余行位置不变）；
  2. sheet 的「停留时间 / 跟随视频倍速」随共用件进入「外观」tab，「播放」tab 只剩「校准与过滤」；
  3. 统一采用设置页语义：字号走 `compactLayout`（不再优先读画布 option）、不透明度推给画布时取两位小数。
- **`VideoDetailsContent`**（`lib/pages/player/widgets/video_details_content.dart`）：视频详情弹层 325 → **54 行**薄外壳，内容件无头、两个 padding 均为**必填参数**（无 `embedded` 布尔）。
- **`player_split_geometry.dart`**：clamp/默认值/越界判定收敛为纯函数 + **29 个单测**。单位歧义已消除：横屏 `resolvePanelWidth`（像素）、竖屏 `resolvePanelHeight`（占比），**不提供**含糊的 `resolveExtent(axis, ratio)`。
- **设计稿同步**：`docs/player-split-panel-mockup.html` / `.png` 已由 4 tab 改为 **5 tab**（PNG 用无头 Chrome 重渲染）。
- **「padding 常量中性化」的落地方式**：改为「内容件无头 + 边距由外壳以参数传入」，因此**不需要**新建常量文件（当前没有第二个消费者）；面板自身边距保持文件私有，禁止设置层 import 播放器面板（§6-7）。

### P1 落地记录

- 新增 `widgets/player_split_layout.dart`（136 行）、`widgets/player_split_divider.dart`（86 行）、`player_split_panel.dart`（121 行）。
- 面板状态全部进 mobx `PlayerPanelController`（可见性 / 页签 / 两方向比例 + 防抖落盘 + `dispose` flush 与 cancel），页面零 `setState` 新增；`player_item.dart` 只做挂载与开合转发。
- 分界线热区**独占槽位**（不再像 v1 那样 `Stack` 叠在面板内容上）；视频区与面板区是两个独立子树，顺带修掉基线就有的真 bug：**右侧区域悬停/滚动不再误改音量**。
- 面板**常挂载**：关闭时尺寸动画到 0（内容经 `OverflowBox` 仍按目标尺寸布局），因此关闭再打开不丢页签内状态。
- 新增 **13 个布局测试**（`test/player_split_layout_test.dart`）：可见性/轴向、记忆值夹取、拖动方向与单位、饱和值、双击复位、动画开关。
- ⚠️ **旧入口尚未退场**：底栏超分/倍速/比例 MenuAnchor 簇、「更多」菜单、顶栏选集/下载按钮仍在，面板当前是占位——这是分片推进的中间态，按 P2–P6 逐项迁移，**P6 用「点面板各入口后路由栈不变」测试 + `git grep pushNamed lib/pages/player` 为空收口**（§6-8）。

## 0. v1 复盘（下列每条都是 v2 某条硬约束的来源）

| # | v1 症状 | 证据 | v2 硬约束 |
|---|---|---|---|
| 1 | **先自造 UI、事后才改用既有组件**，随后 4 个提交只在抠边距 | 提交 `d3cf2df`「样式重做：**改用**设置页组件与收藏页页签条」、`abec6af`、`064de7a`、`94ac4bc` 全是 12/16 边距来回调 | 面板行**只准**用 `SettingsList`/`SettingsSection`/`SettingsSliderTile`/`SelectTile`/`SettingsTile`；页签条先抽共用件再用；禁止自造行样式 |
| 2 | **「收编」根本没发生**：面板只是第 5 个并行入口 | `player_item_panel.dart` 仅 +18 行（只加了 ⚙），底栏超分/倍速/比例 MenuAnchor、更多菜单、顶栏选集/下载按钮、`player_panel_hold.dart` 一个没删 | 面板落地时**同步删除**旧入口；验收 = 「点面板各入口后路由栈不变」测试 + `git grep pushNamed lib/pages/player` 为空 |
| 3 | **同一功能两份实现** | 定时关闭：旧 `player_item_panel.dart:1252-1299`（含自定义/`formatMinutesToDisplay`/`remainingSecondsNotifier`）vs 新 `tab_settings.dart:127-150`（**少了自定义**、裸分钟、`setState((){})`）；投屏逐字重复 | 一个动作只允许一个实现，迁移=移动而非复制 |
| 4 | **状态归属违背项目惯例** | 5 个字段 + 1 个 Timer 用 `setState` 塞进 1414 行的 `_PlayerItemState`，而同面板的 `aspectRatioMode`/`showVideoController` 都在 mobx `PlayerPanelController`(54 行) | 面板状态**全部**进 `player_panel_controller`；clamp 抽纯函数 + 单测 |
| 5 | **超大文件继续膨胀** | `player_item.dart` v1 净 **+313 行**（1414→1727），新增 18 个方法、6 类职责 | `player_item.dart` 增量 **< 40 行**；布局/面板/各 tab 各自独立文件 |
| 6 | **复制粘贴而非共用** | 页签条手抄收藏页且数值漂移（radius 20 vs 24、Tab 高 40 vs 48、minWidth 56 vs 64、padding 14 vs 16），还丢了 `Semantics`/`PageStorageKey` | "照 XX 页同款"必须落到代码共用；共用件抽到 `lib/bean/**` |
| 7 | **反应式同步打补丁** | WIP 在 `GStorage.putSetting` 塞全局广播（`watchSetting` 零消费者=死代码，`reset*` 又不广播=自身不一致），订阅端 `setState` 重读 20 个键；面板侧压根没订阅 | 禁止在存储层加全局副作用；靠"共用内容 widget + 单一数据源"消除同步需求 |
| 8 | **内容/外壳用 `embedded` 布尔分叉** | `danmaku_settings_sheet.dart:107/115/123/236`、`danmaku_time_offset_sheet.dart:91-99`、`video_details_sheet.dart:104/111/125/256`；且设置层为拿一个 `EdgeInsets` **反向 import** 播放器面板（三处） | 内容件永远无头、`padding` 由外壳传入；禁止 `lib/pages/settings/**` import `lib/pages/player/player_split_panel.dart` |
| 9 | **几何/交互契约未达成** | 无开合动画（`disableAnimations` 新文件零引用）、无 `Esc`/快捷键、PiP 不收起面板、面板一关就销毁全部 tab 状态、热区压住页签与列表可点区、持久化 Timer 在 `dispose` 未 cancel | 见 §1.2、§3；每条都要有对应验收 |
| 10 | **拖分界线每帧重建整页** | `setState` 在 build 整体 `Observer` 内（1239-1262），音量/倍速任一变化即整页 + 整面板重建 | 拖动只重建面板；面板数据不因无关 observable 变化而重建 |
| 11 | **手势换算仍用整窗尺寸** | `player_item.dart:1665` `180000 / MediaQuery.sizeOf(context).width`；悬停判据同用整窗高 | 视频区被压窄后，seek 灵敏度/HUD 判据/弹幕 `compactLayout` 全部改用视频区实测尺寸 |
| 12 | **需求中途漂移** | 计划 5 tab / 设计稿 4 tab / 实现 4 tab；横屏默认值从"360px"悄悄改成"自动 W/3"（只改了 `settings_keys` 注释） | 契约先冻结；改动必须同步改计划 + 设计稿 + 键注释 |
| 13 | **没有"完成"的定义** | 7 个提交里 4 个是同一件事的反复微调 | 每片自带验收：analyze 干净 + 测试绿 + 手动核对项 |

## 0.1 v1 里值得保留、直接沿用的东西

1. **`PlayerSplitter` 的契约**：一条线、不占布局宽度、`onDelta` 归一为"面板变大为正"、双击复位、光标按方向——单一职责、纯 UI、可单测（热区位置与尺寸需按 §1.2 修正）。
2. **`PlayerSplitSubpage(title, body)` 值对象**：二级页 = 标题 + body + 返回回调，是"替换 body、不重放动画"的好落点（v2 改为类型化枚举，见 §6）。
3. **`FilterPresetsBody` 的"内容体 + 薄壳"范式**（`filter_presets_settings.dart:14-81` + 83-94）：设置页与面板同源、路由不破——v1 唯一完全正确的一次抽取，应在弹幕显示组、详情 Info/Log、跳过秒数上照做。
4. **一个真 bug 修复**：把悬停与滚轮监听从整容器移到视频区（此前在右侧区域滚动会改音量）。**与面板无关也应独立保留**。
5. **`TabController` 生命周期写法**：`initState` 建 + `dispose` 移除 listener（懒建会在 dispose 抛异常）。
6. **两个比例键的落点**：方向分开记忆、注册进 `byGroup` 分组（支持"恢复默认"）；只需统一"0 = 自动"的语义（§1.2）。
7. **测试手法**：分界线增量符号测试、"窄面板不溢出 = `takeException() isNull`"、多档宽度扫描、Hive 临时目录 bootstrap（抽成共享 helper）。
   **反面**：`expect(padding.left, 16)`、`tester.widget<ListView>(...).padding`、`findsNWidgets(2)` 这类断言打在常量与私有实现上，v2 禁止（§5）。

## 1. 交付契约（冻结，动手后不改）

### 1.1 形态

| 场景 | 切分 | 视频区 | 面板区 |
|---|---|---|---|
| 横屏（桌面窗口、全屏、平板横屏） | 左右 | 左，占满高度 | 右，宽可拖 |
| 竖屏（手机竖屏，含全屏） | 上下 | 上，占满宽度 | 下，高可拖 |
| PiP | 不切分 | 整窗 | **进入 PiP 自动收起**；退出**不**自动恢复 |

- 切分在播放器容器**内部**，容器尺寸不变；视频等比缩放居中留黑边（遵循 `aspectRatioType`）。
- 弹幕层 / 手势层 / HUD / 截图反馈层 / 控制栏全部随视频区（`Positioned.fill` 相对视频区）。
- 面板呼出**不暂停、不遮挡**视频；控制栏照常 4s 自动隐藏，两者互不干扰。
- 全屏切换 / 换集 / 换线路 / 换源：面板保持当前 tab 与开合状态。

### 1.2 分界线与开合

- 视觉：**只有一条线**（不加把手/图标、不占布局宽度）；悬停/拖动变主题色并加粗到 3px。
- 热区：整条线可拖；**桌面 ≥8px / 触摸 ≥12px**（按输入类型区分）；桌面光标 `col-resize`/`row-resize`。
- **热区不得压住页签条与列表的可点区域**（v1 用 `Stack` 叠在面板内容上，吃掉竖屏页签上沿 8px / 横屏左侧 12px）。
- clamp（到边界即停，无回弹）：横屏面板宽 `280 ~ min(640, 容器宽 − 420)`；竖屏面板高 `30% ~ 70%`。
- 复位：双击（双触）→ 回默认（横屏自动档 `clamp(可用宽/3, 320, 420)`；竖屏 `0.45`）。
- 动画：拖动实时无动画；**开合 360ms**；`disableAnimations` 时瞬时。
- 持久化：`playerSplitRatioLandscape`（`0` = 自动档，取 `clamp(W/3,320,420)`）、`playerSplitRatioPortrait`（默认 `0.45`）——**"0 = 自动"的语义必须在计划、键注释、代码三处一致**；拖动落盘要防抖，但**离开页面时 `dispose` 必须 flush + cancel Timer**（v1 两个都没做）。
- 窗口变小导致比例越界时：clamp 显示并**落盘修正值**，避免下次从旧大值起跳。

### 1.3 面板内容（**5 个 tab**）

| tab | 内容 | 收编来源 |
|---|---|---|
| **选集** | 线路/播放源 chips（切换即重载）；集列表（当前集高亮、点击切集、**每集带下载按钮与状态**）；**进入自动定位当前集**（`revealCurrentEpisode()`） | 顶栏选集按钮（`toggleEpisodePanel`）+ 顶栏下载按钮 |
| **弹幕** | 总开关（与顶栏按钮**双向同步**）；来源开关；显示效果（字号/不透明度/时长/行高/滚动/顶部/底部/跟随倍速）；**时间偏移**（二级）；**屏蔽设置**（二级）；**弹幕检索换库**（二级） | 弹幕设置 sheet + `danmaku_source_sheet` + `danmaku_time_offset_sheet` |
| **画面** | **画面调节**（预设 chip + 5 滑杆 + **预设管理内嵌**：新建/重命名/删除）；超分辨率；视频比例；**视频信息**（二级：Info/Log） | 底栏超分/比例 MenuAnchor + 更多菜单的画面调节/视频详情 + `filter_presets_settings` |
| **播放** | 倍速（滑杆 0.25~4x + 常用档位）；音量；**跳过片头/片尾秒数**；**定时关闭**（含**自定义**）；画中画；外部播放；截图（入口 + 历史/候选列表；"选帧/裁剪确认"保留为临时弹层） | 底栏倍速 MenuAnchor + 更多菜单的定时关闭/画中画/外部播放 + `skip_seconds_dialog` + `player_screenshot_sheet` |
| **更多** | 播放器调试开关 / 调试信息；刷新播放源 / 重新加载。**不设任何"跳转设置页"入口** | 更多菜单的重新解析 + `player_debug_controller` |

> 长尾项（默认倍速、硬解开关、后台播放、动画开关等）**不进面板**：它们是"一次性配置"，留在设置页。

### 1.4 硬原则

1. **播放页内不允许跳转他页**：不得出现 `pushNamed`/`Navigator.push`/`Modular.to`（含「去设置页」「管理预设」类入口）。
   存量违规必须一并修掉：`lib/pages/player/widgets/video_filter_sheet.dart:37`（改为一律不跳、面板内完成 CRUD）。
2. **设置页与面板同源**：内容 widget 共用、外壳各管各的、存储层为唯一事实源；两者互不跳转。
3. 播放器页只留播放相关：顶栏（返回/标题/跳过片头/弹幕开关/**面板开关 ⚙**）、底栏（播放暂停/上下集/进度条/音量/全屏）、手势与 HUD 不变。
4. 快捷键：**新增"呼出/收起面板"**（实施时查 `keyboardShortcuts` 选未占用键位）；桌面 **`Esc` 关面板**；二级页时 `Esc` 先返回上一级。

## 2. 架构与落点

### 2.1 新增（带行数预算）

| 文件 | 职责 | 预算 |
|---|---|---|
| `lib/pages/player/widgets/player_split_layout.dart` | 布局壳：轴选择 + clamp 调用 + 开合动画，持有视频区/面板区两个 child | ≤200 |
| `lib/pages/player/widgets/player_split_divider.dart` | 分界线：热区（含 gutter 落位，不压内容）、光标、拖动、双击复位、悬停高亮 | ≤150 |
| `lib/pages/player/controller/player_split_geometry.dart` | **纯函数**：`resolvePanelExtent(axis, available, ratio)` / `clampExtent` / `defaultExtent`——可单测 | ≤120 |
| `lib/pages/player/player_split_panel.dart` | 面板外壳：头部 + 页签条 + body 切换 + 二级页栈 | ≤200 |
| `lib/pages/player/split_tabs/tab_episodes.dart` | 选集 tab | ≤300 |
| `lib/pages/player/split_tabs/tab_danmaku.dart` | 弹幕 tab（薄壳，挂共用内容件） | ≤200 |
| `lib/pages/player/split_tabs/tab_display.dart` | 画面 tab | ≤300 |
| `lib/pages/player/split_tabs/tab_playback.dart` | 播放 tab | ≤300 |
| `lib/pages/player/split_tabs/tab_more.dart` | 更多 tab | ≤200 |
| `lib/bean/settings/capsule_tab_strip.dart` | 胶囊页签条（自 `collect_page.dart:295-336` 提取，收藏页与面板**共用**） | ≤120 |
| `lib/bean/dialog/*` | 面板专用 padding 常量落中性位置（不得放 `player_split_panel.dart`） | ≤20 |

### 2.2 扩展（不重写）

- `lib/pages/player/controller/player_panel_controller.dart`（现 54 行）：新增
  `splitPanelVisible` / `splitPanelTab`（enum）/ `splitPanelSubPage`（enum?）/ `splitRatioLandscape` / `splitRatioPortrait`
  + actions `openSplitPanel(tab)` / `closeSplitPanel()` / `toggleSplitPanel()` / `openSubPage(page)` / `backSubPage()` / `setSplitRatio(axis, value)` / `resetSplitRatio(axis)`。
  比例持久化（防抖 + `dispose` flush）也归它，不留在页面。
- `lib/services/storage/settings_keys.dart`：两个比例键（含"0 = 自动"注释准确）。
- `lib/pages/player/player_item.dart`：仅把现有视频栈包进 `PlayerSplitLayout`，顶栏加 ⚙，接 `Esc`/快捷键。**增量 < 40 行**。
- `lib/pages/player/player_item_panel.dart`：**删除**被面板收编的底栏 MenuAnchor 簇、更多菜单项、顶栏选集/下载按钮。
- `lib/pages/player/player_panel_hold.dart`：无引用后删除。

### 2.3 内容 widget 抽取（P0 完成，后置阶段只挂壳）

| 设置组 | 现状（既有债） | v2 |
|---|---|---|
| 弹幕显示组（字号/不透明度/时长/行高/滚动/顶部/底部/跟随倍速） | 设置页 `danmaku_settings.dart`(397) 与 sheet `danmaku_settings_sheet.dart`(278) **两套滑杆实现** | 抽 `DanmakuDisplaySection`（无头内容件），设置页/sheet/面板三处共用 |
| 画面调节 | 已共用 `VideoFilterSliders`/`VideoFilterPresetPicker`/`FilterPresetsBody` | 保持；外壳改为面板内嵌（消灭跳页） |
| 时间偏移 / 屏蔽 | 已共用（双壳） | 保持，进弹幕 tab 的二级页 |
| 详情 Info/Log | `video_details_sheet.dart`(303) | 抽无头内容件，详情二级页与 sheet 共用 |
| 跳过秒数 | 无共用 | 抽共用输入件，播放 tab 内嵌（替代弹窗） |
| 定时关闭 | 旧菜单实现（含自定义） | **移动**旧实现（连同 `formatMinutesToDisplay`/`notifier`），不新写 |

## 3. 状态与数据流

- **几何**：`PlayerSplitLayout` 用 `LayoutBuilder` 实测容器尺寸，调用 `player_split_geometry.dart` 的纯函数算 clamp；**不用 `MediaQuery` 猜**。
- **状态**：面板可见性/tab/二级页/两方向比例全在 mobx `PlayerPanelController`；订阅一律 `Observer`，不层层传回调，不用 `setState`。
- **重建范围**：拖动分界线只让布局壳与面板重建，**不得重建整个播放页**；面板内容不因音量/倍速等无关 observable 变化而重建。
- **视频区尺寸传播**：视频区实测尺寸（不是整窗）供 seek 灵敏度、HUD 判据、弹幕 `compactLayout`/canvas option 使用。
- **设置读写**：内容件不各自 `setState` 读 Hive；走既有 controller（如 `VideoFilterController`）。
  **共用内容件 + 单一数据源 ⇒ 不存在双向同步问题**，因此不需要 v1 那套广播补丁（§0-7 明令禁止）。
- **二级页**：`enum SplitSubPage { filter, videoInfo, shield, timeOffset, danmakuSearch }` + `splitPanelSubPage`（**禁止 `enum.name` 字符串桥接**）；二级页替换 body、带返回箭头、不重放动画；返回回原 tab；切 tab 不丢 tab 内状态（内容件保持挂载）。

## 4. 实施切片（每片独立提交、独立验收）

> 顺序不可换：**先共用原语 → 再壳 → 最后填内容**。每片结束 `main` 都保持可用。

- **P0 共用原语**：抽 `CapsuleTabStrip` 并让收藏页改用它（外观/行为不变，删除手抄）；
  抽 `DanmakuDisplaySection` 并让设置页/sheet 改用它（**消既有债**）；
  抽详情 Info/Log 无头内容件；落 `player_split_geometry.dart` + 单测；把 padding 常量移到中性位置；
  **同步 `docs/player-split-panel-mockup.*` 为 5 tab**。
  验收：收藏页与弹幕设置行为不变；新增几何/纯函数单测绿；设计稿与 §1.3 一致。
- **P1 布局壳（到此处停下来给用户看）**：`PlayerSplitLayout` + `PlayerSplitDivider` + 控制器状态 + 比例持久化 + 开合动画；顶栏 ⚙；面板 body 先占位。
  验收：横竖屏切分正确；拖动实时；双击复位；clamp 上下界；重启恢复；动画 360ms 且 `disableAnimations` 瞬时；热区不压内容；**应用可启动、可肉眼验收**。
- **P2 选集 tab**：线路 chips + 集列表（**带下载状态与 `onDownload`，用 `video_page.dart:254-267` 的正确语义**，不用 `isOfflineMode`）+ 自动定位当前集；顶栏选集/下载按钮退场。
- **P3 弹幕 tab**：总开关双向同步 + 来源开关 + 共用显示组 + 时间偏移/屏蔽/检索三个二级页。
- **P4 画面 tab**：画面调节（含**预设 CRUD 内嵌**，消灭 `video_filter_sheet.dart:37` 跳页）+ 超分 + 比例 + 视频信息二级页。
- **P5 播放 tab**：倍速/音量/跳过秒数/定时关闭（**迁移旧实现含自定义**）/画中画/外部播放/截图；退场底栏 MenuAnchor 簇与更多菜单对应项。
- **P6 更多 tab + 收尾**：调试/刷新；更多菜单与 `player_panel_hold.dart` 退场；PiP 联动；快捷键/`Esc`；全量回归 + Windows/Android 手测。

每片收尾固定动作：`flutter analyze` 干净、`flutter test` 全绿、当片手动核对项跑一遍、单独提交。

## 5. 测试策略

**要写（行为断言）**
- 几何纯函数：自动档取 `clamp(W/3,320,420)`；记忆档 clamp 到 `280 ~ min(640,W-420)`；竖屏 `30%~70%`；越界落盘修正。
- 分界线：拖动改比例（方向语义：面板变大为正）；clamp 停在上下界；双击回默认；横竖屏互不干扰；**热区不遮挡底层可点区域**。
- 布局壳：横屏左右 / 竖屏上下；窗口尺寸变化不炸；重启用持久化值恢复。
- 面板：开合不暂停播放；切 tab 不丢 tab 内状态；二级页进/返（返回到原 tab）；面板开着时控制栏仍会自动隐藏。
- 硬原则：点各入口**不产生路由跳转**（断言路由栈不变）；`git grep pushNamed lib/pages/player` 为空。
- 选集：下载按钮与状态可见、可点（回归 v1 的"恒禁用"）。
- 单测：比例键读写/默认值；持久化 `dispose` flush。

**禁止写（v1 教训）**
- 精确边距/像素偏移（`padding.left == 16`）、`ListView.padding`、`Slider` 个数、私有方法调用次数。

## 6. 硬约束清单（评审用）

1. `player_item.dart` 增量 **< 40 行**；任何新增逻辑不准进它。
2. 面板状态零 `setState`（全在 mobx controller）。
3. 面板行只用既有设置组件；新样式先抽到 `lib/bean/**`。
4. 内容件**无头**：`padding` 由外壳传入；**禁止 `embedded` 布尔**。
5. 二级页用**类型**（enum/sealed），禁止字符串桥接。
6. 禁止在 `GStorage.putSetting` 等存储 API 上加全局副作用；禁止"广播流 + `setState` 全量重读"。
7. 禁止 `lib/pages/settings/**` 反向 import 播放器面板文件。
8. 一个动作只有一个实现（迁移=移动）；面板与旧入口不得并存。
9. 生命周期：`dispose` cancel Timer + 移除 listener + flush 未落盘比例。
10. 手势/弹幕/布局一律用**视频区实测尺寸**，不用 `MediaQuery` 整窗值。

## 7. 明确不做

- 不改 5 tab 契约（v1 计划与设计稿的 4 tab 版作废）。
- 不动播放/下载/弹幕解析引擎；不改非播放器入口的既有 sheet 行为。
- 不引入新状态管理库（继续 mobx + flutter_mobx）。
- 不做 §1.1 之外的形态实验（如"竖屏面板打开时容器扩高"）。

## 8. 总验收清单

- **分屏框架**：开合动画（含 `disableAnimations`）；拖动实时；双击复位；clamp；重启恢复；横竖屏各自记忆；窗口缩放/全屏切换下比例保持。
- **面板**：5 个 tab 全项可达；二级页可进可返且回到原 tab；切 tab 不丢状态；⚙/`Esc`/快捷键一致。
- **播放器**：单击暂停、双击快进、长按倍速、手势（seek/亮度/音量）、HUD、控制栏自动隐藏、快捷键、返回/锁方向/全屏全部不回归；**右侧区域滚动不再误改音量**。
- **弹幕**：画布随视频区变化；开关双向同步；检索换库；时间偏移实时；屏蔽/去重生效。
- **画面**：滤镜滑杆实时生效（含播放中调参）；超分切换；比例切换；预设新建/改名/删除全在面板内完成、**无跳转**。
- **其他**：选集/线路切换、下载全流程（含状态与重试）、截图、画中画进出（进 PiP 自动收起）、外部播放、定时关闭（含自定义）。
- **平台**：Windows + Android（竖屏上下、横屏左右）各过一遍。
