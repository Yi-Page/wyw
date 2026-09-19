// description: Kavita 漫画源 — 搜索/分类/详情/阅读（由 venera kavita.js v1.0.0 移植，转换脚本自动生成）
// type: manga
//
// 由 venera 源自动转换：
// - 保留原站点的搜索/分类/详情/阅读核心逻辑（_searchApi/_categoryApi/_comicApi/_categoryData 内部对象）
// - 类开头的「wyw 适配层」将其包装为 wyw 插件接口（search/getDetail/openReader/分类四件套/浏览历史回放）
// - 已移除 wyw 无对应支撑的功能：账号登录/网络收藏/评论/点赞/评分/缩略图墙/外链识别/探索页(未映射部分)
// - Network 调用已改写为 wyw 原生风格：Network.get/post 直接返回 body 字符串，失败抛结构化异常（e.status/e.kind）

class kavita extends PluginSource {
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
                Promise.resolve(this.init()).catch((e) => console.warn('[kavita]', 'init 失败:', e))
            } catch (e) {
                console.warn('[kavita]', 'init 失败:', e)
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
            console.error('[kavita]', '搜索失败:', e)
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
        console.log('[kavita]', '详情:', title, '章节数:', isGallery ? 0 : chapters.length)

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
            plugin: 'kavita',
            method: 'loadChapterImages',
            args: [this._comicId, ep.id],
        }))
        Navigator.navigateToReader({
            comicId: this._comicId,
            comicTitle: this._comicTitle,
            chapters: chapters,
            sourceKey: 'kavita',
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
            console.error('[kavita]', '章节图片解析为空: comicId=' + comicId + ' epId=' + epId)
            throw '章节图片解析为空'
        }
        console.log('[kavita]', '图片数:', urls.length)
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

    name = "Kavita"

    key = "kavita"

    version = "1.0.0"



    settings = {
        base_url: {
            title: "服务器地址",
            type: "input",
            default: "https://demo.kavita.org",
            validator: "^(https?:\\/\\/).+$"
        },
        username: {
            title: "服务器账号",
            type: "input",
            default: ""
        },
        password: {
            title: "服务器密码",
            type: "input",
            default: ""
        },
    }

    get baseUrl() {
        let raw = this.loadSetting('base_url')
        if (typeof raw !== 'string' || !raw.trim()) {
            raw = this.settings.base_url.default
        }
        let value = raw.trim()
        if (!/^https?:\/\//i.test(value)) {
            value = `https://${value}`
        }
        return value.replace(/\/$/, '')
    }

    get headers() {
        const headers = { "Accept": "application/json" }
        const token = this.loadData('token')
        if (token) headers["Authorization"] = `Bearer ${token}`
        return headers
    }

    // —— wyw 适配：Kavita 接口需要 JWT + apiKey，用设置中的账号密码自动登录 ——
    async _ensureLogin() {
        let token = this.loadData('token')
        if (token) return token
        const username = this.loadSetting('username')
        const password = this.loadSetting('password')
        if (!username || !password) throw 'Kavita 需要登录：请在插件设置中填写服务器账号与密码'
        const loginHeaders = Object.assign({}, this.headers, { 'Content-Type': 'application/json' })
        const res = await Network.post(this.buildUrl('/api/Account/login'), loginHeaders, JSON.stringify({ username: username, password: password }))
                const body = JSON.parse(res)
        this.saveData('token', body.token)
        this.saveData('apiKey', body.apiKey)
        console.log('[kavita]', '自动登录成功')
        return body.token
    }

    async init() {
        try {
            if (!this.loadData('token')) {
                await this._ensureLogin()
            }
            await this.refreshReferenceData(false)
        } catch (e) {
            console.warn('[kavita]', 'init/登录失败(可忽略，首次请求时会重试):', e)
        }
    }

    FilterComparison = {
        Equals: 0,
        GreaterThan: 1,
        GreaterThanEqual: 2,
        LessThan: 3,
        LessThanEqual: 4,
        Contains: 5,
        MustContains: 6,
        Matches: 7,
        NotContains: 8,
        NotEqual: 9,
        BeginsWith: 10,
        EndsWith: 11,
        IsBefore: 12,
        IsAfter: 13,
        IsInLast: 14,
        IsNotInLast: 15,
        IsEmpty: 16
    }

    FilterField = {
        Summary: 0,
        SeriesName: 1,
        PublicationStatus: 2,
        Languages: 3,
        AgeRating: 4,
        UserRating: 5,
        Tags: 6,
        CollectionTags: 7,
        Translators: 8,
        Publisher: 10,
        Editor: 11,
        CoverArtist: 12,
        Letterer: 13,
        Colorist: 14,
        Inker: 15,
        Penciller: 16,
        Writers: 17,
        Genres: 18,
        Libraries: 19,
        ReadProgress: 20,
        Formats: 21,
        ReleaseYear: 22,
        ReadTime: 23,
        Path: 24,
        FilePath: 25,
        WantToRead: 26,
        ReadingDate: 27,
        AverageRating: 28,
        Imprint: 29,
        Team: 30,
        Location: 31,
        ReadLast: 32,
        FileSize: 33
    };

    // [Optional] account related

    // explore page list
    _explore = [
        {
            title: "Kavita",
            type: "singlePageWithMultiPart",
            load: async () => {
                await this.refreshReferenceData(false)
                const feeds = {}
                const data = {
                    id: 0,
                    name: "",
                    statements: [],
                    combination: 0,
                    sortOptions: {
                        sortField: 4,
                        isAscending: false
                    },
                    limitTo: 0
                }
                const latest = await this.fetchSeriesList(`/api/Series/v2`, { PageNumber: 0, PageSize: 12 }, data)
                if (latest.comics.length) feeds["最新上架"] = latest.comics
                return feeds
            },
        }
    ]

    // categories
    _categoryData = {
        /// title of the category page, used to identify the page, it should be unique
        title: "Kavita",
        parts: [
            {
                name: "常用",
                type: "dynamic",
                loader: () => (
                    [
                        {
                            label: "全部",
                            target: {
                                page: 'category',
                                attributes: {
                                    category: '全部',
                                    param: 'all',
                                },
                            },
                        }
                    ]
                )
            },
            {
                name: "书库",
                type: "dynamic",
                loader: () => {
                    const libraries = this.loadData('kavita_libraries')
                    if (!Array.isArray(libraries) || !libraries.length) {
                        return []
                    }
                    return libraries.map((library) => ({
                        label: library.name,
                        target: {
                            page: 'category',
                            attributes: {
                                category: library.name,
                                param: `library:${library.id}`,
                            },
                        },
                    }))
                }
            },
            {
                name: "作者",
                type: "dynamic",
                loader: () => {
                    const authors = this.loadData('kavita_authors')
                    if (!Array.isArray(authors) || !authors.length) {
                        return []
                    }
                    return authors.map((author) => ({
                        label: author.name,
                        target: {
                            page: 'category',
                            attributes: {
                                category: author.name,
                                param: `author:${author.id}`,
                            },
                        },
                    }))
                }
            },
            {
                name: "题材",
                type: "dynamic",
                loader: () => {
                    const genres = this.loadData('kavita_genres')
                    if (!Array.isArray(genres) || !genres.length) {
                        return []
                    }
                    return genres.map((genre) => ({
                        label: genre.title,
                        target: {
                            page: 'category',
                            attributes: {
                                category: genre.title,
                                param: `genre:${genre.id}`,
                            },
                        },
                    }))
                }
            },
        ],
        // enable ranking page
        enableRankingPage: false,
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
            await this.refreshReferenceData(false)
            const pageSize = 30
            const data = {
                statements: [],
                combination: 0,
                sortOptions: {
                    sortField: 4,
                    isAscending: false
                },
                limitTo: 0
            }

            /*
            * sortField : 排序枚举类型：
            * 1 按系列名称排序,2 创建时间,3 最后修改时间,4 最近添加章节时间,5 阅读时长,6 发布年份,7 阅读进度,8 平均评分,9 随机,10 用户评分
            */

            if (options && options.length) {
                const [sortField, isAscending] = options[0].split(',')
                data.sortOptions.sortField = parseInt(sortField)
                data.sortOptions.isAscending = isAscending === 'true'
            }

            const params = param.split(":")
            if (params[0] === 'library' && params[1]) {
                const libraryId = params[1]
                data.statements.push({
                    comparison: this.FilterComparison.Equals,
                    field: this.FilterField.Libraries,
                    value: libraryId
                })
            }

            if (params[0] === 'genre' && params[1]) {
                const genreId = params[1]
                data.statements.push({
                    comparison: this.FilterComparison.Equals,
                    field: this.FilterField.Genres,
                    value: genreId
                })
            }

            if (params[0] === 'author' && params[1]) {
                const authorId = params[1]
                data.statements.push({
                    comparison: this.FilterComparison.Equals,
                    field: this.FilterField.Writers,
                    value: authorId
                })
            }

            const allowedCategories = ['all', 'library', 'genre', 'author']
            if (allowedCategories.includes(params[0])) {
                const { comics, totalPages } = await this.fetchSeriesList(`/api/Series/v2`, { PageNumber: page, PageSize: pageSize }, data)
                return {
                    comics: comics,
                    maxPage: totalPages
                }
            }
        },
        optionList: [
            {
                label: "排序",
                options: [
                    "4,false-最近添加",
                    "1,true-名称[升序]",
                    "1,false-名称[降序]",
                    "2,false-创建时间[降序]",
                    "2,true-创建时间[升序]",
                    "3,false-修改时间[降序]",
                    "3,true-修改时间[升序]",
                ],
                notShowWhen: null,
                showWhen: null
            }
        ],
    }

    /// search related
    _searchApi = {
        /**
         * load search result
         * @param keyword {string}
         * @param options {(string | null)[]} - options from optionList
         * @param page {number}
         * @returns {Promise<{comics: Comic[], maxPage: number}>}
         */
        load: async (keyword, options, page) => {
            const pageSize = 30
            const data = {
                statements: [],
                combination: 0,
                sortOptions: {
                    sortField: 4,
                    isAscending: false
                },
                limitTo: 0
            }

            if (options && options.length) {
                const type = options[0]
                if (type === 'FilePath') {
                    data.statements.push({
                        comparison: this.FilterComparison.Matches,
                        field: this.FilterField.FilePath,
                        value: keyword
                    })
                } else if (type === 'SeriesName') {
                    data.statements.push({
                        comparison: this.FilterComparison.Matches,
                        field: this.FilterField.SeriesName,
                        value: keyword
                    })
                } else { // all
                    data.statements.push({
                        comparison: this.FilterComparison.Matches,
                        field: this.FilterField.SeriesName,
                        value: keyword
                    }, {
                        comparison: this.FilterComparison.Matches,
                        field: this.FilterField.Summary,
                        value: keyword
                    }, {
                        comparison: this.FilterComparison.Matches,
                        field: this.FilterField.FilePath,
                        value: keyword
                    })
                }
            }

            const { comics, totalPages } = await this.fetchSeriesList(`/api/Series/v2`, { PageNumber: page, PageSize: pageSize }, data)
            return {
                comics: comics,
                maxPage: totalPages
            }

            /*
            const data = await this.getJson('/api/Search/search', { queryString: keyword, includeChapterAndFiles: false })
            const series = Array.isArray(data?.series) ? data.series : []
            const token = this.loadData('token')
            const comics = series.map((item) => this.parseSeries(item, token)).filter(Boolean)
            return { comics: comics, maxPage: 1 }
            */
        },

        // provide options for search
        optionList: [
            {
                type: 'select',
                options: [
                    'All-全部',
                    'SeriesName-名称',
                    'FilePath-文件名',
                ],
                label: '搜索选项'
            }
        ],

        // [Optional] handle tag suggestion click
    }

    /// single comic related
    _comicApi = {
        /**
         * load comic info
         * @param id {string}
         * @returns {Promise<ComicDetails>}
         */
        loadInfo: async (id) => {
            const data = await this.getJson(`/api/Series/${id}`)
            const metadata = await this.getJson(`/api/Series/metadata`, { seriesId: id })
            const volume = await this.getJson(`/api/Series/volumes`, { seriesId: id })
            const chapters = volume
                .flatMap(item => item.chapters || [])
                .reduce((map, { id, titleName, files }) => {
                    let title = titleName
                    if (!title) {
                        title = files[0].filePath.split('/').pop()
                    }
                    map[id] = title;
                    return map;
                }, {});
            const authors = metadata.writers.map(item => item.name)
            const apiKey = this.loadData('apiKey')
            const tagSections = {}
            const isReadable = this.isReadable(data.format)
            console.log(data)
            if (authors.length) tagSections['作者'] = authors
            if (metadata.genres.length) tagSections['类型'] = metadata.genres.map(item => item.title)
            if (metadata.tags.length) tagSections['标签'] = metadata.tags.map(item => item.title)
            if (!isReadable) tagSections['提示'] = ['该系列包含的项目暂不支持阅读']
            const info = ({
                title: data.name,
                subtitle: authors.join(', '),
                cover: this.buildUrl(`/api/Image/series-cover`, { seriesId: id, apiKey: apiKey }),
                description: metadata.summary || '暂无简介',
                tags: tagSections,
                chapters,
                updateTime: data.lastChapterAdded,
                uploadTime: data.created,
                url: this.buildUrl(`/api/Series/${id}`)
            })
            return info
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
            const data = await this.getJson(`/api/Series/chapter`, { chapterId: epId })
            const page = data.pages
            const isReadable = this.isReadable(data.format)
            if (!isReadable) {
                throw '该项目暂不支持阅读'
            }
            const apiKey = this.loadData('apiKey')
            const extractPdf = data.format === 4
            return { images: Array.from({ length: page }, (_, i) => this.buildUrl(`/api/Reader/image`, { chapterId: epId, page: i, apiKey: apiKey, extractPdf })) }
        },

        /**
         * [Optional] Handle tag click event
         * @param namespace {string}
         * @param tag {string}
         * @returns {{action: string, keyword: string, param: string?}}
         */

        // enable tags translate
    }

    async refreshReferenceData(force) {
        const token = this.loadData('token')
        if (!token) {
            this.saveData('kavita_libraries', [])
            this.saveData('kavita_genres', [])
            this.saveData('kavita_authors', [])
            return
        }
        const now = Date.now()
        const last = this.loadData('kavita_meta_ts')
        if (!force && last && now - last < 5 * 60 * 1000) return
        try {
            const [libraries, genres, authors] = await Promise.all([
                this.getJson('/api/Library/libraries'),
                this.getJson('/api/Metadata/genres'),
                this.getJson('/api/metadata/people-by-role?role=3')
            ])
            const libraryList = Array.isArray(libraries) ? libraries.filter((library) => library && library.id) : []
            this.saveData('kavita_libraries', libraryList.map(item => ({ id: item.id, name: item.name })))
            this.saveData('kavita_genres', Array.isArray(genres) ? genres : [])
            this.saveData('kavita_authors', Array.isArray(authors) ? authors.map(item => ({ id: item.id, name: item.name })) : [])
            this.saveData('kavita_meta_ts', now)
        } catch (error) {
            this.saveData('kavita_libraries', [])
            this.saveData('kavita_genres', [])
            this.saveData('kavita_authors', [])
            if (String(error) === 'Login expired') throw error
        }
    }

    async fetchSeriesList(path, query, data) {
        const { content, page } = await this.postJson(path, query, data)
        const series = Array.isArray(content) ? content : []
        const apiKey = this.loadData('apiKey')
        const comics = series.map((item) => this.parseSeries(item, apiKey)).filter(Boolean)
        return {
            comics,
            totalPages: page.totalPages
        }
    }

    parseSeries(series, apiKey) {
        if (!series) return null
        const id = series.id || series.seriesId
        const title = series.name
        return ({
            id: `${id}`,
            title,
            cover: this.buildUrl(`/api/Image/series-cover`, { seriesId: id, apiKey: apiKey }),
        })
    }

    isReadable(format) {
        const readableFormats = [0, 1, 4] // 0 图片, 1 档案, 2 Epub, 4 PDF 
        return readableFormats.includes(format)
    }

    async getJson(path, query) {
        const res = await Network.get(this.buildUrl(path, query), this.headers)
        this.ensureOk(res)
        const text = res
        if (!text) return null
        return JSON.parse(text)
    }

    async postJson(path, query, data) {
        const res = await Network.post(this.buildUrl(path, query), this.headers, data)
        this.ensureOk(res)
        const text = res
        if (!text) return null
        return {
            content: JSON.parse(text),
            page: JSON.parse(res.headers.pagination)
        }
    }

    ensureOk(res) {
        if (!res) throw '请求失败'
                if (res.status < 200 || res.status >= 300) throw `请求失败: ${res.status}`
    }

    buildUrl(path, query) {
        let url = path
        if (!/^https?:\/\//i.test(path)) {
            url = `${this.baseUrl}${path.startsWith('/') ? '' : '/'}${path}`
        }
        const qs = this.buildQuery(query)
        return qs ? `${url}?${qs}` : url
    }

    buildQuery(query) {
        if (!query) return ''
        const parts = []
        for (const key of Object.keys(query)) {
            const value = query[key]
            if (value === undefined || value === null) continue
            if (Array.isArray(value)) {
                for (const item of value) {
                    if (item === undefined || item === null) continue
                    parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(String(item))}`)
                }
            } else {
                parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(String(value))}`)
            }
        }
        return parts.join('&')
    }

    formatDate(value) {
        if (!value) return null
        try {
            const date = new Date(value)
            if (Number.isNaN(date.getTime())) return null
            return date.toISOString().split('T')[0]
        } catch (_) {
            return null
        }
    }
}
