# Kazumi ↔ wyw 播放器设置双端与面板 · 详细对比

> 事实清单，全部结论带 file:line 证据。Kazumi 侧 = `D:\development\AndroidStudioProjects\Kazumi`
> （HEAD，PR#1916 未合入）；wyw 侧 = 当前工作区。PR#1916 侧栏内容对比见 §3。
>
> 回答两个问题：
> **Q1**：设置项在设置页与播放器内都可调的部分，两边各自怎么做的？
> **Q2**：Kazumi 的面板/控制栏与 wyw 有什么差别（如弹幕开关位置）？

## 0. 结论速览

| 维度 | Kazumi（主干） | wyw | 改造取向 |
|---|---|---|---|
| 双端设置实现 | **两套实现 + 3 处共用**（sheet 与设置页互不 import） | **部分共用**（弹幕组同 Kazumi 模式）+ **画面调节全共用** | 统一收敛为 wyw 画面调节的「全共用内容 widget」范式 |
| 双端同步 | Hive 直读写（无响应式）；播放器 sheet 双写（`updateOption` 实时 + `putSetting`） | 同左（弹幕 sheet 同构）；画面调节走 MobX `VideoFilterController` | 统一「GStorage 持久 + MobX/controller 实时」 |
| 弹幕开关 | IconButton，3 处摆放，**持久化** `danmakuEnabledByDefault` | `danmaku_panel_button` 双职责（未匹配→检索），**不持久化** | 统一为独立开关 + 持久化（Kazumi 行为） |
| 弹幕输入框 | 有（发送弹幕） | 无（裁剪） | wyw 不加（裁剪意图） |
| 播放器页面跳转 | **零**（全部 sheet/菜单/对话框） | 1 处（管理预设→设置页） | 修掉（§0 硬原则，Kazumi 本来就是零跳转） |
| 更多菜单 | 11 项（含「一起看」） | 13 项（含画中画/下载/画面调节/重新解析） | 全部收编进分屏面板 |

## 1. Q1 · 设置项双端做法

### 1.1 Kazumi 的做法：「两套实现 + 少量共用」

**弹幕设置**存在两个文件、**互不 import**：

| | 设置页 | 播放器内 |
|---|---|---|
| 文件 | `lib/pages/settings/danmaku/danmaku_settings.dart`（397 行） | `lib/pages/settings/danmaku/danmaku_settings_sheet.dart`（239 行） |
| 形态 | `SettingsList(SettingsSection(switchTile/滑杆))` 页面 | `showAdaptiveBottomSheet` 底部弹层，内部 `DefaultTabController(2)` + `ConnectedTabs(['外观','播放'])`（sheet:79-88） |
| 内容 | 来源×3、屏蔽（跳子页）、显示 9 项、样式 6 项、恢复默认 | 显示 9 项子集 + **时间校准** + **屏蔽规则入口**（二级 sheet） |
| 写入 | 仅 `GStorage.putSetting` | **双写**：`_option.copyWith`→`danmakuController.updateOption`（实时生效）+ `putSetting`（sheet:73-75 等） |

- **共用点仅 3 处**：
  1. `DanmakuChConvertTile`（简繁转换，danmaku_ch_convert_tile.dart:15-64）——两边各嵌一次；
  2. 基础控件 `SettingsSliderTile` / `SettingsTile.switchTile` / `ContentSection`（bean/settings/settings_list.dart）；
  3. **`DanmakuShieldEditor`**（屏蔽编辑器，danmaku_shield_editor.dart:8）——设置页 `DanmakuShieldSettings`（:17）与播放器 `DanmakuShieldSettingsSheet`（:21）各自包壳嵌入（**双壳共用**，与 wyw 相同模式）。
- **重复实现**：字号/透明度/区域/行高/时长/跟随倍速/滚动·顶部·底部 —— 页面用 switchTile、sheet 用 FilterChip，代码两套。
- **内容不一致**：sheet = 设置页子集（9 项共有）+ 2 个播放器专属（时间校准、屏蔽入口）；设置页独有 9 项（来源×3、海量、去重、描边、描边粗细、颜色、字重、恢复默认）。

