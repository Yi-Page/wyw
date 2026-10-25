# 插件持久化规范

> 状态：生效中。第一版（无版本管理）—— 插件记录只有六个字段，顺序就是列表位置。

## 1. 一句话模型

**插件 = 一个 JS 文件 + 一条记录。** 文件里只有代码，宿主需要的一切（展示名、分类、
是否启用、主页、简介）都在 `index.json` 的这条记录上。

```
{appSupportDir}/plugins/
  index.json        ← 插件记录（数组，顺序 = 显示顺序）
  categories.json   ← 用户自定义分类（数组，顺序 = 显示顺序）
  hanime.js         ← 载荷：JS 源码，文件名 = 插件名 + .js
```

随应用打包的还有**出厂安装包** `assets/plugin/`（配置 `index.json` + 载荷 `{name}.js`），
只在「一个插件都没有」时被安装一次（见 §7.2）。

旧的 `plugin_config.json` 与旧结构的 `index.json` **不做迁移**：读不出（不是数组）就
当空表，由目录扫描重建。被覆盖的旧文件会留成 `.bak`。

## 2. 命名链（一条主键贯穿四环）

```
文件名        hanime.js
记录主键      index.json 数组里的 "name": "hanime"
类名          class hanime extends PluginSource
引擎槽位      __plugins__.hanime
```

四环必须**逐字符相同**。任一环不匹配 → 插件不可用。

### 大小写规则

| 层 | 敏感性 | 规则 |
|---|---|---|
| JS 类名 | **大小写敏感** | `class Hanime` ≠ `class hanime`，必须与插件名逐字符相等 |
| 记录主键 | 大小写敏感 | 数组里 `hanime` 与 `Hanime` 算两条（`decode` 只按逐字符去重） |
| 文件系统 | **大小写不敏感**（Windows / macOS） | `hanime.js` 与 `Hanime.js` 是**同一个文件** |

两条合起来的约束：**插件名必须大小写不敏感唯一**。校验分两处：

1. **正则校验**（`PluginSourceRule`）—— 字面量/注释掩码后扫描
   `^class[ \t]+([A-Za-z_$][\w$]*)[ \t]+extends[ \t]+PluginSource\b`，要求恰好 1 处命中，
   且捕获到的类名与插件名**逐字符相等**。
2. **大小写折叠唯一性**——新建前用 `PluginNameFold` 查重，命中不同拼写的同名片则拒绝；
   扫描时若磁盘文件名与已有记录的拼写不一致，直接把文件**改名对齐**记录。

### 名字字符集

`^[A-Za-z_][A-Za-z0-9_]*$`（`PluginNameRules.validate`），一石三鸟：

- 能安全拼进 `new NAME()` 与 `typeof __plugins__.NAME.m === "function"`；
- 天然是安全文件名（无 `/`、`..`、`:`、空格）；
- 无路径穿越。

附加规则：排除 Windows 保留名（`con`/`prn`/`aux`/`nul`/`com1-9`/`lpt1-9`）。

## 3. index.json 结构

整个文件就是**一个数组**，一条记录一个插件，**数组顺序 = 管理页显示顺序**：

```json
[
  {
    "name": "hanime",
    "enabled": false,
    "displayName": "Hanime1",
    "categoryId": "anime",
    "homepage": "https://hanime1.me",
    "description": "…"
  }
]
```

| 字段 | 类型 | 谁写 | 说明 |
|---|---|---|---|
| `name` | string | 只读 | 唯一标识（命名链四环）。**不可修改**，改名等价于导出后以新名字导入 |
| `enabled` | bool | 用户 | 是否注册进引擎。禁用 = 文件保留、不构造不注册，**在列表里的位置不变** |
| `displayName` | string | 用户 | 空则回落 `name` |
| `categoryId` | string | 用户 | 空则按插件方法推断（见 §5） |
| `homepage` | string | 用户 | 仅展示 |
| `description` | string | 用户 | 仅展示 |

没有 `order` 字段：**顺序就是列表位置**，也就是数组下标。没有 `version` / `author` /
`minAppVersion` / `format` / `formatVersion` —— 第一版不做版本管理。

### 一个数据来源：宿主台账

