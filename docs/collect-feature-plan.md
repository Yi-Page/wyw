# 收藏功能改动计划（基于浏览历史的重做）

> 目标：把 wyw 的「浏览历史」重做为「收藏模块」——收藏是基于插件持久化数据
> （`PluginBrowse` 接口暴露给插件的浏览足迹）的**增量管理层**，提供更细化的
> 管理（收藏状态、筛选、排序、分类），不与应用自身的「进度历史」耦合。
>
> 状态：**已实施**（阶段1–4 + 阶段5 的批量管理与插件文档；见 §12 实施记录）。
> 本文档保留为设计依据与决策台账。
>
> 修订：
> - v2 —— 采纳用户补充的四个语义：1) **未收藏是收藏状态之一**（插件收录历史的默认状态）；2) **「全部」tab 展示全部浏览历史**（含未收藏）；3) tab 顺序 = **全部、未收藏、其余 5 态**；4) **删除 = 删除整条浏览历史**，收藏状态只是条目的一个状态字段，随条目一起消失。
> - v3 —— 决策拍板：状态措辞**照 Kazumi**（在看/想看/看过/搁置/抛弃）；卡片布局**只做单列分组**；未收藏保留策略**做成设置项**（自定义上限 / 无上限）。

---

## 0. 结论速览

- 拆分两个模块：
  - **历史模块** = 只留**进度历史**（`HistoryEntry` / Hive box `histories`，应用自带资源的观看/阅读进度）。
  - **收藏模块** = **重做后的浏览历史**（插件浏览足迹 + 收藏状态管理）。
- 收藏**不建立**在进度历史之上，也不把两个历史耦合起来——它们本来就是两套独立存储、独立 key、独立控制器（`PluginHistoryRepository` 的注释明写"与 [HistoryRepository] 独立"）。
- 数据源 = `PluginHistoryEntry`（JSON 文件，插件通过 `PluginBrowse.open` 写入）。
- 收藏状态 = `collectType`（0=未收藏，1..5 为五态，照 Kazumi 的 `CollectType`），存进同一份条目。**未收藏（0）是插件收录历史的默认状态**——插件每次 upsert 新建的条目天然是"未收藏"。
- 状态措辞照 Kazumi（在看/想看/看过/搁置/抛弃）；卡片布局**只做单列分组列表**；未收藏条目保留策略做成**设置项**（自定义上限 / 无上限，见 §5 规则3）。
- UI = 单路由页面，**不在菜单里**（与进度历史的入口方式一致：从「我的」页进入），页面内含 **7 个子 tab**：
  **全部 / 未收藏 / 在看 / 想看 / 看过 / 搁置 / 抛弃**（样式照 Kazumi 追番页的 `TabBar(isScrollable: true)`）。
- **「全部」tab = 全部浏览历史条目（含未收藏的全部）**，即原历史页「浏览」tab 的升级版（时间分组 + 每行可设收藏状态）。
- **删除 = 删除整条浏览历史（含其收藏状态）**；之后插件再次收录（用户再进详情页）会新建一条**未收藏**条目——这是预期行为，不需要墓碑等特殊处理。
- 砍掉的部分：Kazumi 的 Bangumi.tv 账号同步、WebDAV 同步、作品详情页、追番周历——wyw 无对应数据源/账号体系，**做不了**。
- 与本仓库最近的外壳重构（P1–P4：对话框/sheet/顶栏/共享部件照抄 Kazumi）无冲突；收藏页作为新页面接入现有路由。

---

## 1. 目标架构

### 1.1 两个模块（与现状的关系）

| 模块 | 内容 | 存储 | 写入方 | key |
|---|---|---|---|---|
| **历史模块**（现状不变） | 进度历史 `HistoryEntry` | Hive `histories` | 应用自身播放/阅读回写 | `sourceId`（v3 结构化视频 = `'$sourceKey:$videoId'`；漫画 = `'$sourceKey:$comicId'`） |
| **收藏模块**（= 重做后的浏览历史） | 插件浏览足迹 + **收藏状态字段**（同一份数据） | 见 §6（建议迁 Hive） | 插件 `PluginBrowse.open`（自动，默认未收藏）+ 用户在收藏页管理（主动） | `'$pluginName::$id'` |

### 1.2 为什么收藏基于浏览历史（设计约束）

用户明确：**浏览历史是应用主动暴露给插件的持久化接口**，收藏只是在这份数据上做
**更细化的管理**。所以：

- 插件在用户进入详情页时调 `PluginBrowse.open(pluginName, {id, title, cover, kv})`
  写入一条浏览足迹 → 这条足迹**天然是"作品级"**（id 由插件保证唯一，可为作品 id/URL hash）。
- **收藏状态只是浏览历史条目的一个属性**（用户所有、插件不可写），默认值是「未收藏」。
- 两个历史之间保持互不认识：收藏模块不反向依赖进度历史；进度历史也不感知收藏。

### 1.3 与 Kazumi 的结构差异

- Kazumi：`collectibles`（收藏条目）+ `favorites`（bangumi 元数据缓存）+ `histories` 三个独立 box，
  收藏页只展示**已收藏项**，所以它的「全部」tab = 全部已收藏项（不含未收藏，也没有"未收藏"tab）。
