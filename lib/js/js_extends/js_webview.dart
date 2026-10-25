import 'dart:async';
import 'dart:convert';

import 'package:wyw/js/js_extends/js_cookie_store.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/webview/captcha/captcha_webview_controller.dart';

/// JS ↔ WebView 交互模块（WebView 能力的唯一归属地）。
///
/// **为什么独立成模块**：原先 `JsNetwork` 同时管 HTTP(Dio) 与 WebView（实例池、
/// 空闲回收、Cookie 同步、取渲染后 HTML），两件事的生命周期诉求正好相反——
/// 请求是短命高频，WebView 是重资源且验证类场景需要**长时间留着页面**。
/// 拆开后：`JsNetwork` 只做请求，本模块拥有全部 WebView 状态。
///
/// **职责**
///   1. 一次性取页 [fetchHtml]：加载 → 等条件 → 返回渲染后 HTML，成功后把页面
///      Cookie 同步进会话 Cookie 库（= 原 `JsNetwork.webviewHtml` 的行为，逐字保持）。
///   2. 交互会话（租约）：[open] 留页 → [awaitCaptchaImage] 取验证码图 →
///      [fillAndClick] 页面内回填并点击 → [awaitCaptchaGone] 等验证通过 →
///      [getPageHtml]/[getUserAgent] 收尾 → [close] 释放。
///   3. 会话 Cookie 库：按 `session` 分库，[cookiesFor] 交给 `JsNetwork` 做
///      请求前注入 / 响应后摄入——**两边共用同一份**，避免各持一套造成分叉。
///
/// **不变量**
///   - 每个 `session` 下，一次性取页与交互会话**各自一个 WebView 实例**：
///     交互会话不会占住一次性取页的实例、也不会被它的空闲回收牵连（这是
///     「留页等用户输入」能成立的前提）；
///   - 同一实例上的操作一律经该槽位的队列**串行**执行；
///   - 一次性实例空闲 [idleDisposeDelay] 后销毁，下次调用重建（失败实例同样
///     由该定时器清理，即初始化失败有约一个空闲窗口的冷却）；
///   - 交互会话在 `open` 期间**不排空闲销毁**，只有 `close` 之后才恢复回收；
///   - Cookie 库独立于实例：实例销毁重建不影响已同步的 Cookie。
///
/// **平台差异**：Android/iOS/macOS 的 `dispose(clearCookies: true)` 会清空
/// 平台 WebView Cookie（实现层行为），因此交互会话一律以
/// `clearCookies: false` 销毁，避免把刚验证到的 clearance cookie 一起清掉。
class JsWebview {
  JsWebview({
    CaptchaWebviewController Function()? controllerFactory,
    this.idleDisposeDelay = const Duration(seconds: 15),
    this.defaultLeaseMaxLifetime = const Duration(minutes: 5),
    this.initTimeout = const Duration(seconds: 30),
  }) : _controllerFactory =
            controllerFactory ?? CaptchaWebviewControllerFactory.getController;

  /// 实例工厂（可注入：单测用 fake controller）。
  final CaptchaWebviewController Function() _controllerFactory;

  /// 实例空闲多久后释放（一次性槽位与交互槽位共用同一时长）。
  final Duration idleDisposeDelay;

  /// 交互会话未显式指定 maxLifetime 时的默认最长寿命。
  final Duration defaultLeaseMaxLifetime;

  /// WebView 初始化等待上限。
  final Duration initTimeout;

  static const String _defaultSession = '';
  static const Duration _leaseLifetimeFloor = Duration(seconds: 30);
  static const Duration _leaseLifetimeCeil = Duration(minutes: 15);

  final Map<String, _SessionState> _sessions = {};
  bool _disposed = false;

  bool get isDisposed => _disposed;

  // ===== 会话 Cookie 库（与 JsNetwork 共用的唯一来源） =====

  /// 取某会话的 Cookie 库（不存在则惰性建）。
  ///
  /// `JsNetwork` 用它做请求前注入（`cookieHeader`）与响应后摄入
  /// （`ingestFromHeaders`）；本模块用它接收 WebView 页面 Cookie。
  JsCookieStore cookiesFor(String? session) => _sessionFor(session).cookies;

