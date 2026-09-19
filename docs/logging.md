# wyw 日志规范

> 目标：**系统出的所有问题，都能在日志模块（日志页）看到对应的、可定位的信息。**
>
> 基础设施：`lib/services/logging/logger.dart`（`WywLogger` 单例，t/d/i/w/e/f 六级），
> Tag 常量：`lib/services/logging/log_tags.dart`。

## 1. 核心不变式

> **每一个 `catch` 只有三种合法去向：**
> 1. 妥善处理（不算问题，可不记日志）；
> 2. 记 `w`/`e`/`f`（带 `error:`，拿得到堆栈就带 `stackTrace:`）；
> 3. 经审查后允许静默，但**必须**带注释说明为什么可静默（`// 静默可接受：<原因>`）。

任何「出问题但日志里什么都查不到」都视为违反本规范。

## 2. 级别语义

| 级别 | 语义 | 落盘 | 典型例子 |
|------|------|------|---------|
| `t` | 方法级追踪，生产禁用 | 否 | 函数进出（一般不用） |
| `d` | 调试信息 / 可忽略的 best-effort 失败 | 否（仅控制台） | `图片预下载失败（已忽略）` |
| `i` | 正常运行的重要节点与关键决策 | 否 | 服务启动、`播放本地文件 url=...` |
| `w` | 预期内失败但已兜底/降级/重试，功能未损 | **是** | 磁盘缓存读取失败已回源网络 |
| `e` | 操作失败，功能受损，用户可感知 | **是** | 下载失败、搜索超时、播放初始化失败 |
| `f` | 不可恢复：数据损坏 / 全局崩溃 / 未捕获异常 | **是** | 存储初始化失败（由全局钩子产生） |

## 3. 消息格式

```
WywLogger().x('${LogTag.<module>} 中文描述 关键上下文')
```

- **Tag 用 `LogTag` 常量**，选「最窄能定位问题的模块」；同一文件内固定同一个 Tag。
- **消息统一中文**，技术名词/标识符（url、路径、插件名、参数名）保留英文。
- 消息带作用域内已有的关键上下文（id/url/path/name），插值即可；没有就只写动作描述。
- **禁止**：
  - 无 Tag（如 `调用失败`）或泛化消息（如 `Image Loading`）；
  - 把异常文本拼进消息（`${e}` 进 message）——一律走 `error:` 参数保留完整堆栈；
  - 张冠李戴的 Tag（复制日志语句后忘改，Tag/描述要与所在函数一致）。

可用 Tag：`app / storage / plugin / player / download / webview / js / dialog /
search / reader / net / shader / history / platform`（见 `log_tags.dart`）。

## 4. 静默吞异常与 fire-and-forget

- `catch (_) {}` 默认改为：
  `catch (e) { WywLogger().d('${LogTag.x} <做什么>失败（已忽略）', error: e); }`
- 例外：清理临时文件、关闭已关闭资源等「失败属常态且高频」的 best-effort 路径
  可保持静默，但必须补注释 `// 静默可接受：<原因>`。
- fire-and-forget 兜底 `.then<void>((_) {}, onError: (_) {})` 保持结构不变
  （防 unhandled error），onError 内记 `w`：`<后台任务>失败（不影响主流程）`。

## 5. 全局兜底（main.dart，已实施）

启动时安装三层钩子，任何逃逸到框架层的错误都以 `f` 级落盘：

1. `FlutterError.onError` — widget 构建/布局/绘制异常；链回原 handler 保留开发期红屏；
2. `PlatformDispatcher.instance.onError` — 未捕获的 Dart 异步异常；**记录后返回
   `true` 继续运行**（避免单次异常杀死应用，现场在日志页可查）；
3. `Isolate.current.addErrorListener` — 主 isolate 层未捕获错误（端口引用须持有
   防止 GC）。

## 6. 后台 isolate 日志（已实施）

后台 isolate（下载服务）中 path_provider 不可用。做法：主 isolate 在 spawn 前
把日志文件绝对路径作为参数传入；后台 isolate 用纯 `dart:io` append + 自持锁写日志，
不依赖任何 Flutter 插件。后台 isolate 的顶层回调也应 try/catch 并写日志。

## 7. 文件与日志页

- 文件：`<appSupport>/logs/wyw_logs.log`，仅 `w`/`e`/`f`（及 `forceLog: true`）落盘；
- `d`/`i` 只进控制台，用于开发期诊断；
- 日志系统自身失败（写文件失败等）允许裸 `print` 兜底——这是**唯一**允许裸 print
  的位置（避免递归写日志）；
- 文件轮转与日志页过滤/搜索为规划项（阶段 C），尚未实施。

## 8. 违规示例 → 正确写法

```dart
// ❌ 无 Tag、异常拼进消息、吞上下文
WywLogger().e('调用失败 ${e}');
} catch (_) {}

// ✅
WywLogger().e('${LogTag.plugin} 插件方法调用失败 plugin=$name method=${action.method}',
    error: e, stackTrace: s);
} catch (e) {
  WywLogger().d('${LogTag.download} 清理临时分片失败（已忽略）', error: e);
}
```
