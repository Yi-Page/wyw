// description: 包子漫画（BaoziMH）漫画源 — 搜索/分类/详情/章节/阅读
// type: manga
//
// 接口约定：
//   search(keyword, page)  → List<UI.Card>
//   getDetail(id)          → List<UI>（头部 + 简介 + 章节列表）
//   openReader(epId)       → Navigator.navigateToReader（章节惰性加载）
//   loadChapterImages(comicId, epId) → 该章图片 URL 数组
//   getCategory / getCategoryOptions / loadCategory / loadCategoryPage — 分类浏览（分页容器）
//   onOpenBrowseEntry(entry) → 浏览历史回放
//
// 站点现状（2026-10 实测）与 venera 版（v1.1.6）的差异：
//   - 全站（cn.bzmgcn.com 及阅读域 cn.cnbzmg.com）前面多了一层 gatekeeper
//     「正在验证浏览器」挑战：首次访问返回 403 + challenge_url，需要做
//     SHA-256 工作量证明（difficultyBits=16），POST /__gatekeeper_challenge/verify
//     换到 __Host-gk_clearance_* Cookie 后才能访问。venera 版没有处理这层，
//     直接 Network.get 会 403 —— 这是本移植版「很多路径不能用」的根因。
//     本版在插件内用纯 JS 实现 PoW（不依赖 WebView、不跨 JS→Dart 桥），
//     通过后 Cookie 由框架 Cookie 罐自动保存，后续请求自动携带。
//   - venera 的章节接口 appcn.baozimh.com/baozimhapp/... 已被 Cloudflare 完全
//     挡住（Just a moment...），改用网页版章节页：
//     /user/page_direct → 302 → cn.cnbzmg.com/comic/chapter/<id>/0_<slot>.html
//   - 章节列表拆在 #chapter-items 与 #chapters_other_list 两个容器里（各约 24 /
//     210 条），按 slot 升序拼接即为完整目录。
//   - 多页章节标题带「(1/2)」，后续页 URL 为 0_<slot>_2.html。
//
// 说明：
//   - Network.get 直接返回 body 字符串，非 2xx 由框架抛异常（带 status/body）；
//     需要看状态码/响应头时用 Network.sendRequest。
//   - 章节以 chapter_slot 作为 epId（列表索引 ≠ 站点 slot，必须从链接取），
//     图片经 /user/page_direct 重定向到站点章节页解析（域名/路径由站点决定）。
//   - 图片 CDN 支持 /w640 质量前缀（返回 webp，体积约为原图 1/4），
//     由设置项「图片质量」控制；防盗链 Referer 用最近一次章节页检测到的阅读域。

class baozi extends PluginSource {
    name = '包子漫画'
    key = 'baozi'
    version = '1.2.0'

    // 浏览器 UA：站点对非浏览器 UA 会直接 403（Dio 默认 Dart/x 也会被拦）
    ua = 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'

    settings = {
        language: {
            title: '简繁切换',
            type: 'select',
            options: [
                { value: 'cn', text: '简体' },
                { value: 'tw', text: '繁體' },
            ],
            default: 'cn',
        },
        domains: {
            title: '主域名',
            type: 'select',
            options: [
                { value: 'bzmgcn.com', text: 'bzmgcn.com' },
                { value: 'baozimhcn.com', text: 'baozimhcn.com' },
                { value: 'webmota.com', text: 'webmota.com' },
                { value: 'kukuc.co', text: 'kukuc.co' },
                { value: 'twmanga.com', text: 'twmanga.com' },
                { value: 'dinnerku.com', text: 'dinnerku.com' },
            ],
            default: 'bzmgcn.com',
        },
        cdn_domains: {
            title: '图片资源站域名',
            type: 'select',
            options: [
                { value: 'as-rsa1-usla.baozicdn.com', text: 'as-rsa1-usla' },
                { value: 'ascn-a3.bzcdn.net', text: 'ascn-a3' },
                { value: 'asgb-a3.bzcdn.net', text: 'asgb-a3' },
                { value: 'as.baozimh.com', text: 'as' },
                { value: 's1.baozicdn.com', text: 's1' },
                { value: '', text: '默认' },
            ],
            default: '',
        },
        image_quality: {
            title: '图片质量',
            type: 'select',
            options: [
                { value: '/w640', text: '640p' },
                { value: '', text: '原图' },
            ],
            default: '/w640',
        },
        reader_domain: {
            title: '图片防盗链 Referer 域名',
            type: 'input',
            default: 'cn.cnbzmg.com',
        },
    }

    // 分类名 → 接口 type 参数（venera 的 categoryParams）
    static categoryMap = {
        '全部': 'all',
        '恋爱': 'lianai',
        '纯爱': 'chunai',
        '古风': 'gufeng',
        '异能': 'yineng',
        '悬疑': 'xuanyi',
        '剧情': 'juqing',
        '科幻': 'kehuan',
        '奇幻': 'qihuan',
        '玄幻': 'xuanhuan',
        '穿越': 'chuanyue',
        '冒险': 'mouxian',
        '推理': 'tuili',
        '武侠': 'wuxia',
        '格斗': 'gedou',
        '战争': 'zhanzheng',
        '热血': 'rexie',
        '搞笑': 'gaoxiao',
        '大女主': 'danuzhu',
        '都市': 'dushi',
        '总裁': 'zongcai',
        '后宫': 'hougong',
        '日常': 'richang',
        '韩漫': 'hanman',
        '少年': 'shaonian',
        '其它': 'qita',
    }

