// description: 18漫画 漫画源 — 搜索/分类/详情/阅读（由 venera mh18.js v1.0.0 移植）
// type: manga
//
// 接口约定：
//   search(keyword, page)  → List<UI.Card>
//   getDetail(id)          → List<UI>（头部 + 简介 + 章节列表 + 相关推荐）
//   openReader(epId)       → Navigator.navigateToReader（章节惰性加载）
//   loadChapterImages(comicId, epId) → 该章图片 URL 数组
//   getCategory / getCategoryOptions / loadCategory / loadCategoryPage — 分类浏览
//
// 移植说明：
//   - epId 格式为 "data-ms@data-cs"（章节接口的两个 id 拼接）
//   - 分类「近期更新」取自 venera explore 首页板块；首页其余动态板块未移植
//   - wyw 无缩略图墙：venera onThumbnailLoad 的 headers 语义移入 getImageLoadingConfig
//   - 阅读器/详情图片统一带 UA + Referer 防盗链（venera 仅缩略图带，这里全带更稳）
//   - 搜索请求 venera 原实现未带 headers，这里统一补齐浏览器 UA（防 Dart 默认 UA 被 403）

class mh18 extends PluginSource {
    name = '18漫画'
    key = 'mh18'
    version = '1.0.0'

    settings = {
        domains: {
            title: '域名',
            type: 'input',
            default: '18mh.org',
        },
    }

    get baseUrl() {
        const d = this.loadSetting('domains')
        return 'https://' + (d && String(d).trim() ? String(d).trim() : '18mh.org')
    }

