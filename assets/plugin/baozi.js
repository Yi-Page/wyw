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
// 说明：
//   - 由 venera 的 baozi.js（v1.1.6）移植而来；venera 的登录/收藏在 wyw 中无对应支撑，已移除
//   - Network.get 直接返回 body 字符串，非 2xx 由框架抛异常
//   - 分类接口只返回 next 标记、无总页数：有下一页时 maxPage 取上限值，翻到空页由框架兜底
//   - 章节以 chapter_slot 作为 epId（列表索引 ≠ 站点 slot），图片经
//     /user/page_direct 重定向到站点章节页解析（域名/路径由站点决定）
//   - 所有请求统一携带浏览器 UA（见 baseHeaders）：App 接口 appcn.baozimh.com
//     会拒绝非浏览器 UA（Dart 默认 UA 被 403），Venera 原插件经 WebView 加载因此能通

class baozi extends PluginSource {
    name = '包子漫画'
    key = 'baozi'
    version = '1.1.8'

    // 浏览器 UA：App 版章节接口（appcn.baozimh.com/baozimhapp）会拒绝非浏览器
    // UA 的请求（Dio 默认 Dart/x 会被 403）；Venera 原插件经 WebView 带浏览器
    // UA 加载，故此处补齐。所有请求统一携带，避免被反爬拦截。
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
            default: 'dzmanga.com',
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

