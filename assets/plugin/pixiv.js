// description: Pixiv 插画 / 漫画 / 小说源 — 关键词搜索 / ID 直达 / 推荐与排行 / 参数化搜索 / 详情 / 阅读
// type: manga
//
// 接口约定（与 wyw 插件框架）：
//   search(keyword, page)            → List<UI.Card>（搜索模块）
//   getDetail(id)                    → List<UI>（作品详情）
//   openReader(epId)                 → Navigator.navigateToReader（章节惰性加载）
//   loadChapterImages(comicId, epId) → 该章图片 URL 数组
//   getCategory / getCategoryOptions / loadCategory / loadCategoryPage → 浏览页
//   getImageLoadingConfig             → 图片 Referer 等请求头
//   onOpenBrowseEntry                 → 浏览历史回放
//   getNovelDetail / openNovelReader / loadChapterContent → 小说（可选能力）
//
// 数据源：
//   Pixiv App API 的 HibiAPI / PxveAPI 兼容实例（默认 https://api.cocomi.eu.org）。
//   不需要登录即可搜索 / 排行 / 详情 / 推荐；需要收藏、关注、个性化推荐时应自建
//   带 PIXIV_ACCOUNT_TOKEN 的实例。API 实例很慢或被限流时会自动降级为简单搜索。
//
// 图片：
//   默认 i.pixiv.re（按 i.pximg.net 路径反代，600×1200 内自适应，速度快）。
//   原图模式会把 i.pximg.net 原图地址交给同一代理；若代理不支持原图路径，
//   请在设置里换成自建 PxveAPI 的 `https://<host>/pximg`。
//
// 这是「搜索模块 + 浏览页」分工的插件：
//   - 搜索模块只做纯关键词搜索（和 pixiv-viewer 的搜索框一样）。
//   - ID 跳转 / 推荐 / 排行榜 / 带全部筛选参数的搜索都放在浏览页分类里。

class pixiv extends PluginSource {
    static pluginName = 'pixiv'
    static defaultApiBase = 'https://api.cocomi.eu.org'
    static defaultImageProxy = 'i.pixiv.re'
    static ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36'

    get pluginName() {
        return pixiv.pluginName
    }

    // 仅用于出厂 seed 生成时的展示名；运行时宿主以 index.json 为准
    name = 'Pixiv'

    // 宿主会读取 settings 生成插件设置页。未设置时 loadSetting 返回空串，getter 里兜底。
    settings = {
        api_base: {
            title: 'API 实例（公共实例部分接口不可用，建议自建 HibiAPI/PxveAPI）',
            type: 'input',
            default: pixiv.defaultApiBase,
        },
        image_proxy: {
            title: '图片代理（i.pixiv.re 或自建 /pximg）',
            type: 'input',
            default: pixiv.defaultImageProxy,
        },
        quality: {
            title: '阅读画质',
            type: 'select',
            options: [
                { value: 'large', text: '标准（600×1200 自适应，快）' },
                { value: 'master', text: '高清（1200px，需代理支持 img-master）' },
                { value: 'original', text: '原图（需代理支持，较慢）' },
            ],
            default: 'large',
        },
        r18: {
            title: 'R18 内容',
            type: 'select',
            options: [
                { value: '0', text: '隐藏' },
                { value: '1', text: '显示' },
                { value: '2', text: '仅 R18' },
            ],
            default: '0',
        },
        ai: {
            title: 'AI 生成作品',
            type: 'select',
            options: [
                { value: '1', text: '显示' },
                { value: '0', text: '隐藏' },
            ],
            default: '1',
        },
        min_bookmarks: {
            title: '最低收藏数（0 = 不限）',
            type: 'input',
            validator: '^\\d*$',
            default: '0',
        },
        blocked_tags: {
            title: '屏蔽标签（逗号分隔，可留空）',
            type: 'input',
            default: '',
        },
    }

    // 会话内缓存，避免详情 / 阅读器重复请求同一作品
    _artCache = {}
    _chapterCache = {}
    _userCache = {}
    _novelCache = {}
    _seriesCache = {}
    _tagCache = null

    // 当前详情页 / 阅读器上下文
    _comicId = ''
    _comicTitle = ''
    _chapters = []

    // ========================================================================
    // 基础工具
    // ========================================================================

