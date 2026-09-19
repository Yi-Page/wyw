# Wyw 界面与路由设计规范（草案）

**日期**：2026-09-06
**状态**：P0/P1、P2 颜色部分（8A/8B/8C + guard 测试）、B9 顶栏统一菜单已实施并验证；P2 其余（9/7）待做；规范正文待审阅
**范围**：`lib/pages`（页面与路由）、`lib/bean`（通用组件层）、`lib/utils/theme.dart` + `constants.dart`（设计 token）

---

## 第一部分：现状梳理（As-Is）

### 1. 技术底座

| 层 | 选型 |
|---|---|
| 框架 | Flutter 3.44.5，Material 3（`useMaterial3: true`），MiSans 默认字体（可切系统字体） |
| 路由 | flutter_modular **7.x**（Navigator 2.0 重写版），函数式模块声明 `createModule`，导航走 `BuildContext` 扩展（`context.pushNamed` / `context.navigate` / `context.maybePop`） |
| 状态 | MobX（页面 Store）+ ChangeNotifier（ThemeProvider 等全局） |
| DI | modular 作用域：`coreModule` 全局单例，路由级 `provide:` 页面私有 Store |

### 2. 路由现状

#### 2.1 路由总表

应用根模块 `indexModule`（`lib/pages/index_module.dart`），完整路由树如下：

```
appModule
├─ coreModule（纯 DI：仓库/服务/跨页控制器单例）
└─ indexModule（应用根路由）
   ├─ /                          InitPage（初始化入口，transition: none）
   ├─ /error                     内联错误页（初始化失败）
   ├─ /tab                       IndexPage → ScaffoldMenu（Tab 壳，fade 70ms）
   │   ├─ /                      guard：按 defaultStartupPage 设置重定向 → SizedBox.shrink
   │   ├─ /search                SearchPage（transition: none）
   │   ├─ /browse                BrowsePage（transition: none）
   │   └─ /my                    MyPage（transition: none）
   ├─ /video                     VideoPage（provide PlayerController；typed args）
   ├─ /history                   HistoryPage（进度 Tab）
   │   ├─ /browse                HistoryPage(initialTab: browse)
   │   └─ /progress              HistoryPage(initialTab: progress)
   ├─ /webview                   WebviewPage（裸 String url 参数，transition: none）
   ├─ /js-dev                    JsDevPage（provide JsDevController）
   ├─ /descriptor                DescriptorPage（插件通用详情页；Map 参数）
   ├─ /image-preview             ImageViewer（typed args，fade 220ms）
   ├─ /reader                    ComicReaderPage（provide ComicReaderController；typed args）
   ├─ /novel                     NovelReaderPage（provide NovelReaderController；typed args）
   └─ /settings                  SettingsPage（设置壳，双栏/单栏自适应）
       ├─ /theme                 ThemeSettingsPage
       │   └─ /display           SetDisplayMode（屏幕帧率）
       ├─ /keyboard              KeyboardSettingsPage
       ├─ /player                PlayerSettingsPage
       │   ├─ /decoder           DecoderSettings
       │   ├─ /renderer          RendererSettings
       │   └─ /super             SuperResolutionSettings
       ├─ /interface             InterfaceSettingsPage
       ├─ /logs                  LogsPage
       ├─ /comic-reader          ComicReaderSettingsPage
       ├─ /download              DownloadPage（独立模块 downloadPageModule）
       ├─ /download-settings     DownloadSettingsPage
       └─ /plugin                PluginManagerPage
           ├─ /edit              PluginEditPage（pop 回传 PluginEditResult）
           └─ /settings          PluginSettingsPage
```

#### 2.2 已形成的有效约定（值得保留）

1. **一个功能 = 一个模块文件**：`*_module.dart` 与页面同目录（`browse_module.dart`、`video_module.dart`…），根模块只做聚合。
2. **控制器生命周期分层**：
   - 页面私有 Store → 路由级 `provide: (s) => s.add<XxxController>(...)`，离开路由自动销毁（video/reader/novel/js_dev/descriptor 均如此）；
   - 跨页共享状态 → `coreModule` 单例（BrowseController、SearchPageController、HistoryController、VideoPageController、DownloadController、PluginController）；
   - 模块级单例 → 模块内 `addSingleton`（historyModule 的 PluginHistoryController）。
3. **参数校验兜底**：typed args 用 `is! XxxRouteArgs` 判断并回退错误页（video 用 null 容忍，reader/novel 用错误 Scaffold，webview 用 RouteErrorPage）。
4. **guard 用法**：`/tab/` 根路由按 `defaultStartupPage` 设置重定向，是当前唯一的 guard。
5. **壳内导航**：Tab 切换走 `RouterOutlet.navigate('/tab<path>/')`，系统返回在壳层 `PopScope` 拦截（outlet 内 pop → 切回第一个 tab → 双击退出），由 `menu.dart` 统一处理。
6. **强类型路由参数**：`VideoPageRouteArgs` / `ComicReaderPageRouteArgs` / `NovelReaderPageRouteArgs` / `ImageViewerRouteArgs`，与页面同目录定义，含回调字段（如 `onProgressChanged` 由调用方注入历史回写）。
7. **自封闭路由组件**：`ImageViewer` 自带 `routePath` 常量 + 静态 `show()` 入口，调用方无需知道路径字符串。

#### 2.3 现存不一致（规范要解决的）