- wyw：**一份数据 + 状态字段**，未收藏也是状态之一 → tab 为 **全部 / 未收藏 / 在看 / 想看 / 看过 / 搁置 / 抛弃**：
  - 「全部」= 全部浏览历史条目（**含未收藏**），范围比 Kazumi 的「全部」大；
  - 「未收藏」= `collectType == 0` 的筛选视图；
  - 其余 5 态 = 各状态筛选视图；
  - 7 个 tab 的并集即全集，顺序固定为「全部、未收藏、其余的」。

---

## 2. 现状盘点（已确认的事实，带文件位置）

### 2.1 插件浏览历史（收藏的数据源）

- 模型：`lib/services/storage/plugin_history_entry.dart`
  `PluginHistoryEntry { pluginName, id, title, cover, visitTime, kv(Map,自由 schema) }`
  `key = '$pluginName::$id'`
- 仓库：`lib/repositories/plugin_history_repository.dart`
  - 后端：**JSON 文件** `GStorage.pluginHistoryFile` = `${appSupport.path}/plugin_history.json`（全量读写，低频写）
  - API：`upsert`（整条替换）/ `find` / `findSync` / `getAllByPlugin` / `getAll` / `remove` / `restore` / `clearAll` / `changes`(Stream) / `getPrivateMode`
- JS 桥：`lib/js/js_extends/js_bridge.dart`
  - `{method:'plugin_history', function:'upsert'|'find', pluginName, id, title, cover, kv}` → `_handlePluginHistory`
  - `{method:'plugin_browse_entry', pluginName, id}` → `onPluginBrowseEntry` → `PluginController.openBrowseEntry`（调插件 `onOpenBrowseEntry(entryJson)` 回放）
- JS API：`assets/js/init.js` `PluginBrowse.open(...)` / `PluginBrowse.find(...)`
- 文档：`docs/plugin-development.md` §2.9（PluginBrowse）
- **38 个内置插件**调用 `PluginBrowse.open`（`assets/plugin/*.js`）→ **接口必须保持向后兼容**

### 2.2 进度历史（历史模块现状）

- 模型：`lib/services/storage/history_entry.dart` `HistoryEntry{sourceId,type,title,cover,lastWatchTime,progress}`
- 仓库：`lib/repositories/i_history_repository.dart` / `history_repository.dart`（Hive）
- 控制器：`lib/pages/history/history_controller.dart`（⚠ 该文件注释存在历史乱码，可顺手清理）
- 历史页：`lib/pages/history/history_page.dart` —— 两个 tab：**进度**（`HistoryController`）+ **浏览**（`PluginHistoryController`）
  - 进度 tab 已完成单列分组列表重构（提交 `cf3ac2e`）
  - 「浏览」tab 将**整体移入收藏模块**（成为收藏页的「全部」tab），历史页只留进度

### 2.3 控制器与卡片（浏览 tab 现状，将整体迁移）

- `lib/pages/history/plugin_history_controller.dart`（浏览 tab 控制器）
- `lib/bean/card/plugin_history_card.dart`（浏览卡片：封面/标题/插件名/相对时间，点击 `openBrowseEntry`，滑动删除）

---

## 3. 目标数据模型

### 3.1 统一条目（收藏 = 浏览历史 + 收藏字段）

```dart
class CollectEntry {               // 原 PluginHistoryEntry 扩展（或改名为 CollectEntry）
  String pluginName;               // 来源插件（标识）
  String id;                       // 插件保证唯一（作品级）
  String title;
  String cover;
  DateTime visitTime;              // 最近访问（自动，插件 upsert 刷新）
  Map<String, dynamic> kv;         // 插件自由 schema（不动）
  // ↓ 收藏状态字段（用户所有，插件不可写，默认「未收藏」）
  int collectType;                 // 0未收藏/1在看/2想看/3看过/4搁置/5抛弃（照 Kazumi CollectType）
  DateTime? collectedAt;           // 收藏动作时间（"最近变更"排序用；未收藏时可为 null）
}
```

### 3.2 收藏状态枚举（照 Kazumi，未收藏即默认状态）

```dart
enum CollectType {
  none(0, '未收藏'), watching(1, '在看'), planToWatch(2, '想看'),
  onHold(3, '搁置'), watched(4, '看过'), abandoned(5, '抛弃');
  const CollectType(this.value, this.label);
  final int value; final String label;
  bool get isCollected => this != none;
}
```

> ⚠ 数值顺序照 **Kazumi 实际实现**（`onHold=3` < `watched=4`），因为数值会持久化；
> 而 tab 的**展示顺序**由用户拍板为「全部、未收藏、在看、想看、看过、搁置、抛弃」
> （看过在搁置之前）——两者不同是刻意的，见 `collect_page.dart` 的 `collectCategories`。

> 语义要点：**插件 upsert 新建的条目默认 `collectType = none`（未收藏）**——"未收藏"
> 不是"没这回事"，而是浏览历史条目的**默认状态**，与其余 5 态地位相同、可以互相切换。
>
> 已定：措辞照 Kazumi（在看/想看/看过/搁置/抛弃），不改漫画向（§5 规则4）。

