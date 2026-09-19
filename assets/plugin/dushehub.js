// description: 毒舌电影（dushehub.com）视频源 — 搜索 / 分类 / 详情 / 播放
// type: video
//
// 站点 URL 模式（maccms 海螺 hltheme 模板）：
//   搜索：/search/{wd}-------------.html           （第 1 页）
//         /search/{wd}----------{page}---.html     （第 2 页起）
//   分类：/show/{type}-----------.html             （第 1 页，无筛选）
//         /show/{type}--------{page}---.html       （翻页）
//         type: dianying 电影 / dianshiju 电视剧 / dongman 动漫 / zongyi 综艺
//         支持多条件筛选（剧情/地区/语言/年份/字母/排序），槽位见 _showUrl
//   详情：/album/{id}.html
//   播放：/play/{vid}-{sid}-{nid}.html  页面内嵌 var player_aaaa={"url":"..."}
//         url 为 m3u8/mp4 直链（超清/备用线路）或外站页面（极速线路，如 v.qq.com）
//   封面：<img class="lazy lazyload" data-original="..." referrerpolicy="no-referrer">
//         （图片 CDN 免防盗链头）
//
// 接口约定：
//   search(keyword, page)        → List<UI.Card>（框架自动 loadMore 追加分页）
//   loadCategory / loadCategoryPage → 分类浏览（分页 + 多条件筛选）
//   getDetail(id)                → 头部元信息 + 简介 + 多线路剧集
//   play(url, title, cover)      → 优先提取播放页 player_aaaa.url 直链播放，
//                                  网页/加密链接回退交给 wyw 播放器嗅探

class dushehub extends PluginSource {
    name = '毒舌电影'
    key = 'dushehub'
    version = '1.0.0'
    baseUrl = 'https://www.dushehub.com'

    /// 分类名称 → /show/ URL 段
    static catKeys = {
        '电影': 'dianying',
        '电视剧': 'dianshiju',
        '动漫': 'dongman',
        '综艺': 'zongyi',
    }