    get apiBase() {
        let v = String(this.loadSetting('api_base') || pixiv.defaultApiBase).trim()
        if (!/^https?:\/\//i.test(v)) v = 'https://' + v
        v = v.replace(/\/+$/, '')
        v = v.replace(/\/api\/pixiv$/i, '')
        return v
    }

    get imageProxy() {
        let v = String(this.loadSetting('image_proxy') || pixiv.defaultImageProxy).trim()
        if (v) {
            if (!/^https?:\/\//i.test(v)) v = 'https://' + v
            v = v.replace(/\/+$/, '')
        }
        return v
    }

    get quality() {
        const v = String(this.loadSetting('quality') || '')
        if (v === 'original' || v === 'master') return v
        return 'large'
    }

    get showAI() {
        return this.loadSetting('ai') !== '0'
    }

    get minBookmarks() {
        const n = parseInt(this.loadSetting('min_bookmarks'), 10)
        return isNaN(n) || n < 0 ? 0 : n
    }

    _r18Mode() {
        const v = String(this.loadSetting('r18') || '0')
        if (v === '2') return 2
        if (v === '1') return 1
        return 0
    }

    _blockedTags() {
        const raw = String(this.loadSetting('blocked_tags') || '')
        return raw
            .split(/[,，、\s]+/)
            .filter((s) => !!s)
            .map((s) => s.toLowerCase())
    }

    _isBlocked(art) {
        const blocked = this._blockedTags()
        if (!blocked.length) return false
        const tags = art.tags || []
        for (let i = 0; i < tags.length; i++) {
            const name = String(tags[i].name || '').toLowerCase()
            if (blocked.indexOf(name) >= 0) return true
        }
        return false
    }

    _headers() {
        return {
            'User-Agent': pixiv.ua,
            'Accept': 'application/json, text/plain, */*',
            'Accept-Language': 'zh-CN,zh;q=0.9,ja;q=0.8',
        }
    }

    _imgHeaders() {
        return {
            'Referer': 'https://www.pixiv.net/',
            'User-Agent': pixiv.ua,
        }
    }

    _query(params) {
        let qs = ''
        if (params) {
            const keys = Object.keys(params)
            for (let i = 0; i < keys.length; i++) {
                const k = keys[i]
                const v = params[k]
                if (v === undefined || v === null || v === '') continue
                qs += (qs ? '&' : '') + encodeURIComponent(k) + '=' + encodeURIComponent(String(v))
            }
        }
        return qs
    }

    _url(path, params) {
        const qs = this._query(params)
        return this.apiBase + '/api/pixiv' + path + (qs ? '?' + qs : '')
    }

    _errText(e) {
        if (!e) return '未知错误'
        if (typeof e === 'string') return e
        if (e.user_message) return String(e.user_message)
        if (e.message) return String(e.message)
        try {
            return JSON.stringify(e)
        } catch (err) {
            return String(e)
        }
    }

    /**
     * 统一 JSON 请求。Network.get 返回 body 字符串；非 2xx 会抛结构化 Error。
     * 失败返回 null，并按需 toast；调用方负责降级。
     */
    async _api(path, params, opts) {
        opts = opts || {}
        const url = this._url(path, params)
        const timeout = opts.timeout || 30000
        const retries = opts.retries === undefined ? 1 : opts.retries
        try {
            const res = await Network.get(url, this._headers(), { timeout: timeout, retries: retries })
            if (!res) {
                console.error('[pixiv] 空响应', path)
                return null
            }
            let data = null
            try {
                data = JSON.parse(res)
            } catch (e) {
                console.error('[pixiv] JSON 解析失败', path, String(res).slice(0, 200))
                return null
            }
            if (data && data.error) {
                console.error('[pixiv] API 错误', path, this._errText(data.error))
                if (!opts.silent) Dialog.showToast('Pixiv API: ' + this._errText(data.error))
                return null
            }
            return data
        } catch (e) {
            console.error('[pixiv] 请求失败', url, this._errText(e))
            if (!opts.silent) Dialog.showToast('Pixiv 请求失败: ' + this._errText(e))
            return null
        }
    }

    _proxy(url) {
        if (!url) return ''
        const base = this.imageProxy
        if (!base) return url
        return String(url)
            .replace(/^https?:\/\/i\.pximg\.net/i, base)
            .replace(/^https?:\/\/s\.pximg\.net/i, base)
    }

    _coverUrl(obj, size) {
        const urls = obj.image_urls || {}
        if (size === 'large') {
            return urls.large || urls.medium || urls.square_medium || ''
        }
        return urls.medium || urls.square_medium || urls.large || ''
    }

    /** 页面图片地址：large 为 Pixiv 的 600×1200 自适应图（完整画面，非裁剪）。 */
    _pageUrls(illust) {
        const out = []
        const quality = this.quality
        const pages = Array.isArray(illust.meta_pages) ? illust.meta_pages : []
        if (pages.length > 0) {
            for (let i = 0; i < pages.length; i++) {
                const urls = pages[i].image_urls || {}
                const u = this._pickPageUrl(urls, '', quality)
                if (u) out.push(this._proxy(u))
            }
            return out
        }
        const single = illust.meta_single_page || {}
        const urls = illust.image_urls || {}
        const u = this._pickPageUrl(urls, single.original_image_url || '', quality)
        if (u) out.push(this._proxy(u))
        return out
    }

    /**
     * large: 600×1200 自适应（i.pixiv.re 可直接取，最快）
     * master: 去掉 /c/…/ 裁剪前缀的 img-master（1200px 全画面，需代理支持）
     * original: img-original 原图（最慢）
     */
    _pickPageUrl(urls, singleOriginal, quality) {
        const original = urls.original || singleOriginal || ''
        const large = urls.large || singleOriginal || original
        if (quality === 'original') return original || large
        if (quality === 'master') {
            return String(large || original).replace(/\/c\/\d+x\d+(_\d+)?\//, '/')
        }
        return large
    }

    _typeLabel(t) {
        if (t === 'manga') return '漫画'
        if (t === 'ugoira') return '动图'
        return '插画'
    }

    _fmtNum(n) {
        n = Number(n) || 0
        if (n >= 100000000) return (n / 100000000).toFixed(1) + '亿'
        if (n >= 10000) return (n / 10000).toFixed(1) + '万'
        return String(n)
    }

    _fmtDate(d) {
        const p = (n) => (n < 10 ? '0' + n : String(n))
        return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate())
    }

    _periodStart(period) {
        const d = new Date()
        if (period === 'day') d.setDate(d.getDate() - 1)
        else if (period === 'week') d.setDate(d.getDate() - 7)
        else if (period === 'month') d.setMonth(d.getMonth() - 1)
        else if (period === 'half') d.setMonth(d.getMonth() - 6)
        else if (period === 'year') d.setFullYear(d.getFullYear() - 1)
        else return ''
        return this._fmtDate(d)
    }

    _stripHtml(s) {
        return String(s || '')
            .replace(/<br\s*\/?>/gi, '\n')
            .replace(/<[^>]+>/g, '')
            .replace(/&amp;/g, '&')
            .replace(/&lt;/g, '<')
            .replace(/&gt;/g, '>')
            .replace(/&quot;/g, '"')
            .replace(/&#39;/g, "'")
            .trim()
    }

    _defaultFilter() {
        const m = this._r18Mode()
        return {
            hideR18: m === 0,
            onlyR18: m === 2,
            hideAI: !this.showAI,
            minBookmarks: this.minBookmarks,
        }
    }

    _filterList(list, opts) {
        opts = opts || this._defaultFilter()
        const out = []
        const arr = list || []
        for (let i = 0; i < arr.length; i++) {
            const art = arr[i]
            if (!art || !art.id) continue
            if (opts.hideR18 && art.x_restrict > 0) continue
            if (opts.onlyR18 && !(art.x_restrict > 0)) continue
            if (opts.hideAI && (art.illust_ai_type === 2 || art.novel_ai_type === 2)) continue
            if (opts.minBookmarks && (art.total_bookmarks || 0) < opts.minBookmarks) continue
            if (this._isBlocked(art)) continue
            out.push(art)
        }
        return out
    }

    _searchWords(word) {
        return String(word || '')
            .split(/\s+/)
            .filter((s) => !!s && s !== 'R-18' && s !== '-R-18' && s !== '-R18' && s !== '-18+')
    }

    _hasAllTags(art, words) {
        const tags = (art.tags || []).map((t) => String(t.name || '').toLowerCase())
        for (let i = 0; i < words.length; i++) {
            if (tags.indexOf(String(words[i]).toLowerCase()) < 0) return false
        }
        return true
    }

    // ========================================================================
    // 卡片 / 详情头部等 UI 构件
    // ========================================================================

    _badges(art) {
        const badges = []
        if (art.x_restrict === 1) badges.push('R-18')
        else if (art.x_restrict >= 2) badges.push('R-18G')
        if (art.illust_ai_type === 2 || art.novel_ai_type === 2) badges.push('AI')
        if (art.type === 'ugoira') badges.push('动图')
        if (art.type === 'manga') badges.push('漫画')
        return badges
    }

    _tagChip(text, color, textColor) {
        return UI.Tag({
            text: String(text),
            color: color || '#e3f2fd',
            textColor: textColor || '#1565c0',
        })
    }

    _card(art, opts) {
        opts = opts || {}
        if (!art || !art.id) return null
        const title = String(art.title || '无题')
        const cover = this._proxy(this._coverUrl(art, 'medium'))
        const meta = []
        if (opts.rank) meta.push('#' + opts.rank)
        meta.push(this._typeLabel(art.type) + ' · ' + (art.page_count || 1) + ' 页')
        if (art.create_date) meta.push(String(art.create_date).slice(0, 10))
        if (art.total_bookmarks !== undefined && art.total_bookmarks !== null) {
            meta.push('★ ' + this._fmtNum(art.total_bookmarks))
        }
        const tags = (art.tags || []).slice(0, 3).map((t) => '#' + String(t.name || '')).join(' ')
        if (tags) meta.push(tags)
        if (opts.userName) meta.unshift(String(opts.userName))

        const children = [
            cover ? UI.Image({ src: cover, width: 80, height: 116, headers: this._imgHeaders() }) : null,
            UI.SizedBox({ width: 12 }),
            UI.Expanded({
                child: UI.Column({
                    crossAxisAlignment: 'start',
                    mainAxisAlignment: 'start',
                    children: [
                        UI.Text({ content: title, style: { fontSize: 14, weight: 'bold' }, maxLines: 2 }),
                        ...meta.map((m) => UI.Text({ content: m, style: { fontSize: 12, color: '#888888' }, maxLines: 1 })),
                        this._badges(art).length
                            ? UI.Wrap({
                                spacing: 4,
                                runSpacing: 4,
                                children: this._badges(art).map((b) => this._tagChip(
                                    b,
                                    b.indexOf('R-18') === 0 ? '#ffebee' : '#e3f2fd',
                                    b.indexOf('R-18') === 0 ? '#c62828' : '#1565c0',
                                )),
                            })
                            : null,
                    ].filter((x) => x != null),
                }),
            }),
            UI.SizedBox({ width: 8 }),
            UI.IconButton({
                icon: 'chevron_right',
                tooltip: '详情',
                color: '#666666',
                size: 20,
                onTap: UI.Navigate({
                    page: 'descriptor',
                    method: 'getDetail',
                    args: [String(art.id)],
                    title: title,
                }),
            }),
        ].filter((x) => x != null)

        return UI.Card({
            elevation: 0,
            shapeRadius: 16,
            color: '@theme:surfaceContainerLow',
            padding: 4,
            child: UI.Row({ crossAxisAlignment: 'start', children: children }),
        })
    }

    _novelCard(n) {
        if (!n || !n.id) return null
        const title = String(n.title || '无题')
        const cover = this._proxy(this._coverUrl(n, 'medium'))
        const meta = []
        meta.push('小说' + (n.text_length ? ' · ' + this._fmtNum(n.text_length) + ' 字' : ''))
        if (n.create_date) meta.push(String(n.create_date).slice(0, 10))
        if (n.total_bookmarks !== undefined && n.total_bookmarks !== null) {
            meta.push('★ ' + this._fmtNum(n.total_bookmarks))
        }
        const tags = (n.tags || []).slice(0, 3).map((t) => '#' + String(t.name || '')).join(' ')
        if (tags) meta.push(tags)
        return UI.Card({
            elevation: 0,
            shapeRadius: 16,
            color: '@theme:surfaceContainerLow',
            padding: 4,
            child: UI.Row({
                crossAxisAlignment: 'start',
                children: [
                    cover ? UI.Image({ src: cover, width: 80, height: 116, headers: this._imgHeaders() }) : null,
                    UI.SizedBox({ width: 12 }),
                    UI.Expanded({
                        child: UI.Column({
                            crossAxisAlignment: 'start',
                            children: [
                                UI.Text({ content: title, style: { fontSize: 14, weight: 'bold' }, maxLines: 2 }),
                                ...meta.map((m) => UI.Text({ content: m, style: { fontSize: 12, color: '#888888' }, maxLines: 1 })),
                                this._badges(n).length
                                    ? UI.Wrap({
                                        spacing: 4,
                                        runSpacing: 4,
                                        children: this._badges(n).map((b) => this._tagChip(
                                            b,
                                            b.indexOf('R-18') === 0 ? '#ffebee' : '#e3f2fd',
                                            b.indexOf('R-18') === 0 ? '#c62828' : '#1565c0',
                                        )),
                                    })
                                    : null,
                            ].filter((x) => x != null),
                        }),
                    }),
                    UI.SizedBox({ width: 8 }),
                    UI.IconButton({
                        icon: 'chevron_right',
                        tooltip: '详情',
                        color: '#666666',
                        size: 20,
                        onTap: UI.Navigate({
                            page: 'descriptor',
                            method: 'getNovelDetail',
                            args: [String(n.id)],
                            title: title,
                        }),
                    }),
                ].filter((x) => x != null),
            }),
        })
    }

    _userCard(user, preview) {
        if (!user || !user.id) return null
        const title = String(user.name || user.account || ('画师 ' + user.id))
        const avatar = this._proxy((user.profile_image_urls || {}).medium || '')
        const meta = []
        if (user.account) meta.push('@' + String(user.account))
        if (preview && Array.isArray(preview.illusts)) meta.push('预览作品 ' + preview.illusts.length + ' 件')
        if (preview && Array.isArray(preview.novels) && preview.novels.length) meta.push('小说 ' + preview.novels.length + ' 篇')
        return UI.Card({
            elevation: 0,
            shapeRadius: 16,
            color: '@theme:surfaceContainerLow',
            padding: 4,
            child: UI.Row({
                crossAxisAlignment: 'center',
                children: [
                    avatar
                        ? UI.Image({ src: avatar, width: 56, height: 56, headers: this._imgHeaders() })
                        : UI.Icon({ name: 'person', size: 40, color: '#999999' }),
                    UI.SizedBox({ width: 12 }),
                    UI.Expanded({
                        child: UI.Column({
                            crossAxisAlignment: 'start',
                            children: [
                                UI.Text({ content: title, style: { fontSize: 14, weight: 'bold' }, maxLines: 1 }),
                                ...meta.map((m) => UI.Text({ content: m, style: { fontSize: 12, color: '#888888' }, maxLines: 1 })),
                            ],
                        }),
                    }),
                    UI.IconButton({
                        icon: 'chevron_right',
                        tooltip: '画师详情',
                        color: '#666666',
                        size: 20,
                        onTap: UI.Navigate({
                            page: 'descriptor',
                            method: 'getUserDetail',
                            args: [String(user.id)],
                            title: title,
                        }),
                    }),
                ].filter((x) => x != null),
            }),
        })
    }

    _tagCard(t) {
        if (!t) return null
        const tag = String(t.tag || '')
        if (!tag) return null
        const translated = t.translated_name ? String(t.translated_name) : ''
        const pic = t.illust ? this._proxy(this._coverUrl(t.illust, 'medium')) : ''
        return UI.Card({
            elevation: 0,
            shapeRadius: 16,
            color: '@theme:surfaceContainerLow',
            padding: 4,
            child: UI.Row({
                crossAxisAlignment: 'center',
                children: [
                    pic ? UI.Image({ src: pic, width: 56, height: 56, headers: this._imgHeaders() }) : null,
                    UI.SizedBox({ width: 12 }),
                    UI.Expanded({
                        child: UI.Column({
                            crossAxisAlignment: 'start',
                            children: [
                                UI.Text({ content: '#' + tag, style: { fontSize: 14, weight: 'bold' }, maxLines: 1 }),
                                translated
                                    ? UI.Text({ content: translated, style: { fontSize: 12, color: '#888888' }, maxLines: 1 })
                                    : null,
                            ].filter((x) => x != null),
                        }),
                    }),
                    UI.IconButton({
                        icon: 'search',
                        tooltip: '搜索该标签',
                        color: '#666666',
                        size: 20,
                        onTap: UI.Action({ method: 'openTag', args: [tag] }),
                    }),
                ].filter((x) => x != null),
            }),
        })
    }

    _actionButton(label, method, args, icon) {
        return UI.Button({
            label: label,
            style: 'text',
            icon: icon,
            onTap: UI.Action({ method: method, args: args }),
        })
    }

    // ========================================================================
    // 搜索模块：纯关键词搜索
    // ========================================================================

    async search(keyword, page = 1) {
        let kw = String(keyword === undefined || keyword === null ? '' : keyword).trim()
        if (!kw) return [UI.Text('请输入搜索关键词')]

        // 粘贴 Pixiv 链接 / 纯数字 ID 时直接打开作品
        const artworkMatch = kw.match(/artworks?\/(\d+)/i)
        if (artworkMatch) {
            const cards = await this._idCards(artworkMatch[1], 'illust')
            if (cards.length) return page > 1 ? [] : cards
        }
        const userMatch = kw.match(/users?\/(\d+)/i)
        if (userMatch) {
            const cards = await this._idCards(userMatch[1], 'user')
            if (cards.length) return page > 1 ? [] : cards
        }
        if (/^\d+$/.test(kw)) {
            const cards = await this._idCards(kw, 'illust', true)
            if (cards.length) return page > 1 ? [] : cards
        }

        let word = kw
        const r18 = this._r18Mode()
        if (r18 === 0 && word.indexOf('-R-18') < 0) word += ' -R-18 -R18 -18+'
        if (r18 === 2 && word.indexOf('R-18') < 0) word += ' R-18'

        let data = await this._searchOnce(word, page, false)
        if (!data && word !== kw) data = await this._searchOnce(kw, page, true)
        if (!data) {
            console.error('[pixiv] 搜索失败，关键词=', kw)
            return []
        }
        let list = (data.illusts || []).slice()
        list = this._filterList(list, {
            hideR18: r18 === 0,
            onlyR18: r18 === 2,
            hideAI: !this.showAI,
            minBookmarks: this.minBookmarks,
        })
        const cards = list.map((a) => this._card(a)).filter((x) => x != null)
        console.log('[pixiv] 搜索', kw, '第', page, '页 →', cards.length, '条')
        if (cards.length === 0 && page <= 1) {
            Dialog.showToast('未找到结果，请检查关键词')
        }
        return cards
    }

    async _searchOnce(word, page, silent) {
        const data = await this._api('/search', { word: word, page: page }, { silent: !!silent })
        if (!data || !Array.isArray(data.illusts)) return null
        return data
    }

    async _idCards(id, type, silent) {
        const sid = String(id)
        if (type === 'user') {
            const data = await this._api('/member', { id: sid }, { silent: true })
            if (data && data.user) {
                this._userCache[sid] = data
                return [this._userCard(data.user, null)].filter((x) => x != null)
            }
        } else {
            const data = await this._api('/illust', { id: sid }, { silent: true })
            if (data && data.illust) {
                this._artCache[sid] = data.illust
                return [this._card(data.illust)].filter((x) => x != null)
            }
        }
        if (!silent) Dialog.showToast('未找到 ID: ' + sid)
        return []
    }

    // ========================================================================
    // 作品详情
    // ========================================================================

    async _getIllust(id) {
        const sid = String(id)
        if (this._artCache[sid]) return this._artCache[sid]
        const data = await this._api('/illust', { id: sid }, { silent: true })
        if (!data || !data.illust) return null
        this._artCache[sid] = data.illust
        return data.illust
    }

    async _loadSeries(seriesId) {
        const sid = String(seriesId)
        if (this._seriesCache[sid]) return this._seriesCache[sid]
        const data = await this._api('/illust_series', { id: sid, page: 1 }, { silent: true })
        if (!data || !Array.isArray(data.illusts)) return null
        const works = data.illusts
        const chapters = works.map((w) => ({
            id: String(w.id),
            title: String(w.title || ('作品 ' + w.id)),
            pageCount: w.page_count || 0,
        }))
        const detail = data.illust_series_detail || {}
        const result = {
            id: sid,
            title: String(detail.title || ('系列 ' + sid)),
            chapters: chapters,
            works: works,
            description: this._stripHtml(detail.description || ''),
        }
        this._seriesCache[sid] = result
        // 系列作品也进缓存，阅读器切章时无需再次请求
        for (let i = 0; i < works.length; i++) {
            this._artCache[String(works[i].id)] = works[i]
        }
        return result
    }

    async getDetail(id) {
        const sid = String(id)
        const illust = await this._getIllust(sid)
        if (!illust) {
            Dialog.showToast('作品不存在或已被删除')
            return [UI.Text('作品不存在或已被删除（ID ' + sid + '）')]
        }
        const title = String(illust.title || '无题')
        const cover = this._proxy(this._coverUrl(illust, 'large'))
        const user = illust.user || {}
        const tags = (illust.tags || []).slice(0, 30)
        const pages = this._pageUrls(illust)
        const pageCount = pages.length || illust.page_count || 1

        // 系列作品：把系列内所有作品作为章节；否则整件作品作为一章
        let chapters = []
        let series = null
        if (illust.series && illust.series.id) {
            series = await this._loadSeries(illust.series.id)
            if (series && series.chapters.length > 0) chapters = series.chapters
        }
        if (chapters.length === 0) {
            chapters = [{
                id: sid,
                title: pageCount > 1 ? ('全 ' + pageCount + ' 页') : '单页',
                pageCount: pageCount,
            }]
        }

        this._comicId = sid
        this._comicTitle = title
        this._chapters = chapters

        let currentIndex = 0
        for (let i = 0; i < chapters.length; i++) {
            if (String(chapters[i].id) === sid) {
                currentIndex = i
                break
            }
        }

        const meta = []
        meta.push(this._typeLabel(illust.type) + ' · ' + pageCount + ' 页')
        if (illust.create_date) meta.push('投稿 ' + String(illust.create_date).slice(0, 10))
        if (illust.total_view !== undefined) meta.push('浏览 ' + this._fmtNum(illust.total_view))
        if (illust.total_bookmarks !== undefined) meta.push('收藏 ' + this._fmtNum(illust.total_bookmarks))
        if (illust.width && illust.height) meta.push(illust.width + '×' + illust.height)
        if (user.name) meta.push('作者 ' + user.name)

        const items = []
        items.push(UI.Card({
            padding: 12,
            shapeRadius: 8,
            child: UI.Row({
                crossAxisAlignment: 'start',
                children: [
                    cover ? UI.Image({ src: cover, width: 110, height: 150, headers: this._imgHeaders() }) : null,
                    UI.SizedBox({ width: 12 }),
                    UI.Expanded({
                        child: UI.Column({
                            crossAxisAlignment: 'start',
                            mainAxisAlignment: 'start',
                            children: [
                                UI.Text({ content: title, style: { fontSize: 16, weight: 'bold' }, maxLines: 3 }),
                                UI.SizedBox({ height: 6 }),
                                ...meta.map((m) => UI.Text({ content: m, style: { fontSize: 12, color: '#888888' }, maxLines: 1 })),
                                this._badges(illust).length
                                    ? UI.Wrap({
                                        spacing: 4,
                                        runSpacing: 4,
                                        children: this._badges(illust).map((b) => this._tagChip(
                                            b,
                                            b.indexOf('R-18') === 0 ? '#ffebee' : '#e3f2fd',
                                            b.indexOf('R-18') === 0 ? '#c62828' : '#1565c0',
                                        )),
                                    })
                                    : null,
                            ].filter((x) => x != null),
                        }),
                    }),
                ].filter((x) => x != null),
            }),
        }))

        // 操作按钮
        const buttons = []
        buttons.push(UI.Button({
            label: pageCount > 1 ? '开始阅读（' + pageCount + ' 页）' : '查看大图',
            style: 'filled',
            icon: 'menu_book',
            onTap: UI.Action({ method: 'openReader', args: [String(chapters[currentIndex].id)] }),
        }))
        if (user.id) {
            buttons.push(UI.Button({
                label: '作者作品',
                style: 'text',
                icon: 'person',
                onTap: UI.Action({ method: 'openUserWorks', args: [String(user.id), 'illust'] }),
            }))
            if (illust.type === 'manga') {
                buttons.push(UI.Button({
                    label: '作者漫画',
                    style: 'text',
                    icon: 'menu_book',
                    onTap: UI.Action({ method: 'openUserWorks', args: [String(user.id), 'manga'] }),
                }))
            }
        }
        buttons.push(UI.Button({
            label: '相关作品',
            style: 'text',
            icon: 'auto_awesome',
            onTap: UI.Action({ method: 'openRelated', args: [sid] }),
        }))
        buttons.push(UI.Button({
            label: '复制 ID',
            style: 'text',
            icon: 'content_copy',
            onTap: UI.Action({ method: 'copyText', args: [sid] }),
        }))
        buttons.push(UI.Button({
            label: '源站',
            style: 'text',
            icon: 'open_in_new',
            onTap: UI.Action({ method: 'openWeb', args: ['https://www.pixiv.net/artworks/' + sid] }),
        }))
        items.push(UI.Card({
            padding: 12,
            shapeRadius: 8,
            child: UI.Wrap({ spacing: 6, runSpacing: 6, children: buttons }),
        }))

        // 简介
        const caption = this._stripHtml(illust.caption || '')
        if (caption) {
            items.push(UI.Card({
                padding: 12,
                shapeRadius: 8,
                child: UI.Text({ content: caption, style: { fontSize: 13, color: '#555555' }, maxLines: 8 }),
            }))
        }

        // 标签（点击后在浏览/详情栈里打开搜索结果）
        if (tags.length > 0) {
            const tagButtons = tags.map((t) => UI.Button({
                label: '#' + String(t.name || ''),
                style: 'text',
                onTap: UI.Action({ method: 'openTag', args: [String(t.name || '')] }),
            }))
            items.push(UI.Card({
                padding: 12,
                shapeRadius: 8,
                child: UI.Wrap({ spacing: 6, runSpacing: 6, children: tagButtons }),
            }))
        }

        // 系列信息
        if (series) {
            const seriesButtons = [UI.Button({
                label: '查看系列（' + series.chapters.length + ' 部）',
                style: 'text',
                icon: 'collections_bookmark',
                onTap: UI.Action({ method: 'openSeries', args: [String(series.id)] }),
            })]
            items.push(UI.Card({
                padding: 12,
                shapeRadius: 8,
                child: UI.Column({
                    crossAxisAlignment: 'start',
                    children: [
                        UI.Text({ content: '系列：' + series.title, style: { fontSize: 13, weight: 'bold' }, maxLines: 2 }),
                        UI.Wrap({ spacing: 6, runSpacing: 6, children: seriesButtons }),
                    ],
                }),
            }))
        }

        // 多章节：列出全部章节按钮
        if (chapters.length > 1) {
            const epButtons = chapters.map((ep) => UI.Button({
                label: String(ep.title || ep.id),
                style: 'text',
                onTap: UI.Action({ method: 'openReader', args: [String(ep.id)] }),
            }))
            items.push(UI.ExpansionTile({
                title: UI.Text({ content: '章节（' + chapters.length + '）', style: { fontSize: 14, weight: 'bold' }, maxLines: 1 }),
                initiallyExpanded: true,
                shapeRadius: 0,
                children: [
                    UI.Card({
                        padding: 8,
                        shapeRadius: 8,
                        child: UI.Wrap({ spacing: 6, runSpacing: 6, children: epButtons }),
                    }),
                ],
            }))
        }

        if (illust.type === 'ugoira') {
            items.push(UI.Text({
                content: '动图作品在 wyw 阅读器中只会显示静态封面，完整动图请点「源站」查看。',
                style: { fontSize: 12, color: '#999999' },
            }))
        }

        PluginBrowse.open(this.pluginName, {
            id: sid,
            title: title,
            cover: cover,
            kv: { id: sid, type: 'illust' },
        })
        return items
    }

    // ========================================================================
    // 阅读器
    // ========================================================================

    async openReader(epId) {
        const eid = String(epId)
        let chapters = this._chapters || []
        if (chapters.length === 0) {
            chapters = [{ id: eid, title: this._comicTitle || ('作品 ' + eid) }]
        }
        let index = 0
        for (let i = 0; i < chapters.length; i++) {
            if (String(chapters[i].id) === eid) {
                index = i
                break
            }
        }
        const payload = chapters.map((c) => ({
            id: String(c.id),
            title: String(c.title || c.id),
            plugin: this.pluginName,
            method: 'loadChapterImages',
            args: [this._comicId || eid, String(c.id)],
        }))
        Navigator.navigateToReader({
            comicId: String(this._comicId || eid),
            comicTitle: String(this._comicTitle || ''),
            chapters: payload,
            sourceKey: this.pluginName,
            initialChapter: index + 1,
            initialPage: 1,
        })
    }

    async loadChapterImages(comicId, epId) {
        const eid = String(epId)
        const cacheKey = eid + '|' + this.quality + '|' + this.imageProxy
        if (this._chapterCache[cacheKey]) return this._chapterCache[cacheKey]
        const illust = await this._getIllust(eid)
        if (!illust) {
            throw new Error('无法获取作品 ' + eid + ' 的详情（comicId=' + comicId + '）')
        }
        const urls = this._pageUrls(illust)
        if (urls.length === 0) {
            throw new Error('作品 ' + eid + ' 没有可读图片（type=' + illust.type +
                '，page_count=' + illust.page_count + '，meta_pages=' + ((illust.meta_pages || []).length) + '）')
        }
        this._chapterCache[cacheKey] = urls
        console.log('[pixiv] 章节图片', eid, '页数', urls.length, '首图', urls[0])
        return urls
    }

    getImageLoadingConfig(url, comicId, epId) {
        // i.pixiv.re / 自建 pximg 代理一般不需要 Referer；直连 i.pximg.net 时必须带
        if (String(url).indexOf('i.pximg.net') >= 0) {
            return { headers: this._imgHeaders() }
        }
        return { headers: { 'User-Agent': pixiv.ua } }
    }

    async onOpenBrowseEntry(entry) {
        if (!entry || !entry.kv || !entry.kv.id) {
            Dialog.showToast('浏览记录无效')
            return
        }
        const type = entry.kv.type || 'illust'
        if (type === 'user') {
            Navigator.navigateToDescriptor(this.pluginName, {
                method: 'getUserDetail',
                args: [String(entry.kv.id)],
                title: entry.title || '',
            })
            return
        }
        if (type === 'novel') {
            Navigator.navigateToDescriptor(this.pluginName, {
                method: 'getNovelDetail',
                args: [String(entry.kv.id)],
                title: entry.title || '',
            })
            return
        }
        if (type === 'series') {
            Navigator.navigateToDescriptor(this.pluginName, {
                method: 'getSeriesDetail',
                args: [String(entry.kv.id)],
                title: entry.title || '',
            })
            return
        }
        Navigator.navigateToDescriptor(this.pluginName, {
            method: 'getDetail',
            args: [String(entry.kv.id)],
            title: entry.title || '',
        })
    }

    getUrl() {
        return 'https://www.pixiv.net/'
    }

    // ========================================================================
    // 浏览页：分类 / 筛选 / 数据获取
    // ========================================================================

    getCategory() {
        const parts = [
            { name: '快捷入口', categories: ['ID 直达', '画师作品', '画师搜索', '相关作品'] },
            { name: '发现', categories: ['推荐插画', '推荐漫画', '热门预览', '热门标签'] },
            { name: '排行榜', categories: ['综合排行', '插画排行', '漫画排行', '小说排行'] },
            { name: '搜索', categories: ['高级搜索', '更多筛选', '标签搜索', '小说搜索'] },
        ]
        return { title: 'Pixiv', parts: parts }
    }

    _periodOptions(withR18) {
        const list = [
            { value: 'day', text: '日榜' },
            { value: 'week', text: '周榜' },
            { value: 'month', text: '月榜' },
            { value: 'week_rookie', text: '新人' },
            { value: 'week_original', text: '原创' },
            { value: 'day_male', text: '男性向' },
            { value: 'day_female', text: '女性向' },
        ]
        if (withR18) {
            list.push({ value: 'day_r18', text: 'R18 日榜' })
            list.push({ value: 'week_r18', text: 'R18 周榜' })
        }
        return list
    }

    _novelPeriodOptions(withR18) {
        const list = [
            { value: 'day', text: '日榜' },
            { value: 'week', text: '周榜' },
            { value: 'month', text: '月榜' },
            { value: 'week_rookie', text: '新人' },
        ]
        if (withR18) list.push({ value: 'day_r18', text: 'R18 日榜' })
        return list
    }

    _toolOptions() {
        const tools = [
            'SAI', 'Photoshop', 'CLIP STUDIO PAINT', 'Procreate', 'ibisPaint',
            'MediBang Paint', 'Illustrator', 'Krita', 'Blender', '3dsMax',
            'Maya', 'Live2D', 'ComicStudio', 'Paint 3D', 'Aseprite',
            'FireAlpaca', 'GIMP', 'Inkscape', 'openCanvas', 'ArtRage',
        ]
        return [{ value: '', text: '全部' }].concat(tools.map((t) => ({ value: t, text: t })))
    }

    _langOptions() {
        return [
            { value: '', text: '全部' },
            { value: 'ja', text: '日本語' },
            { value: 'zh-cn', text: '简体中文' },
            { value: 'zh-tw', text: '繁體中文' },
            { value: 'en', text: 'English' },
            { value: 'ko', text: '한국어' },
            { value: 'es', text: 'Español' },
            { value: 'fr', text: 'Français' },
            { value: 'de', text: 'Deutsch' },
            { value: 'ru', text: 'Русский' },
            { value: 'other', text: '其他' },
        ]
    }

    getCategoryOptions(category) {
        if (category === 'ID 直达') {
            return [
                {
                    label: '类型',
                    options: [
                        { value: 'illust', text: '作品 ID' },
                        { value: 'user', text: '画师 ID' },
                        { value: 'novel', text: '小说 ID' },
                        { value: 'series', text: '系列 ID' },
                    ],
                },
                { label: 'ID（纯数字）', type: 'input' },
            ]
        }
        if (category === '画师作品') {
            return [
                { label: '画师 ID', type: 'input' },
                {
                    label: '类型',
                    options: [
                        { value: 'illust', text: '插画' },
                        { value: 'manga', text: '漫画' },
                    ],
                },
            ]
        }
        if (category === '画师搜索') {
            return [{ label: '画师名 / 关键词', type: 'input' }]
        }
        if (category === '热门预览') {
            return [{ label: '关键词', type: 'input' }]
        }
        if (category === '标签搜索') {
            return [
                { label: '标签 / 关键词', type: 'input' },
                { label: '排序', options: [{ value: 'date_desc', text: '最新' }, { value: 'date_asc', text: '最早' }] },
                { label: 'R18', options: [{ value: 'auto', text: '跟随设置' }, { value: 'hide', text: '隐藏' }, { value: 'only', text: '仅 R18' }] },
            ]
        }
        if (category === '高级搜索') {
            return [
                { label: '关键词', type: 'input' },
                {
                    label: '匹配方式',
                    options: [
                        { value: 'partial_match_for_tags', text: '部分标签' },
                        { value: 'exact_match_for_tags', text: '完全标签' },
                        { value: 'title_and_caption', text: '标题与简介' },
                        { value: 'keyword', text: '关键词' },
                    ],
                },
                { label: '排序', options: [{ value: 'date_desc', text: '最新' }, { value: 'date_asc', text: '最早' }] },
                {
                    label: '内容类型',
                    options: [
                        { value: 'illust_and_manga_and_ugoira', text: '插画 + 漫画 + 动图' },
                        { value: 'illust_and_ugoira', text: '插画 + 动图' },
                        { value: 'illust', text: '插画' },
                        { value: 'manga', text: '漫画' },
                        { value: 'ugoira', text: '动图' },
                    ],
                },
                {
                    label: 'R18',
                    options: [
                        { value: 'auto', text: '跟随设置' },
                        { value: 'hide', text: '隐藏' },
                        { value: 'show', text: '显示' },
                        { value: 'only', text: '仅 R18' },
                    ],
                },
                {
                    label: 'AI 作品',
                    options: [
                        { value: 'auto', text: '跟随设置' },
                        { value: 'hide', text: '隐藏' },
                        { value: 'show', text: '显示' },
                    ],
                },
                {
                    label: '时间范围',
                    options: [
                        { value: '', text: '不限' },
                        { value: 'day', text: '近一天' },
                        { value: 'week', text: '近一周' },
                        { value: 'month', text: '近一月' },
                        { value: 'half', text: '近半年' },
                        { value: 'year', text: '近一年' },
                    ],
                },
                { label: '最低收藏数（可留空）', type: 'input' },
            ]
        }
        if (category === '更多筛选') {
            return [
                { label: '关键词', type: 'input' },
                { label: '开始日期 YYYY-MM-DD', type: 'input' },
                { label: '结束日期 YYYY-MM-DD', type: 'input' },
                {
                    label: '尺寸',
                    options: [
                        { value: '', text: '不限' },
                        { value: '3000', text: '3000px × 3000px 以上' },
                        { value: '1000', text: '1000px × 1000px - 2999px' },
                        { value: '0', text: '999px × 999px 以下' },
                    ],
                },
                {
                    label: '比例',
                    options: [
                        { value: '', text: '不限' },
                        { value: 'landscape', text: '横图' },
                        { value: 'portrait', text: '竖图' },
                        { value: 'square', text: '方图' },
                    ],
                },
                { label: '作画工具', options: this._toolOptions() },
                { label: '语言（仅漫画）', options: this._langOptions() },
                {
                    label: '收藏数标签',
                    options: [
                        { value: '0', text: '不限' },
                        { value: '100', text: '100 users入り' },
                        { value: '500', text: '500 users入り' },
                        { value: '1000', text: '1000 users入り' },
                        { value: '5000', text: '5000 users入り' },
                        { value: '10000', text: '10000 users入り' },
                        { value: '30000', text: '30000 users入り' },
                    ],
                },
            ]
        }
        if (category === '综合排行' || category === '插画排行' || category === '漫画排行') {
            return [
                { label: '周期', options: this._periodOptions(this._r18Mode() !== 0) },
                { label: '日期 YYYY-MM-DD（留空=默认）', type: 'input' },
            ]
        }
        if (category === '小说排行') {
            return [
                { label: '周期', options: this._novelPeriodOptions(this._r18Mode() !== 0) },
                { label: '日期 YYYY-MM-DD（留空=默认）', type: 'input' },
            ]
        }
        if (category === '相关作品') {
            return [{ label: '作品 ID', type: 'input' }]
        }
        if (category === '小说搜索') {
            return [
                { label: '关键词', type: 'input' },
                {
                    label: '匹配方式',
                    options: [
                        { value: 'partial_match_for_tags', text: '部分标签' },
                        { value: 'exact_match_for_tags', text: '完全标签' },
                        { value: 'text', text: '正文' },
                        { value: 'keyword', text: '关键词' },
                    ],
                },
                { label: '排序', options: [{ value: 'date_desc', text: '最新' }, { value: 'date_asc', text: '最早' }] },
                {
                    label: '类型',
                    options: [
                        { value: '0', text: '全部' },
                        { value: '1', text: '恋爱' },
                        { value: '2', text: '异世界奇幻' },
                        { value: '3', text: '现代奇幻' },
                        { value: '4', text: '悬疑' },
                        { value: '5', text: '恐怖' },
                        { value: '6', text: '科幻' },
                        { value: '7', text: '文学' },
                        { value: '10', text: 'BL' },
                        { value: '11', text: '百合' },
                        { value: '17', text: '其他' },
                    ],
                },
                {
                    label: '语言',
                    options: [
                        { value: '', text: '全部' },
                        { value: 'ja', text: '日本語' },
                        { value: 'zh-cn', text: '简体中文' },
                        { value: 'zh-tw', text: '繁體中文' },
                        { value: 'en', text: 'English' },
                        { value: 'ko', text: '한국어' },
                    ],
                },
            ]
        }
        return null
    }

    async loadCategory(category, page = 1, options = []) {
        const r = await this._fetchCategory(category, 1, options || [])
        if (r && r.direct) return r.direct
        const items = (r && r.items) || []
        if (items.length === 0) {
            return [UI.Text(r && r.message ? r.message : '没有内容')]
        }
        if (!r || !r.maxPage || r.maxPage <= 1) return items
        return [UI.Pagination({
            page: 1,
            maxPage: r.maxPage,
            pageMethod: 'loadCategoryPage',
            pageArgs: [category, 1, options || []],
        })]
    }

    async loadCategoryPage(category, page = 1, options = []) {
        const r = await this._fetchCategory(category, page, options || [])
        return (r && r.items) || []
    }

    async _fetchCategory(category, page, options) {
        options = options || []
        if (category === 'ID 直达') return await this._loadById(options)
        if (category === '画师作品') {
            const uid = String(options[0] || '').trim()
            if (!/^\d+$/.test(uid)) return { items: [UI.Text('请输入纯数字画师 ID')], maxPage: 1 }
            return await this._memberWorks(uid, String(options[1] || 'illust'), page)
        }
        if (category === '画师搜索') {
            const word = String(options[0] || '').trim()
            if (!word) return { items: [UI.Text('请输入画师名 / 关键词')], maxPage: 1 }
            return await this._userSearch(word, page)
        }
        if (category === '标签搜索' || category === '高级搜索' || category === '更多筛选') {
            const spec = this._parseSearchOptions(category, options)
            if (!spec.word) return { items: [UI.Text('请输入关键词')], maxPage: 1 }
            return await this._searchPage(spec, page)
        }
        if (category === '小说搜索') {
            return await this._novelSearch(options, page)
        }
        if (category === '推荐插画') return await this._feed('/illust_recommended', page, '推荐插画')
        if (category === '推荐漫画') return await this._feed('/manga_recommended', page, '推荐漫画')
        if (category === '热门预览') {
            const word = String(options[0] || '').trim()
            if (!word) return { items: [UI.Text('请输入关键词')], maxPage: 1 }
            return await this._popularPreview(word)
        }
        if (category === '最新插画') return await this._feed('/illust_new', page, '最新插画')
        if (category === '最新漫画') return await this._feed('/illust_new', page, '最新漫画', { content_type: 'manga' })
        if (category === '热门标签') return await this._tagsPage()
        if (category === '相关作品') {
            const id = String(options[0] || '').trim()
            if (!/^\d+$/.test(id)) return { items: [UI.Text('请输入作品 ID')], maxPage: 1 }
            return await this._related(id, page)
        }
        if (category === '综合排行' || category === '插画排行' || category === '漫画排行') {
            return await this._rank(category, page, options)
        }
        if (category === '小说排行') {
            return await this._novelRank(page, options)
        }
        return { items: [UI.Text('未知分类：' + category)], maxPage: 1 }
    }

    async _loadById(options) {
        const type = String(options[0] || 'illust')
        const id = String(options[1] || '').trim()
        if (!/^\d+$/.test(id)) return { items: [UI.Text('请输入纯数字 ID')], maxPage: 1 }
        if (type === 'illust') return { direct: await this.getDetail(id) }
        if (type === 'user') return { direct: await this.getUserDetail(id) }
        if (type === 'novel') return { direct: await this.getNovelDetail(id) }
        if (type === 'series') return { direct: await this.getSeriesDetail(id) }
        return { items: [UI.Text('未知 ID 类型：' + type)], maxPage: 1 }
    }

    _parseSearchOptions(category, options) {
        options = options || []
        const spec = {
            word: '',
            params: {},
            contentType: '',
            r18Mode: this._r18Mode(),
            hideAI: !this.showAI,
            minBookmarks: this.minBookmarks,
        }
        if (category === '标签搜索') {
            spec.word = String(options[0] || '').trim()
            const order = String(options[1] || 'date_desc')
            const r18Opt = String(options[2] || 'auto')
            spec.params = { mode: 'partial_match_for_tags', order: order, include_potential_violation_works: 'false' }
            if (spec.hideAI) spec.params.search_ai_type = 1
            this._applyR18Option(spec, r18Opt)
        } else if (category === '高级搜索') {
            spec.word = String(options[0] || '').trim()
            const mode = String(options[1] || 'partial_match_for_tags')
            const order = String(options[2] || 'date_desc')
            spec.contentType = String(options[3] || 'illust_and_manga_and_ugoira')
            const r18Opt = String(options[4] || 'auto')
            const aiOpt = String(options[5] || 'auto')
            const period = String(options[6] || '')
            const min = parseInt(String(options[7] || ''), 10)
            spec.params = {
                mode: mode,
                order: order,
                content_type: spec.contentType,
                include_potential_violation_works: 'false',
            }
            if (period) spec.params.start_date = this._periodStart(period)
            if (!isNaN(min) && min > 0) spec.minBookmarks = min
            this._applyR18Option(spec, r18Opt)
            if (aiOpt === 'hide') {
                spec.hideAI = true
                spec.params.search_ai_type = 1
            } else if (aiOpt === 'show') {
                spec.hideAI = false
            } else if (spec.hideAI) {
                spec.params.search_ai_type = 1
            }
        } else if (category === '更多筛选') {
            spec.word = String(options[0] || '').trim()
            const start = String(options[1] || '').trim()
            const end = String(options[2] || '').trim()
            const size = String(options[3] || '')
            const ratio = String(options[4] || '')
            const tool = String(options[5] || '')
            const lang = String(options[6] || '')
            const bookmarkTag = String(options[7] || '0')
            spec.params = {
                mode: 'partial_match_for_tags',
                order: 'date_desc',
                include_potential_violation_works: 'false',
            }
            if (/^\d{4}-\d{2}-\d{2}$/.test(start)) spec.params.start_date = start
            if (/^\d{4}-\d{2}-\d{2}$/.test(end)) spec.params.end_date = end
            if (size === '3000') {
                spec.params.width_min = 3000
                spec.params.height_min = 3000
            } else if (size === '1000') {
                spec.params.width_min = 1000
                spec.params.height_min = 1000
                spec.params.width_max = 2999
                spec.params.height_max = 2999
            } else if (size === '0') {
                spec.params.width_max = 999
                spec.params.height_max = 999
            }
            if (ratio) spec.params.ratio_pattern = ratio
            if (tool) spec.params.tool = tool
            if (lang) {
                spec.params.lang = lang
                spec.params.content_type = 'manga'
                spec.contentType = 'manga'
            }
            const bm = parseInt(bookmarkTag, 10)
            if (!isNaN(bm) && bm > 0) {
                spec.minBookmarks = bm
                const suffix = bm + 'users入り'
                if (spec.word.indexOf(suffix) < 0) spec.word += ' ' + suffix
            }
            if (spec.hideAI) spec.params.search_ai_type = 1
            // 这里的 R18 跟随设置（没有单独选项）
            if (spec.r18Mode === 0 && spec.word.indexOf('-R-18') < 0) {
                spec.word += ' -R-18 -R18 -18+'
            } else if (spec.r18Mode === 2 && spec.word.indexOf('R-18') < 0) {
                spec.word += ' R-18'
            }
        }
        return spec
    }

    _applyR18Option(spec, r18Opt) {
        if (r18Opt === 'hide') spec.r18Mode = 0
        else if (r18Opt === 'only') spec.r18Mode = 2
        else if (r18Opt === 'show') spec.r18Mode = 1
        if (spec.r18Mode === 0 && spec.word.indexOf('-R-18') < 0) {
            spec.word += ' -R-18 -R18 -18+'
        } else if (spec.r18Mode === 2 && spec.word.indexOf('R-18') < 0) {
            spec.word += ' R-18'
        }
    }

    async _searchPage(spec, page) {
        const params = { word: spec.word, page: page }
        const extra = spec.params || {}
        const keys = Object.keys(extra)
        for (let i = 0; i < keys.length; i++) {
            const k = keys[i]
            if (extra[k] !== undefined && extra[k] !== null && extra[k] !== '') {
                params[k] = extra[k]
            }
        }
        let data = await this._api('/search', params)
        let fallback = false
        if (!data) {
            // 公共实例 / 未授权实例常常拒绝高级参数；退回纯关键词后做本地筛选
            console.warn('[pixiv] 高级搜索失败，降级为纯关键词 + 本地筛选')
            data = await this._api('/search', { word: spec.word, page: page }, { silent: true })
            fallback = true
        }
        if (!data) return { items: [], maxPage: 1, message: '搜索失败：API 实例不可用或已限流' }
        let list = (data.illusts || []).slice()
        if (spec.contentType) {
            let allow = null
            if (spec.contentType === 'illust') allow = ['illust']
            else if (spec.contentType === 'manga') allow = ['manga']
            else if (spec.contentType === 'ugoira') allow = ['ugoira']
            else if (spec.contentType === 'illust_and_ugoira') allow = ['illust', 'ugoira']
            if (allow) {
                list = list.filter((a) => allow.indexOf(String(a.type)) >= 0)
            }
        }
        if (spec.params && spec.params.start_date) {
            list = list.filter((a) => String(a.create_date || '').slice(0, 10) >= spec.params.start_date)
        }
        if (spec.params && spec.params.end_date) {
            list = list.filter((a) => String(a.create_date || '').slice(0, 10) <= spec.params.end_date)
        }
        // 尺寸 / 比例在本地再兜底一次：公共实例拒绝高级参数时也能按用户选择过滤
        if (spec.params) {
            const wmin = Number(spec.params.width_min) || 0
            const wmax = Number(spec.params.width_max) || 0
            const hmin = Number(spec.params.height_min) || 0
            const hmax = Number(spec.params.height_max) || 0
            if (wmin || wmax || hmin || hmax) {
                list = list.filter((a) => {
                    const w = Number(a.width) || 0
                    const h = Number(a.height) || 0
                    if (wmin && w < wmin) return false
                    if (wmax && w > wmax) return false
                    if (hmin && h < hmin) return false
                    if (hmax && h > hmax) return false
                    return true
                })
            }
            const ratio = spec.params.ratio_pattern
            if (ratio === 'landscape') {
                list = list.filter((a) => (Number(a.width) || 0) > (Number(a.height) || 0))
            } else if (ratio === 'portrait') {
                list = list.filter((a) => (Number(a.width) || 0) < (Number(a.height) || 0))
            } else if (ratio === 'square') {
                list = list.filter((a) => {
                    const w = Number(a.width) || 0
                    const h = Number(a.height) || 0
                    if (!w || !h) return false
                    return Math.abs(w - h) <= Math.max(w, h) * 0.05
                })
            }
        }
        list = this._filterList(list, {
            hideR18: spec.r18Mode === 0,
            onlyR18: spec.r18Mode === 2,
            hideAI: spec.hideAI,
            minBookmarks: spec.minBookmarks,
        })
        if (fallback) {
            const words = this._searchWords(spec.word)
            const mode = (spec.params && spec.params.mode) || ''
            if (mode === 'exact_match_for_tags' && words.length) {
                list = list.filter((a) => this._hasAllTags(a, words))
            } else if (mode === 'title_and_caption' && words.length) {
                list = list.filter((a) => {
                    const text = (String(a.title || '') + ' ' + String(a.caption || '')).toLowerCase()
                    for (let i = 0; i < words.length; i++) {
                        if (text.indexOf(String(words[i]).toLowerCase()) < 0) return false
                    }
                    return true
                })
            } else if (mode === 'keyword' && words.length) {
                list = list.filter((a) => this._hasAllTags(a, words) ||
                    (String(a.title || '') + ' ' + String(a.caption || ''))
                        .toLowerCase().indexOf(String(words[0]).toLowerCase()) >= 0)
            }
            if (spec.params && spec.params.order === 'date_asc') list = list.slice().reverse()
        }
        const items = list.map((a) => this._card(a)).filter((x) => x != null)
        return {
            items: items,
            maxPage: data.next_url ? 50 : 1,
            message: items.length ? '' : '没有找到匹配作品',
        }
    }

    async _feed(path, page, label, extra) {
        const params = { page: page }
        if (extra) {
            const keys = Object.keys(extra)
            for (let i = 0; i < keys.length; i++) params[keys[i]] = extra[keys[i]]
        }
        let data = await this._api(path, params, { silent: true })
        let fallbackRank = false
        if (!data) {
            console.warn('[pixiv] ' + label + ' 接口不可用，回退为日榜')
            data = await this._api('/rank', { mode: 'day', page: 1 }, { silent: true })
            fallbackRank = !!data
        }
        if (!data) return { items: [], maxPage: 1, message: label + '接口不可用（该 API 实例可能未授权）' }
        let list = (data.illusts || []).slice()
        if (fallbackRank && label === '推荐插画') {
            list = list.filter((a) => a.type === 'illust')
        } else if (fallbackRank && label === '推荐漫画') {
            list = list.filter((a) => a.type === 'manga')
        }
        list = this._filterList(list, this._defaultFilter())
        return {
            items: list.map((a) => this._card(a)).filter((x) => x != null),
            maxPage: 1,
            message: list.length ? '' : label + '暂无内容',
        }
    }

    async _popularPreview(word) {
        const data = await this._api('/popular_preview', { word: word }, { silent: true })
        if (!data || !Array.isArray(data.illusts)) {
            return { items: [UI.Text('热门预览接口不可用（该 API 实例可能未授权）')], maxPage: 1 }
        }
        let list = this._filterList(data.illusts, this._defaultFilter())
        return {
            items: list.map((a) => this._card(a)).filter((x) => x != null),
            maxPage: 1,
            message: list.length ? '' : '暂无热门预览',
        }
    }

    async _tagsPage() {
        let data = null
        if (this._tagCache) {
            data = this._tagCache
        } else {
            data = await this._api('/tags', {}, { silent: true })
            if (data) this._tagCache = data
        }
        if (!data || !Array.isArray(data.trend_tags)) {
            return { items: [], maxPage: 1, message: '热门标签接口不可用' }
        }
        const items = data.trend_tags.map((t) => this._tagCard(t)).filter((x) => x != null)
        return { items: items, maxPage: 1, message: items.length ? '' : '暂无热门标签' }
    }

    async _related(id, page) {
        const data = await this._api('/related', { id: id, page: page }, { silent: true })
        if (data && Array.isArray(data.illusts)) {
            let list = this._filterList(data.illusts, this._defaultFilter())
            return {
                items: list.map((a) => this._card(a)).filter((x) => x != null),
                maxPage: data.next_url ? 10 : 1,
            }
        }
        // 公共实例没有 related 接口时，用作品首个标签搜索兜底
        console.warn('[pixiv] related 接口不可用，按首个标签搜索兜底')
        const art = await this._getIllust(id)
        const tag = art && art.tags && art.tags[0] ? String(art.tags[0].name || '') : ''
        if (!tag) return { items: [UI.Text('暂无相关作品')], maxPage: 1 }
        const sdata = await this._api('/search', { word: tag, page: page }, { silent: true })
        if (!sdata || !Array.isArray(sdata.illusts)) {
            return { items: [UI.Text('暂无相关作品（related 接口不可用）')], maxPage: 1 }
        }
        let list = sdata.illusts.filter((a) => String(a.id) !== String(id))
        list = this._filterList(list, this._defaultFilter())
        return {
            items: list.map((a) => this._card(a)).filter((x) => x != null),
            maxPage: sdata.next_url ? 10 : 1,
        }
    }

    async _rank(category, page, options) {
        const period = String(options[0] || 'day')
        const date = String(options[1] || '').trim()
        const params = { mode: period, page: page }
        if (/^\d{4}-\d{2}-\d{2}$/.test(date)) params.date = date
        const data = await this._api('/rank', params)
        if (!data || !Array.isArray(data.illusts)) {
            return { items: [UI.Text('排行接口不可用（该 API 实例可能未授权）')], maxPage: 1 }
        }
        let list = data.illusts.slice()
        if (category === '插画排行') list = list.filter((a) => a.type === 'illust')
        else if (category === '漫画排行') list = list.filter((a) => a.type === 'manga')
        const r18Mode = period.indexOf('r18') >= 0 ? 1 : this._r18Mode()
        list = this._filterList(list, {
            hideR18: r18Mode === 0,
            onlyR18: r18Mode === 2,
            hideAI: !this.showAI,
            minBookmarks: this.minBookmarks,
        })
        const baseRank = (page - 1) * 30
        const cards = list.map((a, i) => this._card(a, { rank: baseRank + i + 1 })).filter((x) => x != null)
        return { items: cards, maxPage: data.next_url ? 20 : 1 }
    }

    async _novelRank(page, options) {
        const period = String(options[0] || 'day')
        const date = String(options[1] || '').trim()
        const params = { mode: period, page: page }
        if (/^\d{4}-\d{2}-\d{2}$/.test(date)) params.date = date
        const data = await this._api('/rank_novel', params)
        if (!data || !Array.isArray(data.novels)) {
            return { items: [UI.Text('小说排行接口不可用（该 API 实例可能未授权）')], maxPage: 1 }
        }
        let list = data.novels.slice()
        list = this._filterList(list, this._defaultFilter())
        return {
            items: list.map((n) => this._novelCard(n)).filter((x) => x != null),
            maxPage: data.next_url ? 10 : 1,
        }
    }

    async _memberWorks(userId, type, page) {
        const params = {
            id: String(userId),
            page: page,
            illust_type: type === 'manga' ? 'manga' : 'illust',
        }
        const data = await this._api('/member_illust', params, { silent: true })
        if (data && Array.isArray(data.illusts)) {
            let list = this._filterList(data.illusts, this._defaultFilter())
            return {
                items: list.map((a) => this._card(a)).filter((x) => x != null),
                maxPage: data.next_url ? 50 : 1,
            }
        }
        // 公共实例没有 member_illust 时，按画师名搜索并过滤 user.id 兜底
        console.warn('[pixiv] member_illust 接口不可用，按画师名搜索兜底')
        const uid = String(userId)
        let userData = this._userCache[uid]
        if (!userData) {
            userData = await this._api('/member', { id: uid }, { silent: true })
            if (userData) this._userCache[uid] = userData
        }
        const name = userData && userData.user ? String(userData.user.name || '') : ''
        if (!name) {
            return { items: [UI.Text('无法获取该画师的作品（API 未授权或画师不存在）')], maxPage: 1 }
        }
        const sdata = await this._api('/search', { word: name, page: page }, { silent: true })
        if (!sdata || !Array.isArray(sdata.illusts)) {
            return { items: [UI.Text('无法获取该画师的作品（API 未授权）')], maxPage: 1 }
        }
        let list = sdata.illusts.filter((a) => a.user && String(a.user.id) === uid)
        if (type === 'manga') list = list.filter((a) => a.type === 'manga')
        list = this._filterList(list, this._defaultFilter())
        return {
            items: list.map((a) => this._card(a)).filter((x) => x != null),
            maxPage: sdata.next_url ? 50 : 1,
            message: list.length ? '' : '未搜到该画师的作品（已按画师名兜底搜索）',
        }
    }

    async _userSearch(word, page) {
        const data = await this._api('/search_user', { word: word, page: page }, { silent: true })
        if (!data || !Array.isArray(data.user_previews)) {
            return { items: [UI.Text('画师搜索接口不可用')], maxPage: 1 }
        }
        const cards = []
        for (let i = 0; i < data.user_previews.length; i++) {
            const preview = data.user_previews[i]
            const user = preview.user || preview
            const card = this._userCard(user, preview)
            if (card) cards.push(card)
        }
        return { items: cards, maxPage: data.next_url ? 50 : 1 }
    }

    async _novelSearch(options, page) {
        options = options || []
        const word = String(options[0] || '').trim()
        if (!word) return { items: [UI.Text('请输入小说关键词')], maxPage: 1 }
        const params = {
            word: word,
            page: page,
            mode: String(options[1] || 'partial_match_for_tags'),
            sort: String(options[2] || 'date_desc'),
            include_potential_violation_works: 'false',
        }
        const genre = String(options[3] || '0')
        if (genre && genre !== '0') params.genre = genre
        const lang = String(options[4] || '')
        if (lang) params.lang = lang
        if (!this.showAI) params.search_ai_type = 1
        const data = await this._api('/search_novel', params)
        if (!data) return { items: [UI.Text('小说搜索失败（API 实例不可用或未授权）')], maxPage: 1 }
        let list = (data.novels || []).slice()
        list = this._filterList(list, this._defaultFilter())
        return {
            items: list.map((n) => this._novelCard(n)).filter((x) => x != null),
            maxPage: data.next_url ? 50 : 1,
        }
    }

    // ========================================================================
    // 画师详情 / 系列详情
    // ========================================================================

    async getUserDetail(id) {
        const uid = String(id)
        let data = this._userCache[uid]
        if (!data) {
            data = await this._api('/member', { id: uid })
            if (data) this._userCache[uid] = data
        }
        if (!data || !data.user) {
            Dialog.showToast('画师不存在或 API 不可用')
            return [UI.Text('无法获取画师 ' + uid + ' 的信息')]
        }
        const user = data.user
        const profile = data.profile || {}
        const title = String(user.name || user.account || ('画师 ' + uid))
        const avatar = this._proxy((user.profile_image_urls || {}).medium || '')
        const meta = []
        if (user.account) meta.push('@' + String(user.account))
        if (profile.total_illusts !== undefined) meta.push('插画 ' + this._fmtNum(profile.total_illusts))
        if (profile.total_manga !== undefined) meta.push('漫画 ' + this._fmtNum(profile.total_manga))
        if (profile.total_novels !== undefined) meta.push('小说 ' + this._fmtNum(profile.total_novels))
        if (profile.total_follow_users !== undefined) meta.push('关注者 ' + this._fmtNum(profile.total_follow_users))
        if (profile.total_illust_bookmarks_public !== undefined) {
            meta.push('被收藏 ' + this._fmtNum(profile.total_illust_bookmarks_public))
        }

        const items = []
        items.push(UI.Card({
            padding: 12,
            shapeRadius: 8,
            child: UI.Row({
                crossAxisAlignment: 'start',
                children: [
                    avatar
                        ? UI.Image({ src: avatar, width: 88, height: 88, headers: this._imgHeaders() })
                        : UI.Icon({ name: 'person', size: 64, color: '#999999' }),
                    UI.SizedBox({ width: 12 }),
                    UI.Expanded({
                        child: UI.Column({
                            crossAxisAlignment: 'start',
                            children: [
                                UI.Text({ content: title, style: { fontSize: 16, weight: 'bold' }, maxLines: 2 }),
                                ...meta.map((m) => UI.Text({ content: m, style: { fontSize: 12, color: '#888888' }, maxLines: 1 })),
                            ].filter((x) => x != null),
                        }),
                    }),
                ],
            }),
        }))

        const buttons = []
        buttons.push(UI.Button({
            label: '插画作品',
            style: 'filled',
            icon: 'image',
            onTap: UI.Action({ method: 'openUserWorks', args: [uid, 'illust'] }),
        }))
        buttons.push(UI.Button({
            label: '漫画作品',
            style: 'text',
            icon: 'menu_book',
            onTap: UI.Action({ method: 'openUserWorks', args: [uid, 'manga'] }),
        }))
        buttons.push(UI.Button({
            label: '复制画师 ID',
            style: 'text',
            icon: 'content_copy',
            onTap: UI.Action({ method: 'copyText', args: [uid] }),
        }))
        buttons.push(UI.Button({
            label: '源站',
            style: 'text',
            icon: 'open_in_new',
            onTap: UI.Action({ method: 'openWeb', args: ['https://www.pixiv.net/users/' + uid] }),
        }))
        items.push(UI.Card({
            padding: 12,
            shapeRadius: 8,
            child: UI.Wrap({ spacing: 6, runSpacing: 6, children: buttons }),
        }))

        // 最近 6 件作品
        const works = await this._memberWorks(uid, 'illust', 1)
        if (works && works.items && works.items.length &&
            works.items[0] && works.items[0].__type === 'card') {
            items.push(UI.Text({ content: '最近作品', style: { fontSize: 14, weight: 'bold' } }))
            const take = works.items.slice(0, 6)
            for (let i = 0; i < take.length; i++) items.push(take[i])
        }

        PluginBrowse.open(this.pluginName, {
            id: uid,
            title: title,
            cover: avatar,
            kv: { id: uid, type: 'user' },
        })
        return items
    }

    async getUserWorks(userId, type) {
        return [UI.Pagination({
            page: 1,
            maxPage: 50,
            pageMethod: 'loadCategoryPage',
            pageArgs: ['画师作品', 1, [String(userId), String(type || 'illust')]],
        })]
    }

    async getSeriesDetail(id) {
        const sid = String(id)
        const series = await this._loadSeries(sid)
        if (!series) {
            Dialog.showToast('系列不存在或 API 不可用')
            return [UI.Text('无法获取系列 ' + sid)]
        }
        const cover = series.works && series.works[0]
            ? this._proxy(this._coverUrl(series.works[0], 'large'))
            : ''
        const items = []
        items.push(UI.Card({
            padding: 12,
            shapeRadius: 8,
            child: UI.Row({
                crossAxisAlignment: 'start',
                children: [
                    cover ? UI.Image({ src: cover, width: 110, height: 150, headers: this._imgHeaders() }) : null,
                    UI.SizedBox({ width: 12 }),
                    UI.Expanded({
                        child: UI.Column({
                            crossAxisAlignment: 'start',
                            children: [
                                UI.Text({ content: series.title, style: { fontSize: 16, weight: 'bold' }, maxLines: 2 }),
                                UI.Text({ content: '共 ' + series.chapters.length + ' 部作品', style: { fontSize: 12, color: '#888888' }, maxLines: 1 }),
                                series.description
                                    ? UI.Text({ content: series.description, style: { fontSize: 12, color: '#555555' }, maxLines: 4 })
                                    : null,
                            ].filter((x) => x != null),
                        }),
                    }),
                ].filter((x) => x != null),
            }),
        }))

        this._comicId = sid
        this._comicTitle = series.title
        this._chapters = series.chapters

        const readButtons = []
        for (let i = 0; i < series.chapters.length; i++) {
            const ep = series.chapters[i]
            readButtons.push(UI.Button({
                label: String(ep.title || ep.id),
                style: 'text',
                onTap: UI.Action({ method: 'openReader', args: [String(ep.id)] }),
            }))
        }
        items.push(UI.ExpansionTile({
            title: UI.Text({ content: '系列作品（' + series.chapters.length + '）', style: { fontSize: 14, weight: 'bold' }, maxLines: 1 }),
            initiallyExpanded: true,
            shapeRadius: 0,
            children: [UI.Card({
                padding: 8,
                shapeRadius: 8,
                child: UI.Wrap({ spacing: 6, runSpacing: 6, children: readButtons }),
            })],
        }))

        for (let i = 0; i < series.works.length; i++) {
            const card = this._card(series.works[i])
            if (card) items.push(card)
        }

        PluginBrowse.open(this.pluginName, {
            id: sid,
            title: series.title,
            cover: cover,
            kv: { id: sid, type: 'series' },
        })
        return items
    }

    // ========================================================================
    // 小说（可选能力）
    // ========================================================================

    async getNovelDetail(id) {
        const nid = String(id)
        let novel = this._novelCache[nid]
        if (!novel) {
            const data = await this._api('/novel_detail', { id: nid })
            if (data && data.novel) {
                novel = data.novel
                this._novelCache[nid] = novel
            }
        }
        if (!novel) {
            Dialog.showToast('小说不存在或 API 不可用')
            return [UI.Text('无法获取小说 ' + nid)]
        }
        const title = String(novel.title || '无题')
        const cover = this._proxy(this._coverUrl(novel, 'large'))
        const user = novel.user || {}
        const meta = []
        meta.push('小说' + (novel.text_length ? ' · ' + this._fmtNum(novel.text_length) + ' 字' : ''))
        if (novel.create_date) meta.push('投稿 ' + String(novel.create_date).slice(0, 10))
        if (novel.total_bookmarks !== undefined) meta.push('收藏 ' + this._fmtNum(novel.total_bookmarks))
        if (user.name) meta.push('作者 ' + user.name)

        const items = []
        items.push(UI.Card({
            padding: 12,
            shapeRadius: 8,
            child: UI.Row({
                crossAxisAlignment: 'start',
                children: [
                    cover ? UI.Image({ src: cover, width: 100, height: 140, headers: this._imgHeaders() }) : null,
                    UI.SizedBox({ width: 12 }),
                    UI.Expanded({
                        child: UI.Column({
                            crossAxisAlignment: 'start',
                            children: [
                                UI.Text({ content: title, style: { fontSize: 16, weight: 'bold' }, maxLines: 3 }),
                                ...meta.map((m) => UI.Text({ content: m, style: { fontSize: 12, color: '#888888' }, maxLines: 1 })),
                                this._badges(novel).length
                                    ? UI.Wrap({
                                        spacing: 4,
                                        runSpacing: 4,
                                        children: this._badges(novel).map((b) => this._tagChip(
                                            b,
                                            b.indexOf('R-18') === 0 ? '#ffebee' : '#e3f2fd',
                                            b.indexOf('R-18') === 0 ? '#c62828' : '#1565c0',
                                        )),
                                    })
                                    : null,
                            ].filter((x) => x != null),
                        }),
                    }),
                ].filter((x) => x != null),
            }),
        }))

        const buttons = []
        buttons.push(UI.Button({
            label: '开始阅读',
            style: 'filled',
            icon: 'menu_book',
            onTap: UI.Action({ method: 'openNovelReader', args: [nid] }),
        }))
        if (user.id) {
            buttons.push(UI.Button({
                label: '作者作品',
                style: 'text',
                icon: 'person',
                onTap: UI.Action({ method: 'openUserWorks', args: [String(user.id), 'illust'] }),
            }))
        }
        buttons.push(UI.Button({
            label: '复制 ID',
            style: 'text',
            icon: 'content_copy',
            onTap: UI.Action({ method: 'copyText', args: [nid] }),
        }))
        buttons.push(UI.Button({
            label: '源站',
            style: 'text',
            icon: 'open_in_new',
            onTap: UI.Action({ method: 'openWeb', args: ['https://www.pixiv.net/novel/show.php?id=' + nid] }),
        }))
        items.push(UI.Card({
            padding: 12,
            shapeRadius: 8,
            child: UI.Wrap({ spacing: 6, runSpacing: 6, children: buttons }),
        }))

        const tags = (novel.tags || []).slice(0, 20)
        if (tags.length) {
            items.push(UI.Card({
                padding: 12,
                shapeRadius: 8,
                child: UI.Wrap({
                    spacing: 6,
                    runSpacing: 6,
                    children: tags.map((t) => UI.Button({
                        label: '#' + String(t.name || ''),
                        style: 'text',
                        onTap: UI.Action({ method: 'openTag', args: [String(t.name || '')] }),
                    })),
                }),
            }))
        }

        const desc = this._stripHtml(novel.description || novel.caption || '')
        if (desc) {
            items.push(UI.Card({
                padding: 12,
                shapeRadius: 8,
                child: UI.Text({ content: desc, style: { fontSize: 13, color: '#555555' }, maxLines: 8 }),
            }))
        }

        this._novelTitle = title
        PluginBrowse.open(this.pluginName, {
            id: nid,
            title: title,
            cover: cover,
            kv: { id: nid, type: 'novel' },
        })
        return items
    }

    async openNovelReader(epId) {
        const nid = String(epId)
        let title = this._novelTitle || ('小说 ' + nid)
        const novel = this._novelCache[nid]
        if (novel && novel.title) title = String(novel.title)
        Navigator.navigateToNovelReader({
            novelId: nid,
            novelTitle: title,
            chapters: [{
                id: nid,
                title: '正文',
                plugin: this.pluginName,
                method: 'loadChapterContent',
                args: [nid, nid],
            }],
            sourceKey: this.pluginName,
            initialChapter: 1,
        })
    }

    async loadChapterContent(novelId, epId) {
        const nid = String(novelId || epId || '').trim()
        if (!nid) throw new Error('缺少小说 ID')
        // 优先 /novel_text；部分实例只开放 /webview_novel（返回 {text}），做一次兜底。
        const data = await this._api('/novel_text', { id: nid }, { silent: true, retries: 0 })
        let text = data && data.novel_text
        if (!text) {
            const wv = await this._api('/webview_novel', { id: nid }, { silent: true, retries: 0 })
            if (wv && wv.text) text = this._stripHtml(wv.text)
        }
        if (!text) {
            throw new Error('无法获取小说正文（ID ' + nid + '）：当前 API 实例未配置小说正文权限，请改用自建 PxveAPI（配置 PIXIV_COOKIE），或点「源站」阅读')
        }
        return String(text)
    }

    // ========================================================================
    // 详情页按钮 / 标签等动作
    // ========================================================================

    openTag(tag) {
        const t = String(tag || '').trim()
        if (!t) return
        Navigator.navigateToDescriptor(this.pluginName, {
            method: 'searchResults',
            args: [t, { mode: 'partial_match_for_tags' }],
            title: '#' + t,
        })
    }

    async searchResults(word, params) {
        const w = String(word || '').trim()
        if (!w) return [UI.Text('请输入关键词')]
        return [UI.Pagination({
            page: 1,
            maxPage: 50,
            pageMethod: 'loadSearchResultsPage',
            pageArgs: [w, 1, params || {}],
        })]
    }

    async loadSearchResultsPage(word, page, params) {
        const spec = {
            word: String(word || ''),
            params: params || {},
            contentType: '',
            r18Mode: this._r18Mode(),
            hideAI: !this.showAI,
            minBookmarks: this.minBookmarks,
        }
        const r = await this._searchPage(spec, page)
        if (!r.items || r.items.length === 0) return [UI.Text('没有找到匹配作品')]
        return r.items
    }

    openRelated(id) {
        Navigator.navigateToDescriptor(this.pluginName, {
            method: 'getRelatedWorks',
            args: [String(id)],
            title: '相关作品',
        })
    }

    async getRelatedWorks(id) {
        return [UI.Pagination({
            page: 1,
            maxPage: 10,
            pageMethod: 'loadRelatedWorksPage',
            pageArgs: [String(id), 1],
        })]
    }

    async loadRelatedWorksPage(id, page) {
        const r = await this._related(String(id), page)
        return r.items || []
    }

    openUserWorks(id, type) {
        Navigator.navigateToDescriptor(this.pluginName, {
            method: 'getUserWorks',
            args: [String(id), String(type || 'illust')],
            title: (type === 'manga' ? '漫画' : '插画') + '作品',
        })
    }

    openSeries(id) {
        Navigator.navigateToDescriptor(this.pluginName, {
            method: 'getSeriesDetail',
            args: [String(id)],
            title: '系列',
        })
    }

    openWeb(url) {
        Navigator.navigateToWebview(String(url))
    }

    copyText(text) {
        setClipboard(String(text))
        Dialog.showToast('已复制：' + text)
    }
}