| 类别 | 来源 | 插件代码里有吗 | JS 实例上有吗 |
|---|---|---|---|
| 上面六个字段 | `index.json`；用户可在详情页「管理属性」里直接填改 | ❌ | ❌ |

**判据是「插件自己的逻辑会不会读它」**，逐个实测过 39 个内置插件 + 基类：

| 字段 | 引擎内读取者 | 结论 |
|---|---|---|
| `this.constructor.name` | 基类 `loadData`/`saveData`/`deleteData`/`loadSetting`/`saveSetting`/`isLogged` | **存储命名空间的唯一来源**，见 §6。基类不提供、也不读 `key` 之类的属性，所以插件声明什么都改不了它 |
| `this.key` | 基类 **0** 处；37/37 插件自己声明了它（值都等于插件名） | **死数据**：基类不再消费，只是插件自己的字段，清理即可 |
| `this.name` | **24/39**（`title: … \|\| this.name`、日志前缀） | 只是插件内部展示兜底；宿主不声明也不注入 |
| `this.version` / `homepage` / `author` / `type` / `minAppVersion` | **0** | 宿主台账字段，管理页可填 |

> 曾出现过「声明值 + 用户覆盖」两层结构（`PluginRecord.attached` + `*Override`）。
> 已经删掉：既然插件代码里的声明**没有任何读取者**，它就不该存在，一层用户台账足够。

### 写盘

原子写：先写 `index.json.tmp`，再 `rename` 覆盖；覆盖前把旧文件复制为 `index.json.bak`。
任何解析异常都退化为空表（不阻断启动），下一次保存即修复。

## 4. categories.json 结构

与 `index.json` 完全对称：数组、顺序即展示顺序。

```json
[
  { "id": "anime", "label": "番剧", "icon": "tv" }
]
```

| 字段 | 说明 |
|---|---|
| `id` | 分类 id，插件的 `categoryId` 指向它。小写规范、大小写不敏感查重、**不可修改** |
| `label` | 展示名 |
| `icon` | 图标 key（`CategoryIcons.palette` 的键）；空串 / 未知 key → 默认图标 |

### 图标为什么落盘的是 key 而不是 IconData

Flutter 的 release 构建默认开 `--tree-shake-icons`，它只认**编译期常量**的 `IconData`
并裁掉没用到的字形；运行时用 `IconData(codePoint)` 动态构造会被判定为不可 trim 而
**直接构建失败**。所以候选图标必须全是常量（`CategoryIcons.palette`，29 个），
用户的选择只记一个 key，`CategoryIcons.resolve(key)` 查表。
副作用：调色板可以随时增删条目，旧数据里的未知 key 自动回落，不会读崩。

内置分类（`video` / `manga` / `novel` / `unknown`）仍写在代码里，顺序固定；
自定义分类同 id 顶不掉内置分类。

## 5. 生效分类：填了就查表，没填就推断

```dart
PluginCategory categoryOf(Plugin p) {
  if (p.categoryId 非空) return registry.resolve(p.categoryId);  // 未注册的 id 就地登记为隐式分类
  return _inferred[p.name] ?? unknown;                            // 扫描时算好缓存
}
```

推断规则（要打一次 JS 引擎，所以在扫描 / 启用 / 编辑时算一次并缓存）：

| 插件实现了 | 判为 |
|---|---|
| `play` | 视频 |
| `openReader` | 漫画 |
| `openNovelReader` | 小说 |
| 都不实现 | 其他 |

删除自定义分类时，会把指向它的插件 `categoryId` 清空（回落为推断），并写回
`index.json` —— 分类定义在 `categories.json`，而引用它的字段在 `index.json`，两处都要落。

## 6. 存储命名空间：直接取类名，没有中间属性

基类的 `loadData` / `saveData` / `deleteData` / `loadSetting` / `saveSetting` / `isLogged`
调桥时必须带一个命名空间（`sendMessage({ method: 'load_setting', key: …, setting_key: … })`），
它是**当场算出来的**，不是字段、也不经过任何可被插件声明的属性：

```js
key: this.constructor.name,   // 类名 = 插件名（命名链已校验）
```