### 3.3 键与视图

- 数据键：`'$pluginName::$id'`（不变）
- 一份数据，三种视图：
  - **全部视图**（「全部」tab）：**全部条目（含未收藏）**，按 `visitTime` 时间分组、搜索、分页
    （= 原「浏览」tab 升级版），每行带收藏状态角标 + 状态菜单；
  - **未收藏视图**（「未收藏」tab）：`collectType == 0`，按最近访问排；
  - **收藏视图**（在看/想看/看过/搁置/抛弃 tab）：各状态筛选 + 计数，
    排序：最近变更（`collectedAt`）/ 名称 / 最近访问。

---

## 4. 插件接口兼容性（必须保持）

| JS API | 消息 | 现状 | 改动 |
|---|---|---|---|
| `PluginBrowse.open(pluginName,{id,title,cover,kv})` | `plugin_history/upsert` | `upsert` **整条替换** | **改合并语义**：只更新 `title/cover/kv/visitTime`，**绝不覆盖 `collectType/collectedAt`**（见 §5 规则1）；新条目（不存在）时以 `collectType=0` 创建 |
| `PluginBrowse.find(pluginName,id)` → data/null | `plugin_history/find` | 返回 `entry.toJson()` | **天然兼容**：`toJson` 新增 `collectType`/`collectedAt` 字段，插件忽略未知字段即可 |
| 点击回放 | `plugin_browse_entry` | `onPluginBrowseEntry` → `openBrowseEntry` | 不变 |

- 38 个内置插件 + `docs/plugin-development.md` §2.9 说明需保持行为不变；`find` 返回的新字段需在文档补一句（可选）。

---

## 5. 语义规则（均已定）

### 规则1（已定）：插件 upsert 绝不能覆盖收藏状态【代码证据】

当前实现是**整条替换**（`plugin_history_repository.dart` 的 `_mutate` 里
`entries.removeWhere((e) => e.key == key); entries.add(PluginHistoryEntry(...))`），
一旦加进 `collectType`，现在的 upsert 会把用户设的状态清成未收藏。
**必须改成合并语义**：`upsert` 只更新 `title/cover/kv/visitTime`，保留 `collectType/collectedAt`；
条目不存在时以 `collectType=0`（未收藏）创建。

### 规则2（已定）：删除 = 删除整条浏览历史（收藏状态只是条目的属性）

- **删除任何一条记录（无论处于哪个状态）都只是"删除浏览历史"**：整条移除，
  其 `collectType` 也随之消失。不存在"已收藏条目 vs 未收藏条目"两种删除语义。
- 之后插件再次收录（用户再进详情页触发 `open`）会**新建一条未收藏条目**——
  这是预期行为（对浏览历史合理），不需要墓碑/防复活机制。
- 代价：误删的已收藏条目只能靠重新打开详情页恢复（状态回到未收藏）。
  **建议：删除提供撤销 toast**（仓库已有 `restore`，可选实现）。

### 规则3（已定）：未收藏条目的保留策略 = 设置项

做成设置项（如 `SettingsKeys.uncollectedLimit`，存 `GStorage`），**支持自定义最大条数与「无上限」**：
- 「无上限」= 全留（现状，建议作为默认值）；
- 设 N 时：仅对「未收藏」条目清理，超出 N 按 `visitTime` 最旧优先清除；
- **已收藏条目不参与任何自动清理**（收藏 = 用户意图，必须保住）。

### 规则4（已定）：状态措辞照 Kazumi

「在看 / 想看 / 看过 / 搁置 / 抛弃」，与 Kazumi 完全一致，不改漫画向措辞。

---

## 6. 存储后端

| | 现状 JSON | 迁 Hive |
|---|---|---|
| 写入 | 全量读写（每次序列化整个列表） | 单条 put/delete |
| 收藏管理后 | 改状态/批量/自动清理 → 写频率上升，全量序列化成瓶颈 | 自然 |
| kv 自由 Map | 天然支持 | 支持但注意类型（与 `histories` 等一致即可） |
| 迁移 | — | 一次性从 `plugin_history.json` 导入 → 新 box（如 `collectibles`），老文件备份/保留 |
| 一致性 | 独立特例 | 与 `histories`/`downloads_v2` 一致 |

**建议：迁 Hive**（更细化的管理 = 大量单条写；且可复用仓库 `changes` 流通知模式）。
实施时新增 box（如 `collectibles`，存 `CollectEntry`），老 JSON 做一次性导入（全部为 `none`）。

---

## 7. UI 设计

### 7.1 收藏页 = 单路由页面，不在菜单

- 新路由（如 `/collect`），**不加入底部/侧边导航**（与 `/history/` 相同的"不在 menu"模式）。
- 入口：从「我的」页加一处入口（与历史入口并列），沿用 `WywAppBarMenuButton` 或列表项。
- 页面结构照 Kazumi 追番页：顶部标题 + 可滚动页签。

### 7.2 7 个子 tab（照 Kazumi 追番页样式，顺序固定）

