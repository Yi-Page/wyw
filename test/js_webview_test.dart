import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyw/js/js_extends/js_webview.dart';
import 'package:wyw/webview/captcha/captcha_webview_controller.dart';

/// `JsWebview`（`lib/js/js_extends/js_webview.dart`）的生命周期与契约测试。
///
/// 全部用注入的 [_FakeController] 跑，不碰真机 WebView：
///   - 一次性取页 [JsWebview.fetchHtml] 的行为等价（Cookie 双域同步 / 结构化错误）；
///   - 实例复用、同会话串行、不同会话隔离；
///   - 空闲销毁 / 租约抑制销毁 / 租约最长寿命；
///   - Cookie 库与实例分离、`close(keepCookies/dispose)` 分支；
///   - 「未 open 就调用」的结构化错误契约（不抛异常）。
///
/// 时间窗口都靠构造参数注入（`idleDisposeDelay` / `defaultLeaseMaxLifetime`）
/// 缩到毫秒级，避免测试真等 15 秒；最长寿命用 `defaultLeaseMaxLifetime` 走
/// **不 clamp** 的路径（显式 `maxLifetimeMs` 会被 clamp 到 30s..15min）。
void main() {
  group('fetchHtml 一次性取页（行为等价）', () {
    test('成功后把 url 与 finalUrl 两个域的 cookie 都同步进会话库', () async {
      const url = 'https://a.example/page';
      const finalUrl = 'https://b.example/landing';
      final fakes = <_FakeController>[];
      final webview = JsWebview(
        controllerFactory: () {
          final c = _FakeController()
            ..href = finalUrl
            ..pageHtml = '<html><body>rendered</body></html>'
            ..cookies[url] = 'sid=1'
            ..cookies[finalUrl] = 'sso=2';
          fakes.add(c);
          return c;
        },
        idleDisposeDelay: const Duration(seconds: 5),
      );
      addTearDown(webview.dispose);

      final result = await webview.fetchHtml(url: url, session: 's');

      expect(fakes, hasLength(1));
      expect(result['html'], '<html><body>rendered</body></html>');
      expect(result['finalUrl'], finalUrl);
      expect(result.containsKey('error'), isFalse);
      // url 域的 cookie
      expect(
        webview.cookiesFor('s').cookieHeader('https://a.example/other'),
        contains('sid=1'),
      );
      // finalUrl 域的 cookie（同域子路径也能命中）
      expect(
        webview.cookiesFor('s').cookieHeader('https://b.example/x'),
        contains('sso=2'),
      );
    });

    test('Controller 抛异常时返回 {error:{kind:webview}}（不抛给调用方）', () async {
      final fakes = <_FakeController>[];
      final webview = JsWebview(
        controllerFactory: () {
          final c = _FakeController()
            ..parseError = TimeoutException('取页超时', const Duration(seconds: 1));
          fakes.add(c);
          return c;
        },
        idleDisposeDelay: const Duration(seconds: 5),
      );
      addTearDown(webview.dispose);

      final result = await webview.fetchHtml(url: 'https://a.example/', session: 's');

      final error = result['error'] as Map?;
      expect(error, isNotNull);
      expect(error!['kind'], 'webview');
      expect(error['retryable'], true);
      expect(error['status'], 0);
      expect(error['message'].toString(), isNotEmpty);
      expect(result.containsKey('html'), isFalse);
    });

    test('失败后仍排空闲销毁（下次调用重建实例）', () async {
      final fakes = <_FakeController>[];
      final webview = JsWebview(
        controllerFactory: () {
          final c = _FakeController()..parseError = Exception('boom');
          fakes.add(c);
          return c;
        },
        idleDisposeDelay: const Duration(milliseconds: 60),
      );
      addTearDown(webview.dispose);

      await webview.fetchHtml(url: 'https://a.example/', session: 's');
      expect(fakes, hasLength(1));

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(fakes.first.disposed, isTrue);

      // 失败实例被回收后重建
      await webview.fetchHtml(url: 'https://a.example/', session: 's');
      expect(fakes, hasLength(2));
    });
  });

  group('实例复用与串行', () {
    test('空闲窗口内连续 fetchHtml 复用同一实例（factory 只调用 1 次）', () async {
      final fakes = <_FakeController>[];
      final webview = JsWebview(
        controllerFactory: () {
          fakes.add(_FakeController());
          return fakes.last;
        },
      ); // 默认 idleDisposeDelay = 15s
      addTearDown(webview.dispose);

      await webview.fetchHtml(url: 'https://a.example/1', session: 's');
      await webview.fetchHtml(url: 'https://a.example/2', session: 's');

      expect(fakes, hasLength(1));
      expect(fakes.first.parseHtmlCount, 2);
    });

    test('同 session 并发两次调用按序执行（不交错）', () async {
      final fakes = <_FakeController>[];
      final webview = JsWebview(
        controllerFactory: () {
          final c = _FakeController()
            ..parseDelay = const Duration(milliseconds: 20);
          fakes.add(c);
          return c;
        },
        idleDisposeDelay: const Duration(seconds: 5),
      );
      addTearDown(webview.dispose);

      await Future.wait([
        webview.fetchHtml(url: 'https://a.example/1', session: 's'),
        webview.fetchHtml(url: 'https://a.example/2', session: 's'),
      ]);

      expect(fakes, hasLength(1));
      expect(fakes.first.calls, [
        'init',
        'enter:https://a.example/1',
        'exit:https://a.example/1',
        'enter:https://a.example/2',
        'exit:https://a.example/2',
      ]);
    });

    test('不同 session 各自实例', () async {
      final fakes = <_FakeController>[];
      final webview = JsWebview(
        controllerFactory: () {
          fakes.add(_FakeController());
          return fakes.last;
        },
        idleDisposeDelay: const Duration(seconds: 5),
      );
      addTearDown(webview.dispose);

      await webview.fetchHtml(url: 'https://a.example/', session: 'a');
      await webview.fetchHtml(url: 'https://a.example/', session: 'b');

      expect(fakes, hasLength(2));
      expect(identical(fakes[0], fakes[1]), isFalse);
    });
  });

  group('空闲销毁', () {
    test('超过 idleDisposeDelay 后实例被 dispose，下次调用重建', () async {
      final fakes = <_FakeController>[];
      final webview = JsWebview(
        controllerFactory: () {
          fakes.add(_FakeController());
          return fakes.last;
        },
        idleDisposeDelay: const Duration(milliseconds: 60),
      );
      addTearDown(webview.dispose);

      await webview.fetchHtml(url: 'https://a.example/', session: 's');
      expect(fakes, hasLength(1));
      expect(fakes.first.disposed, isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(fakes.first.disposed, isTrue);

      await webview.fetchHtml(url: 'https://a.example/', session: 's');
      expect(fakes, hasLength(2));
    });
  });

  group('交互租约', () {
    test('open 期间不被空闲销毁；close 后空闲窗口过去才销毁', () async {
      final fakes = <_FakeController>[];
      final webview = JsWebview(
        controllerFactory: () {
          fakes.add(_FakeController()..href = 'https://cap.example/after');
          return fakes.last;
        },
        idleDisposeDelay: const Duration(milliseconds: 80),
        defaultLeaseMaxLifetime: const Duration(seconds: 30),
      );
      addTearDown(webview.dispose);

      final opened = await webview.open(
        session: 's',
        url: 'https://cap.example/verify',
        mode: 'image',
        captchaXpath: '//img[@id="cap"]',
        inputXpath: '//input[@id="code"]',
        buttonXpath: '//button[@id="submit"]',
        script: 'var x = 1;',
      );
      expect(opened['ok'], true);
      expect(opened['finalUrl'], 'https://cap.example/after');
      expect(fakes, hasLength(1));
      // open 把 mode/xpath/script 原样转给控制器
      expect(fakes.first.lastLoadMode, WebviewLoadMode.image);
      expect(fakes.first.lastCaptchaXpath, '//img[@id="cap"]');
      expect(fakes.first.lastInputXpath, '//input[@id="code"]');
      expect(fakes.first.lastButtonXpath, '//button[@id="submit"]');
      expect(fakes.first.lastScript, 'var x = 1;');

      // 租约持有期间：即使超过空闲窗口也不得销毁
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(fakes.first.disposed, isFalse);

      // 交互实例与一次性实例是两个独立槽位
      await webview.fetchHtml(url: 'https://a.example/', session: 's');
      expect(fakes, hasLength(2));
      expect(identical(fakes[0], fakes[1]), isFalse);

      final closed = await webview.close(session: 's');
      expect(closed['ok'], true);
      // dispose:false（默认）→ 先卸页 + 排空闲销毁
      expect(fakes.first.calls, contains('unload'));
      expect(fakes.first.disposed, isFalse);
      expect(fakes.first.disposedClearCookies, isNull);

      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(fakes.first.disposed, isTrue);
      // keepCookies 默认 true → clearCookies:false
      expect(fakes.first.disposedClearCookies, isFalse);
    });

    test('open 后超过 defaultLeaseMaxLifetime 被强制关闭，后续调用返回结构化错误', () async {
      final fakes = <_FakeController>[];
      final webview = JsWebview(
        controllerFactory: () {
          fakes.add(_FakeController());
          return fakes.last;
        },
        idleDisposeDelay: const Duration(seconds: 30),
        defaultLeaseMaxLifetime: const Duration(milliseconds: 60),
      );
      addTearDown(webview.dispose);

      // 注意：不传 maxLifetimeMs，走 defaultLeaseMaxLifetime（不 clamp）
      final opened = await webview.open(session: 's', url: 'https://cap.example/verify');
      expect(opened['ok'], true);
      expect(fakes, hasLength(1));

      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(fakes.first.disposed, isTrue);

      final exec = await webview.exec(session: 's', js: '1 + 1');
      final execError = exec['error'] as Map?;
      expect(execError, isNotNull);
      expect(execError!['kind'], 'webview');
      expect(execError['retryable'], false);
      expect(exec.containsKey('ok'), isFalse);

      final html = await webview.getPageHtml(session: 's');
      expect(html['error'], isNotNull);
      expect(html.containsKey('ok'), isFalse);
    });

    test('close(dispose:true) 立即销毁并按 keepCookies 传 clearCookies', () async {
      final fakes = <_FakeController>[];
      final webview = JsWebview(
        controllerFactory: () {
          fakes.add(_FakeController());
          return fakes.last;
        },
        idleDisposeDelay: const Duration(seconds: 30),
        defaultLeaseMaxLifetime: const Duration(seconds: 30),
      );
      addTearDown(webview.dispose);

      await webview.open(session: 's', url: 'https://cap.example/verify');
      await webview.close(session: 's', keepCookies: true, dispose: true);

      expect(fakes.first.disposed, isTrue); // 立即销毁，不等空闲窗口
      expect(fakes.first.disposedClearCookies, isFalse); // keepCookies:true
    });

    test('close(keepCookies:false, dispose:true) → dispose(clearCookies:true) 且清空会话库', () async {
      const leaseUrl = 'https://cap.example/verify';
      final fakes = <_FakeController>[];
      final webview = JsWebview(
        controllerFactory: () {
          final c = _FakeController()..cookies[leaseUrl] = 'cf_clearance=abc123';
          fakes.add(c);
          return c;
        },
        idleDisposeDelay: const Duration(seconds: 30),
        defaultLeaseMaxLifetime: const Duration(seconds: 30),
      );
      addTearDown(webview.dispose);

      await webview.open(session: 's', url: leaseUrl);
      await webview.close(session: 's', keepCookies: false, dispose: true);

      expect(fakes.first.disposed, isTrue);
      expect(fakes.first.disposedClearCookies, isTrue);
      // keepCookies:false 同时清会话 cookie 库（fetchHtml/getCookies 用的那份）
      expect(webview.cookiesFor('s').count, 0);
      expect(webview.getCookies(session: 's', url: leaseUrl)['cookies'], '');
    });
  });

  group('cookie 与实例分离', () {
    test('close(keepCookies:true) 后同名 session 仍能查到验证期间的 cookie', () async {
      const leaseUrl = 'https://cap.example/verify';
      final fakes = <_FakeController>[];
      final webview = JsWebview(
        controllerFactory: () {
          final c = _FakeController()
            ..cookies[leaseUrl] = 'cf_clearance=abc123; sid=9';
          fakes.add(c);
          return c;
        },
        idleDisposeDelay: const Duration(seconds: 30),
        defaultLeaseMaxLifetime: const Duration(seconds: 30),
      );
      addTearDown(webview.dispose);

      await webview.open(session: 's', url: leaseUrl);
      await webview.close(session: 's', keepCookies: true);

      // Cookie 库独立于实例：实例还活着/销毁都不影响已同步的 cookie
      expect(
        webview.cookiesFor('s').cookieHeader('https://cap.example/next'),
        contains('cf_clearance=abc123'),
      );
      final queried = webview.getCookies(session: 's', url: 'https://cap.example/next');
      expect(queried['cookies'], contains('sid=9'));

      // 同名 session 的一次性取页是**另一个实例**
      await webview.fetchHtml(url: leaseUrl, session: 's');
      expect(fakes, hasLength(2));
      expect(identical(fakes[0], fakes[1]), isFalse);
    });

    test('close(keepCookies:false) 时空闲销毁走 clearCookies:true', () async {
      // keepCookies:false 的两条后果：平台罐（dispose(clearCookies:true)）+ 会话 cookie 库
      // （close 末尾 state.cookies.clear()）。本用例锁 dispose 分支，下一条锁会话库。
      final fakes = <_FakeController>[];
      final webview = JsWebview(
        controllerFactory: () {
          fakes.add(_FakeController());
          return fakes.last;
        },
        idleDisposeDelay: const Duration(milliseconds: 60),
        defaultLeaseMaxLifetime: const Duration(seconds: 30),
      );
      addTearDown(webview.dispose);

      await webview.open(session: 's', url: 'https://cap.example/verify');
      await webview.close(session: 's', keepCookies: false);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(fakes.first.disposed, isTrue);
      expect(fakes.first.disposedClearCookies, isTrue);
    });

    test('close(keepCookies:false) 清空会话库：getCookies 空串、后续 fetchHtml 不再带', () async {
      const leaseUrl = 'https://cap.example/verify';
      final fakes = <_FakeController>[];
      final webview = JsWebview(
        controllerFactory: () {
          final c = _FakeController();
          // 只有交互实例下发页面 cookie；一次性实例返回空，用来证明 keepCookies:false
          // 之后后续 fetchHtml 不会把被丢弃的 cookie 重新带回来。
          if (fakes.isEmpty) {
            c.cookies[leaseUrl] = 'cf_clearance=abc123; sid=9';
          }
          fakes.add(c);
          return c;
        },
        idleDisposeDelay: const Duration(seconds: 30),
        defaultLeaseMaxLifetime: const Duration(seconds: 30),
      );
      addTearDown(webview.dispose);

      // 第一轮 keepCookies:true：会话库确实拿到了验证期间的 cookie
      await webview.open(session: 's', url: leaseUrl);
      await webview.close(session: 's', keepCookies: true);
      expect(
        webview.getCookies(session: 's', url: leaseUrl)['cookies'],
        contains('cf_clearance=abc123'),
      );
      expect(webview.cookiesFor('s').count, 2); // cf_clearance + sid

      // 第二轮同 session、keepCookies:false：会话库被清空
      await webview.open(session: 's', url: leaseUrl);
      await webview.close(session: 's', keepCookies: false);
      expect(webview.getCookies(session: 's', url: leaseUrl)['cookies'], '');
      expect(webview.cookiesFor('s').count, 0);
      // 请求侧（Network.* 注入前读取的就是这个）也拿不到 cookie 了
      expect(webview.cookiesFor('s').cookieHeader(leaseUrl), '');

      // 后续同 session 的一次性 fetchHtml：用另一个实例且不再带这些 cookie
      await webview.fetchHtml(url: leaseUrl, session: 's');
      expect(fakes, hasLength(2));
      expect(webview.cookiesFor('s').count, 0);
      expect(webview.cookiesFor('s').cookieHeader(leaseUrl), '');
    });
  });

  group('错误契约（未 open）', () {
    test('exec/getPageHtml/getUserAgent/fillAndClick/awaitImage/awaitGone 均结构化错误', () async {
      final fakes = <_FakeController>[];
      final webview = JsWebview(
        controllerFactory: () {
          fakes.add(_FakeController());
          return fakes.last;
        },
      );
      addTearDown(webview.dispose);

      Future<void> expectStructuredError(Future<Map<String, dynamic>> future) async {
        final result = await future; // 必须正常 complete（不抛异常）
        final error = result['error'] as Map?;
        expect(error, isNotNull);
        expect(error!['kind'], 'webview');
        expect(error['retryable'], false);
        expect(result.containsKey('ok'), isFalse);
      }

      await expectStructuredError(webview.exec(session: 's', js: '1'));
      await expectStructuredError(webview.getPageHtml(session: 's'));
      await expectStructuredError(webview.getUserAgent(session: 's'));
      await expectStructuredError(webview.fillAndClick(
        session: 's',
        code: '1234',
        inputXpath: '//input',
        buttonXpath: '//button',
      ));
      await expectStructuredError(webview.awaitCaptchaImage(session: 's', timeout: 1));
      await expectStructuredError(webview.awaitCaptchaGone(session: 's', timeout: 1));

      // 未 open 不应创建任何实例
      expect(fakes, isEmpty);
    });
  });

  group('交互会话成功路径', () {
    test('exec/getPageHtml/getUserAgent/fillAndClick 返回 ok', () async {
      final fakes = <_FakeController>[];
      final webview = JsWebview(
        controllerFactory: () {
          final c = _FakeController()
            ..pageHtml = '<html><body>after</body></html>'
            ..userAgent = 'FakeUA/1.0';
          fakes.add(c);
          return fakes.last;
        },
        idleDisposeDelay: const Duration(seconds: 30),
        defaultLeaseMaxLifetime: const Duration(seconds: 30),
      );
      addTearDown(webview.dispose);

      await webview.open(session: 's', url: 'https://cap.example/verify');

      final exec = await webview.exec(session: 's', js: '1 + 1');
      expect(exec['ok'], true);
      expect(exec['value'], 'script-result');

      final html = await webview.getPageHtml(session: 's');
      expect(html['ok'], true);
      expect(html['html'], '<html><body>after</body></html>');

      final ua = await webview.getUserAgent(session: 's');
      expect(ua['ok'], true);
      expect(ua['userAgent'], 'FakeUA/1.0');

      final filled = await webview.fillAndClick(
        session: 's',
        code: '1234',
        inputXpath: '//input[@id="code"]',
        buttonXpath: '//button[@id="submit"]',
      );
      expect(filled['ok'], true);
      // 回填走原生 setter + input/change 事件（受控组件才认）
      final fillScript = fakes.first.calls.last;
      expect(fillScript, contains('HTMLInputElement.prototype'));
      expect(fillScript, contains('1234'));
    });

    test('验证码图 / 通过信号早到不丢（open 时已订阅），超时返回结构化错误', () async {
      final fakes = <_FakeController>[];
      final webview = JsWebview(
        controllerFactory: () {
          fakes.add(_FakeController());
          return fakes.last;
        },
        idleDisposeDelay: const Duration(seconds: 30),
        defaultLeaseMaxLifetime: const Duration(seconds: 30),
      );
      addTearDown(webview.dispose);

      await webview.open(session: 's', url: 'https://cap.example/verify');

      // 图片在 awaitCaptchaImage 之前到达：应命中早到缓存
      fakes.first.emitImage('data:image/png;base64,AAA');
      fakes.first.emitGone();
      await Future<void>.delayed(Duration.zero);

      final image = await webview.awaitCaptchaImage(session: 's', timeout: 1);
      expect(image['ok'], true);
      expect(image['image'], 'data:image/png;base64,AAA');

      final gone = await webview.awaitCaptchaGone(session: 's', timeout: 1);
      expect(gone['ok'], true);

      // 换一个未收到图的会话：等待验证码图超时 → 结构化错误（不抛）
      await webview.open(session: 't2', url: 'https://cap.example/verify2');
      final late = await webview.awaitCaptchaImage(session: 't2', timeout: 1);
      final lateError = late['error'] as Map?;
      expect(lateError, isNotNull);
      expect(lateError!['kind'], 'webview');
      expect(late.containsKey('ok'), isFalse);
    });

    test('awaitCaptchaGone 的「早到」路径也同步 cookie（不是直接 return）', () async {
      const leaseUrl = 'https://cap.example/verify';
      final fakes = <_FakeController>[];
      final webview = JsWebview(
        controllerFactory: () {
          final c = _FakeController()
            ..cookies[leaseUrl] = 'cf_clearance=abc; sid=1';
          fakes.add(c);
          return c;
        },
        idleDisposeDelay: const Duration(seconds: 30),
        defaultLeaseMaxLifetime: const Duration(seconds: 30),
      );
      addTearDown(webview.dispose);

      await webview.open(session: 's', url: leaseUrl);
      // gone 早于 awaitCaptchaGone 到达：lease.passed 已为 true（open 时已订阅）
      fakes.first.emitGone();
      await Future<void>.delayed(Duration.zero);

      final gone = await webview.awaitCaptchaGone(session: 's', timeout: 1);
      expect(gone['ok'], true);
      expect(gone['passed'], true);
      // 早到分支同样要走 _syncWebviewCookies：站点常与「验证通过」同时下发 clearance cookie
      expect(
        webview.cookiesFor('s').cookieHeader(leaseUrl),
        contains('cf_clearance=abc'),
      );
      expect(webview.cookiesFor('s').count, 2); // cf_clearance + sid
    });
  });

  group('在途等待 × 强杀（_failPendingWaiters）', () {
    // 说明：`maxLifetimeMs` 显式正值的 clamp 分支（30s..15min）没有单测 —— clamp 下限就是
    // 30s，跑一次要真等 30s，不适合放进单测；这里只覆盖「不传 maxLifetimeMs」的
    // defaultLeaseMaxLifetime 注入路径（不 clamp），它才是测试可用的短寿命入口。

    test('最长寿命到点：在途 awaitCaptchaImage 立刻失败(<1s)，不是等满 timeout', () async {
      final fakes = <_FakeController>[];
      final webview = JsWebview(
        controllerFactory: () {
          fakes.add(_FakeController());
          return fakes.last;
        },
        idleDisposeDelay: const Duration(seconds: 30),
        // 不传 maxLifetimeMs → 走默认寿命（不 clamp 到 30s 下限）
        defaultLeaseMaxLifetime: const Duration(milliseconds: 60),
      );
      addTearDown(webview.dispose);

      await webview.open(session: 's', url: 'https://cap.example/verify');
      // 在途等待：fake 不发图，timeout 给足 30s
      final pending = webview.awaitCaptchaImage(session: 's', timeout: 30);

      // 等寿命到点强杀（60ms，留足余量）
      await Future<void>.delayed(const Duration(milliseconds: 250));

      final stopwatch = Stopwatch()..start();
      final result = await pending;
      stopwatch.stop();

      final error = result['error'] as Map?;
      expect(error, isNotNull);
      expect(error!['kind'], 'webview');
      expect(error['retryable'], false);
      expect(result.containsKey('ok'), isFalse);
      // 关键：立刻返回（<1s），而不是等满 30s
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('close 期间在途 awaitCaptchaGone 立刻失败(<1s)，retryable:false', () async {
      final fakes = <_FakeController>[];
      final webview = JsWebview(
        controllerFactory: () {
          fakes.add(_FakeController());
          return fakes.last;
        },
        idleDisposeDelay: const Duration(seconds: 30),
        defaultLeaseMaxLifetime: const Duration(seconds: 30),
      );
      addTearDown(webview.dispose);

      await webview.open(session: 's', url: 'https://cap.example/verify');
      final pending = webview.awaitCaptchaGone(session: 's', timeout: 30);
      // goneWaiter 在调用内同步注册；这里再让出一次事件循环，确保它已挂上
      await Future<void>.delayed(Duration.zero);

      final stopwatch = Stopwatch()..start();
      await webview.close(session: 's'); // close 内部会 _failPendingWaiters
      final result = await pending;
      stopwatch.stop();

      final error = result['error'] as Map?;
      expect(error, isNotNull);
      expect(error!['kind'], 'webview');
      expect(error['retryable'], false);
      expect(result.containsKey('ok'), isFalse);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    });
  });
}

/// 可编程的假控制器：记录调用序列，可注入失败/延迟/页面状态。
///
/// `dispose({clearCookies})` 与基类 `dispose({bool clearCookies = true})` 逐字段一致。
class _FakeController extends CaptchaWebviewController {
  // ===== 记录 =====
  final List<String> calls = <String>[];
  int initCount = 0;
  int parseHtmlCount = 0;
  int loadPageCount = 0;
  bool disposed = false;
  bool? disposedClearCookies;
  int disposeCount = 0;

  WebviewLoadMode? lastLoadMode;
  String? lastCaptchaXpath;
  String? lastInputXpath;
  String? lastButtonXpath;
  String? lastScript;

  // ===== 可编程行为 =====
  Object? parseError;
  Duration parseDelay = const Duration(milliseconds: 1);
  String pageHtml = '<html><body>page</body></html>';
  String userAgent = 'FakeUA/1.0';
  String readyState = 'complete';
  String href = 'https://final.example/landing';
  final Map<String, String> cookies = <String, String>{};

  final StreamController<String> _imageCtrl =
      StreamController<String>.broadcast();
  final StreamController<void> _goneCtrl = StreamController<void>.broadcast();

  @override
  Stream<String> get onCaptchaImageFound => _imageCtrl.stream;

  @override
  Stream<void> get onCaptchaDisappeared => _goneCtrl.stream;

  void emitImage(String dataUrl) => _imageCtrl.add(dataUrl);

  void emitGone() => _goneCtrl.add(null);

  @override
  Future<void> init() async {
    initCount++;
    calls.add('init');
    initEventController.add(true);
  }

  @override
  Future<WebviewHtmlResult> parseHtml(
    String url, {
    int overTime = 50,
    Map<String, dynamic>? waitFor,
  }) async {
    parseHtmlCount++;
    calls.add('enter:$url');
    try {
      await Future<void>.delayed(parseDelay);
      final err = parseError;
      if (err != null) throw err;
      return WebviewHtmlResult(html: pageHtml, finalUrl: href);
    } finally {
      calls.add('exit:$url');
    }
  }

  @override
  Future<void> loadPageForInteraction(
    String url, {
    required WebviewLoadMode mode,
    String captchaXpath = '',
    String inputXpath = '',
    String buttonXpath = '',
    String script = '',
  }) async {
    loadPageCount++;
    calls.add('load:$url:${mode.name}');
    lastLoadMode = mode;
    lastCaptchaXpath = captchaXpath;
    lastInputXpath = inputXpath;
    lastButtonXpath = buttonXpath;
    lastScript = script;
  }

  @override
  Future<String?> executeScript(String js) async {
    calls.add('exec:$js');
    if (js.contains('document.readyState')) return readyState;
    if (js.contains('location.href')) return href;
    return 'script-result';
  }

  @override
  Future<String> getPageHtml() async => pageHtml;

  @override
  Future<String> getUserAgent() async => userAgent;

  @override
  Future<String> getCookieString(String pageUrl) async => cookies[pageUrl] ?? '';

  @override
  Future<void> unloadPage() async {
    calls.add('unload');
  }

  @override
  void dispose({bool clearCookies = true}) {
    disposeCount++;
    disposed = true;
    disposedClearCookies = clearCookies;
  }
}