  /// 查询某会话当前已同步的 Cookie 字符串（`"k=v; k2=v2"`）。
  ///
  /// 对应 JS 侧 `Network.cookies(url, session)` / `sendMessage({method:'get_cookies'})`。
  Map<String, dynamic> getCookies({String? session, String url = ''}) {
    return {'cookies': _sessionFor(session).cookies.cookieHeader(url)};
  }

  // ===== 一：一次性取页 =====

  /// 一次性取页：加载 [url]，等 [waitFor] 条件满足后返回渲染后的 HTML。
  ///
  /// 返回 `{html, finalUrl}`；失败返回 `{error: {message, kind:'webview',
  /// retryable, status}}`（结构与重构前一致，`JsNetwork` 直接透传/包装）。
  ///
  /// [session] 用于 Cookie 分库与实例复用；[overTime] 是取页总超时（秒）。
  ///
  /// [waitFor] 收**原始值**（Map `{type,value}` 或 `'selector:x'` / `'text:x'` /
  /// `'js:expr'` 简写），由本模块调 `normalizeWaitFor` 归一——这样调用方
  /// （`js_bridge` / `js_network`）不需要再 import captcha 层。
  Future<Map<String, dynamic>> fetchHtml({
    required String url,
    String? session,
    int overTime = 50,
    Object? waitFor,
  }) {
    final state = _sessionFor(session);
    // 本次调用会续命：先取消空闲销毁，结束后再重排（原语义）。
    state.idleTimer?.cancel();
    return state.runQueued(() async {
      try {
        final webview = await _getOneShotWebview(state);
        final result = await webview.parseHtml(
          url,
          overTime: overTime,
          waitFor: normalizeWaitFor(waitFor),
        );
        // WebView 页面设置的 Cookie（登录态 / CF 验证）→ 会话 Cookie 库
        await _syncWebviewCookies(webview, state, url, result.finalUrl);
        return {'html': result.html, 'finalUrl': result.finalUrl};
      } catch (e) {
        return _error(e.toString(), retryable: true);
      } finally {
        // 无论成功/超时/异常，调用结束后进入空闲计时，到期自动释放
        _scheduleIdleDispose(state);
      }
    });
  }

  // ===== 二：交互会话（留页式） =====