    // SHA-256 轮常量（FIPS 180-4）
    static _K = new Int32Array([
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ])

    // 运行时缓存（getDetail 时填充，openReader / loadChapterImages 复用）
    _comicId = ''
    _comicTitle = ''
    _chapters = []
    /// 最近一次章节页实际所在的 reader 域（canonical 动态检测，供图片防盗链 Referer 用）
    _readerHost = ''

    get lang() {
        return this.loadSetting('language') || 'cn'
    }

    get baseUrl() {
        let domain = this.loadSetting('domains') || 'bzmgcn.com'
        return 'https://' + this.lang + '.' + domain
    }

    get imageQuality() {
        let q = this.loadSetting('image_quality')
        // 注意：'原图' 对应的值是空串，不能用 `||` 兜底，仅在未设置时回退默认
        return (q === null || q === undefined) ? '/w640' : q
    }

    /// 源网站地址（插件管理页「网站」菜单调用）
    getUrl() {
        return this.baseUrl
    }

    // ============ 工具 ============

    /// 相对地址 → 绝对地址
    _absUrl(url) {
        if (!url) return ''
        if (url.startsWith('http://') || url.startsWith('https://')) return url
        if (url.startsWith('//')) return 'https:' + url
        return this.baseUrl + url
    }

    /// 取 URL 的 origin（协议 + 域名），失败返回 baseUrl
    _origin(u) {
        const m = u && u.match(/^(https?:\/\/[^/]+)/)
        return m ? m[1] : this.baseUrl
    }

    /// 以 base 为基准解析相对地址（不依赖 URL 全局对象）
    _resolveUrl(loc, base) {
        if (!loc) return base
        if (loc.startsWith('http://') || loc.startsWith('https://')) return loc
        if (loc.startsWith('//')) return 'https:' + loc
        const origin = this._origin(base)
        if (loc.startsWith('/')) return origin + loc
        return origin + '/' + loc
    }

    /// 取 URL 的 host（含端口），失败返回空串
    _extractHost(u) {
        const m = u && u.match(/^https?:\/\/([^/]+)/)
        return m ? m[1] : ''
    }

    /// 通用请求头（浏览器 UA + 来源页），所有 Network 请求统一携带
    get baseHeaders() {
        return {
            'User-Agent': this.ua,
            'Referer': this.baseUrl + '/',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
            'Accept-Language': this.lang === 'tw' ? 'zh-TW,zh;q=0.9' : 'zh-CN,zh;q=0.9',
        }
    }

    // ============ 网络层：重定向 + gatekeeper 浏览器验证 ============

    /// 单次请求（不抛异常，统一返回 {status, headers, body} 或抛结构化 Error）
    async _send(method, url, headers, data, extra) {
        const opt = Object.assign({ timeout: 30000 }, extra || {})
        return await Network.sendRequest(method, url, headers, data, opt)
    }

    /// GET：自动跟随 302（手动跳转，便于逐域过 gatekeeper），并在 403 时尝试过验证。
    async _get(url, headers) {
        let current = url
        for (let hop = 0; hop < 6; hop++) {
            let res = null
            try {
                res = await this._send('GET', current, headers, null, { redirect: 'manual' })
            } catch (e) {
                // 框架把 3xx 也当非 2xx 抛出：从 e.headers.location 拿跳转目标
                if (e && e.status >= 300 && e.status < 400) {
                    const loc = e.headers && (e.headers.location || e.headers.Location)
                    if (loc) {
                        current = this._resolveUrl(loc, current)
                        continue
                    }
                }
                if (e && e.status === 403 && await this._passGatekeeper(current, headers, e)) {
                    continue
                }
                throw e
            }
            // 部分实现（如命令行测试台）会把 3xx 当成功返回，这里同样跟随
            if (res.status >= 300 && res.status < 400) {
                const loc = res.headers && (res.headers.location || res.headers.Location)
                if (loc) {
                    current = this._resolveUrl(loc, current)
                    continue
                }
            }
            return {
                status: res.status,
                headers: res.headers,
                body: res.body,
                finalUrl: res.finalUrl || current,
            }
        }
        throw '重定向次数过多: ' + url
    }

