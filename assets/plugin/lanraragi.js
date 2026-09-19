// description: Lanraragi 漫画源 — 搜索/分类/详情/阅读（由 venera lanraragi.js v1.1.0 移植，转换脚本自动生成）
// type: manga
//
// 由 venera 源自动转换：
// - 保留原站点的搜索/分类/详情/阅读核心逻辑（_searchApi/_categoryApi/_comicApi/_categoryData 内部对象）
// - 类开头的「wyw 适配层」将其包装为 wyw 插件接口（search/getDetail/openReader/分类四件套/浏览历史回放）
// - 已移除 wyw 无对应支撑的功能：账号登录/网络收藏/评论/点赞/评分/缩略图墙/外链识别/探索页(未映射部分)
// - Network 调用已改写为 wyw 原生风格：Network.get/post 直接返回 body 字符串，失败抛结构化异常（e.status/e.kind）

class lanraragi extends PluginSource {
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
                Promise.resolve(this.init()).catch((e) => console.warn('[lanraragi]', 'init 失败:', e))
            } catch (e) {
                console.warn('[lanraragi]', 'init 失败:', e)
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
            console.error('[lanraragi]', '搜索失败:', e)
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
        console.log('[lanraragi]', '详情:', title, '章节数:', isGallery ? 0 : chapters.length)

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
            plugin: 'lanraragi',
            method: 'loadChapterImages',
            args: [this._comicId, ep.id],
        }))
        Navigator.navigateToReader({
            comicId: this._comicId,
            comicTitle: this._comicTitle,
            chapters: chapters,
            sourceKey: 'lanraragi',
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
            console.error('[lanraragi]', '章节图片解析为空: comicId=' + comicId + ' epId=' + epId)
            throw '章节图片解析为空'
        }
        console.log('[lanraragi]', '图片数:', urls.length)
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

    name = "Lanraragi"
    key = "lanraragi"
    version = "1.2.0"

    settings = {
        api: { title: "API", type: "input", default: "http://lrr.tvc-16.science" },
        apiKey: { title: "APIKEY", type: "input", default: "" }
    }

    get baseUrl() { 
        const api = this.loadSetting('api') || this.settings.api.default

        return api.replace(/\/$/, '')
    }

    get headers() {
        const raw = this.loadSetting('apiKey')
        const headers = {}
        if (raw) {
            headers.Authorization = "Bearer " + Convert.encodeBase64(Convert.encodeUtf8(raw))
        }
        return headers
    }

    // 临时的折中手段，app 尚不支持 api token 形式的授权判断（isLogged）

    _getStart(key, page) {
        if (page === 1) {
            this.saveData(key, 0)
            return 0
        }
        return Number(this.loadData(key) || 0)
    }

    _updateStart(key, returned) {
        const cur = Number(this.loadData(key) || 0)
        this.saveData(key, cur + (returned || 0))
    }

    // Parse various rating string/number formats and convert to 0-5 scale with 0.5 step
    _toStarsFromValue(v) {
        if (v === null || v === undefined) return null
        const s = String(v).trim()
        if (s.length === 0) return null

        // Support emoji star formats like '⭐⭐⭐' or '★★★' used by some Lanraragi setups
        if (s.includes('⭐') || s.includes('★')) {
            const count = (s.match(/⭐/g) || s.match(/★/g) || []).length
            if (count >= 0) return Math.max(0, Math.min(5, count))
        }

        // fraction like 7/10 or 3/5
        if (s.includes('/')) {
            const parts = s.split('/')
            const num = parseFloat(parts[0])
            const den = parseFloat(parts[1]) || 10
            if (!isNaN(num) && !isNaN(den) && den > 0) {
                const scaled = (num / den) * 5
                return Math.round(scaled * 2) / 2
            }
        }

        // percentage like 78%
        if (s.includes('%')) {
            const num = parseFloat(s.replace('%', ''))
            if (!isNaN(num)) {
                const scaled = (num / 100) * 5
                return Math.round(scaled * 2) / 2
            }
        }

        // plain number
        const n = parseFloat(s)
        if (isNaN(n)) return null
        // if number > 5 assume 10-point scale
        if (n > 5) {
            const scaled = n / 2
            return Math.round(scaled * 2) / 2
        }
        // else already 5-point or smaller
        return Math.round(n * 2) / 2
    }

    // Extract rating value from tags (tags can be comma-separated string or array)
    _extractRatingFromTags(tags) {
        if (!tags) return null
        let arr = []
        if (Array.isArray(tags)) {
            arr = tags
        } else {
            arr = String(tags).split(',').map(t => t.trim()).filter(Boolean)
        }
        for (const t of arr) {
            if (typeof t !== 'string') continue
            const low = t.toLowerCase()
            if (low.startsWith('rating:')) {
                const raw = t.slice('rating:'.length).trim()
                // emoji stars like '⭐⭐⭐' or '★★★'
                if (raw.includes('⭐') || raw.includes('★')) {
                    const count = (raw.match(/⭐/g) || raw.match(/★/g) || []).length
                    return String(count)
                }
                return raw
            }
        }
        return null
    }

    // Convert tags input (string comma-separated or array) to array of trimmed strings
    _tagsToArray(tags) {
        if (!tags) return []
        if (Array.isArray(tags)) return tags.map(t => String(t).trim()).filter(Boolean)
        return String(tags).split(',').map(t => t.trim()).filter(Boolean)
    }

    // Clean tags for list display: remove rating:, date_added:, URL-like and source: entries
    _cleanListTags(tags) {
        const arr = this._tagsToArray(tags)
        const out = []
        for (let t of arr) {
            if (typeof t !== 'string') continue
            const lt = t.toLowerCase()
            if (lt.startsWith('rating:')) continue
            if (lt.startsWith('date_added:')) continue
            if (t.includes('://')) continue
            if (lt.startsWith('source:')) continue
            out.push(t)
        }
        return out
    }

    async init() {
        try {
            const url = `${this.baseUrl}/api/categories`
            const res = await Network.get(url, this.headers)
            if (res.status !== 200) { this.saveData('categories', []); return }
            let data = []
            try { data = JSON.parse(res) } catch (_) { data = [] }
            if (!Array.isArray(data)) data = []
            // Save full categories list
            this.saveData('categories', data)
            this.saveData('categories_ts', Date.now())

            if (Array.isArray(data)) {
                const favorites = Array.isArray(data)
                    ? data.filter(c => c && (c.search === "" || c.search === null || typeof c.search === 'undefined'))
                    : []
                this.saveData('favorites', favorites)
                this.saveData('favorites_ts', Date.now())
            } else {
                this.saveData('favorites', [])
            }
        } catch (_) { this.saveData('categories', []) }
    }

    _explore = [
        { title: "Lanraragi", type: "multiPageComicList", load: async (page = 1) => {
            const base = (this.baseUrl || '').replace(/\/$/, '')
            const exploreKey = 'explore_start'
            let start = this._getStart(exploreKey, page)
            const qp = []
            const add = (k, v) => qp.push(`${encodeURIComponent(k)}=${encodeURIComponent(String(v))}`)
            add('sortby', 'date_added')
            add('order', 'desc')
            add('start', String(start))

            const url = `${base}/api/search?${qp.join('&')}`
            const res = await Network.get(url, this.headers)
                        const data = JSON.parse(res)
            const list = Array.isArray(data.data) ? data.data : []

            const parseComic = (item) => {
                let b = base
                if (!/^https?:\/\//.test(b)) b = 'http://' + b
                const cover = `${b}/api/archives/${item.arcid}/thumbnail`
                const tagRating = this._extractRatingFromTags(item.tags)
                const stars = this._toStarsFromValue(tagRating ?? null)
                return ({ id: item.arcid, title: item.title || item.filename || item.arcid, subTitle: '', cover, tags: this._cleanListTags(item.tags), description: '页数: ' + (item.pagecount || '') + ' | 新: ' + (item.isnew || '') + ' | 扩展: ' + (item.extension || ''), stars })
            }

            const returned = list.length
            this._updateStart(exploreKey, returned)

            const total = (typeof data.recordsFiltered === 'number' && data.recordsFiltered >= 0)
                ? data.recordsFiltered
                : (start + returned)
            const serverPage = returned || 1
            const maxPage = Math.max(1, Math.ceil(total / serverPage))

            return { comics: list.map(parseComic), maxPage }
        }}
    ]

    _categoryData = {
        title: "Lanraragi",
        parts: [ { name: "ALL", type: "dynamic", loader: () => {
            const data = this.loadData('categories')
            if (!Array.isArray(data) || data.length === 0) throw 'Please check your API settings or categories.'
            const items = []
            for (const cat of data) {
                if (!cat) continue
                const id = cat.id ?? cat._id ?? cat.name
                const label = cat.name ?? String(id)
                try { items.push({ label, target: new PageJumpTarget({ page: 'category', attributes: { category: id, param: null } }) }) }
                catch (_) { items.push({ label, target: { page: 'category', attributes: { category: id, param: null } } }) }
            }
            return items
        } } ],
        enableRankingPage: false,
    }

    _categoryApi = {
        load: async (category, param, options, page) => {
            // Use /search endpoint filtered by category tag value
            const base = (this.baseUrl || '').replace(/\/$/, '')
            const key = 'category_start_' + String(category || '')
            let start = this._getStart(key, page)

            const qp = []
            const add = (k, v) => qp.push(`${encodeURIComponent(k)}=${encodeURIComponent(String(v))}`)
            add('category', category || '')
            add('sortby', 'date_added')
            add('order', 'desc')
            add('start', String(start))

            const url = `${base}/api/search?${qp.join('&')}`
            const res = await Network.get(url, this.headers)
                        const data = JSON.parse(res)
            const list = Array.isArray(data.data) ? data.data : []
            const comics = list.map(item => {
                const cover = `${base}/api/archives/${item.arcid}/thumbnail`
                const tags = this._cleanListTags(item.tags)
                const tagRating = this._extractRatingFromTags(item.tags)
                const stars = this._toStarsFromValue(tagRating ?? null)
                return ({
                    id: item.arcid,
                    title: item.title || item.filename || item.arcid,
                    subTitle: '',
                    cover,
                    tags,
                    description: '页数: ' + (item.pagecount || '') + ' | 新: ' + (item.isnew || '') + ' | 扩展: ' + (item.extension || ''),
                    stars
                })
            })

            const returned = list.length
            this._updateStart(key, returned)

            const total = typeof data.recordsFiltered === 'number' && data.recordsFiltered >= 0
                ? data.recordsFiltered
                : (start + returned)
            const serverPage = returned || 1
            const maxPage = Math.max(1, Math.ceil(total / serverPage))
            return { comics, maxPage }
        }
    }

    _searchApi = {
        load: async (keyword, options, page = 1) => {
            const base = (this.baseUrl || '').replace(/\/$/, '')

            // Fetch all results once (start=-1), then page locally for consistent UX across servers
            const qp = []
            const add = (k, v) => qp.push(`${encodeURIComponent(k)}=${encodeURIComponent(String(v))}`)
            const pick = (key, def) => {
                let v = options && (options[key])
                if (typeof v === 'string') {
                    const idx = v.indexOf('-');
                    if (idx > 0) v = v.slice(0, idx)
                }
                return (v === undefined || v === null || v === '') ? def : v
            }
            const sortby = pick(0, 'title')
            const order = pick(1, 'asc')
            const newonly = String(pick(2, 'false'))
            const untaggedonly = String(pick(3, 'false'))
            const groupby = String(pick(4, 'true'))

            add('filter', (keyword || '').trim())
            add('sortby', sortby)
            add('order', order)
            add('newonly', newonly)
            add('untaggedonly', untaggedonly)
            add('groupby_tanks', groupby)

            const searchKey = 'search_start_' + encodeURIComponent(String(keyword || ''))
            let start = 0
            if (page === 1) {
                this.saveData(searchKey, 0)
            } else {
                start = Number(this.loadData(searchKey) || 0)
            }
            add('start', String(start))

            const url = `${base}/api/search?${qp.join('&')}`
            const res = await Network.get(url, this.headers)
                        const data = JSON.parse(res)
            const list = Array.isArray(data.data) ? data.data : []

            const comics = list.map(item => {
                const cover = `${base}/api/archives/${item.arcid}/thumbnail`
                const tags = this._cleanListTags(item.tags)
                const tagRating = this._extractRatingFromTags(item.tags)
                const stars = this._toStarsFromValue(tagRating ?? null)
                return ({
                    id: item.arcid,
                    title: item.title || item.filename || item.arcid,
                    subTitle: '',
                    cover,
                    tags,
                    description: '页数: ' + (item.pagecount || '') + ' | 新: ' + (item.isnew || '') + ' | 扩展: ' + (item.extension || ''),
                    stars
                })
            })

            const returned = list.length
            this.saveData(searchKey, start + returned)

            const total = (typeof data.recordsFiltered === 'number' && data.recordsFiltered >= 0)
                ? data.recordsFiltered
                : (start + returned)
            const serverPage = returned || 1
            const maxPage = Math.max(1, Math.ceil(total / serverPage))
            return { comics, maxPage }
        },
        loadNext: async (keyword, options, next) => {
            const page = (typeof next === 'number' && next > 0) ? next : 1
            return await this._searchApi.load(keyword, options, page)
        },
        optionList: [
            { type: "select", options: ["title-按标题","date_added-最新添加","lastread-最近阅读"], label: "sortby", default: "title" },
            { type: "select", options: ["asc-升序","desc-降序"], label: "order", default: "asc" },
            { type: "select", options: ["false-全部","true-仅新"], label: "newonly", default: "false" },
            { type: "select", options: ["false-全部","true-仅未打标签"], label: "untaggedonly", default: "false" },
            { type: "select", options: ["true-启用","false-禁用"], label: "groupby_tanks", default: "true" }
        ],
    }


    _comicApi = {
        loadInfo: async (id) => {
            const url = `${this.baseUrl}/api/archives/${id}/metadata`
            const res = await Network.get(url, this.headers)
                        const data = JSON.parse(res)
            const cover = `${this.baseUrl}/api/archives/${id}/thumbnail`
                let flatTags = data.tags ? data.tags.split(',').map(t=>t.trim()).filter(Boolean) : []
                const rating = flatTags.find(t=>t.startsWith('rating:'))
                if (rating) flatTags = flatTags.filter(t=>!t.startsWith('rating:'))

                let uploadTime = null
                const dateTag = flatTags.find(t => t.startsWith('date_added:'))
                if (dateTag) {
                    uploadTime = dateTag.slice('date_added:'.length).trim()
                    flatTags = flatTags.filter(t => !t.startsWith('date_added:'))
                }

                const nsMap = new Map();
                const nonNs = []
                for (const t of flatTags) {
                    const idx = t.indexOf(':')
                    if (idx > 0) {
                        const ns = t.slice(0, idx)
                        const val = t.slice(idx + 1)
                        if (!nsMap.has(ns)) nsMap.set(ns, [])
                        nsMap.get(ns).push(val)
                    } else {
                        nonNs.push(t)
                    }
                }

                const tagsObj = {}
                for (const [k, v] of nsMap.entries()) {
                    tagsObj[k] = v
                }
                tagsObj['Tags'] = nonNs
                // Preserve special metadata fields
                tagsObj['Pages'] = [String(data.pagecount)]
                tagsObj['Extension'] = [data.extension]

                // Move any tag value that looks like a URL (contains '://') into description
                const urlEntries = []
                const skipKeys = new Set(['Extension', 'Pages'])
                for (const key of Object.keys(tagsObj)) {
                    if (skipKeys.has(key)) continue
                    const arr = tagsObj[key]
                    if (!Array.isArray(arr)) continue
                    const keep = []
                    for (const val of arr) {
                        if (typeof val !== 'string') { keep.push(val); continue }
                        // already a URL with scheme
                        if (val.includes('://')) {
                            urlEntries.push(val)
                            continue
                        }
                        // special-case 'source' namespace: may lack scheme, prepend https://
                        if (String(key).toLowerCase() === 'source') {
                            let corrected = val
                            if (corrected.startsWith('//')) corrected = 'https:' + corrected
                            else if (!/^https?:\/\//i.test(corrected)) corrected = 'https://' + corrected
                            urlEntries.push(corrected)
                            continue
                        }
                        // otherwise keep the tag
                        keep.push(val)
                    }
                    tagsObj[key] = keep
                }

                let summary = data.summary || ''
                if (urlEntries.length) {
                    if (summary) summary += '\n'
                    summary += '关联：' + urlEntries.join(', ')
                }

                let isFavorite = false
                let folders = []
                try {
                    const catUrl = `${this.baseUrl}/api/archives/${id}/categories`
                    const catRes = await Network.get(catUrl, this.headers)
                    if (catRes.status === 200) {
                        let catData = []
                        try { catData = JSON.parse(catRes) } catch (_) { catData = [] }

                        // Normalize common response shapes. Prefer explicit `categories` array.
                        if (catData && typeof catData === 'object') {
                            if (Array.isArray(catData.categories)) catData = catData.categories
                            else if (Array.isArray(catData.data)) catData = catData.data
                            else if (!Array.isArray(catData)) catData = []
                        }

                        if (Array.isArray(catData) && catData.length > 0) {
                            // Find categories that actually contain this archive id in their `archives` list
                            const matched = []
                            for (const c of catData) {
                                const archives = Array.isArray(c.archives) ? c.archives : []
                                if (Array.isArray(archives) && archives.some(a => String(a) === String(id))) {
                                    matched.push(c)
                                }
                            }

                            if (matched.length > 0) {
                                isFavorite = true
                                folders = matched.map(c => String(c.id ?? c._id ?? c.name ?? c))
                            }
                        }
                    }
                } catch (_) { /* ignore category detection errors */ }

                const chapters = new Map(); chapters.set(id, data.title || 'Local manga')
                let stars = this._toStarsFromValue((rating ? rating.replace('rating:', '') : null))
                // Ensure details page always has a numeric star value (0 if no rating),
                // otherwise UI may not allow submitting a rating.
                if (stars === null || stars === undefined) stars = 0
                return {
                    title: data.title || data.filename || id,
                    cover,
                    description: summary,
                    uploadTime: uploadTime,
                    tags: tagsObj,
                    stars,
                    chapters,
                    isFavorite: isFavorite,
                    folders: folders
                }
        },
        loadEp: async (comicId, epId) => {
            const base = (this.baseUrl || '').replace(/\/$/, '')
            const url = `${base}/api/archives/${comicId}/files?force=false`
            const res = await Network.get(url, this.headers)
                        const data = JSON.parse(res)
            const images = (data.pages || []).map(p => {
                if (!p) return null
                const s = String(p)
                if (/^https?:\/\//i.test(s)) return s
                return `${base}${s.startsWith('/') ? s : '/' + s}`
            }).filter(Boolean)
            return { images }
        },
        onImageLoad: (url, comicId, epId) => {
            return {
                headers: this.headers
            }
        },
        // likeComic: async (id, isLike) => {},
        // loadComments: async (comicId, subId, page, replyTo) => {},
        // sendComment: async (comicId, subId, content, replyTo) => {},
        // likeComment: async (comicId, subId, commentId, isLike) => {},
        // voteComment: async (id, subId, commentId, isUp, isCancel) => {},
        // idMatch: null,
        // link: { domains: ['example.com'], linkToId: (url) => null },
    }

    translation = {
        'zh_CN': {
            "language": "语言",
            "artist": "画师",
            "male": "男性",
            "female": "女性",
            "mixed": "混合",
            "other": "其它",
            "parody": "原作",
            "character": "角色",
            "group": "团队",
            "cosplayer": "Coser",
            "reclass": "重新分类",
            "uploader": "上传者",
            "Languages": "语言",
            "Artists": "画师",
            "Characters": "角色",
            "Groups": "团队",
            "Tags": "标签",
            "Parodies": "原作",
            "Categories": "分类",
            "Category": "分类",
            "series": "系列",
            "Series": "系列",
            "Pages": "页数",
            "Extension": "文件类型",
        },
        'en_US': {
            "language": "Language",
            "artist": "Artist",
            "male": "Male",
            "female": "Female",
            "mixed": "Mixed",
            "other": "Other",
            "parody": "Parody",
            "character": "Character",
            "group": "Group",
            "cosplayer": "Cosplayer",
            "reclass": "Reclass",
            "uploader": "Uploader",
            "Languages": "Languages",
            "Artists": "Artists",
            "Characters": "Characters",
            "Groups": "Groups",
            "Tags": "Tags",
            "Parodies": "Parodies",
            "Categories": "Categories",
            "Category": "Category",
            "series": "Series",
            "Series": "Series",
            "Pages": "Pages",
            "Extension": "Extension",
        }
    }
}