基类因此**没有 `key` 成员**（曾经有个 `get key()`，删掉了）：留一个 getter 就等于留一个
「插件声明同名字段就能把它遮蔽掉」的入口，而它的值同时又是存储命名空间 —— 那正是
历史上 `komiic` → `"Komiic"` 错位的成因。现在无论插件在类体里写什么，命名空间都只认类名。

宿主**不声明、不注入、不落盘**，插件代码里也不需要（也不应该）写 `key = '…'`：
命名空间由基类直接取 `this.constructor.name`，**不经过任何插件可声明的属性**，
所以插件在类体里声明 `key` 影响不到它（那份字段只是插件自己的一份死数据）。

> **构造期时序**：现存 **22/39** 个内置插件在构造函数里调 `init()`，而 `init()` 会
> **同步**调 `loadSetting()`（走 `this.constructor.name`）。类名在 `new` 的那一刻
> 就已经确定 —— 不需要在构造前后注入任何东西。
> 这条时序由 `node tools/check_plugin_naming.js --self-test` 的「存储命名空间派生自检」锁住
> （其中一条正是「声明了 key 字段也改变不了命名空间」）。

**旧命名空间不做兼容**：历史上 `komiic` → `"Komiic"`、`manhuagui` → `"ManHuaGui"`
两个插件自称的 key 与插件名不同，兼容层（`storageAlias` / JS 桥读穿透 / 控制器反查表）
已经整体删除，那两个插件也已从 `assets/plugin/` 移除。命名空间从此只有「插件名」一个来源。

## 7. 加载状态

| 状态 | 触发 | 处理 |
|---|---|---|
| `loaded` | 记录 `enabled` + 文件在 + 校验通过 + 注册成功 | 正常使用 |
| `disabled` | 记录 `enabled = false` | 不构造不注册，文件保留，位置不变 |
| `failed` | 文件在但注册抛错 | `loadErrors[名字]`，管理页「异常」分区里可删除 |
| `deleted` | 记录与文件都没有 | `presenceOf` 返回 `deleted` |

另有一类**不是插件**的东西：文件名不合法的 `.js`（`invalidFiles`）。它连记录都建不了，
但也不能静默消失 —— 管理页「异常」分区会把它列出来并提供删除入口。

「异常」分区**标题行右侧**还有两个**批量动作**（语义与逐行按钮完全一致，只是循环一遍）：

- **全部导入**：只对「未导入」生效 —— 为磁盘上那些 `.js` 一次性建立记录并注册；
  另外三类要么没有文件（文件缺失），要么文件名连记录都建不了（文件名非法），
  都不是「导入」能解决的，所以该类为空时按钮置灰。
- **全部删除**：四类一起清 —— 有记录的（注册失败 / 文件缺失）走 `deletePlugin`
  （连记录一起删），没记录的野文件（未导入 / 文件名非法）走 `deleteStrayFile`
  （只删磁盘上的文件，不动索引）。

两者的作用范围都是**当前可见**（关键词筛选之后）的异常项，与分区里显示的行一一对应；
逐条执行（每条都要写一次 `index.json`，并发写不安全），失败项汇总进结果弹窗。
**扫描本身仍然永远不删任何东西**，批量删除只能由用户显式确认。

### 7.1 与磁盘的对账

`PluginController.rescan()` 的对账基准是**索引记录**（顺序 + 用户字段的来源），
磁盘只决定存亡，规则在 `PluginIndex.reconcile(records, onDiskNames)` 里（纯函数、可单测）：

- 记录的文件还在 → 原样保留（顺序与用户填的展示名 / 分类 / 主页 / 简介都不动）；
- 记录的文件没了 → 丢弃该记录（等同用户删除）；
- 磁盘上有、索引里没有的文件 → **追加到末尾**，默认**禁用**（不自动运行未知代码）。

**顺序只来自索引记录**，所以禁用插件在全量列表里的位置天然不变。

启动时的顺序是：`_installFactoryPlugins()` → `rescan()`。

### 7.2 出厂安装（`assets/plugin/`）

插件目录为空时逐条扫描只能得到一张空表（展示名 / 分类 / 简介全空）。
随应用打包的 `assets/plugin/` 就是**出厂安装包**：

- `index.json` —— **出厂配置**，格式与运行时 `index.json` 完全相同（数组、六字段），
  因此读写走同一套代码；
- `{name}.js` —— 配置里每条记录对应的载荷。