  /// 打开/重载交互会话：留页 + 按 [mode] 注入 watcher。
  ///
  /// - [mode]：`image`（图片验证码）/ `button`（自动点击）/ `script`（自定义脚本），
  ///   非法值按 `image` 处理；
  /// - [captchaXpath]/[inputXpath]/[buttonXpath]/[script] 语义与验证码规则一致；
  /// - [timeout]（秒）：等待页面进入可用状态的上限（尽力而为，超时不判失败——
  ///   真正的等待交给 [awaitCaptchaImage] 等接口）；
  /// - [maxLifetimeMs]：租约最长寿命，默认 [defaultLeaseMaxLifetime]；
  ///   非正值视为"未指定"→ 用默认，显式正值 clamp 到 30s..15min；
  ///   到点强制释放，后续调用（含在途等待）立即返回结构化错误。
  ///
  /// 对同一会话重复调用 = 重新加载页面（验证码「换一张」的场景），实例复用。
  Future<Map<String, dynamic>> open({
    required String session,
    required String url,
    String mode = 'image',
    String captchaXpath = '',
    String inputXpath = '',
    String buttonXpath = '',
    String script = '',
    int timeout = 30,
    int? maxLifetimeMs,
  }) async {
    if (_disposed) return _error('JsWebview 已销毁', retryable: false);
    final state = _sessionFor(session);
    // 一进 open 就先掐掉旧租约的寿命定时器：下面的 await（init / 加载 / readyState
    // 轮询）可能耗时数十秒，若旧 timer 在这期间到点，会把**正要被复用的**那个
    // controller 一起销毁，open 最终以结构化错误收场。
    state.lease?.lifetimeTimer?.cancel();
    if (state.lease != null) state.lease!.lifetimeTimer = null;
    try {
      final controller = await _ensureLeaseController(state);
      if (_disposed) return _error('JsWebview 已销毁', retryable: false);

      final lease = _Lease(session: session, url: url, controller: controller);
      await lease.attach();
      // 旧租约只解订阅（实例交给新租约继续用），但必须掐掉它的最长寿命定时器，
      // 否则它会在新租约上误触发一次强制关闭。
      final previous = state.lease;
      if (previous != null) {
        previous.lifetimeTimer?.cancel();
        previous.lifetimeTimer = null;
        previous.detach();
        previous.closed = true;
        previous.closedReason = '已被新的 open 取代';
        _failPendingWaiters(previous, '交互会话已被新的 open 取代');
      }
      state.lease = lease;

      await controller.loadPageForInteraction(
        url,
        mode: _modeFromString(mode),
        captchaXpath: captchaXpath,
        inputXpath: inputXpath,
        buttonXpath: buttonXpath,
        script: script,
      );

      // 尽力等页面可用：不因超时让 open 失败（验证码流程自己会等图片/消失）
      final deadline = DateTime.now().add(Duration(seconds: timeout));
      while (!_disposed && DateTime.now().isBefore(deadline)) {
        final ready = await _safeEval(controller, 'document.readyState');
        if (ready == 'complete' || ready == 'interactive') break;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      final finalUrl = await _safeEval(controller, 'location.href') ?? url;

      final lifetime = _clampLifetime(maxLifetimeMs);
      lease.lifetimeTimer = Timer(lifetime, () {
        _forceCloseLease(state, '交互会话超过最长寿命 ${lifetime.inSeconds}s');
      });
      return {'ok': true, 'finalUrl': finalUrl};
    } catch (e) {
      // 建租约途中失败：把半成品收干净（保留 Cookie，交互路径不清 Cookie）
      _forceCloseLease(state, 'open 失败: $e');
      return _error(e.toString(), retryable: true);
    }
  }

  /// 页面内执行任意 JS，返回字符串结果（不可序列化时为 null）。
  Future<Map<String, dynamic>> exec({
    required String session,
    required String js,
  }) {
    return _withLease(session, (lease) async {
      final value = await lease.runQueued(() => lease.controller.executeScript(js));
      return {'ok': true, 'value': value};
    });
  }

  /// 取当前页面 HTML（页面仍在 loading 时返回空串）+ 当前地址。
  Future<Map<String, dynamic>> getPageHtml({required String session}) {
    return _withLease(session, (lease) async {
      final html = await lease.runQueued(() => lease.controller.getPageHtml());
      final finalUrl = await _safeEval(lease.controller, 'location.href') ?? lease.url;
      return {'ok': true, 'html': html, 'finalUrl': finalUrl};
    });
  }

  /// 取 WebView 实际使用的 User-Agent。
  ///
  /// 反爬场景必须把它和 Cookie 一起用于后续请求（clearance cookie 与 UA 绑定）。
  Future<Map<String, dynamic>> getUserAgent({required String session}) {
    return _withLease(session, (lease) async {
      final ua = await lease.runQueued(() => lease.controller.getUserAgent());
      return {'ok': true, 'userAgent': ua};
    });
  }

  /// 在**留着的那个页面**里回填验证码并点击提交按钮。
  ///
  /// 回填必须走 `HTMLInputElement.prototype` 的原生 value setter 并派发
  /// `input`/`change`，否则 React/Vue 之类的受控组件不会感知到值变化。
  Future<Map<String, dynamic>> fillAndClick({
    required String session,
    required String code,
    required String inputXpath,
    required String buttonXpath,
  }) {
    return _withLease(session, (lease) async {
      final js = _fillAndClickScript(
        code: code,
        inputXpath: inputXpath,
        buttonXpath: buttonXpath,
      );
      final result = await lease.runQueued(() => lease.controller.executeScript(js));
      return {'ok': true, 'result': result};
    });
  }

  /// 等验证码图片（返回 `canvas.toDataURL('image/png')` 的 dataURL）。
  ///
  /// watcher 在 [open] 时就已订阅，因此**图片早于本调用到达也不会丢**（返回缓存）；
  /// 超时返回结构化错误。
  Future<Map<String, dynamic>> awaitCaptchaImage({
    required String session,
    int timeout = 30,
  }) {
    return _withLease(session, (lease) async {
      final cached = lease.lastImage;
      if (cached != null) return {'ok': true, 'image': cached};
      final waiter = lease.imageWaiter ??= Completer<String>();
      try {
        final image = await waiter.future.timeout(Duration(seconds: timeout));
        return {'ok': true, 'image': image};
      } on TimeoutException {
        lease.imageWaiter = null;
        return _error('等待验证码图片超时（${timeout}s）');
      } catch (e) {
        // 租约被强制关闭（最长寿命到点 / 被新 open 取代）：立刻失败，不等满 timeout
        lease.imageWaiter = null;
        return _error('$e', retryable: false);
      }
    });
  }

  /// 等验证通过（验证码元素消失 / 自动点击后导航 / 自定义脚本 done）。
  ///
  /// 事件早于本调用到达同样不会丢（已通过则立即返回）。通过后会顺手同步一次
  /// 页面 Cookie 到会话库，这样插件随后直接用 `Network.*` 即可带上登录态。
  Future<Map<String, dynamic>> awaitCaptchaGone({
    required String session,
    int timeout = 60,
  }) {
    return _withLease(session, (lease) async {
      // 「早到」分支也必须走下面的 Cookie 同步：站点常常与"验证通过"同一时刻
      // 下发 clearance cookie，直接 return 会让紧随其后的 Network.* 拿不到登录态。
      if (!lease.passed) {
        final waiter = lease.goneWaiter ??= Completer<void>();
        try {
          await waiter.future.timeout(Duration(seconds: timeout));
        } on TimeoutException {
          lease.goneWaiter = null;
          return _error('等待验证通过超时（${timeout}s）');
        } catch (e) {
          // 租约被强制关闭：立刻失败，不等满 timeout
          lease.goneWaiter = null;
          return _error('$e', retryable: false);
        }
      }
      final state = _sessionFor(session);
      await _syncWebviewCookies(
        lease.controller,
        state,
        lease.url,
        await _safeEval(lease.controller, 'location.href'),
      );
      return {'ok': true, 'passed': true};
    });
  }

  /// 关闭交互会话（收尾）。
  ///
  /// - [keepCookies]（默认 true）：销毁实例时**不清**平台 WebView Cookie，
  ///   这样刚拿到的 clearance cookie 还能被后续请求复用；
  /// - [dispose]（默认 false）：false = 只卸页面并释放租约，实例留 [idleDisposeDelay]
  ///   后再销毁（便于「换一张」快速重开）；true = 立刻销毁。
  ///
  /// 返回前会把页面 Cookie 再同步一次到会话库（验证通过后站点常会补写 Cookie）。
  Future<Map<String, dynamic>> close({
    required String session,
    bool keepCookies = true,
    bool dispose = false,
  }) async {
    final state = _sessionFor(session);
    final lease = state.lease;
    if (lease != null) {
      lease.lifetimeTimer?.cancel();
      lease.lifetimeTimer = null;
      await _syncWebviewCookies(
        lease.controller,
        state,
        lease.url,
        await _safeEval(lease.controller, 'location.href'),
      );
      lease.detach();
      lease.closed = true;
      lease.closedReason = 'closed by plugin';
      _failPendingWaiters(lease, '交互会话已关闭：closed by plugin');
      state.lease = null;
      try {
        await lease.controller.unloadPage();
      } catch (e) {
        WywLogger().d('${LogTag.webview} 交互会话卸页失败（已忽略）', error: e);
      }
    }
    state.leaseKeepCookies = keepCookies;
    state.leaseIdleTimer?.cancel();
    state.leaseIdleTimer = null;
    if (dispose) {
      final controller = state.leaseController;
      state.leaseController = null;
      controller?.dispose(clearCookies: !keepCookies);
    } else if (state.leaseController != null) {
      state.leaseIdleTimer = Timer(idleDisposeDelay, () {
        final controller = state.leaseController;
        state.leaseController = null;
        controller?.dispose(clearCookies: !state.leaseKeepCookies);
      });
    }
    if (!keepCookies) {
      // 语义收紧：keepCookies=false 表示"这次验证的登录态一点都不留"。
      // 只清平台 WebView 罐不够——后续请求注入用的是会话库（见 [cookiesFor]），
      // 不清它就会出现"调用方要求丢弃，Network.* 却照样带着 clearance cookie"。
      state.cookies.clear();
    }
    return {'ok': true};
  }

  // ===== 生命周期 =====

  /// 立即释放全部 WebView（JS 引擎销毁时由 `JSEngineCommonApi.disposeCommon` 调用）。
  ///
  /// 一次性槽位保持原语义（`dispose()`，Android 会清平台 Cookie）；
  /// 交互槽位按 [cookiesFor] 的取向销毁（不清 Cookie，除非 close 时显式要求过）。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final s in _sessions.values) {
      s.idleTimer?.cancel();
      s.idleTimer = null;
      s.initFuture = null;
      final oneShot = s.oneShot;
      s.oneShot = null;
      oneShot?.dispose();
      s.leaseIdleTimer?.cancel();
      s.leaseIdleTimer = null;
      s.lease?.lifetimeTimer?.cancel();
      s.lease?.detach();
      s.lease = null;
      final leaseController = s.leaseController;
      s.leaseController = null;
      leaseController?.dispose(clearCookies: !s.leaseKeepCookies);
    }
    _sessions.clear();
  }

  // ===== 私有：会话与槽位 =====

  _SessionState _sessionFor(String? key) {
    final k = key == null || key.isEmpty ? _defaultSession : key;
    return _sessions.putIfAbsent(k, () => _SessionState(k));
  }

  /// 一次性取页槽位的实例（惰性创建 + init，`initFuture` 作并发合并与缓存）。
  Future<CaptchaWebviewController> _getOneShotWebview(_SessionState state) {
    return state.initFuture ??= () async {
      final webview = state.oneShot ??= _controllerFactory();
      // 先订阅再 init：broadcast 事件流，避免错过 init 过程中已发出的事件
      final ready = Completer<void>();
      final sub = webview.onInitialized.listen((_) {
        if (!ready.isCompleted) ready.complete();
      });
      try {
        await webview.init();
        await ready.future.timeout(initTimeout);
      } finally {
        sub.cancel();
      }
      return webview;
    }();
  }

  void _scheduleIdleDispose(_SessionState state) {
    state.idleTimer?.cancel();
    state.idleTimer = Timer(idleDisposeDelay, () {
      state.initFuture = null;
      final webview = state.oneShot;
      state.oneShot = null;
      webview?.dispose();
    });
  }

  /// 交互槽位的实例（已存在就直接复用；不存在则创建 + init）。
  Future<CaptchaWebviewController> _ensureLeaseController(_SessionState state) async {
    final existing = state.leaseController;
    if (existing != null) {
      state.leaseIdleTimer?.cancel();
      state.leaseIdleTimer = null;
      return existing;
    }
    final controller = _controllerFactory();
    final ready = Completer<void>();
    final sub = controller.onInitialized.listen((_) {
      if (!ready.isCompleted) ready.complete();
    });
    try {
      await controller.init();
      await ready.future.timeout(initTimeout);
    } catch (e) {
      // 失败不留半成品；交互路径不清平台 Cookie
      controller.dispose(clearCookies: false);
      rethrow;
    } finally {
      sub.cancel();
    }
    state.leaseController = controller;
    state.leaseIdleTimer?.cancel();
    state.leaseIdleTimer = null;
    return controller;
  }

  /// 强制收租约（最长寿命到点 / open 中途失败）：释订阅 + 卸页 + 销毁实例。
  void _forceCloseLease(_SessionState state, String reason) {
    final lease = state.lease;
    if (lease == null) return;
    lease.lifetimeTimer?.cancel();
    lease.lifetimeTimer = null;
    lease.detach();
    lease.closed = true;
    lease.closedReason = reason;
    _failPendingWaiters(lease, '交互会话已关闭：$reason');
    state.lease = null;
    WywLogger().w('${LogTag.webview} 交互会话强制关闭：$reason（session=${state.key}）');
    state.leaseIdleTimer?.cancel();
    state.leaseIdleTimer = null;
    final controller = state.leaseController;
    state.leaseController = null;
    unawaited(Future<void>.sync(() async {
      try {
        await controller?.unloadPage();
      } catch (_) {
        // 已失效的页面卸不掉属常态
      }
    }));
    controller?.dispose(clearCookies: !state.leaseKeepCookies);
  }

  /// 让在途的 `awaitCaptchaImage` / `awaitCaptchaGone` **立刻**失败，
  /// 而不是等它们各自超时（默认 30s / 60s）。
  ///
  /// 触发场景：最长寿命到点强杀、被新的 open 取代、插件主动 close。
  void _failPendingWaiters(_Lease lease, String reason) {
    final failure = _LeaseClosedException(reason);
    final imageWaiter = lease.imageWaiter;
    if (imageWaiter != null && !imageWaiter.isCompleted) {
      imageWaiter.completeError(failure);
    }
    lease.imageWaiter = null;
    final goneWaiter = lease.goneWaiter;
    if (goneWaiter != null && !goneWaiter.isCompleted) {
      goneWaiter.completeError(failure);
    }
    lease.goneWaiter = null;
  }

  /// 统一包装"需要已打开租约"的操作，保证错误是结构化返回而不是抛异常。
  Future<Map<String, dynamic>> _withLease(
    String session,
    Future<Map<String, dynamic>> Function(_Lease lease) body,
  ) async {
    if (_disposed) return _error('JsWebview 已销毁', retryable: false);
    final lease = _sessionFor(session).lease;
    if (lease == null || lease.closed) {
      return _error(
        '交互会话未打开（请先调用 Webview.open）'
        '${lease?.closedReason != null ? '：${lease!.closedReason}' : ''}',
        retryable: false,
      );
    }
    try {
      return await body(lease);
    } catch (e) {
      return _error(e.toString());
    }
  }

  Future<void> _syncWebviewCookies(
    CaptchaWebviewController webview,
    _SessionState state,
    String url,
    String? finalUrl,
  ) async {
    for (final u in {url, if (finalUrl != null && finalUrl.isNotEmpty) finalUrl}) {
      try {
        final cookies = await webview.getCookieString(u);
        state.cookies.importFromString(u, cookies);
      } catch (e) {
        // 单个域失败不影响整体同步
      }
    }
  }

  Future<String?> _safeEval(CaptchaWebviewController controller, String expr) async {
    try {
      final value = await controller.executeScript(expr);
      if (value == null) return null;
      final text = value.trim();
      // 部分实现会把 JS 的 null/undefined 序列化成字面量字符串
      if (text.isEmpty || text == 'null' || text == 'undefined') return null;
      return text;
    } catch (_) {
      return null;
    }
  }

  WebviewLoadMode _modeFromString(String mode) => switch (mode) {
        'button' => WebviewLoadMode.button,
        'script' => WebviewLoadMode.script,
        _ => WebviewLoadMode.image,
      };

  /// 归一租约最长寿命：非正值（null / 0 / 负数）视为"未指定" → 用
  /// [defaultLeaseMaxLifetime]（**不做下限 clamp**）；显式正值才 clamp 到
  /// 30s..15min，避免调用方写出毫秒级寿命把会话瞬间掐掉。
  Duration _clampLifetime(int? ms) {
    if (ms == null || ms <= 0) return defaultLeaseMaxLifetime;
    final value = Duration(milliseconds: ms);
    if (value < _leaseLifetimeFloor) return _leaseLifetimeFloor;
    if (value > _leaseLifetimeCeil) return _leaseLifetimeCeil;
    return value;
  }

  /// 回填 + 点击脚本。
  ///
  /// 值/选择器一律经 [jsonEncode] 变成 JS 双引号字面量（转义引号、反斜杠、换行），
  /// 再补掉 U+2028/U+2029（JSON 合法但会截断 JS 源码）。
  String _fillAndClickScript({
    required String code,
    required String inputXpath,
    required String buttonXpath,
  }) {
    final c = _jsLiteral(code);
    final i = _jsLiteral(inputXpath);
    final b = _jsLiteral(buttonXpath);
    return '''
(function() {
  function evalXpath(xpath) {
    try {
      var r = document.evaluate(xpath, document, null,
        XPathResult.FIRST_ORDERED_NODE_TYPE, null);
      return r.singleNodeValue;
    } catch (e) { return null; }
  }
  var inputEl = evalXpath($i);
  if (inputEl) {
    inputEl.focus();
    // 受控组件（React/Vue）只认原生 setter + input/change 事件
    var nativeSetter = Object.getOwnPropertyDescriptor(
      window.HTMLInputElement.prototype, 'value');
    if (nativeSetter && nativeSetter.set) {
      nativeSetter.set.call(inputEl, $c);
    } else {
      inputEl.value = $c;
    }
    inputEl.dispatchEvent(new Event('input', { bubbles: true }));
    inputEl.dispatchEvent(new Event('change', { bubbles: true }));
  }
  var btnEl = evalXpath($b);
  if (btnEl) { btnEl.click(); }
  return JSON.stringify({ filled: !!inputEl, clicked: !!btnEl });
})();
''';
  }

  String _jsLiteral(String value) => jsonEncode(value)
      .replaceAll('\u2028', r'\u2028')
      .replaceAll('\u2029', r'\u2029');

  Map<String, dynamic> _error(
    String message, {
    String kind = 'webview',
    bool retryable = true,
    int status = 0,
  }) {
    return {
      'error': {
        'message': message,
        'kind': kind,
        'retryable': retryable,
        'status': status,
      }
    };
  }
}