- `TabBar(isScrollable: true, tabAlignment: start, dividerHeight: 0)`，
  胶囊指示器：`primaryContainer` 底 + 圆角 24 + `elastic` 动画（见 Kazumi `collect_library_controls.dart`）。
- tab 列表与顺序：**全部 / 未收藏 / 在看 / 想看 / 看过 / 搁置 / 抛弃**。
  - 「全部」= 全部浏览历史条目（含未收藏）——范围大于 Kazumi 的「全部」（Kazumi 不含未收藏）；
  - 「未收藏」= `collectType == 0` 的筛选子集。
- 每个 tab 带计数语义标签（照 Kazumi `Semantics(label: '${label}，${count} 条')`；注意单位措辞：Kazumi 用"部"，wyw 混视频/漫画/小说建议"条/个"）。「全部」tab 计数 = 总条目数。
- 状态措辞照 Kazumi（在看/想看/看过/搁置/抛弃，已定，见 §5 规则4）。

### 7.3 卡片布局（已定：只做单列分组）

**只做单列分组列表（B 方案）**，不做网格、不做布局切换（无 `CollectLayout` 设置项）：
- 「全部」tab：按 `visitTime` 时间分组（浏览视图）；
- 状态 tab：单列列表 + 计数；
- 每行：封面 + 标题 + 插件名 + 相对时间 + 状态角标/状态菜单（照 Kazumi `CollectButton`）+ 删除。

### 7.4 收藏按钮（可多选位置，彼此独立）

- 浏览历史卡片（长按/菜单）→ 收藏；
- 历史页进度卡片（Kazumi 的历史卡片内置收藏状态子菜单，可参考）→ 收藏；
- 播放页面板（可选）；
- 插件主动提供（通过 `openBrowseEntry` 的 entryJson 携带状态，可选）。
- 状态切换交互：照 Kazumi `CollectButton`（图标 + 菜单选 6 态，每态专属图标）。

### 7.5 打开作品

- 复用 `PluginController.openBrowseEntry`（插件自己的回放入口）——比 Kazumi 的 `/info/`
  更贴 wyw 的插件体系；进度历史场景仍走 `history_entry_launcher`。

---

## 8. 功能覆盖度（对照 Kazumi 收藏）

| Kazumi 功能 | wyw 可行性 |
|---|---|
| 6 种收藏状态 + 标签/图标（未收藏是默认状态） | ✅ 直接照抄 |
| 收藏页：多个子 tab + 计数 | ✅（7 tab：全部含未收藏 + 未收藏单独成 tab） |
| 搜索 | ✅ 按 title（无别名/原名，仅单字段） |
| 按状态筛选 + 排序（最近变更/名称/最近访问） | ✅ 字段齐 |
| 排序：评分最高 / 开播时间 | ❌ 无字段（可让插件写进 kv，宿主可选读取 = △） |
| 卡片上改状态（`CollectButton` 菜单） | ✅ |
| 删除/清空/撤销 | ✅（仓库已有 remove/restore/clearAll；删除即删浏览历史） |
| 从收藏打开作品 | ✅ `openBrowseEntry` |
| Bangumi.tv 账号同步 / WebDAV 同步 | ❌ 都没有 |
| 作品详情页 `/info/`、追番周历 | ❌ 无数据源 |
| 变更流水 + 云端合并 | ❌ 仅同步才需要 |

**结论**：可拿到 Kazumi 收藏的**全部本地管理能力**（约 8 成），且插件零改造
（收藏状态由宿主管理）。

---

## 9. 分阶段实施计划

### 阶段1：模型与存储迁移
- 扩展条目：`PluginHistoryEntry` 加 `collectType`(默认0)/`collectedAt`(null)（或新建 `CollectEntry`）。
- 新建 Hive box `collectibles` + `CollectRepository`（读/写/`changes` 流，参考 `HistoryRepository` 模式）。
- 一次性迁移：读 `plugin_history.json` → 导入新 box（状态=none），老文件备份。
- 文件：`lib/services/storage/plugin_history_entry.dart`、`lib/repositories/plugin_history_repository.dart`、新 `lib/repositories/collect_repository.dart`。
- 验证：`flutter analyze` + `flutter test`；迁移单测（老 JSON → 新 box）。

### 阶段2：插件接口合并语义
- `upsert` 改合并（只更新 title/cover/kv/visitTime，保留 collectType/collectedAt；不存在时以 none 创建）。
- `find` 返回含新字段的 toJson（天然兼容）。
- 文件：`plugin_history_repository.dart`（或新仓库的写入路径）、`js_bridge.dart` 的 `_handlePluginHistory`。
- 验证：单测——「已收藏条目被插件 upsert 后状态不变」是核心回归测试。

### 阶段3：收藏页 UI
- 新路由 `/collect` + 页面：标题 + `TabBar` 7 tab（全部/未收藏/在看/想看/看过/搁置/抛弃） + **单列分组列表**（§7.3）。
- 卡片：状态角标/状态菜单（照 `CollectButton`）。
- 设置项：未收藏保留策略（`SettingsKeys.uncollectedLimit`，上限 / 无上限，见 §5 规则3）。
- 控制器：`CollectController`（MobX，参考 `PluginHistoryController` + `CollectLibraryQuery` 的排序/筛选逻辑）。
- 文件：`lib/pages/collect/*`。
- 验证：analyze + test；widget 测试（tab 计数、筛选、状态切换）。