| # | 问题 | 位置 | 状态 |
|---|---|---|---|
| R1 | **绕过路由表直接 `Navigator.push(MaterialPageRoute)`** | PluginEditPage、PluginSettingsPage（plugin_manager_page.dart） | ✅ 已注册（完整路径 `/settings/plugin/edit`、`/settings/plugin/settings`——pluginModule 挂在 settingsModule 之下，2026-09-17 修正此前写成 `/plugin/...` 导致 `Route not found`） |
| R2 | **路径命名三种风格混用**：snake_case（`/js_dev`）、kebab-case（`/image-preview`、`/download-settings`）、camelCase（`/settings/comicReader`） | 各模块 | ✅ 已统一 kebab-case（`/js-dev`、`/settings/comic-reader`） |
| R3 | **尾斜杠写法不统一**：多数调用带 `/`（`pushNamed('/history/')`），部分不带（`/settings/theme/display`、`/settings/player/decoder`、ImageViewer 的 `routePath`） | 各调用点 | ✅ 已改齐（modular 7 匹配对尾斜杠归一化，已验证） |
| R4 | **参数传递三种风格并存**：typed args class（video/reader/novel/image-preview）、裸 String（webview）、裸 Map（descriptor） | 各模块 | ✅ 已全部 typed args |
| R5 | **参数无效兜底页不统一**：内联 `Scaffold(appBar: AppBar('wyw'))`（index_module、comic_reader_module、novel_reader_module）vs `RouteErrorPage`（webview_module） | 各模块 | ✅ 已统一 RouteErrorPage |
| R6 | 历史页同页面注册 3 条路由表达 Tab 初值（`/history`、`/history/browse`、`/history/progress`），调用方也有直接 `pushNamed('/history/')` | history_module | ✅ 决策：保留三条直达路由 |
| R7 | `/error` 是内联简陋页，与 `RouteErrorPage` 视觉风格不一致 | index_module | ✅ 已对齐 |

### 3. 界面现状

#### 3.1 主题体系

- **构建**：`ThemeData(useMaterial3: true, colorSchemeSeed: <种子色>)`，种子色 9 选一（`color_type.dart`）或系统动态取色（dynamic_color）；暗色支持 OLED 纯黑增强（`oledDarkTheme`）。
- **持有**：`ThemeProvider`（ChangeNotifier）持 light/dark 两套 ThemeData；启动时从设置恢复（themeMode / 动态色 / 字体 / 种子色 / OLED）。
- **M3 2024 新样式开关**：进度指示器与滑块 `year2023: false`；页面转场 `pageTransitionsTheme2024`（Android/iOS/macOS = Cupertino，Linux/Windows = FadeUpwards）。
- **本地化**：固定简体中文（zh-Hans-CN）。

#### 3.2 布局与响应式

- **断点**（`LayoutBreakpoint`）：compact 600×480，medium 840×900。
- **形态判断**（`device.dart`）：`isDesktop` / `isWideScreen`（shortestSide ≥ 600）/ `isTablet` / `isCompact`。
- **Tab 壳自适应**：竖屏 NavigationBar（搜索/浏览/我的），横屏 NavigationRail + 圆角 16 的 outlet 容器（`primaryContainer` 底）。
- **设置壳自适应**：横屏且宽 > 600 → 双栏（280 rail + 详情嵌入同屏，`SettingsPaneScope.embedded`），否则单栏 Navigator 推入；断点跨越时用 `_InstantTransitionDelegate` 抹掉页面动画、只留 rail 形变。
- **底部弹层自适应**：宽 ≤ min(72%, 640)，高 75%（手机横屏非大屏 90%）。

#### 3.3 通用组件清单（lib/bean）

| 组件 | 位置 | 职责 |
|---|---|---|
| `SysAppBar` | appbar/sys_app_bar.dart | 统一 AppBar：桌面拖拽移窗、可选桌面关闭按钮、macOS 红绿灯偏移（22pt）、iOS 标题居中、返回键自动推断、透明系统栏 |
| `DragToMoveArea` | appbar/drag_to_move_bar.dart | 桌面拖拽移动窗口（播放器面板用） |
| `EmbeddedNativeControlArea` | widget/ | macOS 原生窗口控件占位 |
| `WywDialog` | dialog/dialog_helper.dart | `show` / `showConfirm`（标准确认框）/ `showToast`（宽屏限宽 600）/ `showBottomSheet`，Observer 兜底全局上下文 |
| `showAdaptiveBottomSheet` | dialog/adaptive_bottom_sheet.dart | 自适应底部弹层（尺寸口径见 3.2） |
| `MaterialBottomSheetHeader/SegmentedTabs/Section/Group` | dialog/material_bottom_sheet.dart | 弹层内容排版积木（漫画阅读器设置在用） |
| `SettingsList/Section/SplitGroup/Tile(.switchTile/.radioTile)/CategoryTile/SliderTile/RadioSection` | settings/settings_list.dart | M3 Expressive split-list：组端大圆角 24、行间小圆角 4、间隙 4 代分隔线、按压形变 |
| `SplitListRow` | widget/split_list_row.dart | split-list 单行实现 + 按压上报 |
| `SettingsDetailScaffold` + `SettingsPaneScope` | settings/settings_detail_scaffold.dart | 设置详情页骨架：双栏嵌入（透明底）/独立路由（SysAppBar）双形态 |
| `NetworkImgLayer` | card/network_img_layer.dart | 网络图：圆角 12（`imgRadius`）、内存降采样、Hero shuttle |
| `HistoryCard` 系列 / `PaletteCard` / `SwipeToDeleteCard` | card/ | 业务卡片 |
| `ImageViewer` | widget/image_preview.dart | 全局图片预览（自带路由） |
| `StyleString` / `LayoutBreakpoint` | utils/constants.dart | cardSpace 8、safeSpace 12、mdRadius 10、imgRadius 12、aspectRatio 16/10、断点 |
| `DoubleBackExit` | utils/double_back_exit.dart | 双击返回退出（Tab 根） |

