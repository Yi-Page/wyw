/// 弹弹play 开放 API 凭证。
///
/// 凭证不入库也不落盘：由构建期通过 `--dart-define=DANDANAPI_APPID=…` 与
/// `--dart-define=DANDANAPI_KEY=…` 注入（与 Kazumi 的做法一致），避免
/// AppSecret 进入仓库、设置页或 Hive 数据。
library;

const Map<String, String> dandanCredentials = {
  'id': String.fromEnvironment('DANDANAPI_APPID'),
  'value': String.fromEnvironment('DANDANAPI_KEY'),
};

/// 是否已注入完整凭证。
///
/// 未配置时弹幕模块整体静默降级：不发任何请求，也不向用户报错——
/// 本地构建默认不带凭证，这是预期状态而非故障。
bool get isDandanConfigured =>
    (dandanCredentials['id'] ?? '').isNotEmpty &&
    (dandanCredentials['value'] ?? '').isNotEmpty;