**只在「一个插件都没有」时执行一次**：插件目录里没有任何 `.js`，**且** `index.json` 里
没有记录。执行动作 = 按配置把载荷逐个复制进插件目录 + 把这份配置写成 `index.json`
（缺载荷的条目跳过，不写出指向不存在文件的记录）。

**装完之后它们就是普通插件**：

- 没有「内置」这个身份，管理页没有「内置 / 第三方」之分，也没有「内置插件不可删」；
- 可编辑、可禁用、可删除，**删了不会再回来** —— 没有每次启动的重新同步；
- 出厂的 `enabled` 全是 `false`：出厂状态是一张待导入的菜单，不会一装上就自动跑。

出厂配置由 `node tools/gen_plugin_seed.js` 从这些插件里抽取（`// description:` → 简介、
`// type:` → 分类、类字段 `name = '…'` → 展示名），顺序为插件名字典序。
抽出来之后，那些元数据就**只活在这份 JSON 里**，插件源码不再携带它们。

## 8. 校验实现要点

`PluginSourceRule.check(source, pluginName)`：

1. **掩码**：把 `//`、`/* */` 注释、**正则字面量**与 `'…'`、`"…"`、`` `…` `` 字面量替换为
   **等长空白**（换行保留）—— 保证 ① 行号不漂 ② 字面量里的
   `class X extends PluginSource` 不会造成误判。

   > ⚠️ **正则字面量必须单独处理**（实测踩过）：`ikmmh.js:13` 是
   > `/document\.cookie\s*=\s*"([^"]+)"/` —— 里面有**奇数个双引号**。
   > 只按引号配对会让掩码一路吃掉第 45 行的类声明，把合法内置插件误判为不可用。
   > 识别规则：`/` 的前一个有效 token 是运算符 / 语句位置（或 `return`、`typeof`
   > 等关键字）时视为正则开头，并在**同一行内**找结束斜杠；找不到就退回按普通字符处理。
   > `tools/check_plugin_naming.js` 与 Dart 侧实现保持同一套语义，含 14 条规则自检。
2. **扫描**：在掩码结果上跑正则，要求列 0 起、`extends PluginSource` 同行。
3. **判定**：命中数必须为 1；类名必须与插件名逐字符相等；否则给出带行号的拒绝原因。

**只读校验，永不用于改写源码。** 已量过的三个事实决定了不能拿它做「提取/替换类体」：

- 39 个内置插件里 7 个在类外有代码（`hitomi` 818 行、`mycomic` 113、`jcomic` 92、
  `goda` 74、`ikmmh` 26、`wnacg` 15；`shonen_jump_plus` 有 18 行后置代码）；
- 2 个文件在类体内部含列 0 的 `}`（`happy.js:1107`、`mxs.js:788/902`）；
- 38/39 使用模板字面量，大括号配平会被字符串内容污染。

## 9. JS 实体与实例的持有

`Plugin.register(engine)` 是唯一注册入口，它做的全部事情是：

1. 读盘拿到源码；
2. 跑一次 `PluginSourceRule.check`（命名链 + 类声明形态），不通过就抛
   `PluginSourceError`，且不动已有实体；
3. 建 `JsEntity` 并 `register()`：

```dart
JsEntity(
  className: name,          // 命名链第 3 环：new 谁
  entityPath: '__plugins__', // 实例挂到哪个全局对象
  entityName: name,          // 命名链第 4 环：槽位名，之后按它寻址
  engine: engine,
  content: content,
)
```

**`className` 与 `entityName` 是两个独立字段**，虽然命名链现在要求它们逐字符相同：
前者是「`new` 谁」，后者是「挂到哪个槽位、按什么名字寻址」。这两件事本就不同，
本类不假设它们相等 —— 将来要把同一个类挂到别的槽位（测试台、多实例、别名）不用改它。

### 实例为什么记的是挂载路径

QuickJS 的实例活在引擎堆里。flutter_qjs 的 `evaluate` 会把对象**深拷贝成 Dart `Map`**
（`wrapper.dart` 的 `_jsToDart` 只对函数、Promise、Map 返回可长期持有的 `JSRef`），
所以 `new Komiic()` 取回 Dart 侧只是一份快照，拿着它调用毫无意义。
Dart 侧唯一能长期持有实例的办法就是记住它在全局的**挂载路径**：

