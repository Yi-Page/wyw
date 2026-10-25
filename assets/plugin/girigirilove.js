// description: girigiri愛動漫（ani.girigirilove.com）视频源 — 搜索 / 详情 / 播放；内置风控处理（无头渲染降级 + 页面内验证码交互）
// type: video
//
// ============================================================
// 站点 URL 模式（maccms dsn2 主题）
// ============================================================
//   搜索：/index.php/ajax/suggest?mid=1&wd={kw}
//         → JSON {code,list:[{id,name,pic}]}，pic 为 /upload/... 相对路径；**接口本身无验证码**
//   详情：/GV{id}/
//         剧集：<ul class="anthology-list-play size"><li><a href="/playGV{id}-{sid}-{nid}/">线路名</a></li></ul>
//         （一个 tab 一个 ul；与 Kazumi 规则 chapterRoads/chapterResult 一一对应）
//   播放：/playGV{id}-{sid}-{nid}/
//         页面内 <script>var player_aaaa={"flag":"play","encrypt":2,"url":"<hex>"}</script>，
//         由站点自己的 /static/js/player.js 解出 m3u8。
//         ⇒ 本插件**不逆它的加密**，直接回 type:'page' 让 wyw 播放器嗅探
//           （player.js 在 WebView 里跑一遍，嗅探器就能抓到 m3u8）。
//
// ============================================================
// 风控：这个站有两种拦截，别混为一谈
// ============================================================
//   ① 地区封锁（**不是验证码，插件无法解决**）
//      播放页底部内联脚本会 fetch https://cloudflare.com/cdn-cgi/trace，
//      若 loc ∈ {US, JP} 或欧洲国家 → window.location = https://502.girigirilove.com，
//      该页只显示「暫不支持該地區訪問」。插件会识别并给出可读提示，请更换网络地区。
//   ② 验证码 / JS 挑战（**本插件处理**）
//      命中特征（403/429/5xx，或页面含 cf-mitigated / Just a moment / turnstile /
//      challenge-platform / 人机验证 …）时按三级降级：
//        第 1 级  直连（Network.get）
//        第 2 级  无头 WebView 渲染（backend:'webview'）——多数 JS 挑战在无头下自解
//        第 3 级  页面内交互验证码（Webview.* 留页式）：
//                 取验证码图 → Dialog 弹输入框 → 页面内回填点击 → 等通过 → 取 HTML+UA
//      通过后把 WebView 的 UA 记在内存里，与 cookie 成对用于后续请求（UA 与 cookie 必须成对，
//      否则 clearance cookie 立刻失效；wyw 宿主目前不会自动对齐 UA）。
//      验证码的 XPath 因站点/主题而异，全部放在「插件设置」里可改。
//
// 接口约定：
//   search(keyword, page)  → List<UI.Card>（suggest 接口不分页，page>1 返回空）
//   getDetail(id)          → 头部卡片 + 简介 + 多线路剧集（ExpansionTile + Wrap 按钮）
//   play(url, title, cover)→ 结构化进入 wyw 播放页（type:'page' 交嗅探）
//   resolvePlayUrl(url)    → { url, type:'page' }（惰性形态的兜底）
//   getUrl()               → 站点地址（插件管理页「网站」入口）

class girigirilove extends PluginSource {
    name = 'girigiri愛動漫'
    key = 'girigirilove'
    version = '1.0.0'
    baseUrl = 'https://ani.girigirilove.com'

    /// 默认 UA（与 douban/dushehub 一致风格；验证后会被 WebView 的真实 UA 临时覆盖）
    static defaultUA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'