**其他双端项**（Kazumi）：

| 设置项 | 设置页 | 播放器内 | 共用 | 备注 |
|---|---|---|---|---|
| 跳过时长 `buttonSkipTime` | player_settings.dart:497-505（弹窗 :152-214） | 长按快进键 → `_showForwardChange`（player_item_panel.dart:244-281） | ❌ 两套弹窗 | |
| 超分提示 `disableSuperResolutionWarning` | super_resolution_settings.dart:61-74 | 质量档确认弹窗「下次不再询问」（player_item.dart:888-943） | ❌ | |
| 倍速/比例/超分（默认值 vs 运行时） | defaultPlaySpeed / defaultAspectRatioType / defaultSuperResolutionMode 持久化 | 菜单只改**运行时**（MobX），不持久化 | ❌ | 语义分离：设置页=默认，播放器=本次 |
| 弹幕开关 `danmakuEnabledByDefault` | **设置页无 UI** | 开关按钮写入（player_item.dart:579,589） | — | 播放器独写 |
| 时间校准 `danmakuTimeOffset` | **无** | 仅 sheet 二级页 | — | 播放器专属 |

**同步机制**（Kazumi）：GStorage(Hive) 直读写；播放器 init 一次性读入（player_item.dart:1322-1352, 1501-1517）；
**绝大多数双端项无响应式同步**（改一处，另一处重建才生效）。例外：`DanmakuChConvertTile` 用
`GStorage.watchSettings` 流（danmaku_ch_convert_tile.dart:23-25）；sheet 改动即时 `updateOption` 到运行中弹幕。

### 1.2 wyw 的做法：「部分共用（弹幕组）+ 全共用（画面调节）」

| 设置组 | 设置页 | 播放器内 | 共用情况 |
|---|---|---|---|
| **画面调节**（预设+5 滑杆） | `filter_presets_settings.dart` | `video_filter_sheet.dart`（更多菜单「画面调节」） | ✅ **全共用** `VideoFilterSliders`/`VideoFilterPresetPicker`/`showFilterPresetNameDialog`（video_filter_widgets.dart），状态走 MobX `VideoFilterController`——**wyw 独有的更彻底范式** |
| **弹幕显示组** | `DanmakuSettingsPage`（danmaku_settings.dart） | `showDanmakuSettingsSheet`（danmaku_settings_sheet.dart，含「外观/播放」二级） | 与 Kazumi **同模式**：`DanmakuChConvertTile`、`DanmakuShieldEditor` 共用；字号/透明度/区域/行高/滚动等两套实现 |
| 时间偏移 | `danmaku_time_offset_sheet.dart` | sheet 内入口 | ✅ 共用 `DanmakuTimeOffsetSheet` |
| 屏蔽 | `DanmakuShieldSettings` | `DanmakuShieldSettingsSheet` | ✅ 双壳共用 `DanmakuShieldEditor` |
| 跳过秒数 | player_settings「顶部按钮快进时长」（弹窗） | `showSkipSecondsDialog`（底栏长按/菜单） | ❌ 两套弹窗 |
| 超分质量档确认 | `super_resolution_settings.dart:61-74` | player_item.dart:654-733（「下次不再询问」） | ❌（但与 Kazumi 同构） |
| 倍速/比例/超分默认值 | player_settings | 菜单只改运行时 | ❌（同 Kazumi 语义分离） |
| 弹幕开关 `danmakuEnabledByDefault` | **无 UI** | `danmaku_panel_button` **只读不写**（video_controller.dart:602,636、player_item.dart:1055 仅 getSetting） | ⚠️ **与 Kazumi 行为差异：wyw 不持久化** |

### 1.3 双端总对照