### 阶段4：入口接线与历史页拆分
- 历史页去掉「浏览」tab（进度 tab 保留单列分组列表现状）；浏览历史由收藏页「全部」tab 承接。
- 浏览相关文件（`plugin_history_controller`/`plugin_history_card`）移入收藏模块。
- 「我的」页加收藏入口（不在菜单）。
- 文件：`history_page.dart`、`my_page.dart`、模块路由注册。
- 验证：analyze + test + 手动检查历史页只剩进度 tab。

### 阶段5：可选扩展
- 评分/开播排序：插件把值写进 kv，宿主可选读取。
- 批量管理（多选改状态、清空未收藏）。
- 插件文档 §2.9 补收藏字段说明。

---

## 10. 已定项与待拍板的决策点

### 已定（无需再拍板）

| # | 事项 | 决定 |
|---|---|---|
| A | tab 组成与顺序 | **全部 / 未收藏 / 在看 / 想看 / 看过 / 搁置 / 抛弃** |
| B | 「全部」tab 内容 | **全部浏览历史条目（含未收藏）** |
| C | 未收藏的地位 | **浏览历史条目的默认状态**（插件新建条目即未收藏） |
| D | 删除语义 | **删除 = 删除整条浏览历史（含收藏状态）**；再次收录则新建未收藏条目 |
| E | 两模块关系 | 收藏与进度历史**不耦合** |
| F | 状态措辞 | **照 Kazumi**：在看 / 想看 / 看过 / 搁置 / 抛弃 |
| G | 卡片布局 | **只做单列分组列表**（不做网格、不做布局切换） |
| H | 未收藏保留策略 | **做成设置项**：自定义上限 / 无上限（已收藏永不自动清理） |

### 待拍板（实施前必须确认）

| # | 决策 | 选项 | 默认建议 |
|---|---|---|---|
| 1 | 存储后端 | JSON 保留 / 迁 Hive | 迁 Hive |
| 2 | 收藏页入口位置 | 「我的」页列表项 / logo / 其它 | 「我的」页 |
| 3 | 删除撤销 toast | 要 / 不要 | 要（仓库已有 restore） |

> 另两处按默认推进（未反对即视为接受）：「全部」tab 数据源 = **浏览历史**（非进度历史）；
> 历史页移除「浏览」tab，由收藏页「全部」tab 承接。

---

## 11. 相关文件索引（实施后）

### 新增

- `lib/services/storage/collect_type.dart` —— 收藏状态枚举（数值/标签照 Kazumi）
- `lib/services/storage/collect_entry.dart` —— 收藏条目模型（Hive `typeId: 11`）+ 生成适配器
- `lib/repositories/collect_repository.dart` —— Hive `collectibles` 仓库（合并 upsert、
  收藏状态、上限清理、旧 JSON 一次性导入）
- `lib/pages/collect/collect_module.dart` —— `/collect` 模块
- `lib/pages/collect/collect_page.dart` —— 收藏页（7 tab + 单列分组 + 多选管理）
- `lib/pages/collect/collect_controller.dart` —— 收藏页控制器（MobX）
- `lib/pages/collect/collect_library_query.dart` —— 筛选 / 计数 / 排序
- `lib/bean/card/collect_entry_card.dart` —— 单列分组卡片（状态菜单 + 多选）
- `lib/bean/widget/collect_button.dart` —— 收藏状态按钮（照 Kazumi `CollectButton`）
- `lib/pages/settings/collect_settings.dart` —— 收藏设置（未收藏上限）
- 测试：`test/collect_entry_test.dart`、`test/collect_repository_test.dart`、
  `test/collect_library_query_test.dart`、`test/collect_button_test.dart`

### 改动

- `lib/services/storage/storage.dart` —— 新增 `collectibles` box（`pluginHistoryFile` 保留作迁移源）
- `lib/services/storage/settings_keys.dart` —— `uncollectedLimit`（0 = 无上限）
- `lib/js/js_extends/js_bridge.dart` —— `plugin_history` 路由到 `CollectRepository`（`find` 返回新字段）
- `lib/js/production_script_engine.dart`、`lib/core_module.dart`、`lib/pages/init_page.dart` —— 注入与迁移接线
- `lib/pages/history/history_page.dart`、`history_module.dart` —— 移除浏览 tab 与 `/history/browse`
- `lib/pages/my/my_page.dart`、`my_space_view.dart` —— 「我的」页收藏入口
- `lib/bean/appbar/app_bar_menu_button.dart` —— 顶栏「更多」菜单加入收藏入口（与历史记录并列）
- `lib/pages/settings/settings_module.dart`、`settings_page.dart` —— `/settings/collect` 分类
- `lib/pages/index_module.dart` —— 注册 `collectModule`
- `docs/plugin-development.md` §2.9、`docs/ui-routing-design-spec.md`（R6 / 控制器作用域）

### 删除（已迁移）