    settings = {
        captcha_enabled: {
            title: '风控验证处理',
            type: 'select',
            options: [
                { value: 'on', text: '开启（推荐）' },
                { value: 'off', text: '关闭（只直连）' },
            ],
            default: 'on',
        },
        captcha_mode: {
            title: '验证码形态',
            type: 'select',
            options: [
                { value: 'image', text: '图片验证码（读图填字）' },
                { value: 'button', text: '点按式（点一下就过，如 Turnstile）' },
                { value: 'script', text: '站点自定义脚本' },
            ],
            default: 'image',
        },
        captcha_image_xpath: {
            title: '验证码图片 XPath',
            type: 'input',
            default: '//img[contains(@id,"captcha") or contains(@class,"captcha") or contains(@src,"captcha")]',
        },
        captcha_input_xpath: {
            title: '验证码输入框 XPath（image 模式）',
            type: 'input',
            default: '//input[contains(@id,"captcha") or contains(@name,"captcha") or contains(@class,"captcha")]',
        },
        captcha_button_xpath: {
            title: '提交按钮 XPath',
            type: 'input',
            default: '//button[contains(@id,"submit") or contains(@class,"submit")] | //input[@type="submit"]',
        },
        ua_override: {
            title: '固定 User-Agent（留空=默认；验证后自动用 WebView 的 UA）',
            type: 'input',
            default: '',
        },
        session_key: {
            title: '会话键（HTTP 与验证码共用，改动可隔离 cookie）',
            type: 'input',
            default: 'girigiri',
        },
        captcha_script: {
            title: '自定义验证脚本（仅「站点自定义脚本」模式需要）',
            type: 'input',
            default: '',
        },
    }

    constructor() {
        super()
        this.init()
    }

    init() {
        /// 验证通过后 WebView 的真实 UA（仅本次运行有效，与 cookie 成对使用）
        this._ua = ''
        /// getDetail 缓存的整部剧播放源
        this._playSources = null
    }

    /// 会话键：**HTTP 请求与 WebView 验证必须用同一个**。
    ///
    /// wyw 的请求侧 cookie 库按 session 分库（`JsWebview.cookiesFor`），
    /// 若 HTTP 落默认会话 `''` 而验证用 `'girigiri'`，验证拿到的 clearance cookie
    /// 就永远不会被后续直连请求带上——「UA 与 cookie 成对」也就成了空话。
    _sessionKey() {
        return this._setting('session_key') || 'girigiri'
    }

    getUrl() {
        return this.baseUrl
    }

    // ============================================================
    // 设置与请求头
    // ============================================================

    _setting(key) {
        const v = this.loadSetting(key)
        if (v === null || v === undefined || v === '') {
            const def = this.settings[key]
            return def && def.default !== undefined ? def.default : ''
        }
        return v
    }

    _captchaEnabled() {
        return this._setting('captcha_enabled') !== 'off'
    }

    _headers(extra) {
        const headers = {
            'User-Agent': this._ua || this._setting('ua_override') || girigirilove.defaultUA,
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
            'Accept-Language': 'zh-CN,zh;q=0.9',
            'Referer': this.baseUrl + '/',
        }
        if (extra) {
            for (const k in extra) {
                if (extra[k] !== null && extra[k] !== undefined && extra[k] !== '') headers[k] = extra[k]
            }
        }
        return headers
    }

    _abs(href) {
        if (!href) return ''
        if (href.indexOf('http://') === 0 || href.indexOf('https://') === 0) return href
        if (href.indexOf('//') === 0) return 'https:' + href
        if (href.indexOf('/') === 0) return this.baseUrl + href
        return this.baseUrl + '/' + href
    }

    // ============================================================
    // 风控判定
    // ============================================================

    /// 强特征：单独命中一条即可判定为挑战页
    static strongMarkers = [
        'cf-mitigated', 'challenge-platform', 'cf_chl_', 'just a moment',
        'attention required', 'turnstile', '人机验证', '請完成驗證', '请完成验证', '安全验证',
    ]

