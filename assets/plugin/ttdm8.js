// description: 天天动漫（www.ttdm8.me）视频源 — 搜索 / 分类 / 详情 / 播放
// type: video
//
// 站点 URL 模式（maccms 海螺 hltheme 模板，pathinfo 路由）：
//   搜索：/vod-search/{wd}-------------/              （第 1 页）
//         /vod-search/{wd}----------{page}---/        （第 2 页起）
//   分类：/vod-show/{type}-----------/                （第 1 页，无筛选）
//         /vod-show/{type}--------{page}---/          （翻页）
//         type 为数字 ID：1 国漫 / 2 日漫 / 3 欧美动漫 / 4 其他动漫 / 5 动画电影 / 6 里番
//         支持多条件筛选（剧情/字母/排序），槽位见 _showUrl
//   详情：/vod/{id}/                 （如 /vod/18169/）
//   播放：/vod-play/{vid}-{sid}-{nid}/   （如 /vod-play/18169-2-2/）
//         该页为 iframe 包裹页，真实播放器在 /vod-play/{vid}-{sid}-{nid}/?iframe=1
//         内页含 var player_aaaa={"url":"..."}，url 为 m3u8/mp4 直链或外站页面
//   封面：<img class="lazy lazyload" data-original="..." referrerpolicy="no-referrer">
//
// 接口约定：
//   search(keyword, page)        → List<UI.Card>（框架自动 loadMore 追加分页）
//   loadCategory / loadCategoryPage → 分类浏览（分页 + 多条件筛选）
//   getDetail(id)                → 头部元信息 + 简介 + 多线路剧集
//   play(url, title, cover)      → 优先提取播放页 player_aaaa.url 直链播放，
//                                  网页/加密链接回退交给 wyw 播放器嗅探

class ttdm8 extends PluginSource {
    name = '天天动漫'
    key = 'ttdm8'
    version = '1.0.0'
    baseUrl = 'https://www.ttdm8.me'

    /// 分类名称 → /vod-show/ 首段数字 ID
    static catKeys = {
        '国漫': '1',
        '日漫': '2',
        '欧美动漫': '3',
        '其他动漫': '4',
        '动画电影': '5',
        '里番': '6',
    }

