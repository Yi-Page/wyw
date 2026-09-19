/// 进程内 Cookie 存储（按域名），供 JS 插件请求与 WebView 页面间同步。
///
/// - HTTP 响应的 `Set-Cookie` 由 [ingestFromHeaders] 自动摄入；
/// - WebView 页面产生的 Cookie（如 CF 验证、登录态）在 `parseHtml` 成功后由
///   [importFromString] 导入，随后同域名的 `Network.get` 会自动带上；
/// - 发请求前用 [cookieHeader] 生成 `k1=v1; k2=v2` 追加到 Cookie 头。
///
/// 会话级（内存）存储，进程内有效；WebView 侧 Cookie 本身持久化在
/// WebView2 的 user data folder 中，这里只做「页面 → 请求侧」的桥。
class JsCookieStore {
  final _byDomain = <String, Map<String, _CookieValue>>{};

  /// 从 HTTP 响应头 `Set-Cookie` 摄入（可多值）。
  void ingestFromHeaders(String url, List<String>? setCookieHeaders) {
    if (setCookieHeaders == null) return;
    for (final raw in setCookieHeaders) {
      _ingestOne(Uri.parse(url), raw);
    }
  }

  /// 从 WebView 的 `"k1=v1; k2=v2"` cookie 字符串导入到 [url] 的域。
  void importFromString(String url, String cookieString) {
    if (cookieString.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return;
    final host = uri.host.toLowerCase();
    for (final part in cookieString.split(';')) {
      final eq = part.indexOf('=');
      if (eq <= 0) continue;
      final name = part.substring(0, eq).trim();
      final value = part.substring(eq + 1).trim();
      _put(host, name, _CookieValue(value, '/'));
    }
  }

  /// 为 [url] 生成 Cookie 头值（按域后缀 + 路径匹配）。
  String cookieHeader(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return '';
    final host = uri.host.toLowerCase();
    final path = uri.path.isEmpty ? '/' : uri.path;
    final parts = <String>[];
    for (final entry in _byDomain.entries) {
      final domain = entry.key;
      if (host != domain && !host.endsWith('.$domain')) continue;
      for (final c in entry.value.entries) {
        if (!_pathMatches(c.value.path, path)) continue;
        parts.add('${c.key}=${c.value.value}');
      }
    }
    return parts.join('; ');
  }

  /// 已存储的 cookie 条数（调试用）。
  int get count => _byDomain.values.fold(0, (n, m) => n + m.length);

  void _ingestOne(Uri uri, String raw) {
    final segments = raw.split(';');
    if (segments.isEmpty) return;
    final kv = segments[0].trim();
    final eq = kv.indexOf('=');
    if (eq <= 0) return;
    final name = kv.substring(0, eq).trim();
    final value = kv.substring(eq + 1).trim();
    var domain = uri.host.toLowerCase();
    var path = '/';
    for (var i = 1; i < segments.length; i++) {
      final seg = segments[i].trim();
      final lower = seg.toLowerCase();
      if (lower.startsWith('domain=')) {
        final d = seg
            .substring(7)
            .trim()
            .replaceFirst(RegExp(r'^\.+'), '')
            .toLowerCase();
        if (d.isNotEmpty) domain = d;
      } else if (lower.startsWith('path=')) {
        final p = seg.substring(5).trim();
        if (p.isNotEmpty) path = p;
      }
      // max-age / expires 过期：会话级简化处理，忽略
    }
    _put(domain, name, _CookieValue(value, path));
  }

  void _put(String domain, String name, _CookieValue value) {
    (_byDomain[domain] ??= <String, _CookieValue>{})[name] = value;
  }

  bool _pathMatches(String cookiePath, String requestPath) {
    if (cookiePath == '/') return true;
    return requestPath.startsWith(cookiePath);
  }
}

class _CookieValue {
  final String value;
  final String path;
  const _CookieValue(this.value, this.path);
}