    /// 过 gatekeeper 的「正在验证浏览器」挑战（SHA-256 PoW）。
    ///
    /// 流程：403 响应（Accept: application/json 时是 JSON）里拿 challenge_url →
    /// 打开挑战页拿 challengeId / ticket / verifyUrl / difficultyBits →
    /// 本地算 nonce（SHA-256 前缀 = "gatekeeper-pow-v1:<id>:<nonce>"，前导零 ≥ bits）→
    /// POST verify，服务端下发 __Host-gk_clearance_* Cookie（框架自动保存）→ 重试原请求。
    async _passGatekeeper(url, headers, err) {
        const origin = this._origin(url)
        let challengeUrl = ''
        try {
            const j = JSON.parse((err && err.body) || '')
            if (j && j.challenge_url) challengeUrl = j.challenge_url
        } catch (e) { /* 非 JSON：通常是 HTML 挑战页（框架截断到 2000 字），下面换 Accept 重取 */ }
        if (!challengeUrl) {
            try {
                const res = await this._send(
                    'GET', url,
                    Object.assign({}, headers, { 'Accept': 'application/json' }),
                    null, { redirect: 'manual' })
                // 已经能正常返回（例如 Cookie 刚生效）→ 无需验证
                if (res && res.status >= 200 && res.status < 300) return true
            } catch (e2) {
                try {
                    const j = JSON.parse((e2 && e2.body) || '')
                    if (j && j.challenge_url) challengeUrl = j.challenge_url
                } catch (e3) { /* ignore */ }
            }
        }
        if (!challengeUrl) return false

        const startUrl = this._resolveUrl(challengeUrl, origin)
        let start = null
        try {
            start = await this._send('GET', startUrl, headers, null, { timeout: 30000 })
        } catch (e) {
            return false
        }
        const html = (start && start.body) || ''
        const pick = (re) => { const m = html.match(re); return m ? m[1] : '' }
        const challengeId = pick(/challengeId:"([^"]+)"/)
        const ticket = pick(/ticket:"([^"]+)"/)
        const verifyUrl = pick(/verifyUrl:"([^"]+)"/)
        const bits = parseInt(pick(/difficultyBits:(\d+)/) || '16', 10)
        if (!challengeId || !ticket || !verifyUrl) return false

        const nonce = this._powNonce(challengeId, bits)
        if (!nonce) return false
        const payload = JSON.stringify({
            challenge_id: challengeId,
            ticket: ticket,
            nonce: nonce,
        })
        let vr = null
        try {
            vr = await this._send('POST', this._resolveUrl(verifyUrl, origin), {
                'Content-Type': 'application/json',
                'Accept': '*/*',
                'Origin': origin,
                'Referer': origin + '/',
            }, payload, { timeout: 30000 })
        } catch (e) {
            return false
        }
        try {
            const j = JSON.parse((vr && vr.body) || '{}')
            return !!(j && j.status === 'passed')
        } catch (e) {
            return false
        }
    }

    /// ASCII 字符串 → 字节数组（挑战前缀与 nonce 都是 ASCII，无需 TextEncoder）
    _ascii(s) {
        const out = new Uint8Array(s.length)
        for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i) & 0xff
        return out
    }

    /// 前导零位数（按 SHA-256 摘要的大端字节序）
    _leadingZeroBits(h) {
        let n = 0
        for (let i = 0; i < 8; i++) {
            const x = h[i]
            if (x === 0) { n += 32; continue }
            for (let bit = 31; bit >= 0; bit--) {
                if (((x >>> bit) & 1) === 0) n++
                else return n
            }
        }
        return n
    }

    /// SHA-256 压缩函数：处理 b[o..o+64) 一个块，更新状态 h（Int32Array(8)）
    _sha256Block(h, b, o, w) {
        const K = baozi._K
        for (let i = 0; i < 16; i++) {
            const j = o + i * 4
            w[i] = (b[j] << 24) | (b[j + 1] << 16) | (b[j + 2] << 8) | b[j + 3]
        }
        for (let i = 16; i < 64; i++) {
            const x = w[i - 15]
            const y = w[i - 2]
            const s0 = ((x >>> 7) | (x << 25)) ^ ((x >>> 18) | (x << 14)) ^ (x >>> 3)
            const s1 = ((y >>> 17) | (y << 15)) ^ ((y >>> 19) | (y << 13)) ^ (y >>> 10)
            w[i] = (w[i - 16] + s0 + w[i - 7] + s1) | 0
        }
        let a = h[0], bb = h[1], c = h[2], d = h[3]
        let e = h[4], f = h[5], g = h[6], hh = h[7]
        for (let i = 0; i < 64; i++) {
            const S1 = ((e >>> 6) | (e << 26)) ^ ((e >>> 11) | (e << 21)) ^ ((e >>> 25) | (e << 7))
            const ch = (e & f) ^ (~e & g)
            const t1 = (hh + S1 + ch + K[i] + w[i]) | 0
            const S0 = ((a >>> 2) | (a << 30)) ^ ((a >>> 13) | (a << 19)) ^ ((a >>> 22) | (a << 10))
            const maj = (a & bb) ^ (a & c) ^ (bb & c)
            const t2 = (S0 + maj) | 0
            hh = g; g = f; f = e; e = (d + t1) | 0
            d = c; c = bb; bb = a; a = (t1 + t2) | 0
        }
        h[0] = (h[0] + a) | 0
        h[1] = (h[1] + bb) | 0
        h[2] = (h[2] + c) | 0
        h[3] = (h[3] + d) | 0
        h[4] = (h[4] + e) | 0
        h[5] = (h[5] + f) | 0
        h[6] = (h[6] + g) | 0
        h[7] = (h[7] + hh) | 0
    }

    /// 计算满足 difficultyBits 前导零的 nonce（十进制字符串），失败返回空串。
    ///
    /// 优化：挑战前缀固定 84 字节（"gatekeeper-pow-v1:" + 64 位 hex + ":"），
    /// 先算出第一个 64 字节块的中间状态，之后每个 nonce 只需再压缩一个块。
    _powNonce(challengeId, bits) {
        const prefix = 'gatekeeper-pow-v1:' + challengeId + ':'
        const pre = this._ascii(prefix)
        const st = new Int32Array([
            0x6a09e667 | 0, 0xbb67ae85 | 0, 0x3c6ef372 | 0, 0xa54ff53a | 0,
            0x510e527f | 0, 0x9b05688c | 0, 0x1f83d9ab | 0, 0x5be0cd19 | 0,
        ])
        const w = new Int32Array(64)
        let off = 0
        while (off + 64 <= pre.length) {
            this._sha256Block(st, pre, off, w)
            off += 64
        }
        const tailLen = pre.length - off
        const block = new Uint8Array(64)
        const h = new Int32Array(8)
        for (let n = 0; n < 3000000; n++) {
            const nonce = String(n)
            const total = pre.length + nonce.length
            for (let i = 0; i < 64; i++) block[i] = 0
            for (let i = 0; i < tailLen; i++) block[i] = pre[off + i]
            let p = tailLen
            for (let i = 0; i < nonce.length; i++) block[p++] = nonce.charCodeAt(i) & 0xff
            block[p] = 0x80
            const bitsLen = total * 8
            block[63] = bitsLen & 0xff
            block[62] = (bitsLen >>> 8) & 0xff
            block[61] = (bitsLen >>> 16) & 0xff
            block[60] = (bitsLen >>> 24) & 0xff
            for (let i = 0; i < 8; i++) h[i] = st[i]
            this._sha256Block(h, block, 0, w)
            if (this._leadingZeroBits(h) >= bits) return nonce
        }
        return ''
    }

    // ============ 解析 ============

    /// 从章节链接里取站点 chapter_slot（优先 chapter_slot=，其次 0_<slot>.html）
    _extractSlot(href) {
        if (!href) return null
        let m = href.match(/chapter_slot=(\d+)/)
        if (m) return m[1]
        m = href.match(/\/(\d+)_(\d+)(?:_\d+)?\.html/)
        if (m) return m[2]
        return null
    }

    /// 解析 HTML 列表中的漫画卡片（搜索页结构）
    parseComic(e) {
        const a = e.querySelector('a')
        const url = (a && a.attributes['href']) || ''
        const id = url.split('/').pop()
        const h3 = e.querySelector('h3')
        const title = h3 ? h3.text.trim() : ''
        const img = e.querySelector('a > amp-img') || e.querySelector('amp-img')
        const cover = img ? (img.attributes['src'] || '') : ''
        let tags = []
        try {
            tags = e.querySelectorAll('div.tabs > span').map((x) => x.text.trim()).filter((x) => x)
        } catch (err) { /* 结构变化时忽略标签 */ }
        let description = ''
        const small = e.querySelector('small')
        if (small) description = small.text.trim()
        return {
            id: id,
            title: title,
            cover: cover,
            tags: tags,
            description: description,
        }
    }

    /// 解析 JSON 列表中的漫画（分类接口结构）
    parseJsonComic(e) {
        const img = e.topic_img || ''
        return {
            id: e.comic_id,
            title: e.name,
            subTitle: e.author,
            cover: img
                ? 'https://static-tw.bzmgcn.com/cover/' + img + '?w=285&h=375&q=100'
                : '',
            tags: e.type_names || [],
        }
    }

    /// 构造结果卡片（搜索/分类共用，参照 jm）
    _comicCard(c) {
        let metaLines = []
        if (c.subTitle) metaLines.push(c.subTitle)
        if (c.tags && c.tags.length > 0) metaLines.push(c.tags.slice(0, 4).join('、'))
        if (c.description) metaLines.push(c.description)
        return UI.Card({
            elevation: 0,
            shapeRadius: 16,
            color: '@theme:surfaceContainerLow',
            padding: 4,
            child: UI.Row({
                crossAxisAlignment: 'start',
                children: [
                    c.cover ? UI.Image({ src: c.cover, width: 80, height: 116 }) : null,
                    UI.SizedBox({ width: 12 }),
                    UI.Expanded({
                        child: UI.Column({
                            crossAxisAlignment: 'start',
                            mainAxisAlignment: 'start',
                            children: [
                                UI.Text({ content: c.title, style: { fontSize: 14, weight: 'bold' }, maxLines: 2 }),
                                ...metaLines.map((m) => UI.Text({ content: m, style: { fontSize: 12, color: '#888888' }, maxLines: 1 })),
                            ].filter((x) => x != null),
                        }),
                    }),
                    UI.SizedBox({ width: 8 }),
                    UI.IconButton({
                        icon: 'open_in_new',
                        tooltip: '详情',
                        color: '#666666',
                        size: 20,
                        onTap: UI.Navigate({
                            page: 'descriptor',
                            method: 'getDetail',
                            args: [c.id],
                            title: c.title,
                        }),
                    }),
                ].filter((x) => x != null),
            }),
        })
    }

    // ============ 搜索 ============

    async search(keyword, page = 1) {
        const url = this.baseUrl + '/search?q=' + encodeURIComponent(keyword)
        let html
        try {
            html = (await this._get(url, this.baseHeaders)).body
        } catch (e) {
            Dialog.showToast('搜索请求失败: ' + e)
            console.error('搜索请求失败: ' + e)
            return []
        }
        if (!html) return []
        const doc = new HtmlDocument(html)
        const cards = []
        for (const item of doc.querySelectorAll('div.comics-card')) {
            try {
                const c = this.parseComic(item)
                if (!c.id) continue
                c.cover = this._absUrl(c.cover)
                cards.push(this._comicCard(c))
            } catch (err) {
                continue
            }
        }
        doc.dispose()
        if (cards.length === 0 && page <= 1) {
            Dialog.showToast('未找到结果，请检查关键词')
        }
        return cards
    }

    // ============ 分类浏览 ============

    /// 分类结构（venera 的 category）
    getCategory() {
        return {
            title: '包子漫画',
            parts: [
                {
                    name: '类型',
                    categories: Object.keys(baozi.categoryMap),
                },
            ],
        }
    }

    /// 分类筛选选项（venera 的 optionLoader 对应）
    getCategoryOptions(category) {
        return [
            {
                label: '地区',
                options: [
                    { value: 'all', text: '全部' },
                    { value: 'cn', text: '国漫' },
                    { value: 'jp', text: '日本' },
                    { value: 'kr', text: '韩国' },
                    { value: 'en', text: '欧美' },
                ],
            },
            {
                label: '状态',
                options: [
                    { value: 'all', text: '全部' },
                    { value: 'serial', text: '连载中' },
                    { value: 'pub', text: '已完结' },
                ],
            },
        ]
    }

    /// 请求分类列表并解析（venera 的 categoryComics.load 逻辑）
    /// 返回 `{comics, maxPage}`，供 loadCategory / loadCategoryPage 共用
    async _fetchCategoryComics(category, page = 1, options = []) {
        const param = baozi.categoryMap[category] || 'all'
        const region = (options && options.length > 0) ? options[0] : 'all'
        const state = (options && options.length > 1) ? options[1] : 'all'
        const limit = 36
        const url = this.baseUrl + '/api/bzmhq/amp_comic_list' +
            '?type=' + param +
            '&region=' + region +
            '&state=' + state +
            '&filter=%2a' +
            '&page=' + page +
            '&limit=' + limit +
            '&language=' + this.lang +
            '&__amp_source_origin=' + encodeURIComponent(this.baseUrl)
        let html
        try {
            html = (await this._get(url, this.baseHeaders)).body
        } catch (e) {
            Dialog.showToast('分类请求失败: ' + e)
            console.error('分类请求失败: ' + e)
            return { comics: [], maxPage: page }
        }
        let json
        try {
            json = JSON.parse(html)
        } catch (e) {
            console.error('分类响应解析失败: ' + e)
            return { comics: [], maxPage: page }
        }
        const items = json.items || []
        let maxPage
        let total = json.total
        if (total == null) total = json.count
        if (total == null) total = json.total_count
        if (typeof total === 'number' && total > 0) {
            maxPage = Math.max(1, Math.ceil(total / limit))
        } else if (!json.next) {
            // 没有下一页：当前页即最后一页
            maxPage = page
        } else {
            // 接口只返回 next 标记、无总页数：给一个上限，翻到空页时由框架兜底
            maxPage = 200
        }
        return { comics: items.map((e) => this.parseJsonComic(e)), maxPage: maxPage }
    }

    /// 加载某分类第一页：返回分页容器（分页控制 + 声明单页数据来源）。
    async loadCategory(category, page = 1, options = []) {
        const { maxPage } = await this._fetchCategoryComics(category, page, options)
        return [
            UI.Pagination({
                page: page,
                maxPage: maxPage,
                pageMethod: 'loadCategoryPage',
                pageArgs: [category, 1, options],
            }),
        ]
    }

    /// 加载某分类指定页：返回**单纯的结果列表**（UI.Pagination 换页时调用）。
    async loadCategoryPage(category, page = 1, options = []) {
        const { comics } = await this._fetchCategoryComics(category, page, options)
        return comics.map((e) => this._comicCard(e))
    }

    // ============ 详情 ============

    async getDetail(id) {
        let html
        try {
            html = (await this._get(this.baseUrl + '/comic/' + id, this.baseHeaders)).body
        } catch (e) {
            Dialog.showToast('详情请求失败: ' + e)
            console.error('详情请求失败: ' + e)
            return []
        }
        if (!html) return []
        const doc = new HtmlDocument(html)

        // 标题
        let titleEl = doc.querySelector('h1.comics-detail__title')
        let title = titleEl ? titleEl.text.trim() : ''
        if (!title) {
            const t = html.match(/<title>([^<]*)<\/title>/)
            title = t ? t[1].replace(/\s*-\s*包子漫画\s*$/, '').trim() : String(id)
        }

        // 封面（多级兜底）
        let cover = ''
        let coverImg = doc.querySelector('div.l-content > div > div > amp-img')
        if (!coverImg) coverImg = doc.querySelector('amp-img')
        if (coverImg) cover = coverImg.attributes['src'] || ''
        cover = this._absUrl(cover)

        // 作者
        let author = ''
        let authorEl = doc.querySelector('h2.comics-detail__author')
        if (authorEl) author = authorEl.text.trim()

        // 标签
        let tags = []
        for (const e of doc.querySelectorAll('div.tag-list > span')) {
            let t = e.text.trim()
            if (t) tags.push(t)
        }

        // 更新时间（Y年 M月 D日 → Y-M-D；兜底取最后一话标题）
        let updateTime = ''
        let em = doc.querySelector('div.supporting-text > div > span > em')
        if (em) {
            updateTime = em.text.trim().replace('(', '').replace(')', '')
        }
        if (!updateTime) {
            const containers = doc.querySelectorAll('#chapter-items, #chapters_other_list')
            let last = null
            for (const container of containers) {
                const chapters = container.querySelectorAll('.comics-chapters > a')
                for (const ch of chapters) last = ch
            }
            if (last) {
                let span = last.querySelector('div > span')
                updateTime = span ? span.text.trim() : ''
            }
        }
        let updateDate = updateTime
            .replace(/年/g, '-')
            .replace(/月/g, '-')
            .replace(/日/g, '')
            .replace(/\s*更新\s*/g, '')

        // 简介
        let description = ''
        let descEl = doc.querySelector('p.comics-detail__desc')
        if (descEl) description = descEl.text.trim()

        // 章节：以 chapter_slot 作为 epId（列表索引 ≠ 站点 slot，必须从链接取），
        // 并保存 page_direct 链接供 loadChapterImages 使用。
        // 目录拆在两个容器：主列表（前 ~24 话）+ 隐藏的完整列表（其余），按顺序拼接。
        let chapters = []
        let seenSlots = new Set()
        const pushBlock = (selector) => {
            for (const a of doc.querySelectorAll(selector)) {
                const href = a.getAttribute('href') || ''
                const slot = this._extractSlot(href)
                if (slot === null) continue
                if (seenSlots.has(slot)) continue
                seenSlots.add(slot)
                const span = a.querySelector('div > span')
                const ctitle = span ? span.text.trim() : (a.text || '').trim()
                chapters.push({ id: slot, title: ctitle || ('第' + slot + '话'), url: href })
            }
        }
        pushBlock('div#chapter-items > div.comics-chapters > a')
        pushBlock('div#chapters_other_list > div.comics-chapters > a')
        if (chapters.length === 0) {
            // 主/次列表均未匹配：取全部章节链接（站点最新在前，反转成升序）
            const anchors = doc.querySelectorAll('div.comics-chapters > a').reverse()
            for (const a of anchors) {
                const href = a.getAttribute('href') || ''
                const slot = this._extractSlot(href)
                if (slot === null || seenSlots.has(slot)) continue
                seenSlots.add(slot)
                const span = a.querySelector('div > span')
                const ctitle = span ? span.text.trim() : (a.text || '').trim()
                chapters.push({ id: slot, title: ctitle || ('第' + slot + '话'), url: href })
            }
        }

        // 相关推荐（旧版页面结构，可能为空，容错处理）
        let recommend = []
        try {
            for (const c of doc.querySelectorAll('div.recommend--item')) {
                if (c.querySelectorAll('div.tag-comic').length > 0) {
                    let titleEl2 = c.querySelector('span')
                    let aEl = c.querySelector('a')
                    if (!titleEl2 || !aEl) continue
                    let rTitle = titleEl2.text.trim()
                    let rImg = c.querySelector('amp-img')
                    let rCover = rImg ? rImg.attributes['src'] : ''
                    let href = aEl.attributes['href'] || ''
                    let rid = href.split('/').pop()
                    if (!rid) continue
                    recommend.push({ id: rid, title: rTitle, cover: this._absUrl(rCover) })
                }
            }
        } catch (e) {
            recommend = []
        }

        this._comicId = String(id)
        this._comicTitle = title
        this._chapters = chapters

        doc.dispose()

        // ===== 渲染 =====
        const items = []

        // 头部
        let metaLines = []
        if (author) metaLines.push('作者: ' + author)
        if (tags.length > 0) metaLines.push('标签: ' + tags.join('、'))
        if (updateDate) metaLines.push('更新: ' + updateDate)
        let headerChildren = []
        if (cover) {
            headerChildren.push(UI.Image({ src: cover, width: 110, height: 150 }))
            headerChildren.push(UI.SizedBox({ width: 12 }))
        }
        headerChildren.push(
            UI.Expanded({
                child: UI.Column({
                    crossAxisAlignment: 'start',
                    mainAxisAlignment: 'start',
                    children: [
                        UI.Text({ content: title, style: { fontSize: 16, weight: 'bold' }, maxLines: 2 }),
                        UI.SizedBox({ height: 6 }),
                        ...metaLines.map((m) => UI.Text({ content: m, style: { fontSize: 12, color: '#888888' }, maxLines: 3 })),
                    ].filter((x) => x != null),
                }),
            })
        )
        items.push(
            UI.Card({
                padding: 12,
                shapeRadius: 8,
                child: UI.Row({ crossAxisAlignment: 'start', children: headerChildren }),
            })
        )

        // 简介
        if (description) {
            items.push(
                UI.Card({
                    padding: 12,
                    shapeRadius: 8,
                    child: UI.Text({ content: description, style: { fontSize: 13, color: '#555555' }, maxLines: 6 }),
                })
            )
        }

        // 章节
        if (chapters.length === 0) {
            items.push(UI.Text({ content: '未找到章节', style: { fontSize: 12, color: '#FF0000' } }))
        } else {
            const epButtons = chapters.map((ep) =>
                UI.Button({
                    label: ep.title,
                    style: 'text',
                    onTap: UI.Action({ method: 'openReader', args: [ep.id] }),
                })
            )
            items.push(
                UI.ExpansionTile({
                    title: UI.Text({
                        content: '章节（' + chapters.length + ' 话）',
                        style: { fontSize: 14, weight: 'bold' },
                        maxLines: 1,
                    }),
                    initiallyExpanded: true,
                    shapeRadius: 0,
                    children: [
                        UI.Container({
                            padding: 8,
                            child: UI.Wrap({ spacing: 6, runSpacing: 6, children: epButtons }),
                        }),
                    ],
                })
            )
        }

        // 相关推荐
        if (recommend.length > 0) {
            items.push(
                UI.Card({
                    padding: 12,
                    shapeRadius: 8,
                    child: UI.Column({
                        crossAxisAlignment: 'start',
                        children: [
                            UI.Text({ content: '相关推荐', style: { fontSize: 14, weight: 'bold' }, maxLines: 1 }),
                            UI.SizedBox({ height: 8 }),
                            UI.Wrap({
                                spacing: 6,
                                runSpacing: 6,
                                children: recommend.map((r) =>
                                    UI.Button({
                                        label: r.title,
                                        style: 'text',
                                        onTap: UI.Navigate({
                                            page: 'descriptor',
                                            method: 'getDetail',
                                            args: [r.id],
                                            title: r.title,
                                        }),
                                    })
                                ),
                            }),
                        ].filter((x) => x != null),
                    }),
                })
            )
        }

        PluginBrowse.open('baozi', {
            id: String(id),
            title: title,
            cover: cover,
            kv: { id: String(id) },
        })

        return items
    }

    // ============ 进入阅读器 ============

    async openReader(epId) {
        if (this._chapters.length === 0) {
            Dialog.showToast('章节列表为空')
            return
        }
        let initialChapter = 1
        for (let i = 0; i < this._chapters.length; i++) {
            if (this._chapters[i].id === epId) {
                initialChapter = i + 1
                break
            }
        }
        const chapters = this._chapters.map((ep) => ({
            id: ep.id,
            title: ep.title,
            plugin: 'baozi',
            method: 'loadChapterImages',
            args: [this._comicId, ep.id],
        }))
        Navigator.navigateToReader({
            comicId: this._comicId,
            comicTitle: this._comicTitle,
            chapters: chapters,
            sourceKey: 'baozi',
            initialChapter: initialChapter,
            initialPage: 1,
        })
    }

    // ============ 章节图片（阅读器惰性加载） ============

    /// 章节图片（阅读器惰性加载）。
    ///
    /// epId = chapter_slot。章节页经 /user/page_direct 302 到站点章节页
    /// （形如 https://cn.cnbzmg.com/comic/chapter/<slug>/0_<slot>.html），
    /// 域名/路径由站点决定，不能硬编码。
    ///
    /// 分页：站点章节按页拆分，标题形如「第132话(1/3)」（(当前/总页数)，
    /// 单页章节无括号），URL 为 .../0_<slot>.html、.../0_<slot>_2.html、...
    /// 因此先解析标题得到总页数，再从 canonical 拿到真实章节基址，
    /// 依次抓取每一页的图片并去重（相邻页存在重叠图片）。
    async loadChapterImages(comicId, epId) {
        // 优先用详情页保存的 page_direct 链接；缺失时按 comicId + slot 重建
        let pageDirect = ''
        const ch = this._chapters.find((x) => x.id === String(epId))
        if (ch && ch.url) {
            pageDirect = this._absUrl(ch.url)
        } else {
            pageDirect = this.baseUrl + '/user/page_direct?comic_id=' +
                encodeURIComponent(comicId) + '&section_slot=0&chapter_slot=' + epId
        }
        let res
        try {
            res = await this._get(pageDirect, this.baseHeaders)
        } catch (e) {
            throw '章节加载失败: ' + e
        }
        let html = res.body || ''
        if (!html) throw '章节页面为空'

        // ---- 分页信息 ----
        // 总页数：标题「第132话(1/3)」→ 3；单页章节无 (N/M) → 1
        let totalPages = 1
        const titleText = (html.match(/<title>([^<]*)<\/title>/) || ['', ''])[1]
        const tm = titleText.match(/\((\d+)\s*\/\s*(\d+)\)/)
        if (tm && parseInt(tm[2], 10) > 1) {
            totalPages = Math.min(parseInt(tm[2], 10), 99)
        }
        // 真实章节基址（page_direct 重定向后的页面）：
        // 1) canonical 形如 .../0_<slot>.html → 去扩展名做分页拼接
        // 2) 兜底：第 1 页的 #next-chapter 形如 .../0_<slot>_2.html → 去掉 _N.html
        // 3) 再兜底：用重定向后的 finalUrl
        let baseNoExt = ''
        const canonMatch = html.match(/<link[^>]*rel="canonical"[^>]*href="([^"]+)"/) ||
            html.match(/<link[^>]*href="([^"]+)"[^>]*rel="canonical"/)
        if (canonMatch) {
            baseNoExt = this._absUrl(canonMatch[1]).replace(/\.html$/, '')
        }
        if (!baseNoExt) {
            const nextA = html.match(/id="next-chapter"[^>]*href="([^"]+)"/)
            const nextHref = nextA ? nextA[1] : ''
            const m = nextHref.match(/^(.*)_\d+\.html$/)
            if (m) baseNoExt = this._absUrl(m[1])
        }
        if (!baseNoExt && res.finalUrl) {
            baseNoExt = String(res.finalUrl).replace(/\.html$/, '')
        }
        // 动态记录真实 reader 域（站点域路由会变，如 dzmanga.com → cn.cnbzmg.com），
        // 供 getImageLoadingConfig 的防盗链 Referer 使用；未检测到则回退设置项。
        const detectedHost = this._extractHost(baseNoExt || res.finalUrl || '')
        if (detectedHost) {
            this._readerHost = detectedHost
            console.log('[baozi] reader host 检测: ' + detectedHost)
        }

        // ---- 图片解析 ----
        const images = []
        const seen = new Set()
        const push = (u) => {
            if (!u) return
            u = this._absUrl(u)
            u = this._rewriteImage(u)
            if (!seen.has(u)) { seen.add(u); images.push(u) }
        }
        // 解析单个页文档：主取 .comic-contain 内的 amp-img / img；
        // 该页无内容图时兜底全页 amp-img / img（避免把 logo/图标混入）
        const parsePage = (d) => {
            let got = 0
            for (const img of d.querySelectorAll('.comic-contain amp-img, .comic-contain img')) {
                const u = img.attributes['src'] || img.attributes['data-src'] || img.attributes['data-original'] || ''
                if (u) { push(u); got++ }
            }
            if (got === 0) {
                for (const img of d.querySelectorAll('amp-img, img')) {
                    const u = img.attributes['src'] || img.attributes['data-src'] || img.attributes['data-original'] || ''
                    if (u) push(u)
                }
            }
        }
        const firstDoc = new HtmlDocument(html)
        parsePage(firstDoc)
        firstDoc.dispose()

        // ---- 依次抓取剩余分页：.../0_<slot>_N.html ----
        let fetchedPages = 1
        if (totalPages > 1 && baseNoExt) {
            for (let p = 2; p <= totalPages; p++) {
                const pageUrl = baseNoExt + '_' + p + '.html'
                let ph
                try {
                    ph = (await this._get(pageUrl, this.baseHeaders)).body
                } catch (e) {
                    console.error('[baozi] 分页请求失败 page=' + p + ' url=' + pageUrl + ' err=' + e)
                    continue
                }
                if (!ph) continue
                const pdoc = new HtmlDocument(ph)
                parsePage(pdoc)
                pdoc.dispose()
                fetchedPages++
            }
        }

        console.log('[baozi] loadChapterImages title="' + titleText + '" totalPages=' + totalPages +
            ' fetched=' + fetchedPages + ' images=' + images.length + ' epId=' + epId)
        if (images.length === 0) {
            throw '章节图片为空（epId=' + epId + '，标题=' + titleText + '）'
        }
        return images
    }

    /// 图片加载配置（防盗链：CDN 校验 Referer + 浏览器 UA，否则返回被拦截的修改图）。
    /// 参数与 venera 的 comic.onImageLoad 一致：(url, comicId, epId)
    getImageLoadingConfig(url, comicId, epId) {
        let rd = this.loadSetting('reader_domain') || 'cn.cnbzmg.com'
        // 优先用最近一次章节页动态检测到的真实 reader 域（避免站点换域后防盗链失效）
        const refHost = this._readerHost || rd
        return {
            headers: {
                'User-Agent': this.ua,
                'Referer': 'https://' + refHost + '/',
                'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
            },
        }
    }

    /// 按设置改写图片地址：CDN 域名替换 + 质量前缀（/w640 → webp，体积约 1/4）。
    _rewriteImage(u) {
        if (!u) return u
        const m = u.match(/^(https?:\/\/)([^/\s:]+)(:\d+)?(\/.*)$/)
        if (!m) return u
        let host = m[2]
        const port = m[3] || ''
        let path = m[4]
        const setDomain = this.loadSetting('cdn_domains')
        if (setDomain) host = setDomain
        const quality = this.imageQuality
        if (quality && path.indexOf(quality + '/') !== 0) path = quality + path
        return m[1] + host + port + path
    }

    // ============ 浏览历史回放 ============

    async onOpenBrowseEntry(entry) {
        if (!entry || !entry.kv || !entry.kv.id) {
            Dialog.showToast('浏览历史无效')
            return
        }
        Navigator.navigateToDescriptor('baozi', {
            method: 'getDetail',
            args: [entry.kv.id],
            title: entry.title || '',
        })
    }
}
