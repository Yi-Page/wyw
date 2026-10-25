# 文档索引

wyw 项目的说明类文档统一放在本目录；已失效的历史方案归档在 [`archive/`](archive/)。

## 当前生效（改代码前先读）

| 文档 | 说明 |
|---|---|
| [plugin-development.md](plugin-development.md) | 插件开发权威参考（视频源 / 漫画源 / 小说源），由现有代码库整理而成 |
| [plugin-storage-spec.md](plugin-storage-spec.md) | 插件持久化规范：`index.json` / `categories.json` / 载荷文件与出厂安装时序 |
| [logging.md](logging.md) | 日志规范：日志模块用法、级别语义、消息格式 |
| [codegen.md](codegen.md) | 代码生成注意事项（**手写 `.g.dart` 不可被 `--delete-conflicting-outputs` 删除**） |
| [video-entry-identity.md](video-entry-identity.md) | 播放作品身份（code）与进播放页编排层契约 |
| [ui-routing-design-spec.md](ui-routing-design-spec.md) | 界面与路由设计规范（P0/P1 已实施，P2 部分待做） |
| [pixiv-plugin.md](pixiv-plugin.md) | Pixiv 插件功能迁移说明、验证方式与实测结果 |

## 设计台账 / 实施记录

| 文档 | 说明 |
|---|---|
| [collect-feature-plan.md](collect-feature-plan.md) | 收藏模块重做计划（已实施，保留决策台账） |
| [danmaku-analysis.md](danmaku-analysis.md) | 弹幕系统分析（Kazumi 实现拆解）与 wyw 接入方案（M1–M5 已落地） |
| [danmaku-selection-plan.md](danmaku-selection-plan.md) | 弹幕选择重构计划（M0–M5 已交付） |
| [player-split-panel-plan.md](player-split-panel-plan.md) | 播放器分屏面板重做（P0–P3 已完成；设计稿见 `player-split-panel-mockup.html/.png`） |
| [playback-refactor-plan.md](playback-refactor-plan.md) | 播放行为规范重构（**未实施**，方案备查） |
| [kazumi-wyw-player-panel-comparison.md](kazumi-wyw-player-panel-comparison.md) | Kazumi ↔ wyw 播放器设置与面板对比（研究快照） |
| [kazumi-wyw-plugin-comparison.md](kazumi-wyw-plugin-comparison.md) | Kazumi ↔ wyw 插件能力对比（研究快照） |
| [venera-plugin-adaptation.md](venera-plugin-adaptation.md) | Venera 插件逐个适配记录（历史；部分插件已移出内置） |

## 归档

| 文档 | 说明 |
|---|---|
| [archive/ad-filter-mvp.md](archive/ad-filter-mvp.md) | 广告过滤 MVP 实现分析（Dart 侧实现已移除，仅存档） |

> 项目总览、功能特性与快速上手见根目录 [README.md](../README.md)。