#### 3.4 页面骨架的四种既成模式

1. **Tab 容器页**（search/browse/my）：`Scaffold + SysAppBar`，内容区 `SafeArea(top: false)`，列表宽屏居中限宽（settings 1000 / my 800 / 弹层 600~640）。
2. **设置详情页**：`SettingsDetailScaffold(title, body)` + `SettingsSection(SettingsTile...)`，双栏嵌入时自动透明化。
3. **推入式内容页**（history/download/logs…）：`Scaffold + SysAppBar + 内容`。
4. **沉浸式页**（video 播放、reader/novel 阅读、image-preview）：无 AppBar，黑底/画布自绘，覆盖层固定深色语义。

#### 3.5 现存不一致（规范要解决的）

| # | 问题 | 位置 | 状态 |
|---|---|---|---|
| U1 | **裸 `AppBar` 绕过 `SysAppBar`**（丢桌面拖拽/macOS 偏移/桌面关闭钮） | displaymode_settings、plugin_settings_page、plugin_edit_page、storage_error_page | ✅ 前三处已改齐；storage_error_page 为降级页豁免（已注明原因） |
| U2 | **圆角 token 散乱**：mdRadius 10 / imgRadius 12 / my_page `_cardRadius` 16 / splitList 24 / rail outlet 16，页面各说各话 | constants.dart、my_page.dart | P2 |
| U3 | **断点口径不统一**：`LayoutBreakpoint`（600/840）与弹层/Toast 内的裸 600、640 魔法数字并存 | adaptive_bottom_sheet、dialog_helper | P2 |
| U4 | **沉浸层硬编码颜色未集中**：播放器 overlay 的白/黑（合理语义但散落 20+ 处）、小说阅读主题色（0xFFFDF6E3 等）、js_dev 控制台配色 | player/、novel_reader/、js_dev/ | ✅ 已修复（8A 内容层清扫 + 8B MediaChromeColors + 8C palette + guard 测试强制） |
| U5 | 动效参数散落：tab fade 70ms、图片预览 220ms、split-list/设置 250ms easeInOutCubic，无常量 | index_module 等 | P2 |
| U6 | my_page「JS控制台」与「历史记录」复用同一图标（history_rounded），语义混淆 | my_page.dart L95-104 | P2 |
| U7 | 内容区限宽无统一 token：1000（设置）/ 800（我的）/ 640、600（弹层/Toast）各自为政 | settings_list、my_page、dialog_helper | P2 |

---

## 第二部分：设计规范（To-Be，供审阅）

> 标 ❓ 的为需要你拍板的决策点，已给出推荐项；不标 ❓ 的为对现状的归纳固化，改动成本低。

### A. 路由设计规范

#### A1. 模块组织

- 一个功能目录一个 `xxx_module.dart`，与页面、控制器、参数类同目录；`index_module.dart` 只做聚合与顶层路由注册，不写页面逻辑。
- 模块命名：`<feature>Module`；路径即目录语义（`/video`、`/settings`）。
- 新页面注册到哪个模块：属于某个设置分类 → settingsModule；是 Tab 内容 → tabModule；其余顶层功能 → indexModule。

#### A2. 路径命名 ❓（已决策：kebab-case，2026-09-06 采纳）

**推荐：统一小写 kebab-case**（与 Navigator 2.0 的 web 语义一致，URL 友好，也和既有的 `/image-preview`、`/download-settings` 一致）。

需要改名的现状路径（均为纯字符串替换 + 调用点同步）：

| 现状 | 改为 |
|---|---|
| `/js_dev` | `/js-dev` |
| `/settings/comicReader` | `/settings/comic-reader` |

备选：统一 snake_case（`/image-preview` → `/image_preview`），与 Dart 标识符一致但偏离 web 惯例，不推荐。

#### A3. 尾斜杠

**规则：导航调用一律带尾斜杠**（`pushNamed('/history/')`），路由注册路径不带（模块 `path: '/history'` + `route('/')`）。理由：现状多数调用已如此，且 menu 的 `indexForPath` 前缀匹配依赖 `/tab<path>/` 形态。

需要改齐的少数调用：`theme_settings_page`、`player_settings`（3 处）、`ImageViewer.routePath` 常量（`/image-preview` → `/image-preview/`，或调用处补斜杠）。

#### A4. 参数传递

**规则：任何带参数的路由必须定义 typed args 类**，命名 `<Feature>PageRouteArgs`，与页面同目录（`video_route_args.dart` 模式）。三种现状风格的收敛：

- ✅ 保留：video / reader / novel / image-preview（typed args）。
- 🔧 改造：`/descriptor` 的裸 Map → `DescriptorPageRouteArgs`（字段不变：plugin/method/args/title/actions）。
- 🔧 改造：`/webview` 的裸 String → `WebviewPageRouteArgs(url)`。
- 约定：参数类含回调字段是合法用法（如 `onProgressChanged` 回写历史），但回调必须由「发起导航的一方」注入，页面不得反查调用方。
- 历史页 Tab 初值（R6）：**保留三条路由**（可直达、语义清晰，2026-09-06 决策）：`/history/` 默认进度 Tab；`/history/browse/`、`/history/progress/` 仅作直达别名，页面内部切换不再改路由。

#### A5. 参数校验与错误兜底

