// description: 风车动漫（008nnn.com）视频源 — 搜索 / 分类 / 详情 / 播放
// type: video
//
// 站点 URL 模式（maccms 模板）：
//   搜索：/search/?wd={keyword}&pageno={page}
//   分类：/type/{key}/{page}/   key: guoman 国产 / riman 日漫 / oman 欧美 / dmfilm 电影
//   详情：/detail/{id}/
//   播放：/play/{vid}-{sid}-{nid}/  播放页内嵌 Artplayer 的 m3u8 直链
//   封面：<img class="lazy" data-original="...">（图片 CDN 免防盗链头）
//
// 接口约定：
//   search(keyword, page)        → List<UI.Card>
//   loadCategory / loadCategoryPage → 分类浏览（分页容器）
//   getDetail(id)                → 头部元信息 + 简介 + 多线路剧集
//   play(url, title, cover)      → 优先提取播放页 m3u8 直链播放，
//                                  提取失败时把播放页交给 wyw 播放器嗅探

class fc_008nnn extends PluginSource {
    name = '风车动漫'
    key = 'fc_008nnn'
    version = '1.0.0'
    baseUrl = 'https://www.008nnn.com'

    /// 分类名称 → /type/ URL 段
    static catKeys = {
        '国产动漫': 'guoman',
        '日本动漫': 'riman',
        '欧美动漫': 'oman',
        '动漫电影': 'dmfilm',
    }

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
    // 列表解析（搜索页 / 分类页通用）
    // ============================================================

    /// 标题：.txt a > h3 a > 封面链接 title > img alt
    _extractTitle(li) {
        const txtA = li.querySelector('.txt a')
        if (txtA) {
            const t = (txtA.attributes.title || txtA.text || '').trim()
            if (t) return t
        }
        const h3a = li.querySelector('h3 a')
        if (h3a) {
            const t = (h3a.attributes.title || h3a.text || '').trim()
            if (t) return t
        }
        const link = li.querySelector('a[href*="/detail/"]')
        if (link && link.attributes.title) return (link.attributes.title || '').trim()
        const img = li.querySelector('img')
        return img ? (img.attributes.alt || '').trim() : ''
    }

    /// 封面：data-original > data-src > src（跳过占位图）
    _extractCover(li) {
        const img = li.querySelector('img')
        if (!img) return ''
        return (img.attributes['data-original'] || img.attributes['data-src'] || img.attributes.src || '').trim()
    }

    /// 剧集信息：.txt p（更新至X集 / 全X集）或搜索项的「状态：xxx」
    _extractEpInfo(li) {
        const p = li.querySelector('.txt p')
        if (p) {
            const t = (p.text || '').trim()
            if (t) return t
        }
        for (const it of li.querySelectorAll('.item')) {
            const sp = it.querySelector('span')
            const label = sp ? (sp.text || '') : ''
            if (label && label.indexOf('状态') >= 0) {
                return (it.text || '').replace(label, '').trim()
            }
        }
        return ''
    }

    /// 标签（搜索页 .tags div 里的分类 / 年份 / 地区）
    _extractTags(li) {
        const tags = []
        for (const d of li.querySelectorAll('.tags div')) {
            const t = (d.text || '').trim()
            if (t) tags.push(t)
        }
        return tags
    }