| 设置项 | Kazumi 双端 | wyw 双端 | 共用 widget（K/w） | 备注 |
|---|---|---|---|---|
| 弹幕字号/透明度/区域/行高/时长/跟随倍速/滚顶底 | 页+sheet 两套 | 页+sheet 两套 | ❌/❌ | 两仓同病：重复实现 |
| 简繁转换 | ✅ | ✅ | ✅/✅ | watchSettings 流实时 |
| 屏蔽规则 | ✅（双壳） | ✅（双壳） | ✅/✅ | |
| 时间校准 | 播放器专属 | 播放器专属（sheet） | ✅/✅ | |
| 画面调节（预设+滑杆） | —（无此功能） | ✅ 页+sheet | —/✅ 全共用 | wyw 特有 |
| 跳过秒数/跳过时长 | ✅ 两套弹窗 | ✅ 两套弹窗 | ❌/❌ | |
| 超分质量档提示 | ✅ | ✅ | ❌/❌ | |
| 倍速/比例/超分默认 vs 运行时 | ✅ 语义分离 | ✅ 语义分离 | ❌/❌ | |
| 弹幕开关持久化 | ✅ 写 `danmakuEnabledByDefault` | ❌ 不写 | —/— | **行为差异，建议对齐 Kazumi** |
| 弹幕来源开关 | 仅设置页 | 仅设置页 | —/— | wyw 无 Gamer/Bili？（wyw sheet 有来源，页同） |
| 一起看 | 仅播放器（syncplay_sheet） | **无**（裁剪，残留 `syncPlayEndPoint` 键） | —/— | |

### 1.4 Q1 结论（改造取向）

1. **共用范式选 wyw 画面调节的「全共用内容 widget」**：内容 widget（滑杆组/开关组）一份代码，
   设置页与分屏面板各自包壳；Kazumi 弹幕组的「两套实现」是历史债，不照抄。
   > **已实施（2026-10，wyw 侧）**：弹幕设置收敛为两份共用内容件
   > （`danmaku_display_section.dart`：简繁+显示效果+海量+去重；
   > `danmaku_style_section.dart`：描边/描边粗细/颜色/字重），设置页与播放器
   > 「弹幕设置」tab 同源；面板侧只剩「恢复默认设置」不在（页面级动作）。
   > 此前 `DanmakuDisplaySection` 用 `leadingTiles`/`trailingTiles` 插槽把三项留给
   > 设置页，弹层退场后插槽没了消费者，于是"设置里有、面板里没有"。
2. **同步取 Kazumi sheet 的双写 + wyw 的 MobX 实时**：写 GStorage（持久）同时调 controller
   `updateOption`/`applyVf` 等（播放中即时生效）；需要"改一处另一处同步显示"的开关用
   `GStorage.watchSettings` 流（`DanmakuChConvertTile` 已示范）。
3. **弹幕开关对齐 Kazumi：持久化 `danmakuEnabledByDefault`**（wyw 现状只读不写是缺陷）。
4. **"默认值 vs 运行时"语义分离保留**（两仓一致）：设置页存 default*，面板改本次播放值。

## 2. Q2 · 播放器 UI（面板/控制栏）差异

### 2.1 弹幕开关（用户点名项）

| | Kazumi | wyw |
|---|---|---|
| 控件 | 纯开关 `IconButton` `_buildDanmakuToggleButton`（player_item_panel.dart:338-357） | **双职责** `danmaku_panel_button.dart`：未匹配弹幕库→打开检索面板；已匹配→开关 |
| 摆放 | **3 处**：桌面居中行 :615、移动宽底栏 :636-643、compact 顶栏 :829 | **2 处**：宽屏顶栏常驻、窄屏进「更多」菜单（player_item_panel.dart:1023-1025） |
| 行为 | `handleDanmaku`：切换 + **持久化** danmakuEnabledByDefault（player_item.dart:575-591）；无弹幕数据时改走「弹幕切换」（选源） | `setDanmakuEnabled` 切换；未匹配态单击直接开检索（danmaku_panel_button.dart:38「未匹配弹幕库（点击检索）」） |
| 「弹幕切换（选源）」 | 独立菜单项（player_item_panel.dart:859-862）→ `showDanmakuSourceSheet`：**竖屏 bottom sheet、横屏右侧抽屉 KazumiDialog**（danmaku_source_sheet.dart:42/52-70） | 无独立入口（并进开关按钮未匹配态）；`danmaku_source_sheet` 仅 bottom sheet 一种形态 |