- args 类型不符 → 一律渲染 `RouteErrorPage(message: ...)`（route_error_page.dart），禁止各模块内联手写 `Scaffold(appBar: AppBar('wyw'))`。
- `/error`（初始化失败）保持独立路由，但视觉上对齐 RouteErrorPage 的样式（图标 + 文案 + 返回按钮）。

#### A6. 控制器（Store）作用域

| 状态归属 | 放哪 | 例子 |
|---|---|---|
| 页面私有，随路由销毁 | 模块内 `provide: (s) => s.add<XxxController>(...)`，页面用 `context.read<T>()` | PlayerController、ComicReaderController |
| 跨页共享、会话级 | `coreModule` `addSingleton` | BrowseController、HistoryController |
| 单一功能域内跨页 | 功能模块内 `addSingleton` | PluginHistoryController |

**禁则**：页面不得把路由级 Store 塞进 coreModule 变通；跨页 Store 里不得持有页面 Widget 引用。

#### A7. 转场规范

| 页面类型 | 转场 | 说明 |
|---|---|---|
| 启动/初始化（`/`） | `TransitionType.none` | 保持现状 |
| Tab 壳内切换 | 自定义 fade 70ms | 保持现状（模块级 `_tabTransition`） |
| 全屏沉浸页（video/reader/novel） | 平台默认（pageTransitionsTheme2024） | 不覆写 |
| webview | `none` | 保持现状（原生 WebView 自带进场感） |
| 图片预览 | fade 220ms | 保持现状 |
| 普通推入页（history/settings/logs…） | 平台默认 | 不覆写 |
| 设置壳断点重排 | `_InstantTransitionDelegate`（无动画） | 保持现状 |

**规则：转场只在模块注册处声明一次**，页面内不得再包 Transition 动画。

#### A8. 导航 API 与返回行为

- 推入：`context.pushNamed('/path/')`；壳内切换：`RouterOutlet.navigate`；重定向/替换：`context.navigate`（如 guard、返回首页）。
- 返回：页面内优先 `context.maybePop()`；Tab 壳的系统返回逻辑集中在 `menu.dart` 的 PopScope（outlet pop → 切回首 tab → DoubleBackExit）。
- **禁则：业务代码禁止直接 `Navigator.of(context).push(MaterialPageRoute(...))`**（R1 的两个插件页面注册为 `/settings/plugin/edit`、`/settings/plugin/settings`；PluginEditPage 的 `pop(PluginEditResult)` 改为 `pushNamed` 的返回值）。子模块路由按**挂载后的完整路径**导航，不得省略父模块前缀。

#### A9. 新增页面 checklist

```
□ 建目录 lib/pages/<feature>/，写 <feature>_module.dart
□ 参数定义 <Feature>PageRouteArgs（如有），args 校验失败 → RouteErrorPage
□ 路径 kebab-case、注册不带尾斜杠、调用带尾斜杠
□ 页面私有 Store 用 provide:，跨页状态进 coreModule
□ 转场按 A7 表；不在页面内写转场
□ 骨架按 B4 四类模板之一
```

### B. 界面设计规范

#### B1. 颜色

1. **内容层一律取自主题**：`Theme.of(context).colorScheme` / `textTheme`，禁止硬编码 hex / `Colors.white`。
2. **沉浸层豁免**：播放器覆盖层、阅读器画布、js_dev 控制台允许脱离主题（视频画面/阅读底色与主题无关是产品语义），但颜色必须**收敛为具名常量**，不允许行内字面量：
   - 建议 `lib/utils/theme.dart` 增加 `PlayerOverlayColors`（前景白、遮罩黑及其 alpha）与阅读主题 palette 类（现状散在 novel_reader.dart L257-260）；
   - js_dev 的日志等级配色（L170-175）移入常量文件。
3. **主题资产变更点唯一**：种子色 → `color_type.dart`；主题构建 → `app_widget.dart _buildAppTheme`；OLED → `oledDarkTheme`；字体 → `theme_provider`。页面不得自行 copyWith ThemeData。

#### B2. 布局与断点

1. 断点只引用 `LayoutBreakpoint.compact/medium`（600/840），弹层宽度、Toast 限宽等处裸数字改齐（U3）。
2. 形态判断只走 `device.dart`（isDesktop/isWideScreen/isCompact），页面不得自己写 `Platform.isXxx && MediaQuery...` 组合判断。
3. 内容区限宽收敛为一个 token（❓ 推荐统一 800：设置页 1000 可放宽为特例并写注释，其余 800/640/600 全部归一）。

#### B3. 圆角与间距 token（U2/U7）

在 `StyleString` 基础上补全为封闭集合，页面只允许引用 token：

| token | 值 | 用途 |
|---|---|---|
| `radiusXs` | 8 | 小控件、标签 |
| `radiusSm` | 12 | 图片、普通卡片（= 现 imgRadius） |
| `radiusMd` | 16 | 页面级卡片组（my_page）、rail outlet |
| `radiusLg` | 24 | split-list 组端（= splitListOuterRadius） |
| `spaceXs` 4 / `spaceSm` 8 / `spaceMd` 12 / `spaceLg` 16 / `spaceXl` 24 | | 间隙体系（cardSpace/safeSpace 并入） |

#### B4. 页面骨架模板

| 模板 | 结构 | 适用 |
|---|---|---|
| Tab 容器页 | `Scaffold + SysAppBar + SafeArea(top:false) + 限宽列表` | search/browse/my |
| 设置详情页 | `SettingsDetailScaffold + SettingsSection(SettingsTile…)` | settings 全部子页 |
| 推入内容页 | `Scaffold + SysAppBar + 内容` | history/download/logs |
| 沉浸式页 | 无 AppBar；覆盖层颜色走 PlayerOverlayColors/阅读 palette | video/reader/novel/image-preview |