    /// 构建搜索结果 / 分类列表卡片
    _buildCard({ cover, title, epInfo, tags, id }) {
        const infoRows = [
            UI.Text({ content: title, style: { fontSize: 14, weight: 'bold' }, maxLines: 1 }),
        ]
        if (epInfo) {
            infoRows.push(UI.Row({
                crossAxisAlignment: 'center',
                children: [
                    UI.Icon({ name: 'play_circle_outline', size: 14, color: '#666666' }),
                    UI.SizedBox({ width: 4 }),
                    UI.Text({ content: epInfo, style: { fontSize: 12, color: '#666666' }, maxLines: 1 }),
                ],
            }))
        }
        if (tags && tags.length) {
            infoRows.push(UI.Text({
                content: tags.slice(0, 4).join(' · '),
                style: { fontSize: 11, color: '#888888' },
                maxLines: 1,
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
                    UI.IconButton({
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
                    }),
                ].filter(c => c != null),
            }),
        })
    }

    /// 解析列表页里所有 /detail/{id}/ 结果项
    _parseCards(html) {
        const doc = new HtmlDocument(html)
        const cards = []
        const seen = {}
        for (const li of doc.querySelectorAll('li')) {
            try {
                const link = li.querySelector('a[href*="/detail/"]')
                if (!link) continue
                const href = link.attributes.href || ''
                const m = href.match(/\/detail\/(\d+)\//)
                if (!m) continue
                const id = m[1]
                if (seen[id]) continue
                const title = this._extractTitle(li)
                if (!title) continue
                seen[id] = true
                cards.push(this._buildCard({
                    cover: this._extractCover(li),
                    title: title,
                    epInfo: this._extractEpInfo(li),
                    tags: this._extractTags(li),
                    id: id,
                }))
            } catch (e) {
                continue
            }
        }
        doc.dispose()
        return cards
    }

    /// 从分页条提取最大页码（「X / Y」优先，其次扫描页码链接）
    _extractMaxPage(doc) {
        for (const a of doc.querySelectorAll('.page a')) {
            const t = (a.text || '').replace(/\u00a0/g, ' ').trim()
            const m = t.match(/(\d+)\s*\/\s*(\d+)/)
            if (m) return parseInt(m[2], 10)
        }
        let max = 0
        for (const a of doc.querySelectorAll('.page a')) {
            const href = a.attributes.href || ''
            let m = href.match(/pageno=(\d+)/)
            if (!m) m = href.match(/\/(\d+)\/$/)
            if (m) max = Math.max(max, parseInt(m[1], 10))
        }
        return max > 0 ? max : 1
    }

    // ============================================================
    // 搜索
    // ============================================================

    async search(keyword, page = 1) {
        const q = encodeURIComponent((keyword === null || keyword === undefined || keyword === '') ? '' : keyword)
        const url = page <= 1
            ? `${this.baseUrl}/search/?wd=${q}`
            : `${this.baseUrl}/search/?wd=${q}&pageno=${page}`
        let html
        try {
            html = await Network.get(url, this._headers())
        } catch (e) {
            console.error(`[fc_008nnn] 搜索请求失败: ${e}`)
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
    // 分类浏览（/type/{key}/{page}/）
    // ============================================================

    getCategory() {
        return {
            title: '风车动漫',
            parts: [
                { name: '动漫分类', categories: ['国产动漫', '日本动漫', '欧美动漫', '动漫电影'] },
            ],
        }
    }

    getCategoryOptions(category) {
        return null
    }

    _typeUrl(category, page) {
        const key = fc_008nnn.catKeys[category]
        if (!key) return ''
        return `${this.baseUrl}/type/${key}/${Math.max(1, page)}/`
    }

    async loadCategory(category, page = 1, options = []) {
        let maxPage = 1000
        try {
            const first = await Network.get(this._typeUrl(category, 1), this._headers())
            if (first) {
                const doc = new HtmlDocument(first)
                maxPage = this._extractMaxPage(doc)
                doc.dispose()
            }
        } catch (e) {
            console.warn(`[fc_008nnn] 分类最大页探测失败，回退 1000: ${e}`)
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
        const url = this._typeUrl(category, page)
        if (!url) return []
        let html
        try {
            html = await Network.get(url, this._headers())
        } catch (e) {
            console.error(`[fc_008nnn] 分类请求失败: ${e}`)
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
        const url = `${this.baseUrl}/detail/${id}/`
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
        const h2 = doc.querySelector('.detail h2')
        const title = h2 ? (h2.text || '').trim() : ''
        const coverImg = doc.querySelector('.detail .cover img')
        const cover = coverImg
            ? (coverImg.attributes['data-original'] || coverImg.attributes.src || '')
            : ''

        // ===== 2. 元信息（状态 / 年份 / 地区 / 类型 / 语言 / 主演 / 简介） =====
        let status = '', year = '', region = '', genre = '', lang = '', actor = '', desc = ''
        for (const li of doc.querySelectorAll('.detail ul li')) {
            const sp = li.querySelector('span')
            if (!sp) continue
            const label = (sp.text || '').trim()
            const value = (li.text || '').replace(sp.text || '', '').trim()
            if (label.indexOf('状态') >= 0) status = value
            else if (label.indexOf('年份') >= 0) year = value
            else if (label.indexOf('地区') >= 0) region = value
            else if (label.indexOf('类型') >= 0) genre = value
            else if (label.indexOf('语言') >= 0) lang = value
            else if (label.indexOf('主演') >= 0) actor = value
            else if (label.indexOf('简介') >= 0) desc = value
        }

        // ===== 3. 头部卡片 =====
        if (cover || title) {
            const headerChildren = []
            if (cover) {
                headerChildren.push(UI.Image({ src: cover, width: 110, height: 150 }))
                headerChildren.push(UI.SizedBox({ width: 12 }))
            }
            const metaRows = []
            const meta1 = [year, region, genre].filter(Boolean).join(' · ')
            if (meta1) {
                metaRows.push(UI.Text({ content: meta1, style: { fontSize: 12, color: '#888888' }, maxLines: 1 }))
            }
            if (lang) {
                metaRows.push(UI.Text({ content: lang, style: { fontSize: 12, color: '#888888' }, maxLines: 1 }))
            }
            if (actor) {
                metaRows.push(UI.Text({ content: '主演：' + actor, style: { fontSize: 12, color: '#888888' }, maxLines: 1 }))
            }

            headerChildren.push(UI.Expanded({
                child: UI.Column({
                    crossAxisAlignment: 'start',
                    mainAxisAlignment: 'start',
                    children: [
                        UI.Text({ content: title, style: { fontSize: 16, weight: 'bold' }, maxLines: 2 }),
                        ...(status ? [UI.SizedBox({ height: 6 }), UI.Text({
                            content: status,
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

        // ===== 4. 简介卡片 =====
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

        // ===== 5. 剧集列表（每个线路一个 ExpansionTile） =====
        const tabEls = doc.querySelectorAll('.playlist .tabs a')
        const rowEls = doc.querySelectorAll('.playlist .row')
        let sourceCount = 0

        // 结构化播放源缓存（play 时整份传给播放页，支持自由选集/续播）
        this._playSources = { videoId: String(id), title: title, cover: cover, sources: [] }

        for (let i = 0; i < rowEls.length; i++) {
            const row = rowEls[i]
            const eps = row.querySelectorAll('ul li a[href*="/play/"]')
            if (eps.length === 0) continue

            const tab = i < tabEls.length ? tabEls[i] : null
            const sourceName = tab
                ? ((tab.text || '').trim() || ('线路 ' + (i + 1)))
                : ('线路 ' + (i + 1))

            const epButtons = []
            const sourceEpisodes = []
            for (let j = 0; j < eps.length; j++) {
                const a = eps[j]
                const href = a.attributes.href || ''
                const text = (a.text || '').trim() || ('第' + (j + 1) + '集')
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
    // 播放（m3u8 直链优先，页面嗅探回退）
    // ============================================================

    /// 解析单集真实播放地址（供播放页 resolve 调用）。
    /// 返回 { url, type }：type 为 'direct'（直链）/ 'page'（需播放器嗅探）。
    async resolvePlayUrl(url) {
        const pageUrl = this._abs(url)
        let m3u8 = ''
        try {
            const html = await Network.get(pageUrl, this._headers())
            if (html) {
                const m1 = html.match(/url\s*:\s*['"]([^'"]+\.m3u8[^'"]*)['"]/i)
                const m2 = html.match(/https?:\/\/[^'"\s<>]+\.m3u8[^'"\s<>]*/i)
                m3u8 = (m1 && m1[1]) || (m2 && m2[0]) || ''
            }
        } catch (e) {
            console.warn('[fc_008nnn] 提取直链失败，回退页面嗅探: ' + e)
        }
        if (m3u8) {
            return { url: this._abs(m3u8), type: 'direct' }
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
            const m = String(entry.id).match(/\/detail\/(\d+)\//)
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