- `lib/services/storage/plugin_history_entry.dart`
- `lib/repositories/plugin_history_repository.dart`
- `lib/pages/history/plugin_history_controller.dart`（+`.g.dart`）
- `lib/bean/card/plugin_history_card.dart`

### Kazumi 参考

`lib/pages/collect/*`（collect_page / collect_library_view / collect_library_controls /
collect_library_query / collect_module）、`lib/modules/collect/collect_type.dart`、
`lib/bean/widget/collect_button.dart`

---

## 12. 实施记录（与计划的差异）

1. **枚举数值照 Kazumi 实际顺序**：`onHold=3`、`watched=4`（计划草稿曾写成
   `watched=3`/`onHold=4`，已按 Kazumi 修正；数值会持久化）。tab 展示顺序按用户
   拍板为「全部、未收藏、在看、想看、看过、搁置、抛弃」。
2. **仓库命名**：JSON 后端整体替换为 `CollectRepository`（Hive `collectibles`），
   原 `PluginHistoryRepository` / `PluginHistoryEntry` 删除；JS 侧接口
   （`PluginBrowse.open/find`）与消息名（`plugin_history`）不变，38 个内置插件零改造。
3. **key 哈希**：Hive String key 上限 255 字符，业务键 `pluginName::id` 可能很长
   （插件常用 URL hash），统一存 sha256；业务键语义不变。
4. **分组日期键跟随排序主键**：`最近访问` → 条目访问时间；`最近变更` → 收藏时间
   （未收藏回退访问时间）；`名称` → 不分组（平铺，避免分组标题与字母序冲突）。
   所以「全部 / 未收藏」默认（最近访问）按访问日期分组，收藏态 tab 默认（最近变更）
   按变更日期分组；切换排序会同步切换分组键（同一日期分组必然连续）。
5. **批量管理已实现**（阶段5 的可选扩展）：多选改状态、批量删除（带撤销）、
   清空未收藏、清空全部（均需输入「清除」二次确认）。
6. **设置项位置**：新增「设置 → 应用 → 收藏设置」分类（`/settings/collect`），
   而不是塞进「界面设置」。两项：
   - **进入时的默认页签**（`collectDefaultTab`）：`-1` = 全部，其余 = `CollectType`
     数值；存状态数值而非 tab 下标，tab 顺序调整后设置不会错位。
   - **未收藏记录上限**（`uncollectedLimit`）：任意数字（0 或留空 = 无上限），
     保存后立即清理一次。
7. **删除撤销**：单条滑动删除与批量删除都带 4 秒撤销（仓库 `restore` 原样放回，
   含收藏状态与访问时间）。
8. **未做**：评分 / 开播时间排序（无字段）、Bangumi/WebDAV 同步、作品详情页、
   追番周历、变更流水（均无数据源，见 §8）。
9. **验证**：`flutter analyze` 无问题；`flutter test` 384 passed
   （基线 301 + 新增 83）。
10. **卡片状态按钮形态按行宽切换**（后续调整）：卡片可用宽度 ≥ 500 用
    `CollectButton.extend`（图标 + 文字），否则只留图标（图标本身已表达状态，
    文字仍在菜单与 tooltip 里）——窄卡片上"图标 + 文字"会挤掉标题宽度。
    阈值定义在 `CollectEntryCard.extendedStatusMinWidth`，由
    `test/collect_entry_card_test.dart` 锁边界（499 / 500）。

---

## 13. 删除恢复（回收站）—— 收藏页与历史页共用，替代 4 秒 SnackBar 撤销

> 状态：**已实施**。拍板结果：清单**不加上限**；弹窗尺寸/样式**对齐播放器的截图管理弹窗**
> （`lib/pages/player/player_screenshot_sheet.dart` 的 `showPlayerScreenshotSheet`）；
> 其余按 §13.9 的建议执行。
> 动机：现有"4 秒 SnackBar 撤销"实用上不好用。

### 13.1 现有实现的问题

| 问题 | 说明 |
|---|---|
| 窗口太短 | 4 秒后不可恢复 |
| **会互相顶掉** | 删除时先 `hideCurrentSnackBar()`，后一次删除直接顶掉前一次的撤销机会——连续删除时先删的条目**永久丢失** |
| 信息不足 | SnackBar 只显示标题，无法确认"删的到底是哪一条" |
| 入口不稳定 | SnackBar 自己会消失；回头想恢复时已无入口 |
| 无法审阅 | 批量删除 N 条只给一个「撤销」，看不到具体是哪些 |

### 13.2 目标交互

1. 删除**立即落盘**（语义不变：删除 = 删除整条浏览历史，§5 规则2），同时把被删条目的
   **完整快照**记进页面级「本次已删除」清单。
2. 清单**存活到页面 dispose**（离开收藏页即丢弃；不持久化、不入库、不改仓库对外 API）。
3. 顶栏出现**「已删除」按钮**（数量角标 `Badge`），清单非空时可用。
4. 点击弹出**弹窗**：列出本次删除的条目 + 详细信息，支持**单条恢复 / 全部恢复 / 清空记录**。
5. 删除后**不弹任何提示**：唯一反馈是列表少一行 + 顶栏角标 +1（决策 2）。