**强制：内容页一律 `SysAppBar`**，禁止裸 `AppBar`（U1 四处违例需改）。桌面标题栏拖拽、macOS 偏移、状态栏样式都依赖它，绕过即丢平台行为。

#### B5. 弹层与反馈

| 场景 | 用法 |
|---|---|
| 确认/选择（二元） | `WywDialog.showConfirm` |
| 自定义对话框 | `WywDialog.show` |
| 轻提示 | `WywDialog.showToast`（禁止裸 SnackBar） |
| 底部弹层 | `showAdaptiveBottomSheet`（尺寸自适应内置），内容排版用 MaterialBottomSheet* 积木 |

#### B6. 动效 token（U5）

| token | 值 | 用途 |
|---|---|---|
| `motionFast` | 70ms + fade | Tab 切换 |
| `motionPreview` | 220ms + fade | 图片预览 |
| `motionStandard` | 250ms + easeInOutCubic | split-list 形变、设置双栏、通用 |

#### B7. 组件复用

- 列表类页面优先复用 SettingsList 系（它已是通用 split-list，不止用于设置）与 card/ 下的卡片。
- 新通用组件落位 `lib/bean/<category>/`；仅单页使用的留在页面目录。
- 图标语义不重复（U6：JS控制台改 `Icons.terminal_rounded` 之类）。

#### B8. 新增界面 checklist

```
□ 骨架选 B4 四类模板之一；AppBar 用 SysAppBar
□ 颜色全部 colorScheme/textTheme；沉浸层颜色进具名常量
□ 圆角/间距/动效引用 B3/B6 token
□ 弹层走 B5 矩阵
□ 断点/形态判断走 LayoutBreakpoint 与 device.dart
□ 内容页 appbar actions 末尾挂 const WywAppBarMenuButton()
```

#### B9. 顶栏统一导航入口（2026-09-06 增补，已实施）

**组件**：`lib/bean/appbar/app_bar_menu_button.dart`（`WywAppBarMenuButton` + `AppBarMenuEntry`）。

- 默认条目：历史记录 `/history/`、离线下载 `/settings/download/`、设置 `/settings/`（用户决策：三项起步，架构支持追加）。
- **`pagePath` 必填**（2026-09-06 三次修订）：modular 7 的 `routeState()` 只反映**栈底**（push 的页面刻意「不进 URL」，框架注释原文 "modal-like, lost on refresh by design"），组件无法从 context 读到「自己在哪一页」，也无法读到栈顶——所以宿主页面必须显式传自己的注册路径（如 `WywAppBarMenuButton(pagePath: '/history/')`）。
- **防重复导航语义**（2026-09-06 五次修订，收敛为**单一出栈循环**，替代此前的菜单链镜像 / presence 登记 / 互斥双机制）：
  1. **已在本页**（`entry.route == pagePath`）→ 条目**禁用**（置灰可见，不隐藏——菜单布局稳定，当前位置可感知）；
  2. **跳转 = 出栈循环**：`popUntil` 的 predicate 逐层检查栈顶——栈顶是**其他菜单区块** → 出栈继续；栈顶是**目标** → 停止（predicate 闭包捕获落点，回到既有实例，不嵌套）；栈顶是**非菜单层**（播放器/阅读器/普通内容页，原样保留）或**出到了栈底** → `pushNamed` 跳转目标。各全局区块互斥（同一时刻栈内至多一个菜单区块，返回键不重放已离开的区块），非菜单层永不被误弹；
  3. `popUntil`/`pushNamed` 一律在**根 Navigator 的 context** 上执行（`Navigator.of(context, rootNavigator: true)`，位于所有 RouterOutlet 之上），绕过 context 扩展「最近 RouterOutlet 优先」的分发，杜绝 tab 壳内部栈被误弹。
  4. **设置壳特例**（2026-09-06 补）：设置壳单栏模式把详情页挂在壳的内部 Navigator、双栏模式嵌入右窗格——两种形态下可见页都**不在根栈**，出栈循环推理失效。组件用 `SettingsPaneScope` 识别壳内宿主：指向设置根的条目改走壳内 `onBack`（单栏，回分类列表）/禁用（双栏，人已在设置界面）；其余条目一律根栈 push（壳保留在栈下，返回键回原详情页）。注意 日志/规则管理/离线下载管理 存在「壳内分类页」与「独立路由」两种形态，同一组件自动适配。
- **语义回归测试**：`test/app_bar_menu_button_test.dart`（本页禁用 / 夹心栈回退不嵌套 / 互斥抛出旧区块 / presence-less 兜底 push / 设置壳单栏 onBack / 双栏禁用 六用例）。注意写栈断言时 `find.byType(..., skipOffstage: false)`——Navigator 会把不透明路由下方的页面包进 Offstage。
- 页面特有动作不迁移：history 的编辑/清空、descriptor 的插件动作、plugin_manager 的多选动作保留在菜单按钮左侧；本按钮固定放 actions 末尾。
- 应用页（9 个）：my、search、browse、history、descriptor、download、logs、js_dev、plugin_manager。**不加**：阅读器/webview（自有工具行）、settings 二级详情页（返回一步即设置根）、播放器（用户决策：不动；PlayerPanelHoldMenuAnchor 保持播放器专用）。
- 同步收敛的既有散点：search 的历史图标从搜索框行移入标准 actions；browse 补 `SysAppBar`（TabBar 保持 body 顶部，与搜索页同构）；history/descriptor 的独立下载图标由菜单取代。