```dart
String get entityFullPath => '$entityPath.$entityName';   // 实例句柄
bool get isLoaded => engine.evaluate('$entityFullPath !== undefined') == true;
```

**不注入任何字段**。`PluginSource` 里没有 `name` / `version` / `homepage` 这类数据字段，
插件实例上也不会有；宿主需要什么直接读记录。

### 9.1 能力探测：基类不许给能力方法留空实现

基类只放两类东西：**机制**（`loadData` / `saveData` / `deleteData` /
`loadSetting` / `saveSetting` / `isLogged` / `init`，
存储命名空间各方法内部直接取 `this.constructor.name`）与一个**能力探测器**
（`implementsMethod`）。能力方法（`getCategory` / `getCategoryOptions` / `loadCategory` /
`getImageLoadingConfig` / `getSettings`，以及 `search` / `getDetail` / `getUrl` 这些
约定方法）**故意一个实现都不留**：

```js
// PluginSource —— 基类唯一的「能力」相关成员
implementsMethod(name) {
    // 只认插件自己写的可调用成员：
    //   实例自有属性（`search = async () => {}`）+ 插件自己原型链上的方法
    // 基类 PluginSource.prototype 上一律不算；同名但非函数 = 显式关掉该能力
}
```

**为什么不能留空实现**：宿主的每一次能力判断都是
`implementsMethod(name)` → 有事才 `invoke`。基类一旦给 `getCategory` 留个
`return null`，这个判断对**每个插件**都成立 —— 浏览页的「支持分类浏览」筛选会
把所有插件都列进去（这正是改造前 `browse_controller` 的真实 bug）。

| 宿主侧探测点 | 探测什么 | 实现处 |
|---|---|---|
| 浏览页插件筛选 | `getCategory` | `browse_controller.dart` |
| 分类页取数据 / 选项 | `getCategory` / `getCategoryOptions` | `category_browse_view.dart` |
| 阅读器每张图配置 | `getImageLoadingConfig` | `init_page.dart` |
| 「设置」段是否存在 | `getSettings` 方法 **或** `settings` 字段 | `Plugin.readSettingsSchema` |
| 收藏点开 / 源站地址 | `onOpenBrowseEntry` / `getUrl` | `plugin_controller.dart` |

> 设置 schema 的读取规则：插件**自己实现了** `getSettings()` 就用它（`implementsMethod`
> 判），否则读它的 `settings` **数据字段** —— 基类不再提供 `getSettings()` 空实现，
> 所以这条判断也是准的。
>
> 这条不变量由 `node tools/check_plugin_naming.js --self-test` 的
> 「能力探测自检」锁住：它直接 eval `assets/js/init.js` 里的真实基类，断言
> 能力方法一个都不在、机制成员一个都不缺、且 `implementsMethod` 的四种语义正确。
因此「插件无法自称身份」是**结构性**保证：身份只来自记录主键（= 文件名 = 类名 = 引擎槽位）。

> 命名链第 4 环（`__plugins__.<name>`）只对宿主有意义：插件之间不应互相访问对方的实例。
> 当前实现沿用了既有的全局注册表，因此该表对插件**仍然可见**；若后续要收紧跨插件互访，
> 把实例改由宿主闭包私有持有即可 —— 命名链本身不需要改动。

## 10. 配套工具

| 命令 | 作用 |
|---|---|
| `node tools/check_plugin_naming.js` | 校验 `assets/plugin/*.js` 的命名链（14 条规则自检 + 存储命名空间派生自检） |
| `node tools/check_plugin_naming.js <file.js> …` | 校验指定文件 |
| `node tools/check_plugin_naming.js --debug <file.js>` | 打印掩码长度 / 换行 / 引号计数，排查误判 |

扫描会额外给出 `⚠` 提示（**不算违规**）：类字段 `name` / `key` / `version` 是旧的
「插件向宿主声明元数据」写法，**现在整套声明层已经不存在**，这些字段既无人读也不落盘，
清理掉即可。
（`key` 现在只是死数据 —— 存储命名空间由基类直接取 `this.constructor.name`，
插件声明什么都改不了它；见 §6。）
