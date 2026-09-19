/// 日志模块标签常量（日志规范见 `docs/logging.md`）。
///
/// 统一格式：`WywLogger().x('${LogTag.<module>} 中文描述 key=$value', error: e)`
///
/// - Tag 选择「最窄能定位问题的模块」，同一文件内固定使用同一个 Tag；
/// - 消息用中文，技术名词/标识符（url、路径、插件名等）保留英文；
/// - 异常一律通过 `error:` / `stackTrace:` 参数传递，禁止拼进消息。
abstract final class LogTag {
  /// 应用生命周期 / 初始化 / 通用工具
  static const app = '[App]';

  /// 存储层（GStorage / Hive）
  static const storage = '[Storage]';

  /// 插件（加载、启停、调用）
  static const plugin = '[Plugin]';

  /// 播放器（视频/音频/PIP/投屏/外部播放）
  static const player = '[Player]';

  /// 下载（下载管理、代理服务、分片协调）
  static const download = '[Download]';

  /// WebView（视频源解析、验证码、Cookie）
  static const webview = '[WebView]';

  /// JS 引擎与桥接（脚本执行、HTML/网络扩展、UI 渲染）
  static const js = '[JS]';

  /// 弹窗系统（WywDialog）
  static const dialog = '[Dialog]';

  /// 搜索页
  static const search = '[Search]';

  /// 阅读器（漫画/小说）
  static const reader = '[Reader]';

  /// 网络（HTTP 请求/拦截器）
  static const net = '[Net]';

  /// 着色器（Shader）
  static const shader = '[Shader]';

  /// 历史（播放进度/浏览历史）
  static const history = '[History]';

  /// 平台环境（窗口、全屏、显示器模式等平台能力）
  static const platform = '[Platform]';
}