### C. 迁移清单（把不一致改齐的最小改动集）

**P0（行为一致性）— ✅ 已完成（2026-09-06）**
1. ✅ PluginEditPage / PluginSettingsPage 注册进路由表（完整路径 `/settings/plugin/edit`、`/settings/plugin/settings`，typed args），替换两处裸 `Navigator.push`；编辑页结果仍以 pop 携带 `PluginEditResult` 返回。
2. ✅ 三处裸 `AppBar` → `SysAppBar`（plugin_edit / plugin_settings）或 `SettingsDetailScaffold`（displaymode）；storage_error_page 保留裸 AppBar 并注明为降级页豁免。
3. ✅ 参数无效兜底统一 `RouteErrorPage`（index_module / comic_reader_module / novel_reader_module），`/error` 一并对齐。

**P1（一致性收口）— ✅ 已完成（2026-09-06）**
4. ✅ 路径改名：`/js_dev` → `/js-dev`、`/settings/comicReader` → `/settings/comic-reader`（kebab-case 决策已采纳）。
5. ✅ 尾斜杠改齐：theme_settings 1 处、player_settings 3 处、`ImageViewer.show` 改推 `'$routePath/'`（注册路径常量不变）。已验证 modular 7 匹配对尾斜杠归一化，两种写法等价。
6. ✅ descriptor/webview 参数改 typed args：`DescriptorPageRouteArgs`（含 `fromRawMap` 适配 JS 边界）、`WebviewPageRouteArgs`；init_page / category_browse_view / descriptor_page 自跳转 / plugin_manager_page 全部调用点同步。

**P2（token 化，可分批）**
7. StyleString 补 token 并替换各处裸圆角/间距（U2）——待做。
8. ✅ 颜色 M3 单一来源（U4，2026-09-06 完成，详见第三部分 8 节）：
   - 8A 内容层清扫 ~32 处（search/plugin_manager/history/comic_image/webview/descriptor_renderer/选集面板），状态色按语义映射表落地，分类标识色并入 `PluginType` 枚举；
   - 8B `MediaChromeColors`（lib/bean/styles/media_chrome_colors.dart）+ 播放器/图片查看器/阅读器 scrim ~80 处；下载状态强调色接 `colorScheme.primary`/`error`；
   - 8C `NovelCanvasPalette` 入 novel_reader_settings、`JsConsoleColors` 独立文件、种子色默认值统一引用 color_type；
   - guard：`test/no_hardcoded_colors_test.dart` 全库扫描白名单外 `Colors.*`/`Color(0x`/`fromARGB/RGBO`，白名单仅限 palette/token/主题构建/插件透传层。
9. 动效 token、限宽 token（U5/U7）、my_page 图标（U6）——待做。

---

## 第三部分：P2 详细方案与评估（2026-09-06 增补，待审阅）

> 本部分是对迁移清单 P2 三项的落地设计。数据来自全库 grep 实测（2026-09-06）。

### 现状量化基线

| 维度 | 实测 |
|---|---|
| 圆角 | 71 处 `BorderRadius/Radius`；离散值 2/4/6/8/10/12/16/18/20/24/28/30 |
| StyleString 现有 token 使用率 | 仅 4 处引用；`mdRadius(10)`、`safeSpace(12)` 为**死 token**（定义后从未使用） |
| 硬编码颜色（沉浸层） | 约 75 处：player_item_panel 29、smallest_player_item_panel 15、video_page 10、js_dev 10、novel_reader 4、其余散点 |
| Duration | 62 处；其中 UI 动效约 40 处，其余是重试/定时器/手势阈值（不属于动效） |
| Curves.ease* | 48 处 |
| 内容限宽 | 仅 5 个值：1000（设置系）、800（我的/漫画设置）、640+600（弹层/Toast）、500（阅读器面板） |
| EdgeInsets | 约 145 行（pages + bean） |

### 7. StyleString 补 token 并替换裸圆角/间距（U2）

**方案**

constants.dart 的 `StyleString` 重构为封闭圆角刻度（对齐 M3 shape scale），并把 split-list 常量并入同一体系：

```dart
class StyleString {
  static const double cardSpace = 8;
  static const double safeSpace = 12;
  // 圆角刻度（B3 提案落地）
  static const double radiusXs = 8;    // chip、小组件、内嵌容器
  static const double radiusSm = 12;   // 图片、普通卡片（原 imgRadius 保留为别名）
  static const double radiusMd = 16;   // 页面级卡片组（my_page）、rail outlet
  static const double radiusLg = 24;   // split-list 组端（= splitListOuterRadius）
  static const double radiusPill = 28; // M3 rail destination 胶囊（settings_page 专用）
}
```

替换映射（按值 1:1 替换，不改视觉）：

| 现状字面量 | 处数 | 映射 | 备注 |
|---|---|---|---|
| 4（split-list 行内） | 6 | `splitListInnerRadius`（已有） | |
| 8 | ~10 | `radiusXs` | |
| 10（history_page ×2） | 2 | `radiusSm`(12) | ⚠ 唯一视觉变化点：10→12，需目检 |
| 12 | ~7 | `radiusSm` | |
| 16 | ~9 | `radiusMd` | |
| 24 | 1 | `radiusLg` | |
| 28 | 1 | `radiusPill` | |
| 2（进度条）、6（badge） | ~8 | **保留字面量** | 微圆角与控件高度耦合（2px 圆角 = 细条全圆），强行 token 化是过度设计 |
| 18/20/30（player_adjustment_hud、player_item_panel） | ~10 | **移入播放器本地常量** | HUD 专属视觉语言，不进全局 |
| js_descriptor_renderer 动态值 | ~7 | **豁免** | 圆角由 JS 插件数据驱动，不是设计决策 |