    /// 弱特征（验证码 UI）必须出现在**表单/图片/属性上下文**里才算挑战页。
    ///
    /// 为什么不按"弱词出现 ≥2 次"判：核验实测在真实详情页（45KB）注入一处 `captcha`
    /// 注释 + 一处 `verify` 变量就命中，而真实播放页本来就有 `data-verify="0"`。
    /// 同时补上**无标准词**的自定义验证码页（`vcode.php` / 「图形码」/ 拖动滑块）。
    static weakContexts = [
        /<img[^>]{0,240}(captcha|vcode|verifycode|验证码|驗證碼)/i,
        /<input[^>]{0,240}(captcha|vcode|verifycode|验证码|驗證碼)/i,
        /(id|class|name)\s*=\s*["'][^"']{0,60}(captcha|vcode|verifycode|验证码|驗證碼)/i,
        /(请输入|請輸入|输入|輸入)[^<]{0,12}(验证码|驗證碼)/,
        /(图形码|圖形碼|滑块验证|滑塊驗證|拖动滑块|拖動滑塊)/,
    ]

    _looksLikeChallenge(body, status) {
        if (status === 403 || status === 429 || status >= 500) return true
        const s = String(body || '')
        if (!s) return false
        const low = s.toLowerCase()
        for (const m of girigirilove.strongMarkers) {
            if (low.indexOf(m.toLowerCase()) >= 0) return true
        }
        for (const re of girigirilove.weakContexts) {
            if (re.test(s)) return true
        }
        return false
    }

    /// 内容健全性检查：拿到的 HTML/文本是否**真的像目标内容**。
    ///
    /// 只等 `readyState === 'complete'` 不够——SPA 半成品、脱敏挑战页同样是 complete，
    /// 直接接受会让"0 剧集"成为最终结果，永远走不到第 3 级验证码。
    _hasExpectedContent(html, expect) {
        const raw = String(html || '')
        if (!raw) return false
        const s = raw.trim()
        if (expect === 'detail') {
            return s.indexOf('anthology-list-play') >= 0 || s.indexOf('/playGV') >= 0
        }
        if (expect === 'json') {
            return s.indexOf('"list"') >= 0 || s.indexOf('{') === 0
        }
        return true
    }

    _isRegionBlocked(html, finalUrl) {
        // ⚠️ 不能只看「页面里出现 502.girigirilove.com」：站点**每个正常页面的公共页脚**里
        // 都带着那段地区跳转脚本（`window.location.href="https://502.girigirilove.com"`），
        // 那是正常内容。真正的封锁页只显示「暫不支持該地區訪問」。
        // 实测：详情页/播放页含该域名但无该文案；502 页有文案而无该域名。
        if (finalUrl && finalUrl.indexOf('502.girigirilove.com') >= 0) return true
        const s = String(html || '')
        return s.indexOf('暫不支持該地區訪問') >= 0 || s.indexOf('暂不支持该地区访问') >= 0
    }

    _regionError() {
        const err = new Error('该站点按网络地区封锁（502.girigirilove.com：暫不支持該地區訪問）；这不是验证码，插件无法越过，请更换网络地区后重试')
        err.isRegion = true
        return err
    }

    // ============================================================
    // 取页：直连 → 无头渲染 → 交互验证码
    // ============================================================

    /// 取页面文本。返回 { html, finalUrl }
    ///
    /// opts: { referer, session, allowCaptcha, noWebview, expect }
    ///   expect: `'detail'`/`'json'` 时要求内容真的像目标页面（防"SPA 半成品被当真"）。
    ///
    /// **每一级都必须带同一个 `session`**——请求侧 cookie 库按 session 分库，漏传就
    /// 会让验证码拿到的 clearance cookie 落不到直连请求上（核验发现的高危问题）。
    async _fetchText(url, opts) {
        opts = opts || {}
        const headers = this._headers(opts.referer ? { 'Referer': opts.referer } : null)
        const session = opts.session || this._sessionKey()
        const expect = opts.expect || 'any'
        const reqExtra = { timeout: 20000, retries: 1, session: session }

        // ---- 第 1 级：直连 ----
        let body = ''
        let failed = false
        let status = 0
        let kind = ''
        let firstError = null
        try {
            body = await Network.get(url, headers, reqExtra)
        } catch (e) {
            failed = true
            firstError = e
            status = e && typeof e.status === 'number' ? e.status : 0
            kind = e && e.kind ? String(e.kind) : ''
            console.log('[girigirilove] 直连失败 kind=' + kind + ' status=' + status + '：' + (e && e.message ? e.message : e))
        }
        // DNS / 证书错误与风控无关：直接抛可读错误，别把用户推进验证码流程
        if (failed && (kind === 'dns' || kind === 'ssl')) {
            throw new Error('网络请求失败（' + kind + '）：' + (firstError && firstError.message ? firstError.message : ''))
        }
        const challengeLike = failed
            ? this._looksLikeChallenge('', status) // 403/429/5xx 走这里（content 为空）
            : this._looksLikeChallenge(body, status)
        // ⚠️ 只有「直连成功 + 内容符合预期」才当成功返回。
        // 失败时**绝不**返回空串——否则超时/404 会被伪装成"空页面"，
        // 既短路第 2 级无头救援，又让 getDetail 产出伪造的空详情。
        if (!failed && !challengeLike && this._hasExpectedContent(body, expect)) {
            if (this._isRegionBlocked(body, '')) throw this._regionError()
            return { html: body, finalUrl: url }
        }

        // ---- 第 2 级：无头 WebView 渲染（JS 挑战 / 弱网都值得一试） ----
        if (!opts.noWebview && this._captchaEnabled()) {
            try {
                const html = await Network.get(url, headers, {
                    backend: 'webview',
                    webviewTimeout: 30,
                    waitFor: 'js:document.readyState === "complete"',
                    session: session,
                })
                const text = typeof html === 'string' ? html : ''
                if (text && !this._looksLikeChallenge(text, 0) && this._hasExpectedContent(text, expect)) {
                    if (this._isRegionBlocked(text, '')) throw this._regionError()
                    return { html: text, finalUrl: url }
                }
                if (text) body = text // 半成品：留给下一级，**不当真返回**
            } catch (e) {
                if (e && e.isRegion) throw e
                console.log('[girigirilove] 无头渲染失败:', e && e.message ? e.message : e)
            }
        }
        if (this._isRegionBlocked(body, '')) throw this._regionError()

        // 直连失败且**没有任何风控信号**（超时/连接/404/400/未知）：给原始错误，
        // 不要弹验证码——验证码解决不了网络问题，只会让用户白等 30s+90s。
        // 反过来 `challengeLike`（403/429/5xx）要继续走第 3 级。
        if (failed && !challengeLike) {
            throw new Error('请求失败（kind=' + (kind || 'unknown') + ' status=' + status + '）：' + (firstError && firstError.message ? firstError.message : ''))
        }
        // 走到这里可能是：(a) 直连失败但有风控信号；(b) 直连成功、无风控特征但内容
        // 不符合预期（脱敏挑战页 / SPA 半成品）→ 两种都允许第 3 级交互验证码

        // ---- 第 3 级：页面内交互验证码 ----
        if (this._captchaEnabled() && opts.allowCaptcha !== false) {
            return await this._passCaptcha(url, session)
        }
        if (failed) {
            throw new Error('请求失败（kind=' + (kind || 'unknown') + ' status=' + status + '）：' + (firstError && firstError.message ? firstError.message : ''))
        }
        throw new Error('页面内容不含预期结构（可能被风控、地区受限或站点改版）')
    }

    /// 留页式验证码交互：取图 → 用户输入 → 页面内回填点击 → 等通过 → 取 HTML/UA
    async _passCaptcha(url, session) {
        const mode = this._setting('captcha_mode') || 'image'
        const imageXpath = this._setting('captcha_image_xpath')
        const inputXpath = this._setting('captcha_input_xpath')
        const buttonXpath = this._setting('captcha_button_xpath')
        const script = this._setting('captcha_script')
        if (mode === 'script' && !String(script || '').trim()) {
            throw new Error('验证码形态选了「站点自定义脚本」，但没填 captcha_script 设置')
        }

        Dialog.showToast('站点要求人机验证，请在弹窗内完成…')
        await Webview.open(url, {
            session,
            mode,
            captchaXpath: imageXpath,
            inputXpath: inputXpath,
            buttonXpath: buttonXpath,
            script: script,
        })

        if (mode === 'image') {
            let image = null
            try {
                image = await Webview.awaitImage({ session, timeout: 30 })
            } catch (e) {
                // 没等到图：可能是点按式验证码、XPath 不匹配，或跨域图 canvas taint
                console.log('[girigirilove] 未取到验证码图:', e && e.message ? e.message : e)
                Dialog.showToast('未取到验证码图片，可改用「点按式」模式或调整 XPath')
            }
            const code = await Dialog.showInputDialog('请输入验证码', null, image)
            if (!code) {
                // keepCookies:true —— 这个 session 与 HTTP 请求**共用**（见 _sessionKey），
                // 用 false 会把该 session 早先通过 HTTP 拿到的 cookie 一起清掉。
                await Webview.close({ session, keepCookies: true })
                throw new Error('已取消验证码')
            }
            await Webview.fillAndClick({ session, code, inputXpath, buttonXpath })
        }

        // 等验证通过：验证码元素消失 / 页面跳转 / 自定义脚本 done
        try {
            await Webview.awaitGone({ session, timeout: 90 })
        } catch (e) {
            await Webview.close({ session, keepCookies: true })
            throw new Error('验证码未通过或超时：' + (e && e.message ? e.message : e))
        }

        const html = await Webview.getHtml({ session })
        let finalUrl = url
        try {
            finalUrl = (await Webview.exec('location.href', { session })) || url
        } catch (e) {
            // 取不到就沿用原 url
        }
        const ua = await Webview.getUserAgent({ session })
        // keepCookies 显式传 true（API 默认也是 true）：留住登录态/clearance cookie 交给后续请求
        await Webview.close({ session, keepCookies: true })
        if (ua) this._ua = ua

        if (this._isRegionBlocked(html, finalUrl)) throw this._regionError()
        if (!html) throw new Error('验证后仍未取到页面内容')
        return { html, finalUrl }
    }

    // ============================================================
    // 解析工具
    // ============================================================

    _pickTitle(doc) {
        const img = doc.querySelector('img.mask-this2')
        if (img && img.attributes && img.attributes.alt && img.attributes.alt.trim()) {
            return img.attributes.alt.trim()
        }
        const h3 = doc.querySelector('.slide-info-title')
        if (h3 && h3.text && h3.text.trim()) return h3.text.trim()
        return ''
    }

    _pickCover(doc) {
        const img = doc.querySelector('img.mask-this2')
        if (!img || !img.attributes) return ''
        const src = img.attributes['data-src'] || img.attributes['data-original'] || img.attributes.src || ''
        if (!src || src.indexOf('data:image') === 0) return ''
        return this._abs(src)
    }

    _pickDesc(doc) {
        // `.vod-detail` 是**整个详情头部包裹层**（海报+标题+播放数+年份+导演+20 位演员+
        // 类型+评分条+#标签，实测 497 字），而 UI 只渲染 maxLines:6 ≈150-200 字 →
        // 用户只会看到演职员表。真正的简介容器是 `#height_limit`（`.text.cor3`）。
        const el = doc.querySelector('#height_limit') || doc.querySelector('.vod-detail #height_limit') || doc.querySelector('.vod-detail')
        if (!el || !el.text) return ''
        return String(el.text).replace(/\s+/g, ' ').trim()
    }

    /// 解析剧集：优先按线路分组（多个 ul.anthology-list-play），兜底整页找 /playGV{id}- 链接
    _parseSources(doc, id) {
        const sources = []
        const groups = doc.xpathQueryAll("//ul[contains(@class,'anthology-list-play')]")
        let idx = 0
        for (const ul of groups) {
            idx++
            const episodes = []
            const anchors = ul.querySelectorAll('a')
            let n = 0
            for (const a of anchors) {
                const href = (a.attributes && a.attributes.href) || a.getAttribute('href') || ''
                if (!href) continue
                n++
                episodes.push({
                    name: (a.text || '').trim() || ('第 ' + n + ' 集'),
                    type: 'page',
                    url: this._abs(href),
                })
            }
            if (episodes.length) sources.push({ name: '线路 ' + idx, episodes })
        }
        if (!sources.length) {
            const anchors = doc.querySelectorAll('a[href*="/playGV' + id + '-"]')
            const episodes = []
            let n = 0
            for (const a of anchors) {
                const href = (a.attributes && a.attributes.href) || ''
                if (!href) continue
                n++
                episodes.push({
                    name: (a.text || '').trim() || ('第 ' + n + ' 集'),
                    type: 'page',
                    url: this._abs(href),
                })
            }
            if (episodes.length) sources.push({ name: '默认线路', episodes })
        }
        return sources
    }

    _card(id, title, cover) {
        return UI.Card({
            elevation: 0,
            shapeRadius: 16,
            color: '@theme:surfaceContainerLow',
            padding: 4,
            child: UI.Row({
                crossAxisAlignment: 'start',
                children: [
                    cover ? UI.Image({ src: cover, width: 80, height: 116 }) : null,
                    UI.SizedBox({ width: 12 }),
                    UI.Expanded({
                        child: UI.Column({
                            crossAxisAlignment: 'start',
                            children: [
                                UI.Text({ content: title, style: { fontSize: 14, weight: 'bold' }, maxLines: 2 }),
                                UI.Text({
                                    content: '点击右侧按钮查看剧集',
                                    style: { fontSize: 12, color: '#888888' },
                                    maxLines: 1,
                                }),
                            ],
                        }),
                    }),
                    UI.SizedBox({ width: 8 }),
                    UI.IconButton({
                        icon: 'play_circle_filled',
                        tooltip: '查看剧集',
                        color: '#e53935',
                        size: 20,
                        onTap: UI.Navigate({
                            page: 'descriptor',
                            method: 'getDetail',
                            args: [id],
                            title: title,
                        }),
                    }),
                ].filter((x) => x != null),
            }),
        })
    }

    // ============================================================
    // 插件接口
    // ============================================================

    async search(keyword, page = 1) {
        if (!keyword) return []
        // suggest 接口不分页：只有第一页有结果
        if (page > 1) return []
        const url = this.baseUrl + '/index.php/ajax/suggest?mid=1&wd=' + encodeURIComponent(keyword)
        const headers = this._headers()
        const extra = { timeout: 15000, retries: 1, session: this._sessionKey() }
        let text = ''
        try {
            text = await Network.get(url, headers, extra)
        } catch (e) {
            const kind = e && e.kind ? String(e.kind) : ''
            const status2 = e && typeof e.status === 'number' ? e.status : 0
            const msg = e && e.message ? e.message : String(e)
            console.log('[girigirilove] 搜索接口失败 kind=' + kind + ' status=' + status2 + '：' + msg)
            // 只有「HTTP 层风控信号」才值得过一遍验证再重试；超时/连接/DNS 都不是验证码问题
            const httpChallenge = kind === 'http' && (status2 === 403 || status2 === 429 || status2 >= 500)
            if (!httpChallenge || !this._captchaEnabled()) {
                Dialog.showToast('搜索失败：' + msg)
                return []
            }
            // HTTP 层失败时先过一遍验证再重试一次（clearance cookie 是域级的，覆盖 API）
            try {
                await this._passCaptcha(this.baseUrl + '/', this._sessionKey())
                text = await Network.get(url, headers, extra)
            } catch (e2) {
                Dialog.showToast('搜索失败：' + (e2 && e2.message ? e2.message : String(e2)))
                return []
            }
        }
        if (!this._hasExpectedContent(text, 'json')) {
            Dialog.showToast('搜索返回异常（可能被风控或站点改版）')
            return []
        }
        let json = null
        try {
            json = JSON.parse(text)
        } catch (e) {
            Dialog.showToast('搜索返回不是合法 JSON（可能被风控）')
            return []
        }
        const list = (json && json.list) || []
        const cards = []
        for (const it of list) {
            const id = String(it.id || '')
            if (!id) continue
            cards.push(this._card(id, it.name || '', this._abs(it.pic || '')))
        }
        if (!cards.length) Dialog.showToast('未找到相关结果')
        return cards
    }

    async getDetail(id) {
        const detailUrl = this.baseUrl + '/GV' + id + '/'
        let html = ''
        try {
            const r = await this._fetchText(detailUrl, {
                referer: this.baseUrl + '/',
                session: this._sessionKey(),
                expect: 'detail',
            })
            html = r.html
        } catch (e) {
            const msg = e && e.message ? e.message : String(e)
            console.log('[girigirilove] 获取详情失败:', msg)
            Dialog.showToast('获取详情失败：' + msg)
            return []
        }
        const doc = new HtmlDocument(html)
        const title = this._pickTitle(doc) || ('剧集 ' + id)
        const cover = this._pickCover(doc)
        const desc = this._pickDesc(doc)
        const sources = this._parseSources(doc, id)
        doc.dispose()

        this._playSources = { videoId: String(id), title: title, cover: cover, sources: sources }
        try {
            PluginBrowse.open('girigirilove', { id: String(id), title: title, cover: cover, kv: { id: String(id) } })
        } catch (e) {
            console.log('[girigirilove] 记录浏览历史失败（忽略）:', e && e.message ? e.message : e)
        }

        const epCount = sources.reduce((n, s) => n + s.episodes.length, 0)
        if (!epCount) Dialog.showToast('未解析到剧集：站点结构可能改版，或当前网络被风控/地区封锁')

        const items = []
        items.push(UI.Card({
            padding: 12,
            shapeRadius: 8,
            child: UI.Row({
                crossAxisAlignment: 'start',
                children: [
                    cover ? UI.Image({ src: cover, width: 110, height: 150 }) : null,
                    UI.SizedBox({ width: 12 }),
                    UI.Expanded({
                        child: UI.Column({
                            crossAxisAlignment: 'start',
                            children: [
                                UI.Text({ content: title, style: { fontSize: 16, weight: 'bold' }, maxLines: 2 }),
                                UI.Text({
                                    content: '线路 ' + sources.length + ' · 剧集 ' + epCount,
                                    style: { fontSize: 12, color: '#888888' },
                                    maxLines: 1,
                                }),
                            ],
                        }),
                    }),
                ].filter((x) => x != null),
            }),
        }))

        if (desc) {
            items.push(UI.Card({
                padding: 12,
                shapeRadius: 8,
                child: UI.Text({
                    content: desc,
                    style: { fontSize: 13, color: '#555555' },
                    maxLines: 6,
                }),
            }))
        }

        for (let i = 0; i < sources.length; i++) {
            const src = sources[i]
            items.push(UI.ExpansionTile({
                title: UI.Text({
                    content: src.name + '（' + src.episodes.length + '）',
                    style: { fontSize: 14, weight: 'bold' },
                    maxLines: 1,
                }),
                initiallyExpanded: i === 0,
                shapeRadius: 0,
                children: [
                    UI.Container({
                        padding: 8,
                        child: UI.Wrap({
                            spacing: 6,
                            runSpacing: 6,
                            children: src.episodes.map((ep) => UI.Button({
                                label: ep.name,
                                style: 'text',
                                onTap: UI.Action({ method: 'play', args: [ep.url, title, cover] }),
                            })),
                        }),
                    }),
                ],
            }))
        }
        return items
    }

    async play(url, title, cover) {
        const cached = this._playSources
        const m = String(url || '').match(/\/playGV(\d+)-/)
        // 只有在"缓存确实属于这部剧"且能找到该集时才用整部 sources。
        // 否则（历史/收藏入口、跨剧调用）会静默播成上一部剧的第 1 集（核验发现的 bug）。
        if (cached && cached.sources && cached.sources.length && m && cached.videoId === m[1]) {
            let si = 0
            let ei = 0
            let found = false
            for (let i = 0; i < cached.sources.length && !found; i++) {
                const eps = cached.sources[i].episodes || []
                for (let j = 0; j < eps.length; j++) {
                    if (eps[j].url === url) {
                        si = i
                        ei = j
                        found = true
                        break
                    }
                }
            }
            if (found) {
                Navigator.navigateToVideo({
                    videoId: cached.videoId,
                    title: title || cached.title,
                    cover: cover || cached.cover,
                    sourceKey: 'girigirilove',
                    initialSource: si,
                    initialEpisode: ei,
                    sources: cached.sources,
                })
                return
            }
        }
        // 无缓存 / 缓存不属于该剧 / 该集不在缓存里：单集直接交给播放器（页面嗅探，直链直出）
        const isDirect = /\.(m3u8|mp4|flv)(\?|$)/i.test(String(url || ''))
        Navigator.navigateToVideo({
            videoId: m ? m[1] : String(url || ''),
            title: title || url || '',
            cover: cover || '',
            sourceKey: 'girigirilove',
            initialSource: 0,
            initialEpisode: 0,
            sources: [{
                name: '默认线路',
                episodes: [{ name: title || '播放', url: url, type: isDirect ? 'direct' : 'page' }],
            }],
        })
    }

    /// 惰性形态（episodes.type='resolve'）的兜底：本站交给 wyw 嗅探即可
    async resolvePlayUrl(url) {
        return { url: url, type: 'page' }
    }
}