    /// 筛选组（顺序 = getCategoryOptions 返回顺序 = loadCategory options 参数顺序）
    /// dynamic=true 的组（剧情）选项从分类页动态解析，各分类不同
    static filterDefs = [
        { label: '剧情', key: 'class', dynamic: true },
        { label: '字母', key: 'letter', values: ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '0-9'] },
        { label: '排序', key: 'by', values: ['time', 'hits', 'score'], texts: ['时间排序', '人气排序', '评分排序'] },
    ]

    /// 源网站地址（插件管理页「网站」菜单调用）
    getUrl() {
        return this.baseUrl
    }

    // ============================================================
    // 工具
    // ============================================================

    _abs(href) {
        if (!href) return ''
        if (href.indexOf('http://') === 0 || href.indexOf('https://') === 0) return href
        if (href.indexOf('//') === 0) return 'https:' + href
        if (href.indexOf('/') === 0) return this.baseUrl + href
        return this.baseUrl + '/' + href
    }

    _headers() {
        return {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
            'Accept-Language': 'zh-CN,zh;q=0.9',
            'Referer': this.baseUrl + '/',
        }
    }

    // ============================================================
    // 列表解析（海报式：首页/分类；卡片式：搜索结果）
    // ============================================================

    /// 海报式条目（<a class="module-poster-item" href="/vod/{id}/">）
    _posterCard(item) {
        const href = item.attributes.href || ''
        const m = href.match(/\/vod\/(\d+)/)
        if (!m) return null
        const id = m[1]
        const titleEl = item.querySelector('.module-poster-item-title')
        const title = titleEl ? (titleEl.text || '').trim() : (item.attributes.title || '').trim()
        if (!title) return null
        const cover = this._imgData(item)
        const note = this._note(item)
        return this._buildCard({ cover: cover, title: title, note: note, meta: '', id: id, playUrl: '' })
    }

    /// 卡片式条目（搜索结果 <div class="module-card-item">）
    _searchCard(item) {
        const linkEl = item.querySelector('a.module-card-item-poster[href*="/vod/"]')
        if (!linkEl) return null
        const href = linkEl.attributes.href || ''
        const m = href.match(/\/vod\/(\d+)/)
        if (!m) return null
        const id = m[1]
        const titleEl = item.querySelector('.module-card-item-title a')
        const title = titleEl ? (titleEl.text || '').trim() : ''
        if (!title) return null
        const cover = this._imgData(item)
        const note = this._note(item)
        // 元信息行（如 "2023 / 中国大陆 / 剧情,动画..."）
        let meta = ''
        for (const it of item.querySelectorAll('.module-info-item-content')) {
            const t = (it.text || '').trim()
            if (t) { meta = t; break }
        }
        // 搜索结果卡片带直接播放按钮（/vod-play/{id}-{sid}-{nid}/）
        let playUrl = ''
        const playBtn = item.querySelector('a.play-btn[href*="/vod-play/"]')
        if (playBtn) playUrl = playBtn.attributes.href || ''
        return this._buildCard({ cover: cover, title: title, note: note, meta: meta, id: id, playUrl: playUrl })
    }

    /// 封面：data-original > src（跳过占位图）
    _imgData(item) {
        const img = item.querySelector('img')
        if (!img) return ''
        return (img.attributes['data-original'] || img.attributes.src || '').trim()
    }

    /// 更新状态：.module-item-note（更新至X集 / 已完结 / 全X集 / HD国语...）
    _note(item) {
        const el = item.querySelector('.module-item-note')
        return el ? (el.text || '').trim() : ''
    }

    /// 构建列表卡片
    _buildCard({ cover, title, note, meta, id, playUrl }) {
        const infoRows = [
            UI.Text({ content: title, style: { fontSize: 14, weight: 'bold' }, maxLines: 1 }),
        ]
        if (note) {
            infoRows.push(UI.Row({
                crossAxisAlignment: 'center',
                children: [
                    UI.Icon({ name: 'play_circle_outline', size: 14, color: '#666666' }),
                    UI.SizedBox({ width: 4 }),
                    UI.Text({ content: note, style: { fontSize: 12, color: '#666666' }, maxLines: 1 }),
                ],
            }))
        }
        if (meta) {
            infoRows.push(UI.Text({ content: meta, style: { fontSize: 11, color: '#888888' }, maxLines: 1 }))
        }
        const actionButtons = []
        actionButtons.push(UI.IconButton({
            icon: 'open_in_new',
            tooltip: '详情',
            color: '#666666',
            size: 20,
            onTap: UI.Navigate({
                page: 'descriptor',
                method: 'getDetail',
                args: [id],
                title: title,
            }),
        }))
        if (playUrl) {
            actionButtons.push(UI.IconButton({
                icon: 'play_circle_filled',
                tooltip: '播放',
                color: '#e53935',
                size: 20,
                onTap: UI.Action({ method: 'play', args: [playUrl, title, cover] }),
            }))
        }
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
                            mainAxisAlignment: 'start',
                            children: infoRows,
                        }),
                    }),
                    UI.SizedBox({ width: 8 }),
                    UI.Column({
                        crossAxisAlignment: 'start',
                        children: [
                            ...actionButtons,
                        ]
                    }),
                ].filter(c => c != null),
            }),
        })
    }

    /// 解析列表页所有条目（海报式 + 卡片式），按 href 去重
    _parseCards(html) {
        const doc = new HtmlDocument(html)
        const cards = []
        const seen = {}
        for (const item of doc.querySelectorAll('a.module-poster-item[href*="/vod/"]')) {
            const card = this._posterCard(item)
            if (card && !seen[item.attributes.href]) {
                seen[item.attributes.href] = true
                cards.push(card)
            }
        }
        for (const item of doc.querySelectorAll('div.module-card-item')) {
            const card = this._searchCard(item)
            if (card) {
                const href = (item.querySelector('a.module-card-item-poster[href*="/vod/"]') || {}).attributes || {}
                const key = href.href || ('' + cards.length)
                if (!seen[key]) {
                    seen[key] = true
                    cards.push(card)
                }
            }
        }
        doc.dispose()
        return cards
    }

    // ============================================================
    // 搜索
    // ============================================================

    _searchUrl(keyword, page) {
        const wd = encodeURIComponent(keyword)
        if (page <= 1) return `${this.baseUrl}/vod-search/${wd}-------------/`
        return `${this.baseUrl}/vod-search/${wd}----------${page}---/`
    }

    async search(keyword, page = 1) {
        if (keyword === null || keyword === undefined || keyword === '') keyword = ''
        let html
        try {
            html = await Network.get(this._searchUrl(keyword, page), this._headers())
        } catch (e) {
            console.error(`[ttdm8] 搜索请求失败: ${e}`)
            return []
        }
        if (!html) return []
        const cards = this._parseCards(html)
        if (cards.length === 0 && page <= 1) {
            Dialog.showToast('未找到结果，请检查关键词')
        }
        return cards
    }

    // ============================================================
    // 分类浏览（/vod-show/{type}-{...}-{page}-{...}/，支持多条件筛选）
    //
    // /vod-show/ URL 槽位（type 之后共 11 个 "-值" 槽，索引 0..10）：
    //   0=地区(area)  1=排序(by)  2=剧情(class)  3=语言(lang)  4=字母(letter)
    //   7=页码(page)  10=年份(year)
    //   本站分类页实际只暴露「剧情 / 字母 / 排序」，其余槽位保持空
    // ============================================================

    getCategory() {
        return {
            title: '天天动漫',
            parts: [
                { name: '动漫分类', categories: ['国漫', '日漫', '欧美动漫', '其他动漫', '动画电影', '里番'] },
            ],
        }
    }

    /// 构造 /vod-show/ 筛选列表 URL
    _showUrl(typeKey, page, opts) {
        const s = new Array(11).fill('')
        if (opts) {
            s[0] = opts.area || ''
            s[1] = opts.by || ''
            s[2] = opts.class || ''
            s[3] = opts.lang || ''
            s[4] = opts.letter || ''
            s[10] = opts.year || ''
        }
        s[7] = page > 1 ? String(page) : ''
        let path = typeKey
        for (let i = 0; i < 11; i++) path += '-' + encodeURIComponent(s[i])
        return `${this.baseUrl}/vod-show/${path}/`
    }

    /// options 数组（与 filterDefs 顺序一致）→ 键值对象
    _buildOpts(options) {
        const opts = {}
        const defs = ttdm8.filterDefs
        for (let i = 0; i < defs.length; i++) {
            let v = (options && i < options.length) ? String(options[i] || '').trim() : ''
            if (v === '全部') v = ''
            opts[defs[i].key] = v
        }
        return opts
    }

    /// 从分类页解析筛选组选项（「剧情」动态，各分类不同）
    _parseFilterGroup(html, label) {
        const doc = new HtmlDocument(html)
        const options = []
        for (const titleEl of doc.querySelectorAll('.module-item-title')) {
            const t = (titleEl.text || '').trim()
            if (t.indexOf(label) < 0) continue
            const box = titleEl.nextElementSibling
            if (!box) continue
            for (const a of box.querySelectorAll('a[title]')) {
                const text = (a.attributes.title || '').trim()
                if (!text) continue
                options.push({ value: text, text })
            }
            break
        }
        doc.dispose()
        return options
    }

    /// 筛选组（「剧情」动态解析，其余固定）
    async getCategoryOptions(category) {
        const key = ttdm8.catKeys[category]
        if (!key) return null
        let classOptions = []
        try {
            const html = await Network.get(this._showUrl(key, 1, {}), this._headers())
            classOptions = this._parseFilterGroup(html, '剧情')
        } catch (e) {
            console.warn(`[ttdm8] 解析筛选选项失败: ${e}`)
        }
        const groups = []
        for (const d of ttdm8.filterDefs) {
            let opts
            if (d.dynamic) {
                opts = classOptions
            } else {
                opts = d.values.map((v, i) => ({ value: v, text: (d.texts && d.texts[i]) || v }))
            }
            groups.push({
                label: d.label,
                options: [{ value: '全部', text: '全部' }].concat(opts),
            })
        }
        return groups
    }

    /// 从分页条 href 提取页码
    _pageFromHref(href) {
        const m = href.match(/\/vod-show\/[^/]+/)
        if (!m) return 0
        const parts = m[0].replace(/^\/vod-show\//, '').replace(/\/$/, '').replace(/0-9/g, '09').split('-')
        const page = parseInt(parts[8] || '0', 10)
        return isNaN(page) ? 0 : page
    }

    _extractMaxPage(doc) {
        let max = 1
        for (const a of doc.querySelectorAll('a.page-link')) {
            const t = (a.text || '').trim()
            if (/^\d+$/.test(t)) {
                max = Math.max(max, parseInt(t, 10))
            } else if ((a.attributes.title || '') === '尾页') {
                const p = this._pageFromHref(a.attributes.href || '')
                if (p > 0) max = Math.max(max, p)
            }
        }
        return max
    }

    async loadCategory(category, page = 1, options = []) {
        const key = ttdm8.catKeys[category]
        if (!key) return []
        const opts = this._buildOpts(options)
        let maxPage = 1000
        try {
            const first = await Network.get(this._showUrl(key, 1, opts), this._headers())
            if (first) {
                const doc = new HtmlDocument(first)
                maxPage = this._extractMaxPage(doc)
                doc.dispose()
            }
        } catch (e) {
            console.warn(`[ttdm8] 分类最大页探测失败: ${e}`)
        }
        return [
            UI.Pagination({
                page: Math.min(Math.max(1, page), maxPage),
                maxPage: maxPage,
                pageMethod: 'loadCategoryPage',
                pageArgs: [category, 1, options],
            }),
        ]
    }

    async loadCategoryPage(category, page = 1, options = []) {
        const key = ttdm8.catKeys[category]
        if (!key) return []
        const opts = this._buildOpts(options)
        let html
        try {
            html = await Network.get(this._showUrl(key, page, opts), this._headers())
        } catch (e) {
            console.error(`[ttdm8] 分类请求失败: ${e}`)
            Dialog.showToast('分类加载失败，请检查网络')
            return []
        }
        if (!html) return []
        const cards = this._parseCards(html)
        if (cards.length === 0 && page <= 1) {
            Dialog.showToast('该分类暂无内容')
        }
        return cards
    }

    // ============================================================
    // 详情页（头部元信息 + 简介 + 多线路剧集）
    // ============================================================

    async getDetail(id) {
        const url = `${this.baseUrl}/vod/${id}/`
        let html
        try {
            html = await Network.get(url, this._headers())
        } catch (e) {
            Dialog.showToast(`详情页请求失败: ${e}`)
            console.error(`详情页请求失败: ${e}`)
            return []
        }
        if (!html) return []

        const doc = new HtmlDocument(html)
        const items = []

        // ===== 1. 标题 / 封面 =====
        const h1 = doc.querySelector('.module-info-heading h1')
        const title = h1 ? (h1.text || '').trim() : ''
        const coverImg = doc.querySelector('.module-info-poster .module-item-pic img')
        const cover = coverImg ? (coverImg.attributes['data-original'] || coverImg.attributes.src || '') : ''

        // ===== 2. 标签（年份 / 地区 / 类型） =====
        const tagLinks = doc.querySelectorAll('.module-info-tag-link a')
        const tagTexts = []
        for (const a of tagLinks) {
            const t = (a.text || '').trim()
            if (t) tagTexts.push(t)
        }

        // ===== 3. 元信息（导演 / 主演 / 集数 / 更新） =====
        let director = '', actor = '', epCount = '', update = ''
        for (const item of doc.querySelectorAll('.module-info-item')) {
            const labelEl = item.querySelector('.module-info-item-title')
            const label = labelEl ? (labelEl.text || '').trim() : ''
            const contentEl = item.querySelector('.module-info-item-content')
            const value = contentEl ? (contentEl.text || '').trim() : ''
            if (label.indexOf('导演') >= 0) director = value
            else if (label.indexOf('主演') >= 0) actor = value
            else if (label.indexOf('集数') >= 0) epCount = value
            else if (label.indexOf('更新') >= 0) update = value
        }

        // ===== 4. 简介 =====
        let desc = ''
        const descEl = doc.querySelector('.module-info-introduction-content p')
        if (descEl) desc = (descEl.text || '').trim()

        // ===== 5. 头部卡片 =====
        if (cover || title) {
            const headerChildren = []
            if (cover) {
                headerChildren.push(UI.Image({ src: cover, width: 110, height: 150 }))
                headerChildren.push(UI.SizedBox({ width: 12 }))
            }
            const metaRows = []
            if (tagTexts.length) {
                metaRows.push(UI.Text({ content: tagTexts.join(' · '), style: { fontSize: 12, color: '#888888' }, maxLines: 1 }))
            }
            if (director) {
                metaRows.push(UI.Text({ content: '导演：' + director, style: { fontSize: 12, color: '#888888' }, maxLines: 1 }))
            }
            if (actor) {
                metaRows.push(UI.Text({ content: '主演：' + actor, style: { fontSize: 12, color: '#888888' }, maxLines: 2 }))
            }
            if (update) {
                metaRows.push(UI.Text({ content: '更新：' + update, style: { fontSize: 12, color: '#888888' }, maxLines: 1 }))
            }

            headerChildren.push(UI.Expanded({
                child: UI.Column({
                    crossAxisAlignment: 'start',
                    mainAxisAlignment: 'start',
                    children: [
                        UI.Text({ content: title, style: { fontSize: 16, weight: 'bold' }, maxLines: 2 }),
                        ...(epCount ? [UI.SizedBox({ height: 6 }), UI.Text({
                            content: epCount,
                            style: { fontSize: 13, color: '#FF6B6B', weight: 'bold' },
                            maxLines: 1,
                        })] : []),
                        ...(metaRows.length ? [UI.SizedBox({ height: 6 })] : []),
                        ...metaRows,
                    ].filter(c => c != null),
                }),
            }))

            items.push(UI.Card({
                padding: 12,
                shapeRadius: 8,
                child: UI.Row({ crossAxisAlignment: 'start', children: headerChildren }),
            }))
        }

        // ===== 6. 简介卡片 =====
        if (desc) {
            items.push(UI.Card({
                padding: 12,
                shapeRadius: 8,
                child: UI.Text({
                    content: desc,
                    style: { fontSize: 13, color: '#555555' },
                    maxLines: 8,
                }),
            }))
        }

        // ===== 7. 剧集列表（每个线路一个 ExpansionTile） =====
        const tabEls = doc.querySelectorAll('.module-tab-items .module-tab-item')
        const panelEls = doc.querySelectorAll('.module-list.sort-list.tab-list')
        let sourceCount = 0

        // 结构化播放源缓存（play 时整份传给播放页，支持自由选集/续播）
        this._playSources = { videoId: String(id), title: title, cover: cover, sources: [] }

        for (let i = 0; i < panelEls.length; i++) {
            const panel = panelEls[i]
            const eps = panel.querySelectorAll('a.module-play-list-link[href*="/vod-play/"]')
            if (eps.length === 0) continue

            let sourceName = '线路 ' + (i + 1)
            if (i < tabEls.length) {
                const tab = tabEls[i]
                const dv = tab.attributes['data-dropdown-value']
                const sp = tab.querySelector('span')
                sourceName = (dv || (sp ? (sp.text || '').trim() : '') || sourceName).trim()
            }

            const epButtons = []
            const sourceEpisodes = []
            for (let j = 0; j < eps.length; j++) {

                const a = eps[j]
                const href = a.attributes.href || ''
                const span = a.querySelector('span')
                const text = (span ? (span.text || '').trim() : '') || ('第' + (j + 1) + '集')
                epButtons.push(UI.Button({
                    label: text,
                    style: 'text',
                    onTap: UI.Action({
                        method: 'play',
                        args: [href, title + ' ' + text, cover],
                    }),
                }))
                sourceEpisodes.push({
                    name: text,
                    type: 'resolve',
                    plugin: this.key,
                    method: 'resolvePlayUrl',
                    args: [href],
                })
            }

            sourceCount++
            this._playSources.sources.push({ name: sourceName, episodes: sourceEpisodes })
            items.push(UI.ExpansionTile({
                title: UI.Text({
                    content: sourceName + '（' + epButtons.length + ' 集）',
                    style: { fontSize: 14, weight: 'bold' },
                    maxLines: 1,
                }),
                initiallyExpanded: sourceCount === 1,
                shapeRadius: 0,
                children: [
                    UI.Container({
                        padding: 8,
                        child: UI.Wrap({
                            spacing: 6,
                            runSpacing: 6,
                            children: epButtons,
                        }),
                    }),
                ],
            }))
        }

        if (sourceCount === 0) {
            items.push(UI.Text({
                content: '未找到剧集，请稍后重试或尝试其他资源',
                style: { fontSize: 12, color: '#FF0000' },
            }))
        }

        PluginBrowse.open(this.key, {
            id: url,
            title: title,
            cover: cover,
            kv: { id: String(id) },
        })

        doc.dispose()
        return items
    }

    // ============================================================
    // 播放（player_aaaa.url 直链优先，页面嗅探回退）
    //
    // 本站播放页是 iframe 包裹页：/vod-play/{id}-{sid}-{nid}/ 里只有一个
    // <iframe src="/vod-play/{id}-{sid}-{nid}/?iframe=1">，真实播放配置
    // player_aaaa={"url":"..."} 在内页里。因此先直接请求 ?iframe=1 内页拿直链。
    // ============================================================

    /// 从播放器内页 HTML 提取真实播放地址
    _extractPlayUrl(html) {
        // 1. 常见播放器配置对象（maccms/mxpro 各主题）：var xxx={"encrypt":0,"url":"..."}
        for (const name of ['player_aaaa', 'player_data', 'player_info', 'playdata', 'player_config']) {
            const re = new RegExp(name + '\\s*=\\s*(\\{[\\s\\S]*?\\})</script>')
            const m = html.match(re)
            if (!m) continue
            try {
                const cfg = JSON.parse(m[1])
                if (cfg && cfg.url) return { url: cfg.url, encrypt: cfg.encrypt || 0 }
            } catch (e) { /* 继续下一个 */ }
        }
        // 2. 页面里直接出现的媒体直链字符串（.m3u8/.mp4/...），最可靠的兜底
        const mm = html.match(/["']([^"']*?\.(?:m3u8|mp4|flv|mkv|ts|webm)[^"']*)["']/)
        if (mm && mm[1]) return { url: mm[1].replace(/\\\//g, '/'), encrypt: 0 }
        // 3. MacPlayer.Html 内嵌 iframe src
        const m3 = html.match(/MacPlayer\.Html\s*=\s*['"][^'"]*<iframe[^>]*src=["']([^"']+)["']/)
        if (m3 && m3[1]) return { url: m3[1], encrypt: 0 }
        // 4. 通用 "url":"..." —— 值必须像资源地址（含 :// 或 / 开头或媒体后缀），
        //    避免误抓 var maccms={url:"www.ttdm.me"} 这类站点域名
        const m2 = html.match(/"url"\s*:\s*"([^"]+)"/)
        if (m2 && m2[1]) {
            const u = m2[1].replace(/\\\//g, '/')
            if (/^(https?:)?\/\//.test(u) || u.indexOf('/') === 0 || /\.(m3u8|mp4|flv|mkv|ts|webm)/i.test(u)) {
                return { url: u, encrypt: 0 }
            }
        }
        return null
    }

    /// 解析单集真实播放地址（供播放页 resolve 调用）。
    /// 返回 { url, type }：type 为 'direct'（直链）/ 'page'（需播放器嗅探）。
    async resolvePlayUrl(url) {
        const pageUrl = this._abs(url)
        // 播放器内页（注意保留尾部斜杠，站点 iframe 写法为 /vod-play/.../?iframe=1）
        const innerUrl = pageUrl.replace(/\/+$/, '') + '/?iframe=1'
        let videoUrl = ''
        try {
            let html = await Network.get(innerUrl, this._headers())
            let info = html ? this._extractPlayUrl(html) : null
            if (!info || !info.url || info.encrypt !== 0) {
                // 兜底：少数线路可能把 player_aaaa 直接放在完整播放页里
                const outer = await Network.get(pageUrl, this._headers())
                info = outer ? this._extractPlayUrl(outer) : info
            }
            if (info && info.url && info.encrypt === 0) videoUrl = info.url
        } catch (e) {
            console.warn('[ttdm8] 提取直链失败，回退页面嗅探: ' + e)
        }
        if (videoUrl) {
            const direct = /\.(m3u8|mp4|flv|mkv|ts|webm)(\?|$)/i.test(videoUrl) || videoUrl.indexOf('.m3u8') >= 0
            // 直链 → type=direct；外站网页 → type=page 交给播放器嗅探
            return { url: this._abs(videoUrl), type: direct ? 'direct' : 'page' }
        }
        // 拿不到直链：让播放器直接嗅探内页（含 m3u8，比外壳页更容易嗅探）
        return { url: innerUrl, type: 'page' }
    }

    /// 进入播放：结构化传参（整部剧 sources + 当前集）。
    /// sources 来自 getDetail 缓存（每集 resolve 描述符），播放页可自由选集。
    async play(url, title, cover) {
        const cache = this._playSources
        if (cache && cache.sources && cache.sources.length) {
            let initialSource = 0
            let initialEpisode = 0
            let found = false
            for (let s = 0; s < cache.sources.length && !found; s++) {
                const eps = cache.sources[s].episodes || []
                for (let e = 0; e < eps.length; e++) {
                    if ((eps[e].args && eps[e].args[0]) === url) {
                        initialSource = s
                        initialEpisode = e
                        found = true
                        break
                    }
                }
            }
            Navigator.navigateToVideo({
                videoId: cache.videoId,
                title: title || cache.title,
                cover: cover || cache.cover,
                sourceKey: this.key,
                initialSource: initialSource,
                initialEpisode: initialEpisode,
                sources: cache.sources,
            })
            return
        }
        // 无缓存兜底：解析单集后按单源单集进入
        const resolved = await this.resolvePlayUrl(url)
        const resolvedTitle = title || url
        Navigator.navigateToVideo({
            videoId: url,
            title: resolvedTitle,
            cover: cover || '',
            sourceKey: this.key,
            initialSource: 0,
            initialEpisode: 0,
            sources: [{
                name: '默认线路',
                episodes: [{ name: resolvedTitle, url: resolved.url, type: resolved.type }],
            }],
        })
    }

    // ============================================================
    // 浏览历史回放
    // ============================================================

    async onOpenBrowseEntry(entry) {
        if (!entry) {
            Dialog.showToast('浏览历史无效')
            return
        }
        let id = entry.kv && entry.kv.id
        if (!id && entry.id) {
            const m = String(entry.id).match(/\/vod\/(\d+)/)
            if (m) id = m[1]
        }
        if (!id) {
            Dialog.showToast('浏览历史无效')
            return
        }
        Navigator.navigateToDescriptor(this.key, {
            method: 'getDetail',
            args: [id],
            title: entry.title || '',
        })
    }
}