> 有趣的是 **Kazumi 的横屏弹幕切换已经是"右侧抽屉"**（`KazumiDialog.show` :52-70），
> 与本次分屏改造方向暗合，可以视为分屏面板的前身形态。

### 2.2 弹幕输入框（发送弹幕）

- Kazumi：**有**。`_danmakuTextField`（player_item_panel.dart:174-242，TextField :183 +「发送」suffix :211-228），
  桌面宽屏居中行（>600px，:617）、移动宽底栏 `Expanded`（:646）；发送走 `showDanmakuDestinationSheet`。
  compact（宽<600）无输入框（:735 整条替换）。
- wyw：**无**（裁剪掉发送弹幕功能）。
- 结论：分屏改造不为 wyw 新增输入框（保持裁剪）；若未来要加，放面板 Tab2。

### 2.3 「更多选项」菜单清单对照

| 菜单项 | Kazumi（player_item_panel.dart:834-928） | wyw（player_item_panel.dart:1050-1212） |
|---|---|---|
| 视频比例 | （compact）SubmenuButton :849-851 | （compact）SubmenuButton :1150-1164 |
| 倍速 | （compact）SubmenuButton :852-853 | （compact）SubmenuButton :1134-1149 |
| 超分辨率 | （compact）SubmenuButton :854-856 | （compact）SubmenuButton :1119-1133 |
| 一起看 | ✅ :857/:926 → syncplay_sheet | ❌（裁剪） |
| 弹幕切换 | ✅ :859-862 → showDanmakuSwitch（选源） | ❌（并进弹幕按钮未匹配态） |
| 弹幕设置 | （compact）:863 → showDanmakuSettingsSheet | ✅ :1084-1094 → showDanmakuSettingsSheet |
| 弹幕开关 | ❌（独立按钮） | （compact）:1073-1082 |
| 视频详情 | ✅ :864-867 | ✅ :1166-1171 |
| 远程投屏 | ✅ :868-882 | ✅ :1178-1189 |
| 外部播放 | ✅ :883-886 | ✅ :1190-1195 |
| 定时关闭 | ✅ SubmenuButton :887-925（15/30/60/自定义） | ✅ 同构 `_buildTimedShutdownMenu`（:1234-1284） |
| 画中画 | ❌（顶栏独立按钮） | ✅ :1096-1111 |
| 下载 | ❌（顶栏独立按钮 + 状态） | （compact）:1113-1117「下载（播放即下载）」 |
| 画面调节 | ❌（无此功能） | ✅ :1172-1177 → showVideoFilterSheet |
| 重新解析 | ❌ | ✅ :1196-1209 |

### 2.4 底部栏簇（超分/倍速/比例）

两仓**同构**：均为 MenuAnchor 弹出菜单（Kazumi `_menuButton` :590-601 / wyw `PlayerPanelHoldMenuAnchor`），
宽屏放底栏右侧、compact 进更多菜单。差异仅细节：Kazumi 倍速 TextButton 显示当前倍速（:654-661），
wyw 同（:855）；比例 Kazumi IconButton、wyw 同（:886-903）。

### 2.5 顶栏对照

| | Kazumi | wyw |
|---|---|---|
| 返回/标题拖动区/跳过 | ✅ | ✅ |
| 弹幕开关 | compact 顶栏（:829）；宽屏在中央行/底栏 | **宽屏顶栏常驻**（danmaku_panel_button）；窄屏进菜单 |
| 选集面板 | ✅ IconButton（:667-673） | ✅（:1025-1031，toggleEpisodePanel） |
| 下载按钮 | ✅（带解析中/排队/失败状态，:166-229） | ✅（同构状态 tooltip，:166-294）；compact 进菜单 |
| 画中画 | ✅ 顶栏（PR 前在顶栏，diff 显示） | 进「更多」菜单 |
| 弹幕输入框 | 宽屏居中/底栏 | 无 |

### 2.6 页面跳转（硬原则对照）

- **Kazumi：零跳转**。`lib/pages/player/` 全目录 grep 仅命中 sheet 内 `Navigator.pop`；
  一切二级功能 = bottom sheet / MenuAnchor / AlertDialog / KazumiDialog 右侧抽屉。