    get headers() {
        return {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:144.0) Gecko/20100101 Firefox/144.0',
            'Referer': this.baseUrl,
        }
    }

    // ============ 解析 ============

    /// 列表页通用解析：.pb-2 卡片
    _parseComics(doc) {
        const result = []
        for (const item of doc.querySelectorAll('.pb-2')) {
            try {
                result.push({
                    id: item.querySelector('a').attributes['href'],
                    title: item.querySelector('h3').text,
                    cover: item.querySelector('img').attributes['src'],
                })
            } catch (e) {
                continue
            }
        }
        console.log('[mh18]', 'parseComics 命中:', result.length)
        return result
    }

    /// 首页「近期更新」板块
    _parseRecent(doc) {
        const result = []
        const box = doc.querySelector('.pb-unit-md')
        if (!box) return result
        for (const item of box.querySelectorAll('.slicarda')) {
            try {
                result.push({
                    id: item.attributes['href'],
                    title: item.querySelector('h3').text,
                    cover: item.querySelector('img').attributes['src'],
                })
            } catch (e) {
                continue
            }
        }
        console.log('[mh18]', 'parseRecent 命中:', result.length)
        return result
    }

    _comicCard(c) {
        const metaLines = []
        if (c.subtitle) metaLines.push(c.subtitle)
        if (c.tags && c.tags.length > 0) metaLines.push(c.tags.slice(0, 4).join('、'))
        return UI.Card({
            elevation: 0,
            shapeRadius: 16,
            color: '@theme:surfaceContainerLow',
            padding: 4,
            child: UI.Row({
                crossAxisAlignment: 'start',
                children: [
                    c.cover ? UI.Image({ src: c.cover, width: 80, height: 116, headers: this.headers }) : null,
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
        const url = this.baseUrl + '/s/' + encodeURIComponent(keyword) + '?page=' + page
        console.log('[mh18]', '搜索请求:', url)
        let html
        try {
            html = await Network.get(url, this.headers)
        } catch (e) {
            Dialog.showToast('搜索请求失败: ' + e)
            console.error('[mh18]', '搜索请求失败:', e)
            return []
        }
        if (!html) return []
        const doc = new HtmlDocument(html)
        const comics = this._parseComics(doc)
        doc.dispose()
        return comics.map((c) => this._comicCard(c))
    }

    // ============ 分类 ============

    /// 分类名 → 路径参数（venera categoryParams）
    static categoryMap = {
        '全部': '/manga',
        '韓漫': '/manga-genre/hanman',
        '真人寫真': '/manga-genre/zhenrenxiezhen',
        '日漫': '/manga-genre/riman',
        'AI寫真': '/manga-genre/aixiezhen',
        '熱門漫畫': '/manga-genre/hots',
        '多人': '/manga-tag/duoren',
        '慾望': '/manga-tag/yuwang',
        '正妹': '/manga-tag/zhengmei',
        '同居': '/manga-tag/tongju',
        '女學生': '/manga-tag/nxuesheng',
        '劇情': '/manga-tag/juqing',
        '偷情': '/manga-tag/touqing',
        '校园': '/manga-tag/xiaoyuan',
        '逆襲': '/manga-tag/nixi',
        '办公室': '/manga-tag/bangongshi',
        '誘惑': '/manga-tag/youhuo',
        '反转': '/manga-tag/fanzhuan',
        '熟女': '/manga-tag/shun',
        '人妻': '/manga-tag/renqi',
        '初戀': '/manga-tag/chulian',
        '少妇': '/manga-tag/shaofu',
        '刺激': '/manga-tag/ciji',
        '女大学生': '/manga-tag/ndaxuesheng',
        '治疗': '/manga-tag/zhiliao',
        '超能力': '/manga-tag/chaonengli',
        '浪漫校园': '/manga-tag/langmanxiaoyuan',
        '戏剧': '/manga-tag/xiju',
        '学姐': '/manga-tag/xuejie',
        '大学生': '/manga-tag/daxuesheng',
        '泳衣': '/manga-tag/yongyi',
        '暧昧': '/manga-tag/aimei',
        '写真': '/manga-tag/xiezhen',
        '女神': '/manga-tag/nshen',
        '大尺度': '/manga-tag/dachidu',
        '纯情警察': '/manga-tag/chunqingjingcha',
        '近期更新': '__recent__',
    }

    getCategory() {
        return {
            title: this.name,
            parts: [
                {
                    name: '板块',
                    categories: ['近期更新'],
                },
                {
                    name: '类型',
                    categories: ['全部', '韓漫', '真人寫真', '日漫', 'AI寫真', '熱門漫畫'],
                },
                {
                    name: '标签',
                    categories: [
                        '多人', '慾望', '正妹', '同居', '女學生', '劇情', '偷情', '校园', '逆襲', '办公室',
                        '誘惑', '反转', '熟女', '人妻', '初戀', '少妇', '刺激', '女大学生', '治疗', '超能力',
                        '浪漫校园', '戏剧', '学姐', '大学生', '泳衣', '暧昧', '写真', '女神', '大尺度', '纯情警察',
                    ],
                },
            ],
        }
    }

    getCategoryOptions(category) {
        return null
    }

    /// 拉取某分类数据：{comics, maxPage}
    async _fetchCategoryComics(category, page = 1) {
        const param = mh18.categoryMap[category]
        if (!param) throw '未知分类: ' + category
        if (param === '__recent__') {
            // 首页「近期更新」板块，无分页
            const html = await Network.get(this.baseUrl, this.headers)
            const doc = new HtmlDocument(html)
            const comics = this._parseRecent(doc)
            doc.dispose()
            return { comics: comics, maxPage: 1 }
        }
        const url = this.baseUrl + param + '/page/' + page
        console.log('[mh18]', '分类请求:', url)
        const html = await Network.get(url, this.headers)
        const doc = new HtmlDocument(html)
        let maxPage = 1
        try {
            const btns = doc.querySelectorAll('button.text-small')
            maxPage = parseInt(btns[btns.length - 1].text.replaceAll('\n', '').replaceAll(' ', ''))
        } catch (_) {
            maxPage = 1
        }
        if (isNaN(maxPage) || maxPage < 1) maxPage = 1
        const comics = this._parseComics(doc)
        doc.dispose()
        return { comics: comics, maxPage: maxPage }
    }

    /// 分类第一页：返回分页容器
    async loadCategory(category, page = 1, options = []) {
        const { maxPage } = await this._fetchCategoryComics(category, page)
        return [
            UI.Pagination({
                page: page,
                maxPage: maxPage,
                pageMethod: 'loadCategoryPage',
                pageArgs: [category, 1, options],
            }),
        ]
    }

    /// 分类翻页：返回单纯结果列表
    async loadCategoryPage(category, page = 1, options = []) {
        const { comics } = await this._fetchCategoryComics(category, page)
        return comics.map((c) => this._comicCard(c))
    }

    // ============ 详情 ============

    // 运行时缓存（getDetail 时填充，openReader / loadChapterImages 复用）
    _comicId = ''
    _comicTitle = ''
    _comicCover = ''
    _chapters = []

    async getDetail(id) {
        let url = String(id)
        if (!url.startsWith('http')) url = this.baseUrl + url
        console.log('[mh18]', '详情请求:', url)
        const html = await Network.get(url, this.headers)
        const doc = new HtmlDocument(html)

        const title = doc.querySelector('.text-xl').text.trim().split('   ')[0]
        const cover = doc.querySelector('.object-cover').attributes['src']
        const description = doc.querySelector('p.text-medium').text
        const infos = doc.querySelectorAll('div.py-1')
        const authors = []
        const types = []
        const tags = []
        try {
            for (const a of infos[0].querySelectorAll('a > span')) {
                let t = a.text.trim()
                if (t.endsWith(',')) t = t.slice(0, -1).trim()
                authors.push(t)
            }
            for (const a of infos[1].querySelectorAll('a > span')) {
                let t = a.text.trim()
                if (t.endsWith(',')) t = t.slice(0, -1).trim()
                types.push(t)
            }
            for (const a of infos[2].querySelectorAll('a')) {
                tags.push(a.text.replace('\n', '').replaceAll(' ', '').replace('#', ''))
            }
        } catch (e) {
            console.warn('[mh18]', '标签解析部分失败:', e)
        }

        // 章节：经站点接口取完整章节列表
        const mangaId = doc.querySelector('#mangachapters').attributes['data-mid']
        const chapterUrl = this.baseUrl + '/manga/get?mid=' + mangaId + '&mode=all&t=' + Date.now()
        console.log('[mh18]', '章节请求:', chapterUrl)
        const chapterHtml = await Network.get(chapterUrl, this.headers)
        const chapterDoc = new HtmlDocument(chapterHtml)
        const chapters = []
        for (const ch of chapterDoc.querySelectorAll('.chapteritem')) {
            const info = ch.querySelector('a')
            chapters.push({
                id: info.attributes['data-ms'] + '@' + info.attributes['data-cs'],
                title: ch.querySelector('.chaptertitle').text,
            })
        }
        chapterDoc.dispose()
        console.log('[mh18]', '章节数:', chapters.length, '作者:', authors.join(','), '类型:', types.join(','))

        // 相关推荐
        const recommend = []
        for (const item of doc.querySelectorAll('div.cardlist > div.pb-2')) {
            try {
                recommend.push({
                    id: item.querySelector('a').attributes['href'],
                    title: item.querySelector('h3').text,
                })
            } catch (e) {
                continue
            }
        }
        doc.dispose()

        this._comicId = url
        this._comicTitle = title
        this._comicCover = cover
        this._chapters = chapters

        const items = []
        // 1) 头部卡片
        items.push(UI.Card({
            padding: 12,
            shapeRadius: 8,
            child: UI.Row({
                crossAxisAlignment: 'start',
                children: [
                    cover ? UI.Image({ src: cover, width: 110, height: 150, headers: this.headers }) : null,
                    UI.SizedBox({ width: 12 }),
                    UI.Expanded({
                        child: UI.Column({
                            crossAxisAlignment: 'start',
                            children: [
                                UI.Text({ content: title, style: { fontSize: 16, weight: 'bold' }, maxLines: 3 }),
                                authors.length ? UI.Text({ content: '作者: ' + authors.join(', '), style: { fontSize: 12, color: '#888888' }, maxLines: 1 }) : null,
                                types.length ? UI.Text({ content: '类型: ' + types.join(', '), style: { fontSize: 12, color: '#888888' }, maxLines: 1 }) : null,
                            ].filter((x) => x != null),
                        }),
                    }),
                ].filter((x) => x != null),
            }),
        }))
        // 2) 标签
        if (tags.length > 0) {
            items.push(UI.Card({
                padding: 12,
                shapeRadius: 8,
                child: UI.Wrap({
                    spacing: 6,
                    runSpacing: 6,
                    children: tags.map((t) => UI.Tag({ text: t })),
                }),
            }))
        }
        // 3) 简介
        if (description) {
            items.push(UI.Card({
                padding: 12,
                shapeRadius: 8,
                child: UI.Text({ content: description, style: { fontSize: 13, color: '#555555' }, maxLines: 6 }),
            }))
        }
        // 4) 章节
        if (chapters.length > 0) {
            items.push(UI.ExpansionTile({
                title: UI.Text({ content: '章节（' + chapters.length + ' 话）', style: { fontSize: 14, weight: 'bold' }, maxLines: 1 }),
                initiallyExpanded: chapters.length <= 30,
                shapeRadius: 0,
                children: [
                    UI.Container({
                        padding: 8,
                        child: UI.Wrap({
                            spacing: 6,
                            runSpacing: 6,
                            children: chapters.map((ep) => UI.Button({
                                label: ep.title,
                                style: 'text',
                                onTap: UI.Action({ method: 'openReader', args: [ep.id] }),
                            })),
                        }),
                    }),
                ],
            }))
        }
        // 5) 相关推荐
        if (recommend.length > 0) {
            items.push(UI.Card({
                padding: 12,
                shapeRadius: 8,
                child: UI.Column({
                    crossAxisAlignment: 'start',
                    children: [
                        UI.Text({ content: '相关推荐', style: { fontSize: 14, weight: 'bold' } }),
                        UI.SizedBox({ height: 8 }),
                        UI.Wrap({
                            spacing: 6,
                            runSpacing: 6,
                            children: recommend.map((r) => UI.Button({
                                label: r.title,
                                style: 'text',
                                onTap: UI.Navigate({
                                    page: 'descriptor',
                                    method: 'getDetail',
                                    args: [r.id],
                                    title: r.title,
                                }),
                            })),
                        }),
                    ],
                }),
            }))
        }

        PluginBrowse.open(this.key, {
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
            Dialog.showToast('章节列表为空，请先从详情页进入')
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
            plugin: 'mh18',
            method: 'loadChapterImages',
            args: [this._comicId, ep.id],
        }))
        Navigator.navigateToReader({
            comicId: this._comicId,
            comicTitle: this._comicTitle,
            chapters: chapters,
            sourceKey: 'mh18',
            initialChapter: initialChapter,
            initialPage: 1,
        })
    }

    // ============ 章节图片（阅读器惰性加载） ============

    async loadChapterImages(comicId, epId) {
        const ids = String(epId).split('@')
        const url = this.baseUrl + '/chapter/getcontent?m=' + ids[0] + '&c=' + ids[1]
        console.log('[mh18]', '章节图片请求:', url)
        const html = await Network.get(url, this.headers)
        const doc = new HtmlDocument(html)
        const box = doc.querySelector('#chapcontent')
        const images = []
        if (box) {
            for (const img of box.querySelectorAll('img')) {
                images.push(img.attributes['data-src'] ? img.attributes['data-src'] : img.attributes['src'])
            }
        }
        doc.dispose()
        if (images.length === 0) {
            console.error('[mh18]', '章节图片解析为空: url=' + url + ' 页长=' + html.length)
            throw '章节图片解析为空: url=' + url
        }
        console.log('[mh18]', '图片数:', images.length)
        return images
    }

    // ============ 图片加载定制 ============

    getImageLoadingConfig(url, comicId, epId) {
        return { headers: this.headers }
    }

    // ============ 浏览历史回放 ============

    async onOpenBrowseEntry(entry) {
        if (!entry || !entry.kv || !entry.kv.id) {
            Dialog.showToast('浏览历史无效')
            return
        }
        Navigator.navigateToDescriptor(this.key, {
            method: 'getDetail',
            args: [entry.kv.id],
            title: entry.title || '',
        })
    }
}