**间距 token 的诚实评估**：全库约 145 行 EdgeInsets，逐个替换"padding: 16"→"padding: spaceLg"收益极低（EdgeInsets 值是版式事实而非语义），churn 却是全量的。**建议收缩为**：
- token 照 B3 定义（spaceXs 4 / sm 8 / md 12 / lg 16 / xl 24），**只强制用于 `lib/bean` 组件层**（约 30 处）与新代码；
- pages 层存量不扫（review 规则覆盖增量即可）。

**范围**：constants.dart + 约 20 个文件 ~45 处替换。
**工作量**：4–5h。**风险**：低（常量替换，analyze 可验）。**视觉影响**：仅 history_page 两处 10→12。

### 8. 颜色：M3 ColorScheme 单一来源（U4 修订版，最高优先）

> 2026-09-06 修订：采纳评审意见——既然系统有主题色设置，UI 不允许硬编码颜色。首轮审计只搜了 white/black/hex，漏掉 grey/red/orange/accent 系；全量 `Colors.*` 审计后结论修正如下。

**三档边界**（替代原"沉浸层豁免"的粗糙二分）：

| 档 | 判据 | 处理 |
|---|---|---|
| ① 内容层 UI | 背景是主题 surface 的控件/文字 | **全部改走 `colorScheme`，零硬编码** |
| ② 媒体铬层 | 叠加在任意内容（视频帧/漫画图/照片）上的控件 | M3 官方立场也是固定深色铬（对比度是功能需求，背景不可知）；收缩为**最小固定集** token，强调色接 `colorScheme.primary` |
| ③ 用户可选内容色 | 背后是用户设置/插件数据（种子色列表、阅读画布、JS 传色） | 是"数据"不是"UI"：收敛为具名 palette 常量，豁免 |

**8A. 内容层 M3 化清扫（新增，优先级最高）**

内容层共 ~31 处违例，其中不少是暗色模式对比度 bug 级（`Colors.grey` 文字在暗色 surface 上）：

| 文件 | 处数 | 修复映射 |
|---|---|---|
| search_page.dart | ~13 | grey ×9（筛选/提示文字）→ `onSurfaceVariant`；状态色 map ×4 → 见下方语义映射 |
| plugin_manager_page.dart | ~14 | red ×2（删除确认）→ `error`；grey ×6 → `onSurfaceVariant`/`outline`；orange ×3 → `tertiary`；状态色 map ×4 |
| history_page.dart | 1 | redAccent（清空按钮）→ `error` |
| comic_image.dart | 2 | grey（加载失败文字）/ blue（重试）→ `onSurfaceVariant` / `primary`（背景是阅读器 surface，不是图片） |
| webview inappwebview impl | 1 | 下拉刷新 Colors.blue → `colorScheme.primary` |
| js_descriptor_renderer.dart | 1 | grey（描述符 disabled **fallback**）→ `onSurfaceVariant`（插件显式传色不归 Dart 管） |

状态色语义映射（M3 无 success/warning token，全库约定）：

| 语义 | M3 token |
|---|---|
| 进行中/下载中 | `colorScheme.primary` |
| 已完成 | `colorScheme.primary`（若与"进行中"需区分则 `tertiary`，二选一全库统一） |
| 失败 | `colorScheme.error` |
| 暂停/禁用/占位 | `colorScheme.onSurfaceVariant` |
| 警告提示（orange 系） | `colorScheme.tertiary` |

工作量 3h；风险低；**收益是修 bug**（暗色对比度），不只是风格统一。

**8B. 媒体铬层：最小固定集 + 主题强调色（原方案修订）**

不可推导的最小固定集（叠加在任意视频帧/图片上的部分）：

```dart
// lib/bean/styles/media_chrome_colors.dart
abstract final class MediaChromeColors {
  static const Color foreground = Colors.white;        // 图标/主文字
  static const Color foregroundDim = Colors.white70;
  static const Color foregroundFaint = Colors.white54;
  static const Color surface = Colors.black;           // 视频面底/图片查看器底
  static const Color barrier = Colors.black45;         // 面板投影/渐变端点
}
```

范围：player 7 文件 ~60 处、video_page 10、image_preview 10、漫画阅读器图片上的 scrim/页码 ~4。alpha（0.18~0.5）保持行内。

**主题化机会（与固定集并存）**：面板里接主题的强调色——进度条活跃色、高亮按钮、player_item_panel 的 greenAccent/redAccent 指示 ×2 → `colorScheme.primary`/`error`，让主题色在播放器里有存在感；字幕样式（player_item_surface 的 pink + 白描边）留在固定集并注释为媒体样式，未来可做成用户设置。

**8C. 用户可选内容色 palette 收敛**

- 小说阅读画布：`novelBackground` 设置已存在（'light'/'dark'），画布四色是它的支撑**数据**——从 novel_reader.dart 内联移到 `novel_reader_settings.dart` 命名 palette（paperBg/paperInk/darkBg/darkInk + 画布次要文字 inkSecondary）；reader 内 grey 文字（L335）随画布 palette 走。
- JS 控制台：`JsConsoleColors` 具名常量（dev 工具终端语义豁免，理由同种子色列表）。
- 种子色列表 `color_type.dart` / `oledDarkTheme`：本就是数据/主题构建层，豁免。

