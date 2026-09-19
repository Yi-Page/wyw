// description: Picacg 漫画源 — 搜索/分类/详情/阅读（由 venera picacg.js v1.0.6 移植，转换脚本自动生成）
// type: manga
//
// 由 venera 源自动转换：
// - 保留原站点的搜索/分类/详情/阅读核心逻辑（_searchApi/_categoryApi/_comicApi/_categoryData 内部对象）
// - 类开头的「wyw 适配层」将其包装为 wyw 插件接口（search/getDetail/openReader/分类四件套/浏览历史回放）
// - 已移除 wyw 无对应支撑的功能：账号登录/网络收藏/评论/点赞/评分/缩略图墙/外链识别/探索页(未映射部分)
// - Network 调用已改写为 wyw 原生风格：Network.get/post 直接返回 body 字符串，失败抛结构化异常（e.status/e.kind）

class picacg extends PluginSource {
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
                Promise.resolve(this.init()).catch((e) => console.warn('[picacg]', 'init 失败:', e))
            } catch (e) {
                console.warn('[picacg]', 'init 失败:', e)
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
            console.error('[picacg]', '搜索失败:', e)
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
        console.log('[picacg]', '详情:', title, '章节数:', isGallery ? 0 : chapters.length)

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
            plugin: 'picacg',
            method: 'loadChapterImages',
            args: [this._comicId, ep.id],
        }))
        Navigator.navigateToReader({
            comicId: this._comicId,
            comicTitle: this._comicTitle,
            chapters: chapters,
            sourceKey: 'picacg',
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
            console.error('[picacg]', '章节图片解析为空: comicId=' + comicId + ' epId=' + epId)
            throw '章节图片解析为空'
        }
        console.log('[picacg]', '图片数:', urls.length)
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

    name = "Picacg"

    key = "picacg"

    version = "1.0.6"



    static defaultApiUrl = "https://picaapi.picacomic.com"

    apiKey = "C69BAF41DA5ABD1FFEDC6D2FEA56B";

    createSignature(path, nonce, time, method) {
        let data = path + time + nonce + method + this.apiKey
        let key = '~d}$Q7$eIni=V)9\\RK/P.RM4;9[7|@/CA}b~OW!3?EV`:<>M7pddUBL5n|0/*Cn'
        let s = Convert.encodeUtf8(key)
        let h = Convert.encodeUtf8(data.toLowerCase())
        return Convert.hmacString(s, h, 'sha256')
    }

    buildHeaders(method, path, token) {
        let uuid = createUuid()
        let nonce = uuid.replace(/-/g, '')
        let time = (new Date().getTime() / 1000).toFixed(0)
        let signature = this.createSignature(path, nonce, time, method.toUpperCase())
        return {
            "api-key": "C69BAF41DA5ABD1FFEDC6D2FEA56B",
            "accept": "application/vnd.picacomic.com.v1+json",
            "app-channel": this.loadSetting('appChannel') || "3",
            "authorization": token ?? "",
            "time": time,
            "nonce": nonce,
            "app-version": "2.2.1.3.3.4",
            "app-uuid": "defaultUuid",
            "image-quality": this.loadSetting('imageQuality') || "original",
            "app-platform": "android",
            "app-build-version": "45",
            "Content-Type": "application/json; charset=UTF-8",
            "user-agent": "okhttp/3.8.1",
            "version": "v1.5.4",
            "signature": signature,
            "http_client": "dart:io",
        }
    }


    parseComic(comic) {
        let tags = []
        tags.push(...(comic.tags ?? []))
        tags.push(...(comic.categories ?? []))
        return ({
            id: comic._id,
            title: comic.title,
            subTitle: comic.author,
            cover: comic.thumb.fileServer + '/static/' + comic.thumb.path,
            tags: tags,
            description: `${comic.totalLikes ?? comic.likesCount} likes`,
            maxPage: comic.pagesCount,
        })
    }

    _explore = [
        {
            title: "Picacg Random",
            type: "multiPageComicList",
            load: async (page) => {
                if (!this.isLogged) {
                    throw 'Not logged in'
                }
                let res
try {
    res = await Network.get(
                    `${this.loadSetting('base_url')}/comics/random`,
                    this.buildHeaders('GET', 'comics/random', this.loadData('token'))
                )
} catch (e) {
    if (e && e.status === 401) {
        await this._ensureToken()
        res = await Network.get(
                    `${this.loadSetting('base_url')}/comics/random`,
                    this.buildHeaders('GET', 'comics/random', this.loadData('token'))
                )
    } else {
        throw e
    }
}
                
                let data = JSON.parse(res)
                let comics = []
                data.data.comics.forEach(c => {
                    comics.push(this.parseComic(c))
                })
                return {
                    comics: comics
                }
            }
        },
        {
            title: "Picacg Latest",
            type: "multiPageComicList",
            load: async (page) => {
                if (!this.isLogged) {
                    throw 'Not logged in'
                }
                let res
try {
    res = await Network.get(
                    `${this.loadSetting('base_url')}/comics?page=${page}&s=dd`,
                    this.buildHeaders('GET', `comics?page=${page}&s=dd`, this.loadData('token'))
                )
} catch (e) {
    if (e && e.status === 401) {
        await this._ensureToken()
        res = await Network.get(
                    `${this.loadSetting('base_url')}/comics?page=${page}&s=dd`,
                    this.buildHeaders('GET', `comics?page=${page}&s=dd`, this.loadData('token'))
                )
    } else {
        throw e
    }
}
                
                let data = JSON.parse(res)
                let comics = []
                data.data.comics.docs.forEach(c => {
                    comics.push(this.parseComic(c))
                })
                return {
                    comics: comics
                }
            }
        },
        {
            title: "Picacg H24",
            type: "multiPageComicList",
            load: async (page) => {
                if (!this.isLogged) {
                    throw 'Not logged in'
                }
                let res
try {
    res = await Network.get(
                    `${this.loadSetting('base_url')}/comics/leaderboard?tt=H24&ct=VC`,
                    this.buildHeaders('GET', 'comics/leaderboard?tt=H24&ct=VC', this.loadData('token'))
                )
} catch (e) {
    if (e && e.status === 401) {
        await this._ensureToken()
        res = await Network.get(
                    `${this.loadSetting('base_url')}/comics/leaderboard?tt=H24&ct=VC`,
                    this.buildHeaders('GET', 'comics/leaderboard?tt=H24&ct=VC', this.loadData('token'))
                )
    } else {
        throw e
    }
}
                
                let data = JSON.parse(res)
                let comics = []
                data.data.comics.forEach(c => {
                    comics.push(this.parseComic(c))
                })
                return {
                    comics: comics
                }
            }
        },
        {
            title: "Picacg D7",
            type: "multiPageComicList",
            load: async (page) => {
                if (!this.isLogged) {
                    throw 'Not logged in'
                }
                let res
try {
    res = await Network.get(
                    `${this.loadSetting('base_url')}/comics/leaderboard?tt=D7&ct=VC`,
                    this.buildHeaders('GET', 'comics/leaderboard?tt=D7&ct=VC', this.loadData('token'))
                )
} catch (e) {
    if (e && e.status === 401) {
        await this._ensureToken()
        res = await Network.get(
                    `${this.loadSetting('base_url')}/comics/leaderboard?tt=D7&ct=VC`,
                    this.buildHeaders('GET', 'comics/leaderboard?tt=D7&ct=VC', this.loadData('token'))
                )
    } else {
        throw e
    }
}
                
                let data = JSON.parse(res)
                let comics = []
                data.data.comics.forEach(c => {
                    comics.push(this.parseComic(c))
                })
                return {
                    comics: comics
                }
            }
        },
        {
            title: "Picacg D30",
            type: "multiPageComicList",
            load: async (page) => {
                if (!this.isLogged) {
                    throw 'Not logged in'
                }
                let res
try {
    res = await Network.get(
                    `${this.loadSetting('base_url')}/comics/leaderboard?tt=D30&ct=VC`,
                    this.buildHeaders('GET', 'comics/leaderboard?tt=D30&ct=VC', this.loadData('token'))
                )
} catch (e) {
    if (e && e.status === 401) {
        await this._ensureToken()
        res = await Network.get(
                    `${this.loadSetting('base_url')}/comics/leaderboard?tt=D30&ct=VC`,
                    this.buildHeaders('GET', 'comics/leaderboard?tt=D30&ct=VC', this.loadData('token'))
                )
    } else {
        throw e
    }
}
                
                let data = JSON.parse(res)
                let comics = []
                data.data.comics.forEach(c => {
                    comics.push(this.parseComic(c))
                })
                return {
                    comics: comics
                }
            }
        }
    ]

    /// 分类页面
    /// 一个漫画源只能有一个分类页面, 也可以没有, 设置为null禁用分类页面
    _categoryData = {
        /// 标题, 同时为标识符, 不能与其他漫画源的分类页面重复
        title: "Picacg",
        parts: [
            {
                name: "主题",
                type: "fixed",
                categories: [
                    "大家都在看",
                    "大濕推薦",
                    "那年今天",
                    "官方都在看",
                    "嗶咔漢化",
                    "全彩",
                    "長篇",
                    "同人",
                    "短篇",
                    "圓神領域",
                    "碧藍幻想",
                    "CG雜圖",
                    "英語 ENG",
                    "生肉",
                    "純愛",
                    "百合花園",
                    "耽美花園",
                    "偽娘哲學",
                    "後宮閃光",
                    "扶他樂園",
                    "單行本",
                    "姐姐系",
                    "妹妹系",
                    "SM",
                    "性轉換",
                    "足の恋",
                    "人妻",
                    "NTR",
                    "強暴",
                    "非人類",
                    "艦隊收藏",
                    "Love Live",
                    "SAO 刀劍神域",
                    "Fate",
                    "東方",
                    "WEBTOON",
                    "禁書目錄",
                    "歐美",
                    "Cosplay",
                    "重口地帶"
                ],
                itemType: "category",
            }
        ],
        enableRankingPage: true,
    }

    /// 分类漫画页面, 即点击分类标签后进入的页面
    _categoryApi = {
        load: async (category, param, options, page) => {
            let type = param ?? 'c'
            const d = (v, def) => (v === undefined || v === null || v === "" ? def : v)
            options = Array.isArray(options) ? options : []
            let res
try {
    res = await Network.get(
                `${this.loadSetting('base_url')}/comics?page=${page}&${type}=${encodeURIComponent(category)}&s=${d(options[0], 'dd')}`,
                this.buildHeaders('GET', `comics?page=${page}&${type}=${encodeURIComponent(category)}&s=${d(options[0], 'dd')}`, this.loadData('token'))
            )
} catch (e) {
    if (e && e.status === 401) {
        await this._ensureToken()
        res = await Network.get(
                `${this.loadSetting('base_url')}/comics?page=${page}&${type}=${encodeURIComponent(category)}&s=${d(options[0], 'dd')}`,
                this.buildHeaders('GET', `comics?page=${page}&${type}=${encodeURIComponent(category)}&s=${d(options[0], 'dd')}`, this.loadData('token'))
            )
    } else {
        throw e
    }
}
            
            let data = JSON.parse(res)
            let comics = []
            data.data.comics.docs.forEach(c => {
                comics.push(this.parseComic(c))
            })
            return {
                comics: comics,
                maxPage: data.data.comics.pages
            }
        },
        // 提供选项
        optionList: [
            {
                options: [
                    "dd-New to old",
                    "da-Old to new",
                    "ld-Most likes",
                    "vd-Most nominated",
                ],
            }
        ],
        ranking: {
            options: [
                "H24-Day",
                "D7-Week",
                "D30-Month",
            ],
            load: async (option, page) => {
                let res
try {
    res = await Network.get(
                    `${this.loadSetting('base_url')}/comics/leaderboard?tt=${option}&ct=VC`,
                    this.buildHeaders('GET', `comics/leaderboard?tt=${option}&ct=VC`, this.loadData('token'))
                )
} catch (e) {
    if (e && e.status === 401) {
        await this._ensureToken()
        res = await Network.get(
                    `${this.loadSetting('base_url')}/comics/leaderboard?tt=${option}&ct=VC`,
                    this.buildHeaders('GET', `comics/leaderboard?tt=${option}&ct=VC`, this.loadData('token'))
                )
    } else {
        throw e
    }
}
                
                let data = JSON.parse(res)
                let comics = []
                data.data.comics.forEach(c => {
                    comics.push(this.parseComic(c))
                })
                return {
                    comics: comics,
                    maxPage: 1
                }
            }
        }
    }

    /// 搜索
    _searchApi = {
        load: async (keyword, options, page) => {
            let res
try {
    res = await Network.post(
                `${this.loadSetting('base_url')}/comics/advanced-search?page=${page}`,
                this.buildHeaders('POST', `comics/advanced-search?page=${page}`, this.loadData('token')),
                JSON.stringify({
                    keyword: keyword,
                    sort: options[0],
                })
            )
} catch (e) {
    if (e && e.status === 401) {
        await this._ensureToken()
        res = await Network.post(
                `${this.loadSetting('base_url')}/comics/advanced-search?page=${page}`,
                this.buildHeaders('POST', `comics/advanced-search?page=${page}`, this.loadData('token')),
                JSON.stringify({
                    keyword: keyword,
                    sort: options[0],
                })
            )
    } else {
        throw e
    }
}
            
            let data = JSON.parse(res)
            let comics = []
            data.data.comics.docs.forEach(c => {
                comics.push(this.parseComic(c))
            })
            return {
                comics: comics,
                maxPage: data.data.comics.pages
            }
        },
        optionList: [
            {
                options: [
                    "dd-New to old",
                    "da-Old to new",
                    "ld-Most likes",
                    "vd-Most nominated",
                ],
                label: "Sort"
            }
        ]
    }

    /// 收藏

    /// 单个漫画相关
    _comicApi = {
        // 加载漫画信息
        loadInfo: async (id) => {
            let infoLoader = async () => {
                let res = await Network.get(
                    `${this.loadSetting('base_url')}/comics/${id}`,
                    this.buildHeaders('GET', `comics/${id}`, this.loadData('token'))
                )
                
                let data = JSON.parse(res)
                return data.data.comic
            }
            let epsLoader = async () => {
                let eps = new Map();
                let i = 1;
                let j = 1;
                let allEps = [];
                while (true) {
                    let res = await Network.get(
                        `${this.loadSetting('base_url')}/comics/${id}/eps?page=${i}`,
                        this.buildHeaders('GET', `comics/${id}/eps?page=${i}`, this.loadData('token'))
                    );
                    
                    let data = JSON.parse(res);
                    allEps.push(...data.data.eps.docs);
                    if (data.data.eps.pages === i) {
                        break;
                    }
                    i++;
                }
                allEps.sort((a, b) => a.order - b.order);
                allEps.forEach(e => {
                    eps.set(j.toString(), e.title);
                    j++;
                });
                return eps;
            }
            let relatedLoader = async () => {
                let res = await Network.get(
                    `${this.loadSetting('base_url')}/comics/${id}/recommendation`,
                    this.buildHeaders('GET', `comics/${id}/recommendation`, this.loadData('token'))
                )
                
                let data = JSON.parse(res)
                let comics = []
                data.data.comics.forEach(c => {
                    comics.push(this.parseComic(c))
                })
                return comics
            }
            let info, eps, related
            try {
                [info, eps, related] = await Promise.all([infoLoader(), epsLoader(), relatedLoader()])
            }
            catch (e) {
                if (e === 'Invalid status code: 401') {
                    await this._ensureToken();
                    [info, eps, related] = await Promise.all([infoLoader(), epsLoader(), relatedLoader()]);
                }
                throw e
            }
            let tags = {}
            if(info.author) {
                tags['Author'] = [info.author];
            }
            if(info.chineseTeam) {
                tags['Chinese Team'] = [info.chineseTeam];
            }
            let updateTime = new Date(info.updated_at)
            let formattedDate = updateTime.getFullYear() + '-' + (updateTime.getMonth() + 1) + '-' + updateTime.getDate()
            return ({
                title: info.title,
                cover: info.thumb.fileServer + '/static/' + info.thumb.path,
                description: info.description,
                tags: {
                    ...tags,
                    'Categories': info.categories,
                    'Tags': info.tags,
                },
                chapters: eps,
                isFavorite: info.isFavourite ?? false,
                isLiked: info.isLiked ?? false,
                recommend: related,
                commentCount: info.commentsCount,
                likesCount: info.likesCount,
                uploader: info._creator.name,
                updateTime: formattedDate,
                maxPage: info.pagesCount,
            })
        },
        // 获取章节图片
        loadEp: async (comicId, epId) => {
            let images = []
            let i = 1
            while(true) {
                let res = await Network.get(
                    `${this.loadSetting('base_url')}/comics/${comicId}/order/${epId}/pages?page=${i}`,
                    this.buildHeaders('GET', `comics/${comicId}/order/${epId}/pages?page=${i}`, this.loadData('token'))
                )
                
                let data = JSON.parse(res)
                data.data.pages.docs.forEach(p => {
                    images.push(p.media.fileServer + '/static/' + p.media.path)
                })
                if(data.data.pages.pages === i) {
                    break
                }
                i++
            }
            return {
                images: images
            }
        },
        onImageLoad: async (url, comicId, epId) => {
            return {
                url: url,
                headers: {
                    "user-agent": "okhttp/3.8.1",
                }
            }
        },
        // 加载评论
        // 发送评论, 返回任意值表示成功
    }

    // —— wyw 适配：哔咔接口需要鉴权 token，这里用设置中的账号密码自动登录（401 时触发重试） ——
    async _ensureToken() {
        let token = this.loadData('token')
        if (token) return token
        const email = this.loadSetting('email')
        const password = this.loadSetting('password')
        if (!email || !password) throw '哔咔需要登录：请在插件设置中填写账号(邮箱)与密码'
        const body = JSON.stringify({ email: email, password: password })
        const res = await Network.post(
            `${this.loadSetting('base_url')}/auth/sign-in`,
            this.buildHeaders('POST', 'auth/sign-in'),
            body)
        if (res.status === 200) {
            const json = JSON.parse(res)
            if (!json.data?.token) throw '哔咔登录失败（未返回 token）: ' + res
            this.saveData('token', json.data.token)
            console.log('[picacg]', '自动登录成功')
            return json.data.token
        }
        throw '哔咔登录失败: HTTP ' + res.status
    }

    settings = {
        base_url: {
            title: "API地址(地址末尾不要添加斜杠)",
            type: "input",
            validator: null,
            default: picacg.defaultApiUrl,
        },
        email: {
            title: "哔咔账号(邮箱)",
            type: "input",
            default: "",
        },
        password: {
            title: "哔咔密码",
            type: "input",
            default: "",
        },
        'imageQuality': {
            type: 'select',
            title: 'Image quality',
            options: [
                {
                    value: 'original',
                },
                {
                    value: 'medium'
                },
                {
                    value: 'low'
                }
            ],
            default: 'original',
        },
        'appChannel': {
            type: 'select',
            title: 'App channel',
            options: [
                {
                    value: '1',
                },
                {
                    value: '2'
                },
                {
                    value: '3'
                }
            ],
            default: '3',
        },
        'favoriteSort': {
            type: 'select',
            title: 'Favorite sort',
            options: [
                {
                    value: 'dd',
                    text: 'New to old'
                },
                {
                    value: 'da',
                    text: 'Old to new'
                },
            ],
            default: 'dd',
        }
    }

    translation = {
        'zh_CN': {
            'Picacg Random': "哔咔随机",
            'Picacg Latest': "哔咔最新",
            'Picacg H24': "哔咔日榜",
            'Picacg D7': "哔咔周榜",
            'Picacg D30': "哔咔月榜",
            'New to old': "新到旧",
            'Old to new': "旧到新",
            'Most likes': "最多喜欢",
            'Most nominated': "最多指名",
            'Day': "日",
            'Week': "周",
            'Month': "月",
            'Author': "作者",
            'Chinese Team': "汉化组",
            'Categories': "分类",
            'Tags': "标签",
            'Image quality': "图片质量",
            'App channel': "分流",
            'Favorite sort': "收藏排序",
            'Sort': "排序",
        },
        'zh_TW': {
            'Picacg Random': "哔咔隨機",
            'Picacg Latest': "哔咔最新",
            'Picacg H24': "哔咔日榜",
            'Picacg D7': "哔咔周榜",
            'Picacg D30': "哔咔月榜",
            'New to old': "新到舊",
            'Old to new': "舊到新",
            'Most likes': "最多喜歡",
            'Most nominated': "最多指名",
            'Day': "日",
            'Week': "周",
            'Month': "月",
            'Author': "作者",
            'Chinese Team': "漢化組",
            'Categories': "分類",
            'Tags': "標籤",
            'Image quality': "圖片質量",
            'App channel': "分流",
            'Favorite sort': "收藏排序",
            'Sort': "排序",
        },
    }
}