    /// 筛选组（顺序 = getCategoryOptions 返回顺序 = loadCategory options 参数顺序）
    /// dynamic=true 的组（剧情）选项从分类页动态解析
    static filterDefs = [
        { label: '类型', key: 'type', dynamic: true },
        { label: '剧情', key: 'class', dynamic: true },
        { label: '地区', key: 'area', values: ['内地', '港台', '日韩', '欧美'] },
        { label: '语言', key: 'lang', values: ['国语', '英语', '粤语', '闽南语', '韩语', '日语', '其它'] },
        { label: '年份', key: 'year', values: ['2026', '2025', '2024', '2023', '2022', '2021', '2020', '2019', '2018', '2017', '2016', '2015', '2014', '2013', '2012', '2011', '2010'] },
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

    /// 海报式条目（<a class="module-poster-item" href="/album/{id}.html">）
    _posterCard(item) {
        const href = item.attributes.href || ''
        const m = href.match(/\/album\/(\d+)\.html/)
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
        const linkEl = item.querySelector('a.module-card-item-poster[href*="/album/"]')
        if (!linkEl) return null
        const href = linkEl.attributes.href || ''
        const m = href.match(/\/album\/(\d+)\.html/)
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
        // 搜索结果卡片带直接播放按钮（/play/{id}-{sid}-{nid}.html）
        let playUrl = ''
        const playBtn = item.querySelector('a.play-btn[href*="/play/"]')
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

    /// 解析列表页所有条目（海报式 + 卡片式），按 id 去重
    _parseCards(html) {
        const doc = new HtmlDocument(html)
        const cards = []
        const seen = {}
        for (const item of doc.querySelectorAll('a.module-poster-item[href*="/album/"]')) {
            const card = this._posterCard(item)
            if (card && !seen[item.attributes.href]) {
                seen[item.attributes.href] = true
                cards.push(card)
            }
        }
        for (const item of doc.querySelectorAll('div.module-card-item')) {
            const card = this._searchCard(item)
            if (card) {
                const href = (item.querySelector('a.module-card-item-poster[href*="/album/"]') || {}).attributes || {}
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
        if (page <= 1) return `${this.baseUrl}/search/${wd}-------------.html`
        return `${this.baseUrl}/search/${wd}----------${page}---.html`
    }

    async search(keyword, page = 1) {
        if (keyword === null || keyword === undefined || keyword === '') keyword = ''
        let html
        try {
            html = await Network.get(this._searchUrl(keyword, page), this._headers())
        } catch (e) {
            console.error(`[dushehub] 搜索请求失败: ${e}`)
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
    // 分类浏览（/show/{type}-{...}-{page}-{...}.html，支持多条件筛选）
    //
    // /show/ URL 槽位（type 之后共 11 个 "-值" 槽，索引 0..10）：
    //   0=地区(area)  1=排序(by)  2=剧情(class)  3=语言(lang)  4=字母(letter)
    //   7=页码(page)  10=年份(year)
    //   「类型」筛选直接替换基础 type（如 /show/dongzuo-----------.html）
    // ============================================================

    getCategory() {
        return {
            title: '毒舌电影',
            parts: [
                { name: '影视分类', categories: ['电影', '电视剧', '动漫', '综艺'] },
            ],
        }
    }

    /// 构造 /show/ 筛选列表 URL（「类型」筛选直接替换基础 type）
    _showUrl(typeKey, page, opts) {
        const type = (opts && opts.type) || typeKey
        const s = new Array(11).fill('')
        s[0] = opts.area || ''
        s[1] = opts.by || ''
        s[2] = opts.class || ''
        s[3] = opts.lang || ''
        s[4] = opts.letter || ''
        s[7] = page > 1 ? String(page) : ''
        s[10] = opts.year || ''
        let path = type
        for (let i = 0; i < 11; i++) path += '-' + encodeURIComponent(s[i])
        return `${this.baseUrl}/show/${path}.html`
    }

    /// options 数组（与 filterDefs 顺序一致）→ 键值对象
    _buildOpts(options) {
        const opts = {}
        const defs = dushehub.filterDefs
        for (let i = 0; i < defs.length; i++) {
            let v = (options && i < options.length) ? String(options[i] || '').trim() : ''
            if (v === '全部') v = ''
            opts[defs[i].key] = v
        }
        return opts
    }

    /// 从分类页解析筛选组选项（「类型/剧情」动态，各分类不同）
    /// 「类型」取 href 首段作为值（如 /show/dongzuo-... → dongzuo）
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
                let value = text
                if (label === '类型') {
                    const m = (a.attributes.href || '').match(/\/show\/([^-]+)/)
                    if (m) value = m[1]
                }
                options.push({ value, text })
            }
            break
        }
        doc.dispose()
        return options
    }

    /// 筛选组（「类型/剧情」动态解析，其余固定）
    async getCategoryOptions(category) {
        const key = dushehub.catKeys[category]
        if (!key) return null
        let typeOptions = []
        let classOptions = []
        try {
            const html = await Network.get(this._showUrl(key, 1, { type: '', area: '', by: '', class: '', lang: '', letter: '', year: '' }), this._headers())
            typeOptions = this._parseFilterGroup(html, '类型')
            classOptions = this._parseFilterGroup(html, '剧情')
        } catch (e) {
            console.warn(`[dushehub] 解析筛选选项失败: ${e}`)
        }
        const groups = []
        for (const d of dushehub.filterDefs) {
            let opts
            if (d.dynamic) {
                opts = d.key === 'type' ? typeOptions : classOptions
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

    /// 从分页条提取最大页码
    _pageFromHref(href) {
        const m = href.match(/\/show\/[^/]+\.html/)
        if (!m) return 0
        const parts = m[0].replace(/^\/show\//, '').replace(/\.html$/, '').replace(/0-9/g, '09').split('-')
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
        const key = dushehub.catKeys[category]
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
            console.warn(`[dushehub] 分类最大页探测失败: ${e}`)
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
        const key = dushehub.catKeys[category]
        if (!key) return []
        const opts = this._buildOpts(options)
        let html
        try {
            html = await Network.get(this._showUrl(key, page, opts), this._headers())
        } catch (e) {
            console.error(`[dushehub] 分类请求失败: ${e}`)
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
        const url = `${this.baseUrl}/album/${id}.html`
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
            const eps = panel.querySelectorAll('a.module-play-list-link[href*="/play/"]')
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
    // ============================================================

    /// 从播放页提取真实播放地址
    _extractPlayUrl(html) {
        const m = html.match(/player_aaaa\s*=\s*(\{[\s\S]*?\})<\/script>/)
        if (m) {
            try {
                const cfg = JSON.parse(m[1])
                if (cfg && cfg.url) return { url: cfg.url, encrypt: cfg.encrypt || 0 }
            } catch (e) {
                // 忽略，走兜底
            }
        }
        const m2 = html.match(/"url"\s*:\s*"([^"]+)"/)
        if (m2 && m2[1]) return { url: m2[1].replace(/\\\//g, '/'), encrypt: 0 }
        return null
    }

    /// 解析单集真实播放地址（供播放页 resolve 调用）。
    /// 返回 { url, type }：type 为 'direct'（直链）/ 'page'（需播放器嗅探）。
    async resolvePlayUrl(url) {
        const pageUrl = this._abs(url)
        let videoUrl = ''
        try {
            const html = await Network.get(pageUrl, this._headers())
            if (html) {
                const info = this._extractPlayUrl(html)
                if (info && info.url && info.encrypt === 0) videoUrl = info.url
            }
        } catch (e) {
            console.warn('[dushehub] 提取直链失败，回退页面嗅探: ' + e)
        }
        if (videoUrl) {
            const direct = /\.(m3u8|mp4|flv|mkv|ts|webm)(\?|$)/i.test(videoUrl) || videoUrl.indexOf('.m3u8') >= 0
            // 直链 → type=direct；外站网页 → type=page 交给播放器嗅探
            return { url: this._abs(videoUrl), type: direct ? 'direct' : 'page' }
        }
        return { url: pageUrl, type: 'page' }
    }

    /// 进入播放：结构化传参（整部剧 sources + 当前集）。
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
            const m = String(entry.id).match(/\/album\/(\d+)/)
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