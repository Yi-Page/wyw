// description: MangaDex 漫画源 — 搜索/分类/详情/阅读（由 venera manga_dex.js v1.1.0 移植，转换脚本自动生成）
// type: manga
//
// 由 venera 源自动转换：
// - 保留原站点的搜索/分类/详情/阅读核心逻辑（_searchApi/_categoryApi/_comicApi/_categoryData 内部对象）
// - 类开头的「wyw 适配层」将其包装为 wyw 插件接口（search/getDetail/openReader/分类四件套/浏览历史回放）
// - 已移除 wyw 无对应支撑的功能：账号登录/网络收藏/评论/点赞/评分/缩略图墙/外链识别/探索页(未映射部分)
// - Network 调用已改写为 wyw 原生风格：Network.get/post 直接返回 body 字符串，失败抛结构化异常（e.status/e.kind）

class manga_dex extends PluginSource {
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
                Promise.resolve(this.init()).catch((e) => console.warn('[manga_dex]', 'init 失败:', e))
            } catch (e) {
                console.warn('[manga_dex]', 'init 失败:', e)
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
            console.error('[manga_dex]', '搜索失败:', e)
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
        console.log('[manga_dex]', '详情:', title, '章节数:', isGallery ? 0 : chapters.length)

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
            plugin: 'manga_dex',
            method: 'loadChapterImages',
            args: [this._comicId, ep.id],
        }))
        Navigator.navigateToReader({
            comicId: this._comicId,
            comicTitle: this._comicTitle,
            chapters: chapters,
            sourceKey: 'manga_dex',
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
            console.error('[manga_dex]', '章节图片解析为空: comicId=' + comicId + ' epId=' + epId)
            throw '章节图片解析为空'
        }
        console.log('[manga_dex]', '图片数:', urls.length)
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
    name = "MangaDex"

    // unique id of the source
    key = "manga_dex"

    version = "1.1.1"


    // update url

    comicsPerPage = 20

    api = {
        parseComic: (data) => {
            let id = data['id']
            let titles = {}
            let mainTitles = data['attributes']['title']
            for (let lang of Object.keys(mainTitles)) {
                titles[lang] = mainTitles[lang]
            }
            for (let at of data['attributes']['altTitles']) {
                for (let lang of Object.keys(at)) {
                    if (titles[lang] === undefined) {
                        titles[lang] = at[lang]
                    }
                }
            }
            let locale = APP.locale
            let mainTitle = ''
            let firstTitle = titles[Object.keys(titles)[0]]
            if (locale.startsWith('en')) {
                mainTitle = titles['en'] || titles['ja'] || firstTitle
            } else if (locale.startsWith('zh_CN')) {
                mainTitle = titles['zh'] || titles['zh-hk'] || titles['zh-tw'] || titles['ja'] || firstTitle
            } else if (locale.startsWith('zh_TW')) {
                mainTitle = titles['zh-hk'] || titles['zh-tw'] || titles['zh'] || titles['ja'] || firstTitle
            }
            let tags = []
            for (let tag of data['attributes']['tags']) {
                tags.push(tag['attributes']['name']['en'])
            }
            let cover = data['relationships'].find((e) => e['type'] === 'cover_art')?.['attributes']['fileName']
            if (cover) {
                cover = `https://mangadex.org/covers/${id}/${cover}.256.jpg`
            } else {
                cover = ""
            }
            let description = data['attributes']['description']['en']
            let createTime = data['attributes']['createdAt']
            let updateTime = data['attributes']['updatedAt']
            let status = data['attributes']['status']
            let authors = []
            let artists = []
            for (let rel of data['relationships']) {
                if (rel['type'] === 'author') {
                    let name = rel['attributes']['name'];
                    let id = rel['id']
                    authors.push(name)
                    this.authors[name] = id
                } else if (rel['type'] === 'artist') {
                    let name = rel['attributes']['name'];
                    let id = rel['id']
                    artists.push(name)
                    this.artists[name] = id
                }
            }

            return {
                id: id,
                title: mainTitle,
                subtitle: authors.at(0),
                titles: titles,
                cover: cover,
                tags: tags,
                description: description,
                createTime: createTime,
                updateTime: updateTime,
                status: status,
                authors: authors,
                artists: artists,
            }
        },
        getPopular: async (page) => {
            let time = new Date()
            time = new Date(time.getTime() - 30 * 24 * 60 * 60 * 1000)
            let popularUrl = `https://api.mangadex.org/manga?` +
                `includes[]=cover_art&` +
                `includes[]=artist&` +
                `includes[]=author&` +
                `order[followedCount]=desc&` +
                `hasAvailableChapters=true&` +
                `createdAtSince=${time.toISOString().substring(0, 19)}&` +
                `limit=${this.comicsPerPage}`
            if (page && page > 1) {
                popularUrl += `&offset=${(page - 1) * this.comicsPerPage}`
            }
            let res = await Network.fetch(popularUrl)
            let data = await res.json()
            let total = data['total']
            let maxPage = Math.ceil(total / this.comicsPerPage)
            let comics = []
            for (let comic of data['data']) {
                comics.push(this.api.parseComic(comic))
            }
            return {
                comics: comics,
                maxPage: maxPage
            }
        },
        getRecent: async (page) => {
            let recentUrl = `https://api.mangadex.org/manga?` +
                `includes[]=cover_art&` +
                `includes[]=artist&` +
                `includes[]=author&` +
                `order[createdAt]=desc&` +
                `hasAvailableChapters=true&` +
                `limit=${this.comicsPerPage}`
            if (page && page > 1) {
                recentUrl += `&offset=${(page - 1) * this.comicsPerPage}`
            }
            let res = await Network.fetch(recentUrl)
            let data = await res.json()
            let total = data['total']
            let maxPage = Math.ceil(total / this.comicsPerPage)
            let comics = []
            for (let comic of data['data']) {
                comics.push(this.api.parseComic(comic))
            }
            return {
                comics: comics,
                maxPage: maxPage
            }
        },
        getUpdated: async (page) => {
            let updatedUrl = `https://api.mangadex.org/manga?` +
                `includes[]=cover_art&` +
                `includes[]=artist&` +
                `includes[]=author&` +
                `order[latestUploadedChapter]=desc&` +
                `contentRating[]=safe&` +
                `contentRating[]=suggestive&` +
                `hasAvailableChapters=true&` +
                `limit=${this.comicsPerPage}`
            if (page && page > 1) {
                updatedUrl += `&offset=${(page - 1) * this.comicsPerPage}`
            }
            let res = await Network.fetch(updatedUrl)
            let data = await res.json()
            let total = data['total']
            let maxPage = Math.ceil(total / this.comicsPerPage)
            let comics = []
            for (let comic of data['data']) {
                comics.push(this.api.parseComic(comic))
            }
            return {
                comics: comics,
                maxPage: maxPage
            }
        }
    }

    // Account feature is not implemented yet
    // TODO: implement account feature
    // account = {}

    // explore page list
    _explore = [
        {
            // title of the page.
            // title is used to identify the page, it should be unique
            title: "Manga Dex",

            /// multiPartPage or multiPageComicList or mixed
            type: "multiPartPage",

            load: async (page) => {
                let res = await Promise.all([
                    this.api.getPopular(page),
                    this.api.getRecent(page),
                    this.api.getUpdated(page)
                ])
                let titles = ["Popular", "Recent", "Updated"]
                let viewMore = [
                    {
                        page: "search",
                        attributes: {
                            options: ["popular", "any", "any"],
                        },
                    },
                    {
                        page: "search",
                        attributes: {
                            options: ["recent", "any", "any"],
                        },
                    },
                    {
                        page: "search",
                        attributes: {
                            options: ["updated", "any", "any"],
                        },
                    }
                ]
                let parts = []
                for (let i = 0; i < res.length; i++) {
                    let part = res[i]
                    parts.push({
                        title: titles[i],
                        comics: part.comics,
                        viewMore: viewMore[i]
                    })
                }
                return parts
            },
        }
    ]

    // categories
    _categoryData = {
        /// title of the category page, used to identify the page, it should be unique
        title: "MangaDex",
        parts: [
            {
                // title of the part
                name: "Tags",

                // fixed or random or dynamic
                // if random, need to provide `randomNumber` field, which indicates the number of comics to display at the same time
                // if dynamic, need to provide `loader` field, which indicates the function to load comics
                type: "dynamic",

                // number of comics to display at the same time
                // randomNumber: 5,

                // load function for dynamic type
                        loader: () => {
                    let categories = []
                    for (let tag of Object.keys(this.tags)) {
                        categories.push({
                            label: tag,
                            target: {
                                        action: "category",
                                        keyword: tag,
                                        param: this.tags[tag],
                            }
                        })
                    }
                    return categories
                }
            }
        ],
        // enable ranking page
        enableRankingPage: false,
    }

    _categoryApi = {
        load: async (category, param, options = [], page = 1) => {
            if (!param) {
                throw new Error("No tag id provided for category comics")
            }

            const parseOption = (option, fallback) => {
                if (option === undefined || option === null || option === "") {
                    return fallback
                }
                let value = option.split("-")[0]
                return value || fallback
            }

            const sortOption = parseOption(options[0], "popular")
            const ratingOption = parseOption(options[1], "any")
            const statusOption = parseOption(options[2], "any")

            let params = [
                "includes[]=cover_art",
                "includes[]=artist",
                "includes[]=author",
                "hasAvailableChapters=true",
                `limit=${this.comicsPerPage}`,
                `includedTags[]=${encodeURIComponent(param)}`
            ]

            if (page && page > 1) {
                params.push(`offset=${(page - 1) * this.comicsPerPage}`)
            }

            if (sortOption !== "any") {
                const orderMap = {
                    popular: "followedCount",
                    follows: "followedCount",
                    recent: "createdAt",
                    updated: "latestUploadedChapter",
                    rating: "rating"
                }
                const orderKey = orderMap[sortOption]
                if (orderKey) {
                    params.push(`order[${orderKey}]=desc`)
                }
            }

            let ratingList
            if (ratingOption === "any") {
                ratingList = ["safe", "suggestive", "erotica"]
            } else {
                ratingList = [ratingOption]
            }
            for (let rating of ratingList) {
                params.push(`contentRating[]=${encodeURIComponent(rating)}`)
            }

            if (statusOption !== "any") {
                params.push(`status[]=${encodeURIComponent(statusOption)}`)
            }

            let url = `https://api.mangadex.org/manga?${params.join("&")}`
            let res = await Network.fetch(url)
            if (!res.ok) {
                throw new Error("Network response was not ok")
            }
            let data = await res.json()
            let total = data['total'] || 0
            let comics = []
            for (let comic of data['data'] || []) {
                comics.push(this.api.parseComic(comic))
            }
            let maxPage = total ? Math.ceil(total / this.comicsPerPage) : (comics.length < this.comicsPerPage ? page : page + 1)
            return {
                comics: comics,
                maxPage: maxPage
            }
        },
        optionList: [
            {
                label: "排序",
                options: [
                    "any-Any",
                    "popular-Popular",
                    "recent-Recent",
                    "updated-Updated",
                    "rating-Rating",
                    "follows-Follows"
                ]
            },
            {
                label: "分级",
                options: [
                    "any-Any",
                    "safe-Safe",
                    "suggestive-Suggestive",
                    "erotica-Erotica"
                ]
            },
            {
                label: "状态",
                options: [
                    "any-Any",
                    "ongoing-Ongoing",
                    "completed-Completed",
                    "hiatus-Hiatus",
                    "cancelled-Cancelled"
                ]
            }
        ]
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
            let order = ""
            if (options[0] !== "any") {
                order = {
                    "popular": `order[followedCount]=desc&`,
                    "recent": `order[createdAt]=desc&`,
                    "updated": `order[latestUploadedChapter]=desc&`,
                    "rating": `order[rating]=desc&`,
                    "follows": `order[followedCount]=desc&`
                }[options[0]]
            }
            let contentRating = ""
            if (options[1] !== "any") {
                contentRating = `contentRating[]=${options[1]}&`
            }
            let status = ""
            if (options[2] !== "any") {
                status = `status[]=${options[2]}&`
            }
            let url = `https://api.mangadex.org/manga?` +
                `includes[]=cover_art&` +
                `includes[]=artist&` +
                `includes[]=author&` +
                order +
                contentRating +
                status +
                `hasAvailableChapters=true&` +
                `limit=${this.comicsPerPage}`
            if (page && page > 1) {
                url += `&offset=${(page - 1) * this.comicsPerPage}`
            }
            if (keyword) {
                let splits = keyword.split(" ")
                let reformated = []
                for (let s of splits) {
                    if (s === "") {
                        continue
                    }
                    if (s.startsWith('tag:')) {
                        let tag = s.substring(4)
                        tag = tag.replaceAll('_', ' ')
                        let id = this.tags[tag]
                        if (id !== undefined) {
                            url += `&includedTags[]=${id}`
                        } else {
                            reformated.push(s)
                        }
                    } else if (s.startsWith('author:')) {
                        let author = s.substring(7)
                        author = author.replaceAll('_', ' ')
                        let id = this.authors[author]
                        if (id !== undefined) {
                            url += `&authorOrArtist=${id}`
                        } else {
                            reformated.push(s)
                        }
                    } else if (s.startsWith('artist:')) {
                        let artist = s.substring(7)
                        artist = artist.replaceAll('_', ' ')
                        let id = this.artists[artist]
                        if (id !== undefined) {
                            url += `&authorOrArtist=${id}`
                        } else {
                            reformated.push(s)
                        }
                    } else {
                        reformated.push(s)
                    }
                }
                keyword = reformated.join(" ")
                if (keyword !== "")
                    url += `&title=${keyword}`
            }
            let res = await Network.fetch(url)
            if (!res.ok) {
                throw new Error("Network response was not ok")
            }
            let data = await res.json()
            let total = data['total']
            let maxPage = Math.ceil(total / this.comicsPerPage)
            let comics = []
            for (let comic of data['data']) {
                comics.push(this.api.parseComic(comic))
            }
            return {
                comics: comics,
                maxPage: maxPage
            }
        },

        // provide options for search
        optionList: [
            {
                label: "Sort By",
                type: "select",
                options: [
                    "any-Any",
                    "popular-Popular",
                    "recent-Recent",
                    "updated-Updated",
                    "rating-Rating",
                    "follows-Follows",
                ],
            },
            {
                label: "Content Rating",
                type: "select",
                options: [
                    "any-Any",
                    "safe-Safe",
                    "suggestive-Suggestive",
                    "erotica-Erotica",
                ]
            },
            {
                label: "Status",
                type: "select",
                options: [
                    "any-Any",
                    "ongoing-Ongoing",
                    "completed-Completed",
                    "hiatus-Hiatus",
                    "cancelled-Cancelled",
                ]
            },
        ],

        // enable tags suggestions
    }

    /// single comic related
    _comicApi = {
        getComic: async (id) => {
            let res = await Network.fetch(`https://api.mangadex.org/manga/${id}?includes[]=cover_art&includes[]=artist&includes[]=author`)
            if (!res.ok) {
                throw new Error("Network response was not ok")
            }
            let data = await res.json()
            return this.api.parseComic(data['data'])

        },
        getChapters: async (id) => {
            let res = await Network.fetch(`https://api.mangadex.org/manga/${id}/feed?limit=500&translatedLanguage[]=en&order[chapter]=asc`)
            if (!res.ok) {
                throw new Error("Network response was not ok")
            }
            let data = await res.json()
            let chapters = new Map()
            for (let chapter of data['data']) {
                let id = chapter['id']
                let chapterId = chapter['attributes']['chapter'] ?? "Oneshot"
                let title = chapter['attributes']['title']
                if (title) {
                    title = `${chapterId}: ${title}`
                } else {
                    title = chapterId
                }
                let volume = chapter['attributes']['volume']
                if (volume) {
                    volume = `Volume ${volume}`
                } else {
                    volume = "No Volume"
                }
                if (chapters.get(volume) === undefined) {
                    chapters.set(volume, new Map())
                }
                chapters.get(volume).set(id, title)
            }
            return chapters
        },
        getStats: async (id) => {
            let res = await Network.fetch(`https://api.mangadex.org/statistics/manga/${id}`)
            if (!res.ok) {
                throw new Error("Network response was not ok")
            }
            let data = await res.json()
            return {
                comments: data['statistics'][id]['comments']?.['repliesCount'] || 0,
                threadId: data['statistics'][id]['comments']?.['threadId'],
                follows: data['statistics'][id]['follows'] || 0,
                rating: data['statistics'][id]['rating']['average'] || 0,
            }
        },
        /**
         * load comic info
         * @param id {string}
         * @returns {Promise<ComicDetails>}
         */
        loadInfo: async (id) => {
            let res = await Promise.all([
                this._comicApi.getComic(id),
                this._comicApi.getChapters(id),
                this._comicApi.getStats(id)
            ])
            let comic = res[0]
            let chapters = res[1]
            let stats = res[2]

            return ({
                id: comic.id,
                title: comic.title,
                subtitle: comic.subtitle,
                cover: comic.cover,
                tags: {
                    "Tags": comic.tags,
                    "Status": comic.status,
                    "Authors": comic.authors,
                    "Artists": comic.artists,
                },
                description: comic.description,
                updateTime: comic.updateTime,
                uploadTime: comic.createTime,
                status: comic.status,
                chapters: chapters,
                stars: (stats.rating || 0) / 2,
                url: `https://mangadex.org/title/${comic.id}`,
            })
        },

        /**
         * rate a comic
         * @param id
         * @param rating {number} - [0-10] app use 5 stars, 1 rating = 0.5 stars,
         * @returns {Promise<any>} - return any value to indicate success
         */

        /**
         * load images of a chapter
         * @param comicId {string}
         * @param epId {string?}
         * @returns {Promise<{images: string[]}>}
         */
        loadEp: async (comicId, epId) => {
            if (!epId) {
                throw new Error("No chapter id provided")
            }
            let res = await Network.fetch(`https://api.mangadex.org/at-home/server/${epId}`)
            if (!res.ok) {
                throw new Error("Network response was not ok")
            }
            let data = await res.json()
            let images = []
            let image_quality = this.loadSetting('image_quality')
            if (image_quality == "Original"){
                for (let image of data['chapter']['data']) {
                    images.push(`https://uploads.mangadex.org/data/${data['chapter']['hash']}/${image}`)
                }          
            }else{
                for (let image of data['chapter']['dataSaver']) {
                    images.push(`https://uploads.mangadex.org/data-saver/${data['chapter']['hash']}/${image}`)
                }
            }
            return {
                images: images
            }
        },
        /**
         * [Optional] load comments
         *
         * Since app version 1.0.6, rich text is supported in comments.
         * Following html tags are supported: ['a', 'b', 'i', 'u', 's', 'br', 'span', 'img'].
         * span tag supports style attribute, but only support font-weight, font-style, text-decoration.
         * All images will be placed at the end of the comment.
         * Auto link detection is enabled, but only http/https links are supported.
         * @param comicId {string}
         * @param subId {string?} - ComicDetails.subId
         * @param page {number}
         * @param replyTo {string?} - commentId to reply, not null when reply to a comment
         * @returns {Promise<{comments: Comment[], maxPage: number?}>}
         */
        /**
         * [Optional] send a comment, return any value to indicate success
         * @param comicId {string}
         * @param subId {string?} - ComicDetails.subId
         * @param content {string}
         * @param replyTo {string?} - commentId to reply, not null when reply to a comment
         * @returns {Promise<any>}
         */
        /**
         * [Optional] Handle tag click event
         * @param namespace {string}
         * @param tag {string}
         * @returns {PageJumpTarget}
         */
        /**
         * [Optional] Handle links
         */
    }

    settings = {
        image_quality: {
            title: "Image Quality",
            type: "select",
            options: [
                {
                    value: 'Original',
                    text: 'Original'
                },
                {
                    value: 'Compressed',
                    text: 'Compressed'
                }
            ],
            default: "Original"
        }
    }

    // [Optional] translations for the strings in this config
    translation = {
        'zh_CN': {},
        'zh_TW': {},
        'en': {}
    }

    tags = {"Oneshot":"0234a31e-a729-4e28-9d6a-3f87c4966b9e","Thriller":"07251805-a27e-4d59-b488-f0bfbec15168","Award Winning":"0a39b5a1-b235-4886-a747-1d05d216532d","Reincarnation":"0bc90acb-ccc1-44ca-a34a-b9f3a73259d0","Sci-Fi":"256c8bd9-4904-4360-bf4f-508a76d67183","Time Travel":"292e862b-2d17-4062-90a2-0356caa4ae27","Genderswap":"2bd2e8d0-f146-434a-9b51-fc9ff2c5fe6a","Loli":"2d1f5d56-a1e5-4d0d-a961-2193588b08ec","Traditional Games":"31932a7e-5b8e-49a6-9f12-2afa39dc544c","Official Colored":"320831a8-4026-470b-94f6-8353740e6f04","Historical":"33771934-028e-4cb3-8744-691e866a923e","Monsters":"36fd93ea-e8b8-445e-b836-358f02b3d33d","Action":"391b0423-d847-456f-aff0-8b0cfc03066b","Demons":"39730448-9a5f-48a2-85b0-a70db87b1233","Psychological":"3b60b75c-a2d7-4860-ab56-05f391bb889c","Ghosts":"3bb26d85-09d5-4d2e-880c-c34b974339e9","Animals":"3de8c75d-8ee3-48ff-98ee-e20a65c86451","Long Strip":"3e2b8dae-350e-4ab8-a8ce-016e844b9f0d","Romance":"423e2eae-a7a2-4a8b-ac03-a8351462d71d","Ninja":"489dd859-9b61-4c37-af75-5b18e88daafc","Comedy":"4d32cc48-9f00-4cca-9b5a-a839f0764984","Mecha":"50880a9d-5440-4732-9afb-8f457127e836","Anthology":"51d83883-4103-437c-b4b1-731cb73d786c","Boys' Love":"5920b825-4181-4a17-beeb-9918b0ff7a30","Incest":"5bd0e105-4481-44ca-b6e7-7544da56b1a3","Crime":"5ca48985-9a9d-4bd8-be29-80dc0303db72","Survival":"5fff9cde-849c-4d78-aab0-0d52b2ee1d25","Zombies":"631ef465-9aba-4afb-b0fc-ea10efe274a8","Reverse Harem":"65761a2a-415e-47f3-bef2-a9dababba7a6","Sports":"69964a64-2f90-4d33-beeb-f3ed2875eb4c","Superhero":"7064a261-a137-4d3a-8848-2d385de3a99c","Martial Arts":"799c202e-7daa-44eb-9cf7-8a3c0441531e","Fan Colored":"7b2ce280-79ef-4c09-9b58-12b7c23a9b78","Samurai":"81183756-1453-4c81-aa9e-f6e1b63be016","Magical Girls":"81c836c9-914a-4eca-981a-560dad663e73","Mafia":"85daba54-a71c-4554-8a28-9901a8b0afad","Adventure":"87cc87cd-a395-47af-b27a-93258283bbc6","Self-Published":"891cf039-b895-47f0-9229-bef4c96eccd4","Virtual Reality":"8c86611e-fab7-4986-9dec-d1a2f44acdd5","Office Workers":"92d6d951-ca5e-429c-ac78-451071cbf064","Video Games":"9438db5a-7e2a-4ac0-b39e-e0d95a34b8a8","Post-Apocalyptic":"9467335a-1b83-4497-9231-765337a00b96","Sexual Violence":"97893a4c-12af-4dac-b6be-0dffb353568e","Crossdressing":"9ab53f92-3eed-4e9b-903a-917c86035ee3","Magic":"a1f53773-c69a-4ce5-8cab-fffcd90b1565","Girls' Love":"a3c67850-4684-404e-9b7f-c69850ee5da6","Harem":"aafb99c1-7f60-43fa-b75f-fc9502ce29c7","Military":"ac72833b-c4e9-4878-b9db-6c8a4a99444a","Wuxia":"acc803a4-c95a-4c22-86fc-eb6b582d82a2","Isekai":"ace04997-f6bd-436e-b261-779182193d3d","4-Koma":"b11fda93-8f1d-4bef-b2ed-8803d3733170","Doujinshi":"b13b2a48-c720-44a9-9c77-39c9979373fb","Philosophical":"b1e97889-25b4-4258-b28b-cd7f4d28ea9b","Gore":"b29d6a3d-1569-4e7a-8caf-7557bc92cd5d","Drama":"b9af3a63-f058-46de-a9a0-e0c13906197a","Medical":"c8cbe35b-1b2b-4a3f-9c37-db84c4514856","School Life":"caaa44eb-cd40-4177-b930-79d3ef2afe87","Horror":"cdad7e68-1419-41dd-bdce-27753074a640","Fantasy":"cdc58593-87dd-415e-bbc0-2ec27bf404cc","Villainess":"d14322ac-4d6f-4e9b-afd9-629d5f4d8a41","Vampires":"d7d1730f-6eb0-4ba6-9437-602cac38664c","Delinquents":"da2d50ca-3018-4cc0-ac7a-6b7d472a29ea","Monster Girls":"dd1f77c5-dea9-4e2b-97ae-224af09caf99","Shota":"ddefd648-5140-4e5f-ba18-4eca4071d19b","Police":"df33b754-73a3-4c54-80e6-1a74a8058539","Web Comic":"e197df38-d0e7-43b5-9b09-2842d0c326dd","Slice of Life":"e5301a23-ebd9-49dd-a0cb-2add944c7fe9","Aliens":"e64f6742-c834-471d-8d72-dd51fc02b835","Cooking":"ea2bc92d-1c26-4930-9b7c-d5c0dc1b6869","Supernatural":"eabc5b4c-6aff-42f3-b657-3e90cbd00b75","Mystery":"ee968100-4191-4968-93d3-f82d72be7e46","Adaptation":"f4122d1c-3b44-44d0-9936-ff7502c39ad3","Music":"f42fbf9e-188a-447b-9fdc-f19dc1e4d685","Full Color":"f5ba408b-0e7a-484d-8d49-4e9125ac96de","Tragedy":"f8f62932-27da-4fe4-8ee1-6779a8c5edba","Gyaru":"fad12b5e-68ba-460e-b933-9ae8318f5b65"}

    // [authors] and [artists] are dynamic map
    authors = {}
    artists = {}
}