- **wyw：1 处**——`video_filter_sheet.dart:37`「管理预设」→ `context.pushNamed('/settings/player/filters/')`。
- 结论：你的硬原则（播放页禁止跳转）**正是 Kazumi 的既有做法**；wyw 只需修掉这一处
  （计划 §0 已列：预设管理 CRUD 内嵌面板 Tab3）。

## 3. PR#1916 侧栏内容对比（head `f57d9f0`，对照 base `ad15ed9`）

### 3.1 侧栏总体形态

- **容器** `PlayerControlPanel`：覆盖式右侧滑入（宽 `panelWidth=360 + 右 padding`），左缘 40px 渐变，
  左侧整块是点击关闭区，深色 `0xB3000000` 背景（player_control_panel.dart:16-122）。
- **入口分流** `_showPlayerSettingsPanel`（player_item.dart:876-908）：横屏→侧栏（isSidebar: true）；
  竖屏→关侧栏 + `showModalBottomSheet`（isSidebar: false）；竖屏下侧栏自动关闭（:1043-1062）。
- **面板结构**：双 tab `_buildPlayerSettingsTabbedSheet`（:910-989）——**「弹幕设置」「播放器设置」**
  （Tab1=DanmakuSettingsSheet，Tab2=PlayerMoreSettingsSheet；isSidebar 时 tab 栏放底部）。
  另有 **4 个独立侧栏内嵌面板**（替换侧栏 body，切换不重放动画 :852-858）：
  弹幕屏蔽、弹幕检索、自定义定时、视频详情。
- **入口**：顶栏「更多选项」→ 侧栏「播放器设置」tab；底栏「弹幕设置」图标 →「弹幕设置」tab；
  **桌面右键**呼出「播放器设置」（:1943-1952）。
- **isSidebar 契约精确用法**（4 种）：①主题换深色 0xCC000000；②子面板去掉 SysAppBar
  （danmaku_shield_settings.dart:27-34）；③动作前先 `onRequestCloseSidebar`（画中画/投屏/外部播放）；
  ④竖屏 fallback 到 sheet/AlertDialog（检索按钮 :509 → 旧 showDanmakuSwitch 对话框）。
- **零页面跳转**（与主干一致）：全 PR 唯一路由在设置页（danmaku_settings.dart:195）；
  「管理预设」类按钮 grep 零命中。

### 3.2 侧栏内容总表

| tab/面板 | 分区 | 内容项 |
|---|---|---|
| Tab「弹幕设置」 | 快捷块行1 | 顶部/底部/滚动（轨道开关）、重复（去重）、叠加（海量） |
| 同上 | 快捷块行2 | **弹幕检索**（→侧栏检索面板）、**关键词屏蔽**（→侧栏屏蔽面板） |
| 同上 | 弹幕来源 | BiliBili / Gamer / DanDan |
| 同上 | 弹幕样式 | 字号、不透明度、字重、描边、描边粗细、颜色 |
| 同上 | 弹幕显示 | 区域、持续时间、行高、跟随倍速 |
| Tab「播放器设置」 | 快捷行 | 视频详情、画中画*、远程投屏*、外部播放*（*=动作前关侧栏） |
| 同上 | 画面设置 | 倍速（滑杆+快捷 chip）、亮度**、音量、视频比例、超分辨率、定时关闭（分段+更多→自定义面板） |
| 同上 | 一起看 | 当前房间/加入房间表单/服务器下拉（`syncPlayEndPoint`） |
| 独立面板 ×4 | — | 弹幕屏蔽（输入+Chip 列表）、弹幕检索（搜索→分集→换弹幕）、自定义定时（时/分双滚轮）、视频详情（Info/Log 双 tab，点击复制） |

（** 亮度仅非桌面显示；player_more_settings_sheet.dart:89-90, 431-444）

### 3.3 控制栏保留 vs 移除 —— **PR 是"双入口"，不是"移入"**

