# 代码生成（build_runner）注意事项

本项目用 `build_runner` 生成三类文件：MobX Store（`*.g.dart`）、Hive 适配器（`*.g.dart` + `hive_registrar.g.dart`）。

## ⚠️ 不要用 `--delete-conflicting-outputs`

**这个仓库里有手写的 `.g.dart` 文件**，`--delete-conflicting-outputs` 会把它们当"冲突产物"删掉：

| 文件 | 性质 |
|---|---|
| `lib/services/storage/history_type.g.dart` | **手写**。文件头注释写明是为了绕开 `hive_ce_generator 1.11.2` 与 analyzer 12 不兼容导致的 enum 解析失败 |

真实事故（2026-10）：为了给新的弹幕控制器生成 `.g.dart`，执行了

```
dart run build_runner build --delete-conflicting-outputs
```

结果 `git status` 出现：

```
 D lib/services/storage/history_type.g.dart
```

`history_type.dart` 里的 `part 'history_type.g.dart'` 随即失效，`HistoryTypeAdapter` 变成未定义，整个项目编译不过。恢复方式是 `git checkout -- lib/services/storage/history_type.g.dart`。

## 正确做法

给单个目标生成时用 `--build-filter` 限定范围，不要动全局：

```
# 只为某个新增的 MobX Store 生成代码
dart run build_runner build --build-filter="lib/pages/player/controller/player_danmaku_controller.g.dart"
```

如果确实要全量重建：

```
dart run build_runner build        # 不加 --delete-conflicting-outputs
```

遇到冲突提示时**先看清楚是哪个文件**，再决定是否删除——凡是顶部带"适配器手写"之类注释的 `.g.dart`，一律以 `git checkout` 恢复为准。

## 检查清单

生成代码之后：

1. `git status --short` 看有没有意外的 `D`（删除）记录；
2. `flutter analyze` 必须零问题；
3. `flutter test` 全绿（`test/no_hardcoded_colors_test.dart` 等 guard 测试会扫 `lib/`）。
