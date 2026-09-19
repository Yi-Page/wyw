# wyw

> Watch you want on net by web scraper.

基于 Flutter 的跨平台聚合阅读 / 播放应用，通过 **JS 插件机制**扩展任意站点，支持**漫画 / 小说 / 视频**三大内容类型。

## ✨ 功能特性

- **JS 插件机制** — 站点源以 JS 插件形式接入，运行于 QuickJS（`flutter_qjs`），通过 `sendMessage` 桥与 Dart 通信。可热重载、可独立调试，详见 [插件开发文档](docs/plugin-development.md)
- **阅读器** — 漫画阅读器（支持翻页、缩放、图源增强着色器）与小说阅读器
- **视频播放器** — 基于 media_kit 的播放内核，支持后台音频、音量控制、DLNA 投屏
- **内容管理** — 书源浏览、搜索、下载管理、历史记录与阅读进度同步
- **界面** — Material 3 + 动态取色，内置 MiSans 字体，支持浅 / 深色模式
- **系统集成** — 系统托盘（Windows / Linux）、屏幕亮度控制、WebView 页面支持
- **图像增强** — 内置 Anime4K 着色器（放大 / 降噪 / 还原）
- **日志系统** — 统一日志基础设施与规范，见 [日志规范](docs/logging.md)

## 🖥 支持平台

Android · iOS · Linux · macOS · Windows · Web

## 🚀 快速开始

1. 安装 [Flutter SDK](https://docs.flutter.dev/get-started/install)（版本要求见 `pubspec.yaml`）
2. 拉取依赖：

   ```bash
   flutter pub get
   ```

3. 运行：

   ```bash
   flutter run -d <device>
   ```

> 部分依赖（`flutter_qjs`、`media_kit` 等）以 git 引用形式声明在 `pubspec.yaml`，首次拉取依赖需要网络访问 GitHub。

## 📁 项目结构

```
lib/
├── main.dart            # 应用入口
├── app_module.dart      # 模块装配（flutter_modular）
├── modules/             # 功能模块：漫画 / 小说 / 视频 / 历史 / 下载 / WebView
├── pages/               # 页面与路由
├── plugins/             # 插件运行时、配置与类型
├── services/            # 日志 / 网络 / 存储 / 播放等服务
├── js/                  # JS 引擎桥（QuickJS + init.js API 注入）
├── repositories/        # 数据仓库（Hive 持久化）
├── bean/                # 通用数据模型与组件
└── utils/               # 工具库

assets/
├── js/init.js           # JS API 库（注入到插件运行环境）
├── plugin/              # 内置站点插件（*.js）
├── shaders/             # Anime4K 着色器
└── images/              # 图标与图片资源
```

## 📚 文档

| 文档 | 说明 |
|---|---|
| [docs/plugin-development.md](docs/plugin-development.md) | 插件开发文档（视频源 / 漫画源 / 小说源的权威参考） |
| [docs/logging.md](docs/logging.md) | 日志规范 |
| [docs/ui-routing-design-spec.md](docs/ui-routing-design-spec.md) | 界面与路由设计规范 |