**防回归 guard（新增建议）**：`test/no_hardcoded_colors_test.dart`——扫描 `lib/**/*.dart` 源码的单元测试，断言白名单（palette/token/主题构建文件）之外不出现 `Colors.` 与 `Color(0x`；规则靠 `flutter test` 卡住，不靠 review。

### 9. 动效 token、限宽 token、my_page 图标（U5/U6/U7）

**动效 token**（新文件 `lib/utils/motion.dart` 或并入 constants.dart）：

```dart
abstract final class Motion {
  static const Duration fast = Duration(milliseconds: 70);     // Tab 切换 fade
  static const Duration preview = Duration(milliseconds: 220); // 图片预览 fade
  static const Duration standard = Duration(milliseconds: 250);// split-list/设置双栏/通用
  static const Curve curveStandard = Curves.easeInOutCubic;
}
```

- 只替换规范 B6 点名的 4 个落点（index_module ×2、settings_page `_paneMotion`，`splitListMotionDuration` 改为引用 `Motion.standard` 消除双份定义）。
- **明确不动**（实测甄别结论）：播放器 HUD 全部时序（160/180/200/420/650ms——是交互行为调优值不是装饰动效）、阅读器手势阈值（`_kDoubleTapMaxTime` 等）、网络重试退避、controller 定时器、video_page 侧栏 120ms。这些是"行为"不是"token"，扫进去只会制造假一致性。

**限宽 token**（constants.dart）：

```dart
abstract final class ContentWidth {
  static const double page = 800;    // 普通内容页（my_page、漫画设置，已是 800，零变化）
  static const double settings = 1000;// 设置系（settings_list 默认/download/keyboard，作特例保留）
  static const double sheet = 640;   // 底部弹层上限
  static const double readerPane = 500; // 阅读器内面板/设置弹层
}
```

实测好消息：**现有 5 个值各得其所，本项替换零视觉变化**，纯粹是把魔法数字变成有名字的约定（~12 处）。Toast 的 600 与弹层的 640 不合并——600 是断点判断（`LayoutBreakpoint.medium`），640 是弹层上限，语义不同。

**my_page 图标**（U6）：JS控制台 `Icons.history_rounded` → `Icons.terminal_rounded`（与"历史记录"的 history_rounded 区分）。5 分钟。

**范围**：~10 个文件 ~20 处。**工作量**：2h。**风险**：最低。

### P2 总体评估（2026-09-06 修订：颜色优先）

| 批次 | 内容 | 处数/文件数 | 工作量 | 视觉变化 | 风险 | 顺序 |
|---|---|---|---|---|---|---|
| 8A 内容层 M3 清扫 | grey/red/orange/accent → colorScheme | ~31 / 8 | 3h | 暗色对比度改善（正面） | 低 | ① 最高优先 |
| 8B 媒体铬固定集 | 白/黑系 → MediaChromeColors + 强调色接主题 | ~75 / 11 | 3h | 强调色 2 处接主题色 | 低 | ② |
| 8C 内容色 palette | 阅读画布/JS 控制台具名化 | ~8 / 3 | 1h | 无 | 低 | ③ |
| 9 动效/限宽/图标 | Motion/ContentWidth token + terminal 图标 | ~20 / 10 | 2h | 无 | 最低 | ④ |
| 7 圆角/间距 | 圆角刻度 + bean 层间距 token | ~45 / 21 | 4–5h | history 10→12 | 低 | ⑤ |
| guard 测试 | no_hardcoded_colors_test.dart | 1 个新文件 | 1h | 无 | 无 | 随 8A 一起落地 |

合计约 14–15h。颜色三批（8A/8B/8C）合计 7h，先于其余全部工作。三批都可用 `flutter analyze` + `flutter test` 验证 + 对应页面明暗两套主题目检（播放器面板、阅读器、设置、我的、搜索、插件管理）。

**明确不做的事**（防止过度工程化）：
1. 不全量扫 145 处 EdgeInsets（语义稀薄，churn 大于收益）；
2. 不动 js_descriptor_renderer 的 JS 驱动圆角与显式传色；
3. 不统一播放器 HUD 时序与阅读器 500 限宽（各有版式/行为约束）；
4. 不合并 Toast 600 与弹层 640（语义不同）；
5. 不把媒体铬层硬套 ColorScheme（背景不可知，对比度是功能需求——M3 对媒体应用的官方立场）。

**明确不做的事**（防止过度工程化）：
1. 不全量扫 145 处 EdgeInsets（语义稀薄，churn 大于收益）；
2. 不动 js_descriptor_renderer 的 JS 驱动圆角；
3. 不统一播放器 HUD 时序与阅读器 500 限宽（各有版式/行为约束）；
4. 不合并 Toast 600 与弹层 640（语义不同）。

---

## 附：与现状的映射索引

- 路由注册：`lib/app_module.dart`、`lib/core_module.dart`、`lib/pages/index_module.dart`、`lib/pages/*/**_module.dart`
- Tab 壳：`lib/pages/menu/menu.dart` + `lib/pages/router.dart`
- 设置壳：`lib/pages/settings/settings_page.dart`
- 主题：`lib/app_widget.dart`、`lib/bean/settings/theme_provider.dart`、`lib/utils/theme.dart`、`lib/bean/settings/color_type.dart`
- 组件层：`lib/bean/**`
- Token：`lib/utils/constants.dart`（StyleString/LayoutBreakpoint）、`lib/bean/widget/split_list_row.dart`（split-list 常量）