/// 一个 `session` 的状态：Cookie 库 + 一次性取页槽位 + 交互会话槽位。
///
/// **为什么两个槽位分开**：一次性取页是"用完就走"，交互会话是"留着等用户"。
/// 若共用一个实例，交互期间的一次性调用（unloadPage + loadUrl）会打断留着的页面，
/// 反向也会让交互会话把别人的取页堵住（队列要等几分钟）。
class _SessionState {
  _SessionState(this.key);

  final String key;

  /// 会话 Cookie 库：实例销毁重建不影响它。
  final JsCookieStore cookies = JsCookieStore();

  // ===== 一次性取页槽位 =====
  CaptchaWebviewController? oneShot;
  Future<CaptchaWebviewController>? initFuture;
  Timer? idleTimer;
  Future<void> _opQueue = Future<void>.value();

  /// 串行化同槽位操作：同一 WebView 上并发 load/unload 会互相踩踏。
  Future<T> runQueued<T>(Future<T> Function() op) {
    final result = _opQueue.then((_) => op());
    // 吞掉前一个失败，避免队列断链；错误仍由调用方拿到
    _opQueue = result.then<void>((_) {}, onError: (Object e, StackTrace s) {
      WywLogger().w('${LogTag.js} WebView 会话队列任务失败 key=$key（不影响主流程）', error: e);
    });
    return result;
  }