    /// 解析 HTML 列表中的漫画卡片（搜索页结构）
    parseComic(e) {
        let url = e.querySelector('a').attributes['href']
        let id = url.split('/').pop()
        let title = e.querySelector('h3').text.trim()
        let cover = e.querySelector('a > amp-img').attributes['src']
        let tags = e.querySelectorAll('div.tabs > span').map((x) => x.text.trim())
        let description = ''
        let small = e.querySelector('small')
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
        return {
            id: e.comic_id,
            title: e.name,
            subTitle: e.author,
            cover: 'https://static-tw.baozimh.com/cover/' + e.topic_img + '?w=285&h=375&q=100',
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
            html = await Network.get(url, this.baseHeaders)
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
            html = await Network.get(url, this.baseHeaders)
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
            html = await Network.get(this.baseUrl + '/comic/' + id, this.baseHeaders)
        } catch (e) {
            Dialog.showToast('详情请求失败: ' + e)
            console.error('详情请求失败: ' + e)
            return []
        }
        if (!html) return []
        const doc = new HtmlDocument(html)

        // 标题
        let titleEl = doc.querySelector('h1.comics-detail__title')
        let title = titleEl ? titleEl.text.trim() : String(id)

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

        // 简介
        let description = ''
        let descEl = doc.querySelector('p.comics-detail__desc')
        if (descEl) description = descEl.text.trim()

        // 章节：以 chapter_slot 作为 epId（列表索引 ≠ 站点 slot，必须从链接取），
        // 并保存 page_direct 链接供 loadChapterImages 使用
        let chapters = []
        let i = 0
        // 从链接提取站点章节号：优先 chapter_slot=，其次直接章节页 0_<slot>.html
        const extractSlot = (href) => {
            if (!href) return null
            let m = href.match(/chapter_slot=(\d+)/)
            if (m) return m[1]
            m = href.match(/\/(\d+)_(\d+)\.html/)
            if (m) return m[2]
            return null
        }
        const pickChapterBlock = (containerSel) => {
            for (const a of doc.querySelectorAll(containerSel + ' > div.comics-chapters > a')) {
                const href = a.getAttribute('href') || ''
                const span = a.querySelector('div > span')
                const title = span ? span.text.trim() : (a.text || '').trim()
                const slot = extractSlot(href)
                chapters.push({ id: slot !== null ? slot : String(i), title: title, url: href })
                i++
            }
        }
        pickChapterBlock('div#chapter-items')
        pickChapterBlock('div#chapters_other_list')
        if (i === 0) {
            // 主/次列表均未匹配：将全部章节反转（站点最新在前）
            const anchors = doc.querySelectorAll('div.comics-chapters > a').reverse()
            for (const a of anchors) {
                const href = a.getAttribute('href') || ''
                const span = a.querySelector('div > span')
                const title = span ? span.text.trim() : (a.text || '').trim()
                const slot = extractSlot(href)
                chapters.push({ id: slot !== null ? slot : String(i), title: title, url: href })
                i++
            }
        }
        console.error('[baozi] getDetail chapters=' + chapters.length +
            ' 前3=' + JSON.stringify(chapters.slice(0, 3)))

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
    /// epId = chapter_slot。章节页经 /user/page_direct 重定向到站点章节页
    /// （形如 cn.dzmanga.com/comic/chapter/<slug>/0_<slot>.html），
    /// 域名/路径由站点决定，不能硬编码 appcn 接口。
    ///
    /// 分页：站点章节按页拆分，标题形如「第132话(1/3)」（(当前/总页数)，
    /// 单页章节无括号），URL 为 .../0_<slot>.html、.../0_<slot>_2.html、...
    /// 因此先解析标题得到总页数，再从 canonical/next-chapter 拿到真实章节基址，
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
        let html
        try {
            html = await Network.get(pageDirect, this.baseHeaders)
        } catch (e) {
            throw '章节加载失败: ' + e
        }
        if (!html) throw '章节页面为空'
        const doc = new HtmlDocument(html)

        // ---- 分页信息 ----
        // 总页数：标题「第132话(1/3)」→ 3；单页章节无 (N/M) → 1
        let totalPages = 1
        const titleEl = doc.querySelector('title')
        const titleText = titleEl ? titleEl.text.trim() : ''
        const tm = titleText.match(/\((\d+)\s*\/\s*(\d+)\)/)
        if (tm && parseInt(tm[2], 10) > 1) {
            totalPages = Math.min(parseInt(tm[2], 10), 99)
        }
        // 真实章节基址（page_direct 重定向后的页面）：
        // 1) canonical 形如 .../0_<slot>.html → 去扩展名做分页拼接
        // 2) 兜底：第 1 页的 #next-chapter 形如 .../0_<slot>_2.html → 去掉 _N.html
        let baseNoExt = ''
        const canonEl = doc.querySelector('link[rel="canonical"]')
        if (canonEl) {
            const href = canonEl.getAttribute('href') || ''
            if (href) baseNoExt = this._absUrl(href).replace(/\.html$/, '')
        }
        if (!baseNoExt) {
            const nextA = doc.querySelector('#next-chapter')
            const nextHref = nextA ? (nextA.getAttribute('href') || '') : ''
            const m = nextHref.match(/^(.*)_\d+\.html$/)
            if (m) baseNoExt = this._absUrl(m[1])
        }
        // 动态记录真实 reader 域（站点域路由会变，如 dzmanga.com → www.baozimh.com），
        // 供 getImageLoadingConfig 的防盗链 Referer 使用；未检测到则回退设置项。
        const detectedHost = this._extractHost(baseNoExt)
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
        parsePage(doc)
        let fetchedPages = 1
        // 诊断用：第 1 页用真实章节页地址（baseNoExt + .html），后续页为各自分页地址
        const pageUrls = [baseNoExt ? baseNoExt + '.html' : pageDirect]
        // 诊断：统计各选择器命中数，便于定位页面结构
        let probes = ''
        for (const sel of ['.chapter-img', '.comic-contain', '.comic-contain amp-img', 'amp-img', 'img']) {
            probes += sel + '=' + doc.querySelectorAll(sel).length + ' '
        }
        doc.dispose()

        // ---- 依次抓取剩余分页：.../0_<slot>_N.html ----
        if (totalPages > 1 && baseNoExt) {
            for (let p = 2; p <= totalPages; p++) {
                const pageUrl = baseNoExt + '_' + p + '.html'
                let ph
                try {
                    ph = await Network.get(pageUrl, this.baseHeaders)
                } catch (e) {
                    console.error('[baozi] 分页请求失败 page=' + p + ' url=' + pageUrl + ' err=' + e)
                    continue
                }
                if (!ph) continue
                const pdoc = new HtmlDocument(ph)
                parsePage(pdoc)
                pdoc.dispose()
                fetchedPages++
                pageUrls.push(pageUrl)
            }
        }

        // 诊断：统计各选择器命中数，便于定位页面结构
        console.error('[baozi] loadChapterImages url=' + pageDirect +
            ' htmlLen=' + (html ? html.length : 0) +
            ' title="' + titleText + '" totalPages=' + totalPages +
            ' fetched=' + fetchedPages + ' pages=' + JSON.stringify(pageUrls) +
            ' images=' + images.length + ' epId=' + epId + ' | ' + probes +
            ' 前3=' + JSON.stringify(images.slice(0, 3)))
        if (images.length === 0) {
            throw '章节图片为空（详见日志：' + probes + '）'
        }
        return images
    }

    /// 图片加载配置（防盗链：CDN 校验 reader 域 Referer + 浏览器 UA，否则返回被拦截的修改图）。
    /// 参数与 venera 的 comic.onImageLoad 一致：(url, comicId, epId)
    getImageLoadingConfig(url, comicId, epId) {
        let rd = this.loadSetting('reader_domain') || 'dzmanga.com'
        // 优先用最近一次章节页动态检测到的真实 reader 域（避免站点换域后防盗链失效）
        const refHost = this._readerHost || (this.lang + '.' + rd)
        return {
            headers: {
                'User-Agent': this.ua,
                'Referer': 'https://' + refHost + '/',
                'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
            },
        }
    }

    /// 按设置的 cdn 域名改写图片地址（默认保持原样；不擅自插入质量参数，避免破坏 CDN URL）
    _rewriteImage(u) {
        const setDomain = this.loadSetting('cdn_domains')
        if (!setDomain) return u
        const m = u.match(/^(https?:\/\/)?([^/\s:]+)(:\d+)?(\/.*)/)
        if (!m) return u
        return m[1] + setDomain + (m[3] || '') + m[4]
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
