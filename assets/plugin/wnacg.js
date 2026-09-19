// description: 紳士漫畫 漫画源 — 搜索/分类/详情/阅读（由 venera wnacg.js v1.0.5 移植，转换脚本自动生成）
// type: manga
//
// 由 venera 源自动转换：
// - 保留原站点的搜索/分类/详情/阅读核心逻辑（_searchApi/_categoryApi/_comicApi/_categoryData 内部对象）
// - 类开头的「wyw 适配层」将其包装为 wyw 插件接口（search/getDetail/openReader/分类四件套/浏览历史回放）
// - 已移除 wyw 无对应支撑的功能：账号登录/网络收藏/评论/点赞/评分/缩略图墙/外链识别/探索页(未映射部分)
// - Network 调用已改写为 wyw 原生风格：Network.get/post 直接返回 body 字符串，失败抛结构化异常（e.status/e.kind）

class wnacg extends PluginSource {
    // ================================================================
    // wyw 适配层（转换脚本统一注入）
    // venera 原内部结构保留：_searchApi / _categoryApi / _comicApi / _categoryData / _explore
    // 本层把它们包装为 wyw 插件接口：search / getDetail / openReader / loadChapterImages / 分类四件套
    // ================================================================

    constructor() {
        super()
        // wyw 引擎不会调用 init()：构造时兜底触发（异步、不阻塞注册）
        if (typeof this.init === 'function') {
            try {
                Promise.resolve(this.init()).catch((e) => console.warn('[wnacg]', 'init 失败:', e))
            } catch (e) {
                console.warn('[wnacg]', 'init 失败:', e)
            }
        }
    }