### 13.3 数据与生命周期

```dart
typedef DeletedCollectEntry = ({CollectEntry entry, DateTime deletedAt});

/// 纯 Dart（无 Flutter 依赖）→ 可单测
class DeletedEntriesLedger {
  List<DeletedCollectEntry> get entries;  // 最新删除在前（只读视图）
  int get count;
  bool get isEmpty;
  bool get isNotEmpty;
  void add(CollectEntry entry, {DateTime? at});
  void addAll(Iterable<CollectEntry> entries, {DateTime? at});  // 批次内保持传入顺序
  DeletedCollectEntry? remove(CollectEntry entry);  // 恢复成功后出账
  void clear();                           // 放弃恢复机会（不删数据）
}
```

- **不加上限**（用户拍板）：内存代价 = 被删条目的快照，条目本身已从 Hive 删除，
  清单大小只受本次会话删除量影响。

- 归属：`_CollectPageState` 持有实例，`dispose` 自然回收 → 精确对应"直到页面 dispose"。
- **跨 tab 保留**：ledger 是页面级，不随 tab 切换清空（在「在看」tab 也能恢复刚在「全部」删的条目）。
- **不持久化**：关页即放弃恢复机会（用户明确要求，因此无需存储层改动）。

### 13.4 顶栏按钮

- 位置：`actions` 里排在「多选管理 / 清空」之前；`WywAppBarMenuButton`（全局导航）仍固定最后（规范 B9）。
- 形态：`IconButton` + `Badge` 数量角标，图标 `Icons.restore_from_trash_rounded`。
- 语义：`tooltip: '本次已删除（N 条，可恢复）'` + `Semantics(label: ...)`。
- 清单为空：**禁用**（置灰可见，保持布局稳定——与菜单按钮"已在本页即禁用"同一取向）。
- 多选模式：隐藏（决策 5）。

### 13.5 弹窗内容

标题：`本次已删除（N 条）`；列表最新删除在前，每行：

| 元素 | 内容 |
|---|---|
| 封面 | 缩略图（无封面则省略） |
| 标题 | 最多 2 行 |
| 来源插件 | 展示名（`displayNameOf` 由调用方注入回调 → 弹窗不依赖 DI，可单测） |
| 收藏状态 | 图标 + 文字，只读 chip（复用 `CollectButton.iconFor`） |
| 访问时间 | 相对时间 |
| **删除时间** | 相对时间（"3 分钟前"） |
| 操作 | 「恢复」 |

底部动作：**全部恢复**（空则禁用）/ **清空记录**（只丢弃恢复机会，不删数据 → 不需要二次确认）/ **关闭**。

其它规格（**对齐播放器截图管理弹窗**）：
- `Dialog` + `insetPadding` 16（宽 < 700 或高 < 500）/ 24 + 圆角 28 + `surfaceContainerHigh`
- 内容 `width: 1120` + `maxHeight: min(840, 屏高 - inset*2)`，可滚动列表
- 同一套 compact/wide 阈值（高 < 500 记 compact、宽 ≥ 700 记 wide）；窄屏行内换行
- 空态用 `GeneralEmptyState`；Esc 关闭；标题下副标题显示条数与"恢复后回到原状态"
- 不设条数上限 → 无需"已丢弃"提示

### 13.6 恢复语义与边界

1. **同 key 冲突（可达但很窄，已核实触发链）**：撤销窗口从 4 秒变成"整页生命周期"后，
   被删条目在恢复前**可能**被插件重新 `upsert`。内置插件普遍在 `getDetail()` 末尾
   upsert（`ccc.js:356`、`jm.js:682`、`hitomi.js:1335`、`picacg.js:519`…），
   而详情页含「相关推荐」→ `UI.Navigate({page:'descriptor', method:'getDetail', args:[其他 id]})`。
   触发链：

   1. 收藏页里有 A、D 两条（同插件）；删掉 D → 出库、快照进 ledger，收藏页仍在栈顶；
   2. **不离开收藏页**，点 A 的卡片 → 插件 `getDetail(A)` → 详情页 push 在收藏页**之上**
      （收藏页 `State` 未 dispose，ledger 还活着）；
   3. A 的详情页点「相关推荐」里的 D → `getDetail(D)` → `PluginBrowse.open(D)`
      → D 以「未收藏 + 新访问时间」重建；
   4. 返回收藏页 → 「已删除」弹窗对 D 点「恢复」→ **旧快照覆盖新记录**
      （访问时间倒退；第 3 步之后设的收藏状态被抹掉）。

   ⚠ 这条链要求"删掉的作品恰好出现在另一个作品的推荐位里、且用户点了它"，
   并且只在收藏页**未 dispose** 的窗口内成立（离开收藏页 → ledger 丢弃）。
   所以它是**窄边界，不是常见路径**——本节保留它只是因为一旦发生就是静默数据损坏。
   处理选项：

   - **(a) 合并**：保留较新的插件字段（title/cover/kv/visitTime），仅当现存条目是
     「未收藏」且快照是「已收藏」时补回收藏状态（约 10 行 + 1 条测试）；
   - **(b) 跳过并提示**：同 key 已存在时不动数据，提示"该条目已重新出现，未恢复"
     （更简单、永不覆盖；代价是用户需手动再设一次状态）；
   - **(c) 覆盖旧快照**：= 现有 `restore` 行为，不建议。