| 控件 | PR 版处理 |
|---|---|
| 返回/标题/跳过/画中画/追番 | 顶栏保留（player_item_panel.dart:1029-1136） |
| 「更多选项」下拉 MenuAnchor（整套） | **删除下拉**，改为单按钮 → 侧栏（:1122-1129） |
| 弹幕开关 | **保留在底栏**（桌面 :715、移动 :733-742）；侧栏**无总开关**（只有顶部/底部/滚动分轨道开关）；小窗版在顶栏（smallest:597） |
| 弹幕设置图标 | 保留在底栏（:716-724），改为开双 tab 面板 |
| 弹幕输入框+发送 | 保留在底栏（:725/752） |
| 超分/倍速/比例 MenuAnchor | **保留在底栏**（:757-985）+ **侧栏第二入口**（分段按钮/滑杆） |
| 选集/全屏/截图/锁定 | 保留 |
| 「播放速度」对话框（含默认速度） | **删除**（只留「跳过秒数」对话框 :186-229） |
| 小窗面板全部菜单 | **删除**，统一「更多选项」→ 侧栏（smallest:611-613） |

> **关键差异**：PR 收编的是「更多选项」下拉与小窗菜单，**底栏高频控件一律双入口保留**；
> wyw 的要求（播放器只留播放相关按钮）比 PR **更激进**——底栏超分/倍速/比例菜单与弹幕设置图标
> 只留面板单入口。这是 wyw 分屏方案的自觉决策，不照抄 PR 的双入口。

### 3.4 弹幕开关位置 · 三方对照（用户点名项）

| | 位置 | 持久化 | 附带职责 |
|---|---|---|---|
| Kazumi 主干 | IconButton，3 处（桌面中央行/移动宽底栏/compact 顶栏） | ✅ 写 `danmakuEnabledByDefault` | 无弹幕时转「弹幕切换」 |
| Kazumi PR 版 | 底栏（桌面/移动），小窗顶栏 | ✅（player_item.dart:445-468） | 同上 |
| wyw 现状 | **顶栏**（宽屏常驻/窄屏菜单） | ❌ 只读不写 | **双职责**：未匹配→弹幕检索 |
| wyw 计划 | 顶栏保留（默认决策 1） | ✅ 补持久化（对齐 Kazumi） | 拆分：未匹配提示仍在按钮，检索进 Tab2 |

### 3.5 其他 PR 细节（供分屏实现参考）

- **二级面板切换不重放动画**：`showPlayerControlPanel` 的 `isSwitchingSidebarPanel` 分支
  （player_item.dart:852-858）直接换 body——分屏面板的子面板切换同理。
- **关闭后 360ms 才清 body**（:811-838）配合退场动画；`disableAnimations` 时瞬时。
- 「弹幕切换」不再是独立入口，成为「弹幕检索」面板的结果动作（切换成功 toast + 关面板）。
- 面板内有**亮度滑杆**（非桌面）与**音量滑杆**（player_more_settings_sheet.dart:431-457），
  直接调播放器参数、无跳转。
- PR 残留：`onShowDanmakuSwitch`/`onShowSyncPlayEndPointSwitchDialog` 声明未用。

## 4. 对分屏改造计划的影响（已吸收）

1. 「全共用内容 widget」为双端唯一范式（计划 §3.1 已更新）。
2. 弹幕开关：保留独立高频 toggle（计划默认决策 1）+ **补持久化**（对齐 Kazumi，修复 wyw 缺陷）。
3. 零跳转硬原则（计划 §0）——Kazumi 主干与 PR 版均为零跳转，即上游既有形态。
4. **单入口 vs PR 双入口**：PR 保留底栏双入口；wyw 计划更激进（只留面板），验证时注意
   底栏精简后高频操作的可达性。
5. **二级面板切换**沿用 PR 的「换 body 不重放动画」（子面板：检索/屏蔽/自定义定时/视频详情）。
6. Kazumi 横屏弹幕切换的「右侧抽屉」（KazumiDialog）证明横向面板形态有先例，分屏是其自然延伸。
7. 「默认值 vs 运行时」语义分离保留：面板只改本次播放值，default* 留设置页（不进面板，计划 Tab5）。
8. 面板内嵌**音量/亮度滑杆**（PR 已有先例）可纳入 wyw 面板 Tab4。