  // ===== 交互会话槽位 =====
  CaptchaWebviewController? leaseController;
  Timer? leaseIdleTimer;
  bool leaseKeepCookies = true;
  _Lease? lease;
}

/// 租约被关闭（最长寿命到点 / 被新 open 取代 / 插件主动 close）。
///
/// 专用类型只为让插件侧看到的错误文案干净：`toString()` 直接给消息，
/// 不带 `StateError` 的 `Bad state:` 前缀。
class _LeaseClosedException implements Exception {
  const _LeaseClosedException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 一次交互会话（租约）：实例 + 事件订阅 + 等到来的图片/通过信号 + 最长寿命。
class _Lease {
  _Lease({required this.session, required this.url, required this.controller});

  final String session;
  final String url;
  final CaptchaWebviewController controller;

  StreamSubscription<String>? _imageSub;
  StreamSubscription<void>? _goneSub;
  StreamSubscription<String>? _logSub;

  /// 最近一次验证码图（open 时即订阅，故早到的图不会丢）。
  String? lastImage;

  /// 是否已观察到"验证通过"。
  bool passed = false;

  bool closed = false;
  String? closedReason;

  Timer? lifetimeTimer;
  Completer<String>? imageWaiter;
  Completer<void>? goneWaiter;

  Future<void> _opQueue = Future<void>.value();

  Future<void> attach() async {
    _imageSub = controller.onCaptchaImageFound.listen((data) {
      lastImage = data;
      final waiter = imageWaiter;
      if (waiter != null && !waiter.isCompleted) waiter.complete(data);
      imageWaiter = null;
    });
    _goneSub = controller.onCaptchaDisappeared.listen((_) {
      passed = true;
      final waiter = goneWaiter;
      if (waiter != null && !waiter.isCompleted) waiter.complete();
      goneWaiter = null;
    });
    _logSub = controller.onLog.listen((msg) {
      WywLogger().d('${LogTag.webview} 交互会话 $session：$msg');
    });
  }

  void detach() {
    _imageSub?.cancel();
    _imageSub = null;
    _goneSub?.cancel();
    _goneSub = null;
    _logSub?.cancel();
    _logSub = null;
  }

  Future<T> runQueued<T>(Future<T> Function() op) {
    final result = _opQueue.then((_) => op());
    _opQueue = result.then<void>((_) {}, onError: (Object e, StackTrace s) {
      WywLogger().w('${LogTag.js} 交互会话队列任务失败 session=$session（不影响主流程）',
          error: e);
    });
    return result;
  }
}