2. **恢复后**：出账 → 角标减一 → 列表经 `changes` 流自动刷新 → toast「已恢复「X」」。
3. **重复删除同一 key**：恢复即出账，不会出现两行；再次删除重新入账。
4. **批量删除**：同一批共享 `deletedAt`，在弹窗里天然相邻。
5. **清空未收藏 / 清空全部**：是否入账见决策 1（建议入账——否则"清空"是最危险的
   不可恢复操作）；入账时受 500 上限约束。
6. **导航**：`push` 到别的页面再返回，`State` 仍在 → 清单保留；返回上一页（dispose）→ 丢弃。

### 13.7 文件与改动（两页共用）

| 文件 | 改动 |
|---|---|
| `lib/utils/deleted_ledger.dart`（新，通用） | `DeletedLedger<T>`：纯 Dart 清单（不加上限 + 出账，`keyOf` 决定身份口径） |
| `lib/bean/dialog/deleted_entries_dialog.dart`（新，通用） | 弹窗外壳：尺寸/样式对齐播放器截图管理弹窗；tile 与文案由调用方注入 |
| `lib/pages/collect/collect_deleted_dialog.dart`（新） | 收藏页包装 + 行内容（封面/插件/状态/访问/删除时间） |
| `lib/pages/history/history_deleted_dialog.dart`（新） | 历史页包装 + 行内容（封面/类型/进度摘要/上次观看/删除时间） |
| `lib/pages/history/history_progress_summary.dart`（新） | 从 `history_page.dart` 抽出的进度摘要/类型标签（两处共用，防漂移） |
| `lib/pages/collect/collect_page.dart` | ledger 状态 + 顶栏角标按钮 + 删除/批量/清空入账 + 轻提示 + 弹窗 |
| `lib/pages/history/history_page.dart` | 同上（历史页只有单条删除与清空） |
| `lib/repositories/collect_repository.dart` | `restore` 增加同 key 合并分支（§13.6-1） |

### 13.8 实施步骤

1. **ledger + 仓库恢复合并**（纯逻辑 + 单测，不动 UI）
2. **弹窗**（独立 widget + 测试）
3. **接线**：顶栏按钮/角标、删除路径入账、SnackBar 改轻提示
4. 文档同步 + 真机确认（角标、弹窗滚动、恢复后列表刷新）

### 13.9 拍板结果（已定）

| # | 决策 | 结果 |
|---|---|---|
| 1 | 清空未收藏 / 清空全部 是否入账可恢复 | **入账**（先按当前列表取快照再落盘删除） |
| 2 | 删除后的 SnackBar | **不要任何提示**（唯一反馈 = 行消失 + 角标 +1；撤销职责交给常驻按钮） |
| 3 | 恢复时同 key 已存在 | **(a) 合并**（保留较新的插件字段 + 补回收藏状态；收藏时间沿用快照） |
| 4 | 弹窗形态 | **对话框**，尺寸/样式对齐播放器截图管理弹窗 |
| 5 | 多选模式下是否显示该按钮 | **隐藏**（退出多选即回到常规动作） |
| 6 | 清单上限 | **不限** |

### 13.10 实施记录

**第一批（收藏页）**

- 新增 `deleted_entries_ledger.dart`（纯 Dart 清单，不加上限）、
  `deleted_entries_dialog.dart`（弹窗，注入 `displayNameOf` 回调，不依赖 DI）
- `collect_page.dart`：ledger 状态 + 顶栏角标按钮（`Badge.count`，空清单禁用）
  + 删除/批量删除/清空入账 + 弹窗接线（**删除不弹任何提示**）
- `collect_repository.dart`：`restore` 增加同 key 合并分支
- 清空确认文案同步：不再说"无法撤销"，改为"删除后可在顶栏「已删除」中恢复（离开本页后失效）"

**第二批（历史页复用 + 抽通用件）**

- 清单抽成 `DeletedLedger<T>`（`keyOf` 决定身份口径：收藏页 `pluginName::id`、
  历史页 `sourceId`），删除原 `pages/collect/deleted_entries_ledger.dart`
- 弹窗外壳抽成 `showDeletedEntriesDialog<T>`（尺寸/交互/快捷键共用，行内容与文案注入），
  删除原 `pages/collect/deleted_entries_dialog.dart`
- 历史页接入同一套回收站：顶栏角标按钮 + 删除/清空入账 + 弹窗
  （历史页行内容额外显示**类型**与**进度摘要**）
- 抽出 `history_progress_summary.dart`：进度摘要 / 类型中文名 / 类型图标，
  历史页「继续观看」与删除弹窗共用同一实现（原先 `_continueSubtitle` 只在页面里）
- 测试：`deleted_ledger_test`（通用件，含两种类型）、`deleted_entries_shell_test`（外壳）、
  `collect_deleted_dialog_test`、`history_deleted_dialog_test`、`history_progress_summary_test`、
  `collect_repository_test` 增「恢复同 key 合并」三条