    // —— 通用结果卡片（venera Comic 字段 → UI.Card）——
    _comicCard(c) {
        if (!c) return null
        const metaLines = []
        const subtitle = c.subtitle || c.subTitle
        if (subtitle) metaLines.push(String(subtitle))
        if (c.language) metaLines.push(String(c.language))
        if (Array.isArray(c.tags) && c.tags.length) metaLines.push(c.tags.slice(0, 4).join('、'))
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
                                UI.Text({ content: String(c.title || ''), style: { fontSize: 14, weight: 'bold' }, maxLines: 2 }),
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
                        onTap: UI.Navigate({ page: 'descriptor', method: 'getDetail', args: [c.id], title: String(c.title || '') }),
                    }),
                ].filter((x) => x != null),
            }),
        })
    }

    // —— 搜索 ——
    async search(keyword, page = 1) {
        try {
            if (this._searchApi && typeof this._searchApi.load === 'function') {
                const res = await this._searchApi.load.call(this, keyword, [], page)
                return ((res && res.comics) || []).map((c) => this._comicCard(c)).filter((x) => x != null)
            }
            if (this._searchApi && typeof this._searchApi.loadNext === 'function') {
                const comics = await this._walkNext('search::' + keyword, (next) => this._searchApi.loadNext.call(this, keyword, [], next), page)
                return comics.map((c) => this._comicCard(c)).filter((x) => x != null)
            }
            return []
        } catch (e) {
            console.error('[wnacg]', '搜索失败:', e)
            Dialog.showToast('搜索失败: ' + e)
            return []
        }
    }

    // loadNext 型接口的页码模拟：逐页走 token 链到目标页（带缓存，回翻不重复请求）
    async _walkNext(cacheKey, nextFn, page) {
        const states = (this._walkStates = this._walkStates || {})
        let st = states[cacheKey]
        if (!st || st.page > page) st = states[cacheKey] = { page: 0, next: null, comics: [] }
        let comics = st.comics
        let next = st.next
        for (let p = st.page + 1; p <= page; p++) {
            const r = await nextFn(next)
            comics = (r && r.comics) || []
            next = (r && r.next) || null
            st.page = p
            st.next = next
            st.comics = comics
            if (!next) break
        }
        return comics
    }

    // —— 分类浏览 ——
    getCategory() {
        if (!this._categoryData) return null
        const parts = (this._categoryData.parts || [])
            .map((p) => ({ name: p.name, categories: p.categories || [] }))
            .filter((p) => p.categories.length > 0)
        if (parts.length === 0) return null
        return { title: this._categoryData.title || this.name, parts: parts }
    }

    getCategoryOptions(category) {
        if (!this._categoryApi || !Array.isArray(this._categoryApi.optionList)) return null
        return this._categoryApi.optionList.map((group) => ({
            label: group.label || '筛选',
            options: (group.options || []).map((s) => {
                const i = String(s).indexOf('-')
                // 前导 "-" 表示空值（如 "-全部"→value="",text="全部"）；"-" 是 value/text 分隔符
                return i < 0 ? { value: s, text: String(s) } : { value: String(s).slice(0, i), text: String(s).slice(i + 1) }
            }),
        }))
    }

    async _fetchCategoryComics(category, page = 1, options = []) {
        const api = this._categoryApi
        if (!api) throw '该源未实现分类加载'
        // 分类名 → venera 的 category param（categoryParams / groupParam）
        let param = null
        if (this._categoryData) {
            for (const p of this._categoryData.parts || []) {
                const idx = (p.categories || []).indexOf(category)
                if (idx >= 0) {
                    if (p.categoryParams && p.categoryParams[idx] != null) param = p.categoryParams[idx]
                    else if (p.groupParam) param = p.groupParam
                    else param = category
                    break
                }
            }
        }
        if (param == null) param = category
        if (typeof api.load === 'function') {
            return await api.load.call(this, category, param, options || [], page)
        }
        if (api.ranking && typeof api.ranking.load === 'function') {
            return await api.ranking.load.call(this, category, page)
        }
        throw '该源未实现分类加载: ' + category
    }

    async loadCategory(category, page = 1, options = []) {
        let maxPage = 200
        const res = await this._fetchCategoryComics(category, page, options)
        if (res && typeof res.maxPage === 'number' && res.maxPage > 0) maxPage = res.maxPage
        return [
            UI.Pagination({
                page: page,
                maxPage: maxPage,
                pageMethod: 'loadCategoryPage',
                pageArgs: [category, 1, options],
            }),
        ]
    }

    async loadCategoryPage(category, page = 1, options = []) {
        const res = await this._fetchCategoryComics(category, page, options)
        return ((res && res.comics) || []).map((c) => this._comicCard(c)).filter((x) => x != null)
    }

    // —— 详情（运行时缓存供 openReader / loadChapterImages 复用）——
    _comicId = ''
    _comicTitle = ''
    _comicCover = ''
    _chapters = []

    async getDetail(id) {
        if (!this._comicApi || typeof this._comicApi.loadInfo !== 'function') throw '该源未实现详情加载'
        const info = await this._comicApi.loadInfo.call(this, id)
        const title = String((info && info.title) || '')
        const cover = (info && info.cover) || ''
        this._comicId = id
        this._comicTitle = title
        this._comicCover = cover

        let chapters = []
        if (info && info.chapters && typeof info.chapters === 'object') {
            // venera 的 chapters 允许普通对象或 Map；如 copy_manga 会传嵌套 Map<分组名, Map<epId, 标题>>
            const pushFlat = (mapLike, prefix) => {
                const add = (epId, title) => {
                    chapters.push({ id: String(epId), title: prefix ? prefix + ' · ' + String(title) : String(title) })
                }
                if (mapLike instanceof Map) mapLike.forEach((title, epId) => add(epId, title))
                else for (const epId of Object.keys(mapLike)) add(epId, mapLike[epId])
            }
            if (info.chapters instanceof Map) {
                const values = Array.from(info.chapters.values())
                const isNested = values.length > 0 && values.every((v) => v && typeof v === 'object')
                if (isNested && info.chapters.size > 1) {
                    info.chapters.forEach((v, groupTitle) => pushFlat(v, String(groupTitle)))
                } else if (isNested) {
                    info.chapters.forEach((v) => pushFlat(v, ''))
                } else {
                    pushFlat(info.chapters, '')
                }
            } else {
                pushFlat(info.chapters, '')
            }
        }
        const isGallery = chapters.length === 0
        if (isGallery) chapters = [{ id: '__all__', title: '阅读' }]
        this._chapters = chapters
        console.log('[wnacg]', '详情:', title, '章节数:', isGallery ? 0 : chapters.length)

        const items = []
        // 1) 头部卡片
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
                                UI.Text({ content: title, style: { fontSize: 16, weight: 'bold' }, maxLines: 3 }),
                                info && info.subtitle ? UI.Text({ content: String(info.subtitle), style: { fontSize: 12, color: '#888888' }, maxLines: 1 }) : null,
                                info && info.uploader ? UI.Text({ content: '上传: ' + info.uploader, style: { fontSize: 12, color: '#888888' }, maxLines: 1 }) : null,
                                info && info.updateTime ? UI.Text({ content: '更新: ' + info.updateTime, style: { fontSize: 12, color: '#888888' }, maxLines: 1 }) : null,
                            ].filter((x) => x != null),
                        }),
                    }),
                ].filter((x) => x != null),
            }),
        }))
        // 2) 标签
        const tagGroups = []
        if (info && Array.isArray(info.tags)) tagGroups.push(['标签', info.tags])
        else if (info && info.tags && typeof info.tags === 'object') {
            for (const ns of Object.keys(info.tags)) {
                if (Array.isArray(info.tags[ns]) && info.tags[ns].length) tagGroups.push([ns, info.tags[ns]])
            }
        }
        if (tagGroups.length) {
            items.push(UI.Card({
                padding: 12,
                shapeRadius: 8,
                child: UI.Column({
                    crossAxisAlignment: 'start',
                    children: tagGroups.flatMap((g) => [
                        UI.Text({ content: String(g[0]), style: { fontSize: 12, weight: 'bold', color: '#666666' } }),
                        UI.Wrap({ spacing: 6, runSpacing: 6, children: g[1].slice(0, 30).map((t) => UI.Tag({ text: String(t) })) }),
                        UI.SizedBox({ height: 4 }),
                    ]),
                }),
            }))
        }
        // 3) 简介
        if (info && info.description) {
            items.push(UI.Card({
                padding: 12,
                shapeRadius: 8,
                child: UI.Text({ content: String(info.description), style: { fontSize: 13, color: '#555555' }, maxLines: 8 }),
            }))
        }
        // 4) 章节
        items.push(UI.ExpansionTile({
            title: UI.Text({ content: isGallery ? '阅读' : '章节（' + chapters.length + ' 话）', style: { fontSize: 14, weight: 'bold' }, maxLines: 1 }),
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
        // 5) 相关推荐
        if (info && Array.isArray(info.recommend) && info.recommend.length) {
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
                            children: info.recommend.map((r) => UI.Button({
                                label: String((r && r.title) || ''),
                                style: 'text',
                                onTap: UI.Navigate({ page: 'descriptor', method: 'getDetail', args: [r.id], title: String((r && r.title) || '') }),
                            })),
                        }),
                    ],
                }),
            }))
        }

        PluginBrowse.open(this.key, { id: String(id), title: title, cover: cover, kv: { id: String(id) } })
        return items
    }

    // —— 阅读器（章节惰性加载）——
    async openReader(epId) {
        if (!this._chapters.length) {
            Dialog.showToast('章节列表为空，请先从详情页进入')
            return
        }
        let initialChapter = 1
        for (let i = 0; i < this._chapters.length; i++) {
            if (this._chapters[i].id === String(epId)) { initialChapter = i + 1; break }
        }
        const chapters = this._chapters.map((ep) => ({
            id: ep.id,
            title: ep.title,
            plugin: 'wnacg',
            method: 'loadChapterImages',
            args: [this._comicId, ep.id],
        }))
        Navigator.navigateToReader({
            comicId: this._comicId,
            comicTitle: this._comicTitle,
            chapters: chapters,
            sourceKey: 'wnacg',
            initialChapter: initialChapter,
            initialPage: 1,
        })
    }

    async loadChapterImages(comicId, epId) {
        if (!this._comicApi || typeof this._comicApi.loadEp !== 'function') throw '该源未实现章节图片加载'
        const realEp = epId === '__all__' ? null : epId
        const res = await this._comicApi.loadEp.call(this, comicId, realEp)
        const raw = (res && res.images) ? res.images : (Array.isArray(res) ? res : [])
        const urls = raw
            .map((x) => (typeof x === 'string' ? x : (x && x.url) || ''))
            .filter((u) => !!u)
        if (urls.length === 0) {
            console.error('[wnacg]', '章节图片解析为空: comicId=' + comicId + ' epId=' + epId)
            throw '章节图片解析为空'
        }
        console.log('[wnacg]', '图片数:', urls.length)
        return urls
    }

    getImageLoadingConfig(url, comicId, epId) {
        if (this._comicApi && typeof this._comicApi.onImageLoad === 'function') {
            const cfg = this._comicApi.onImageLoad.call(this, url, comicId, epId)
            if (cfg && typeof cfg === 'object') return cfg
        }
        return {}
    }

    // —— 浏览历史回放 ——
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
    // ================= wyw 适配层结束 =================

    // Note: The fields which are marked as [Optional] should be removed if not used

    // name of the source
    name = "紳士漫畫"

    // unique id of the source
    key = "wnacg"

    version = "1.0.5"


    // update url

    static domains = [];

    get baseUrl() {
        let selection = this.loadSetting('domainSelection')
        if (selection === undefined || selection === null) selection = 0
        selection = parseInt(selection)

        if (selection === 0) {
            // 选择自定义域名
            let domain0 = this.loadSetting('domain0')
            if (!domain0 || domain0.trim() === '') {
                throw 'Custom domain is not set'
            }
            return `https://${domain0.trim()}`
        } else {
            // 选择获取的域名 (Domain 1-3)
            let index = selection - 1
            if (index >= wnacg.domains.length) {
                throw 'Selected domain is unavailable'
            }
            return `https://${wnacg.domains[index]}`
        }
    }

    overwriteDomains(domains) {
        if (domains.length != 0) wnacg.domains = domains
    }

    // [Optional] account related

    async init() {
        if (this.loadSetting('refreshDomainsOnStart') === '1') await this.refreshDomains(false)
    }

    /**
     * 刷新域名列表
     * @param showConfirmDialog {boolean}
     */
    async refreshDomains(showConfirmDialog) {
        let url = "https://wn01.link/"
        let title = ""
        let message = ""
        let domains = []

        try {
            let res = await Network.fetch(url)
            if (res.status == 200) {
                let html = await res.text()
                let document = new HtmlDocument(html)
                // 提取所有链接
                let links = document.querySelectorAll("a[href]")
                let seenDomains = new Set()

                for (let link of links) {
                    let href = link.attributes["href"]
                    if (!href) continue

                    // 提取域名（支持 http:// 和 https://）
                    let match = href.match(/^https?:\/\/([^\/]+)/)
                    if (match) {
                        let domain = match[1]
                        // 只提取有效的域名，排除 wn01.link 自身和其他无关链接
                        if (domain &&
                            domain.includes(".") &&
                            !domain.includes("wn01.link") &&
                            !domain.includes("google.cn") &&
                            !domain.includes("cdn-cgi") &&
                            !seenDomains.has(domain)) {
                            domains.push(domain)
                            seenDomains.add(domain)
                        }
                    }
                }
                document.dispose()

                if (domains.length > 0) {
                    title = "Update Success"
                    message = "Fetched: \n\n"
                }
            }
        } catch (e) {
            // 获取失败，使用自定义域名
        }

        if (domains.length == 0) {
            title = "Update Failed"
            message = "Using Custom: \n\n"
            domains = wnacg.domains
        }

        for (let i = 0; i < domains.length; i++) {
            message = message + `URL ${i + 1}: ${domains[i]}\n`
        }
        message = message + `\n Total: ${domains.length} URLs\n\n Re-enter page to refresh`

        if (showConfirmDialog) {
            Dialog.showDialog(
                title,
                message,
                [
                    {
                        text: "Cancel",
                        callback: () => { }
                    },
                    {
                        text: "Apply",
                        callback: () => this.overwriteDomains(domains)
                    }
                ]
            )
        } else {
            this.overwriteDomains(domains)
        }
    }

    parseComic(c) {
        let link = c.querySelector("div.pic_box > a").attributes["href"];
        let id = RegExp("(?<=-aid-)[0-9]+").exec(link)[0];
        let image =
            c.querySelector("div.pic_box > a > img").attributes["src"];
        image = `https:${image}`;
        let name = c.querySelector("div.info > div.title > a").text;
        let info = c.querySelector("div.info > div.info_col").text.trim();
        info = info.replaceAll('\n', '');
        info = info.replaceAll('\t', '');
        return ({
            id: id,
            title: name,
            cover: image,
            description: info,
        })
    }

    // explore page list
    _explore = [
        {
            // title of the page.
            // title is used to identify the page, it should be unique
            title: "紳士漫畫",

            /// multiPartPage or multiPageComicList or mixed
            type: "multiPartPage",

            /**
             * load function
             * @param page {number | null} - page number, null for `singlePageWithMultiPart` type
             * @returns {{}}
             * - for `multiPartPage` type, return [{title: string, comics: Comic[], viewMore: string?}]
             * - for `multiPageComicList` type, for each page(1-based), return {comics: Comic[], maxPage: number}
             * - for `mixed` type, use param `page` as index. for each index(0-based), return {data: [], maxPage: number?}, data is an array contains Comic[] or {title: string, comics: Comic[], viewMore: string?}
             */
            load: async (page) => {
                let res = await Network.get(this.baseUrl, {})
                
                let document = new HtmlDocument(res)
                let titleBlocks = document.querySelectorAll("div.title_sort");
                let comicBlocks = document.querySelectorAll("div.bodywrap");
                if (titleBlocks.length !== comicBlocks.length) {
                    throw "Invalid Page"
                }
                let result = []
                for (let i = 0; i < titleBlocks.length; i++) {
                    let title = titleBlocks[i].querySelector("div.title_h2").text.replaceAll(/\s+/g, '')
                    let link = titleBlocks[i].querySelector("div.r > a").attributes["href"]
                    let comics = []
                    let comicBlock = comicBlocks[i]
                    let comicElements = comicBlock.querySelectorAll("div.gallary_wrap > ul.cc > li")
                    for (let comicElement of comicElements) {
                        comics.push(this.parseComic(comicElement))
                    }
                    result.push({
                        title: title,
                        comics: comics,
                        viewMore: `category:${title}@${link}`
                    })
                }
                document.dispose()
                return result
            }
        }
    ]

    // categories
    _categoryData = {
        /// title of the category page, used to identify the page, it should be unique
        title: "紳士漫畫",
        parts: [
            {
                // title of the part
                name: "最新",

                // fixed or random
                // if random, need to provide `randomNumber` field, which indicates the number of comics to display at the same time
                type: "fixed",

                // number of comics to display at the same time
                // randomNumber: 5,

                categories: ["最新"],

                // category or search
                // if `category`, use categoryComics.load to load comics
                // if `search`, use search.load to load comics
                itemType: "category",

                // [Optional] {string[]?} must have same length as categories, used to provide loading param for each category
                categoryParams: ["/albums.html"],

                // [Optional] {string} cannot be used with `categoryParams`, set all category params to this value
                groupParam: null,
            },
            {
                // title of the part
                name: "同人誌",

                // fixed or random
                // if random, need to provide `randomNumber` field, which indicates the number of comics to display at the same time
                type: "fixed",

                // number of comics to display at the same time
                // randomNumber: 5,

                categories: ["同人誌", "漢化", "日語", "English", "CG畫集", "3D漫畫", "寫真Cosplay"],

                // category or search
                // if `category`, use categoryComics.load to load comics
                // if `search`, use search.load to load comics
                itemType: "category",

                // [Optional] {string[]?} must have same length as categories, used to provide loading param for each category
                categoryParams: [
                    "/albums-index-cate-5.html",
                    "/albums-index-cate-1.html",
                    "/albums-index-cate-12.html",
                    "/albums-index-cate-16.html",
                    "/albums-index-cate-2.html",
                    "/albums-index-cate-22.html",
                    "/albums-index-cate-3.html",
                ],

                // [Optional] {string} cannot be used with `categoryParams`, set all category params to this value
                groupParam: null,
            },
            {
                // title of the part
                name: "單行本",

                // fixed or random
                // if random, need to provide `randomNumber` field, which indicates the number of comics to display at the same time
                type: "fixed",

                // number of comics to display at the same time
                // randomNumber: 5,

                categories: ["單行本", "漢化", "日語", "English",],

                // category or search
                // if `category`, use categoryComics.load to load comics
                // if `search`, use search.load to load comics
                itemType: "category",

                // [Optional] {string[]?} must have same length as categories, used to provide loading param for each category
                categoryParams: [
                    "/albums-index-cate-6.html",
                    "/albums-index-cate-9.html",
                    "/albums-index-cate-13.html",
                    "/albums-index-cate-17.html",
                ],

                // [Optional] {string} cannot be used with `categoryParams`, set all category params to this value
                groupParam: null,
            },
            {
                // title of the part
                name: "雜誌短篇",

                // fixed or random
                // if random, need to provide `randomNumber` field, which indicates the number of comics to display at the same time
                type: "fixed",

                // number of comics to display at the same time
                // randomNumber: 5,

                categories: ["雜誌短篇", "漢化", "日語", "English",],

                // category or search
                // if `category`, use categoryComics.load to load comics
                // if `search`, use search.load to load comics
                itemType: "category",

                // [Optional] {string[]?} must have same length as categories, used to provide loading param for each category
                categoryParams: [
                    "/albums-index-cate-7.html",
                    "/albums-index-cate-10.html",
                    "/albums-index-cate-14.html",
                    "/albums-index-cate-18.html",
                ],

                // [Optional] {string} cannot be used with `categoryParams`, set all category params to this value
                groupParam: null,
            },
            {
                // title of the part
                name: "韓漫",

                // fixed or random
                // if random, need to provide `randomNumber` field, which indicates the number of comics to display at the same time
                type: "fixed",

                // number of comics to display at the same time
                // randomNumber: 5,

                categories: ["韓漫", "漢化", "生肉",],

                // category or search
                // if `category`, use categoryComics.load to load comics
                // if `search`, use search.load to load comics
                itemType: "category",

                // [Optional] {string[]?} must have same length as categories, used to provide loading param for each category
                categoryParams: [
                    "/albums-index-cate-19.html",
                    "/albums-index-cate-20.html",
                    "/albums-index-cate-21.html",
                ],

                // [Optional] {string} cannot be used with `categoryParams`, set all category params to this value
                groupParam: null,
            },
        ],
        // enable ranking page
        enableRankingPage: true,
    }

    /// category comic loading related
    _categoryApi = {
        /**
         * load comics of a category
         * @param category {string} - category name
         * @param param {string?} - category param
         * @param options {string[]} - options from optionList
         * @param page {number} - page number
         * @returns {Promise<{comics: Comic[], maxPage: number}>}
         */
        load: async (category, param, options, page) => {
            let url = this.baseUrl + param
            if (page !== 0) {
                if (!url.includes("-")) {
                    url = url.replaceAll(".html", "-.html");
                }
                url = url.replaceAll("index", "");
                let lr = url.split("albums-");
                lr[1] = `index-page-${page}${lr[1]}`;
                url = `${lr[0]}albums-${lr[1]}`;
            }

            let res = await Network.get(url, {})
            
            let document = new HtmlDocument(res)
            let comicElements = document.querySelectorAll("div.grid div.gallary_wrap > ul.cc > li")
            let comics = []
            for (let comicElement of comicElements) {
                comics.push(this.parseComic(comicElement))
            }
            let pagesLink = document.querySelectorAll("div.f_left.paginator > a");
            let pages = Number(pagesLink[pagesLink.length - 1].text)
            document.dispose()
            return {
                comics: comics,
                maxPage: pages,
            }
        },
        ranking: {
            options: [
                "day-Day",
                "week-Week",
                "month-Month",
            ],
            load: async (option, page) => {
                let url = `${this.baseUrl}/albums-favorite_ranking-type-${option}.html`
                if (page !== 0) {
                    url = `${this.baseUrl}/albums-favorite_ranking-page-${page}-type-${option}.html`
                }

                let res = await Network.get(url, {})
                

                let document = new HtmlDocument(res)
                let comicElements = document.querySelectorAll("div.grid div.gallary_wrap > ul.cc > li")
                let comics = []
                for (let comicElement of comicElements) {
                    comics.push(this.parseComic(comicElement))
                }

                let pagesLink = document.querySelectorAll("div.f_left.paginator > a")
                let pages = 1
                if (pagesLink.length > 0) {
                    pages = Number(pagesLink[pagesLink.length - 1].text)
                }

                document.dispose()
                return {
                    comics: comics,
                    maxPage: pages,
                }
            }
        }
    }

    /// search related
    _searchApi = {
        /**
         * load search result
         * @param keyword {string}
         * @param options {string[]} - options from optionList
         * @param page {number}
         * @returns {Promise<{comics: Comic[], maxPage: number}>}
         */
        load: async (keyword, options, page) => {
            let url = `${this.baseUrl}/search/?q=${encodeURIComponent(keyword)}&f=_all&s=create_time_DESC&syn=yes`
            if (page !== 0) {
                url += `&p=${page}`
            }
            let res = await Network.get(url, {})
            
            let document = new HtmlDocument(res)
            let comicElements = document.querySelectorAll("div.grid div.gallary_wrap > ul.cc > li")
            let comics = []
            for (let comicElement of comicElements) {
                comics.push(this.parseComic(comicElement))
            }
            let total = document.querySelectorAll("p.result > b")[0].text.replaceAll(',', '')
            const comicsPerPage = 24
            let pages = Math.ceil(Number(total) / comicsPerPage)
            document.dispose()
            return {
                comics: comics,
                maxPage: pages,
            }
        },
    }

    // favorite related

    /// single comic related
    _comicApi = {
        /**
         * load comic info
         * @param id {string}
         * @returns {Promise<ComicDetails>}
         */
        loadInfo: async (id) => {
            let res = await Network.get(`${this.baseUrl}/photos-index-page-1-aid-${id}.html`, {})
            
            let document = new HtmlDocument(res)
            let title = document.querySelector("div.userwrap > h2").text
            let cover = document.querySelector("div.userwrap > div.asTB > div.asTBcell.uwthumb > img").attributes["src"]
            cover = 'https:' + cover
            cover = cover.substring(0, 6) + cover.substring(8)
            let labels = document.querySelectorAll("div.asTBcell.uwconn > label")
            let category = labels[0].text.split("：")[1]
            let pages = labels[1].text.split("：")[1];
            let tagsDom = document.querySelectorAll("a.tagshow");
            let tags = new Map()
            tags.set("頁數", [pages])
            tags.set("分類", [category])
            if (tagsDom.length > 0) {
                tags.set("標籤", tagsDom.map((e) => e.text))
            }
            let description = document.querySelector("div.asTBcell.uwconn > p").text;
            let uploader = document.querySelector("div.asTBcell.uwuinfo > a > p").text;

            return ({
                id: id,
                title: title,
                cover: cover,
                pages: pages,
                tags: tags,
                description: description,
                uploader: uploader,
            })
        },
        /**
         * [Optional] load thumbnails of a comic
         * @param id {string}
         * @param next {string | null | undefined} - next page token, null for first page
         * @returns {Promise<{thumbnails: string[], next: string?}>} - `next` is next page token, null for no more
         */
        /**
         * load images of a chapter
         * @param comicId {string}
         * @param epId {string?}
         * @returns {Promise<{images: string[]}>}
         */
        loadEp: async (comicId, epId) => {
            let res = await Network.get(`${this.baseUrl}/photos-gallery-aid-${comicId}.html`, {})
            
            const regex = RegExp(String.raw`//[^"]+/[^"]+\.[^"]+`, 'g');
            const matches = Array.from(res.matchAll(regex));
            return {
                images: matches.map((e) => 'https:' + e[0].substring(0, e[0].length - 1))
            }
        },
        /**
         * [Optional] Handle tag click event
         * @param namespace {string}
         * @param tag {string}
         * @returns {{action: string, keyword: string, param: string?}}
         */
    }

    get settings() {
        // 动态生成选项，总是保留 Custom Domain (0)，然后根据 wnacg.domains 数量添加选项
        let domainOptions = [{ value: '0', text: 'Custom Domain' }]
        for (let i = 0; i < wnacg.domains.length; i++) {
            domainOptions.push({
                value: String(i + 1),
                text: wnacg.domains[i]
            })
        }

        return {
            refreshDomainsOnStart: {
                title: "Refresh Domain List on Startup",
                type: "select",
                options: [
                    { value: '1', text: '开' },
                    { value: '0', text: '关' },
                ],
                default: '1',
            },
            domainSelection: {
                title: "Domain Selection",
                type: "select",
                options: domainOptions,
                default: "0",
            },
            domain0: {
                title: "Custom Domain",
                type: "input",
                validator: String.raw`^(?!:\/\/)(?=.{1,253})([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$`,
                default: 'wnacg.com',
            },
        }
    }

    translation = {
        'zh_CN': {
            'Refresh Domain List': '刷新域名列表',
            'Refresh': '刷新',
            'Refresh Domain List on Startup': '启动时刷新域名列表',
            'Domain Selection': '域名选择',
            'Custom Domain': '自定义域名',
            'Custom domain is not set': '未设置自定义域名',
            'Selected domain is unavailable': '所选域名不可用，请先刷新域名列表',
            'Day': '日',
            'Week': '周',
            'Month': '月',
        },
        'zh_TW': {
            'Refresh Domain List': '刷新域名列表',
            'Refresh': '刷新',
            'Refresh Domain List on Startup': '啟動時刷新域名列表',
            'Domain Selection': '域名選擇',
            'Custom Domain': '自定義域名',
            'Custom domain is not set': '未設置自定義域名',
            'Selected domain is unavailable': '所選域名不可用，請先刷新域名列表',
            'Day': '日',
            'Week': '周',
            'Month': '月',
        },
    }
}
