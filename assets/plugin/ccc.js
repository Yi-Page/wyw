// description: CCC追漫台 漫画源 — 搜索/分类/详情/阅读（由 venera ccc.js v1.0.1 移植，转换脚本自动生成）
// type: manga
//
// 由 venera 源自动转换：
// - 保留原站点的搜索/分类/详情/阅读核心逻辑（_searchApi/_categoryApi/_comicApi/_categoryData 内部对象）
// - 类开头的「wyw 适配层」将其包装为 wyw 插件接口（search/getDetail/openReader/分类四件套/浏览历史回放）
// - 已移除 wyw 无对应支撑的功能：账号登录/网络收藏/评论/点赞/评分/缩略图墙/外链识别/探索页(未映射部分)
// - Network 调用已改写为 wyw 原生风格：Network.get/post 直接返回 body 字符串，失败抛结构化异常（e.status/e.kind）

class ccc extends PluginSource {
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
                Promise.resolve(this.init()).catch((e) => console.warn('[ccc]', 'init 失败:', e))
            } catch (e) {
                console.warn('[ccc]', 'init 失败:', e)
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
            console.error('[ccc]', '搜索失败:', e)
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
        console.log('[ccc]', '详情:', title, '章节数:', isGallery ? 0 : chapters.length)

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
            plugin: 'ccc',
            method: 'loadChapterImages',
            args: [this._comicId, ep.id],
        }))
        Navigator.navigateToReader({
            comicId: this._comicId,
            comicTitle: this._comicTitle,
            chapters: chapters,
            sourceKey: 'ccc',
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
            console.error('[ccc]', '章节图片解析为空: comicId=' + comicId + ' epId=' + epId)
            throw '章节图片解析为空'
        }
        console.log('[ccc]', '图片数:', urls.length)
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
    name = "CCC追漫台"

    // unique id of the source
    key = "ccc"

    version = "1.0.1"


    // update url

    apiUrl = "https://api.creative-comic.tw"

    processToken(body) {
        const result = JSON.parse(body);
        if (result.code != 0) {
            throw "登錄失敗";
        }
        this.saveData("expireTime", Math.floor(Date.now() / 1000) + result.expires_in);
        this.saveData("refreshToken", result.refresh_token);
        this.saveData("token", result.access_token);
    }

    async getApiHeaders(login = false) {
        let token = this.loadData("token");
        if (!login && token) {
            if (Math.floor(Date.now() / 1000) > this.loadData("expireTime")) {
                const res = await Network.post(`${this.apiUrl}/token`, {
                    device: "web_desktop",
                    uuid: "null"
                }, {
                    "grant_type": "refresh_token",
                    "client_id": "2",
                    "client_secret": "9eAhsCX3VWtyqTmkUo5EEaoH4MNPxrn6ZRwse7tE",
                    "refresh_token": this.loadData("refreshToken")
                });
                if (res.search("Token has been revoked") == -1) {
                    this.processToken(res);
                } else {
                    throw "Token 已失效（wyw 版未实现账号登录），请重试";
                }
                token = this.loadData("token");
            }
            return {
                device: "web_desktop",
                Authorization: `Bearer ${token}`
            }
        }
        return {
            device: "web_desktop",
            uuid: "null"
        }
    }

    base64ToArrayBuffer(base64) {
        const base64Data = base64.split(',')[1] || base64;
        return Convert.decodeBase64(base64Data);
    }

    async parseComics(url) {
        const res = await Network.get(url, await this.getApiHeaders());
        const result = [];
        const jsonData = JSON.parse(res)["data"];
        for (let c of jsonData["data"]) {
            const tags = [];
            for (let a of c["author"]) {
                tags.push(a["name"]);
            }
            if (typeof (c["type"]) == "object") {
                tags.push(c["type"]["name"]);
            }
            result.push({
                id: (("book_id" in c) ? c["book_id"] : c["id"]).toString(),
                title: c["name"],
                subtitle: c["brief"],
                description: c["description"],
                cover: c["image1"]??c["image2"]??c["image3"],
                tags: tags
            });
        }
        return { comics: result, maxPage: Math.ceil(jsonData["total"] / 20) };
    }

    // [Optional] account related

    // explore page list
    _explore = [
        {
            // title of the page.
            // title is used to identify the page, it should be unique
            title: "CCC追漫台",

            /// multiPartPage or multiPageComicList or mixed
            type: "singlePageWithMultiPart",

            /**
             * load function
             * @param page {number | null} - page number, null for `singlePageWithMultiPart` type
             * @returns {{}}
             * - for `multiPartPage` type, return [{title: string, comics: Comic[], viewMore: string?}]
             * - for `multiPageComicList` type, for each page(1-based), return {comics: Comic[], maxPage: number}
             * - for `mixed` type, use param `page` as index. for each index(0-based), return {data: [], maxPage: number?}, data is an array contains Comic[] or {title: string, comics: Comic[], viewMore: string?}
             */
            load: async () => {
                const res = await Network.get(`${this.apiUrl}/public/home_v2`, await this.getApiHeaders());
                const result = {};
                const jsonData = JSON.parse(res)["data"];
                let curTitle = null;
                for (let data of jsonData["templates"]) {
                    if ([4, 5].indexOf(data["type"]) != -1) {
                        continue;
                    }
                    const comics = [];
                    for (let c of data["list"]) {
                        comics.push({
                            id: c["value"],
                            title: c["name"],
                            cover: c["image1"]??c["image2"]??c["image3"],
                            tags: [c["book_type"]["name"]],
                            subtitle: c["brief"]
                        });
                    }
                    if (data["title"]) {
                        curTitle = data["title"];
                        result[curTitle] = comics;
                    } else {
                        result[curTitle] = result[curTitle].concat(comics);
                    }
                }
                return result;
            }
        }
    ]

    // categories
    _categoryData = {
        /// title of the category page, used to identify the page, it should be unique
        title: "CCC追漫台",
        parts: [
            {
                name: "CCC追漫台",
                type: "fixed",
                categories: ["排行榜"],
                itemType: "category",
                categoryParams: ["top"]
            }
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
            if (options == null) {
                options = ["", "read"];
            }
            const type = options[0] ? `&type=${options[0]}` : "";
            const url = `${this.apiUrl}/rank?page=${page}&rows_per_page=20&rank=${options[1]}&class=2${type}`;
            return await this.parseComics(url);
        },
        /**
         * [Optional] load options dynamically. If `optionList` is provided, this will be ignored.
         * @param category {string}
         * @param param {string?}
         * @return {Promise<{options: string[], label?: string}[]>} - return a list of option group, each group contains a list of options
         */
        optionList: [
            {
                label: "分類",
                // For a single option, use `-` to separate the value and text, left for value, right for text
                options: [
                    "-全部",
                    "2-劇情",
                    "6-愛情",
                    "5-青春成長",
                    "3-幽默搞笑",
                    "10-歷史古裝",
                    "7-奇幻架空",
                    "4-溫馨療癒",
                    "9-冒險動作",
                    "8-恐怖驚悚",
                    "12-新感覺推薦",
                    "11-推理懸疑",
                    "13-活動"
                ]
            },
            {
                label: "排行榜",
                // For a single option, use `-` to separate the value and text, left for value, right for text
                options: [
                    "read-人氣榜",
                    "buy-銷售榜",
                    "donate-斗内榜",
                    "collect-收藏榜"
                ]
            }
        ]
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
            options[0] = "&sort_by=" + options[0];
            if (options[1]) {
                options[1] = "&type=" + options[1];
            }
            if (options[2]) {
                options[2] = "&serial=" + options[2];
            }
            if (options[3]) {
                options[3] = "&updated_at=" + options[3];
            }
            if (options[4]) {
                options[4] = "&literature_form=" + options[4];
            }
            if (options[5]) {
                options[5] = "&comic_type=" + options[5];
            }
            if (options[6]) {
                options[6] = "&publisher=" + options[6];
            }
            const url = `https://api.creative-comic.tw/book?page=${page}&rows_per_page=20&keyword=${keyword}&class=2${options.join("")}`;
            return await this.parseComics(url);
        },

        // provide options for search
        optionList: [
            {
                type: "select",
                // For a single option, use `-` to separate the value and text, left for value, right for text
                options: [
                    "updated_at-最新",
                    "read_count-閲覽",
                    "like_count-推薦",
                    "collect_count-收藏"
                ],
                // option label
                label: "排序"
            },
            {
                type: "select",
                // For a single option, use `-` to separate the value and text, left for value, right for text
                options: [
                    "-全部",
                    "2-劇情",
                    "6-愛情",
                    "5-青春成長",
                    "3-幽默搞笑",
                    "10-歷史古裝",
                    "7-奇幻架空",
                    "4-溫馨療癒",
                    "9-冒險動作",
                    "8-恐怖驚悚",
                    "12-新感覺推薦",
                    "11-推理懸疑",
                    "13-活動"
                ],
                // option label
                label: "分類"
            },
            {
                type: "select",
                // For a single option, use `-` to separate the value and text, left for value, right for text
                options: [
                    "-全部",
                    "2-已完結",
                    "0-連載中"
                ],
                // option label
                label: "連載狀態"
            },
            {
                type: "select",
                // For a single option, use `-` to separate the value and text, left for value, right for text
                options: [
                    "-全部",
                    "month-本月",
                    "week-本周"
                ],
                // option label
                label: "更新日期"
            },
            {
                type: "select",
                // For a single option, use `-` to separate the value and text, left for value, right for text
                options: [
                    "-全部",
                    "1-短篇",
                    "2-中篇",
                    "3-長篇"
                ],
                // option label
                label: "作品篇幅"
            },
            {
                type: "select",
                // For a single option, use `-` to separate the value and text, left for value, right for text
                options: [
                    "-全部",
                    "3-條漫",
                    "2-格漫",
                ],
                // option label
                label: "作品形式"
            },
            {
                type: "dropdown",
                options: [
                    "-全部",
                    "44-MOJOIN",
                    "37-目宿媒體股份有限公司",
                    "4-大辣出版",
                    "18-MarsCat火星貓科技",
                    "2-CCC創作集",
                    "23-海穹文化",
                    "11-國立歷史博物館",
                    "6-未來數位",
                    "34-虎尾建國眷村再造協會",
                    "24-鏡文學股份有限公司",
                    "43-Taiwan Comic City",
                    "42-聯經出版事業股份有限公司",
                    "48-東立出版社有限公司",
                    "9-留守番工作室",
                    "16-獨步文化",
                    "21-尖端媒體集團",
                    "29-相之丘tōkhiu books",
                    "7-威向文化",
                    "54-白範出版工作室",
                    "22-時報文化出版企業股份有限公司",
                    "20-國立臺灣工藝研究發展中心",
                    "17-獨立出版",
                    "51-大寬文化工作室",
                    "32-金繪國際有限公司",
                    "47-前衛出版社",
                    "36-奇異果文創",
                    "14-綺影映畫",
                    "53-彰化縣政府",
                    "31-艾德萊娛樂",
                    "8-特有生物研究保育中心",
                    "39-聚場文化",
                    "38-XPG",
                    "52-陌上商行有限公司",
                    "49-國際合製｜臺漫新視界",
                    "40-KADOKAWA",
                    "10-國立臺灣美術館",
                    "26-金漫獎",
                    "5-台灣東販",
                    "45-國立國父紀念館",
                    "35-國立臺灣歷史博物館",
                    "15-蓋亞文化",
                    "1-長鴻出版社",
                    "19-柒拾陸號原子",
                    "33-台灣角川",
                    "28-一顆星工作室",
                    "46-好人出版",
                    "27-澄波藝術文化股份有限公司",
                    "12-黑白文化",
                    "13-慢工文化 Slowork Publishing",
                    "30-經濟部智慧財產局",
                    "50-Contents Lab. Blue TOKYO",
                    "3-大塊文化",
                    "25-目色出版",
                    "41-文化內容策進院"
                ],
                label: "出版社"
            }
        ],
    }

    // favorite related

    /// single comic related
    _comicApi = {
        freeRead: (data) => {
            let free_read = true;
            if (!data["is_free"]) {
                if (data["sales_plan"] != 0) {
                    if ((data["is_coin_buy"] || data["is_point_buy"]) && !data["is_buy"]) {
                        if ((data["is_coin_rent"] || data["is_point_rent"]) && !data["is_rent"]) {
                            free_read = false;
                        }
                    }
                }
            }
            return free_read;
        },
        /**
         * load comic info
         * @param id {string}
         * @returns {Promise<ComicDetails>}
         */
        loadInfo: async (id) => {
            const res = await Network.get(`${this.apiUrl}/book/${id}/info`, await this.getApiHeaders());
            const jsonData = JSON.parse(res)["data"];
            const authors = [];
            for (let a of jsonData["author"]) {
                authors.push(a["name"]);
            }
            const tags = [];
            for (let t of jsonData["tags"]) {
                tags.push(t["name"]);
            }
            const chapter_res = await Network.get(`${this.apiUrl}/book/${id}/chapter`, await this.getApiHeaders());
            const chapterData = JSON.parse(chapter_res)["data"];
            const chapters = {};
            for (let c of chapterData["chapters"]) {
                chapters[c["id"].toString()] = `${!this._comicApi.freeRead(c) ? "[付費]" : ""}${c["vol_name"]}-${c["name"]}`;
            }
            const recommend_res = await Network.get(`${this.apiUrl}/book/${id}/recommend`, await this.getApiHeaders());
            const recommendData = JSON.parse(recommend_res)["data"];
            const recommends = [];
            for (let r of recommendData["hot"]) {
                recommends.push({
                    title: r["name"],
                    cover: r["image1"]??r["image2"]??r["image3"],
                    id: r["id"].toString(),
                    subtitle: r["brief"]
                });
            }
            for (let r of recommendData["history"]) {
                recommends.push({
                    title: r["name"],
                    cover: r["image1"]??r["image2"]??r["image3"],
                    id: r["id"].toString()
                });
            }
            for (let r of recommendData["also_buy"]) {
                recommends.push({
                    title: r["name"],
                    cover: r["image1"]??r["image2"]??r["image3"],
                    id: r["id"].toString()
                });
            }
            return ({
                title: jsonData["name"],
                subtitle: jsonData["brief"],
                cover: jsonData["image1"]??jsonData["image2"]??jsonData["image3"],
                description: jsonData["description"],
                likesCount: jsonData["like_count_only_uuid"],
                chapters: chapters,
                tags: {
                    "作者": authors,
                    "分類": [jsonData["type"]["name"]],
                    "標籤": tags,
                },
                isFavorite: (jsonData["is_collected"] == 1),
                updateTime: jsonData["updated_at"],
                recommend: recommends
            })
        },
        /**
         * load images of a chapter
         * @param comicId {string}
         * @param epId {string?}
         * @returns {Promise<{images: string[]}>}
         */
        loadEp: async (comicId, epId) => {
            const res = await Network.get(`${this.apiUrl}/book/chapter/${epId}`, await this.getApiHeaders());
            if (res.status == 403) {
                Dialog.showDialog("提示", "該章節需付費后閲讀", [
                    {
                        text: "取消",
                        callback: () => { }
                    },
                    {
                        text: "去購買",
                        callback: () => {
                            Dialog.showToast('請在瀏覽器打開: https://www.creative-comic.tw/zh/book/' + comicId + '/content');
                        }
                    }
                ]);
                return { images: [] };
            }
            const jsonData = JSON.parse(res)["data"];
            const images = [];
            for (let img of jsonData["chapter"]["proportion"]) {
                images.push(img["id"].toString());
            }
            return {
                images: images
            }
        },
        /**
         * [Optional] provide configs for an image loading
         * @param url
         * @param comicId
         * @param epId
         * @returns {{} | Promise<{}>}
         */
        onImageLoad: async (url, comicId, epId) => {
            const res = await Network.get(`${this.apiUrl}/book/chapter/image/${url}`, await this.getApiHeaders());
            const encryptedKey = Convert.decodeBase64(JSON.parse(res)["data"]["key"]);
            let token = this.loadData("token");
            if (token == null) {
                token = "freeforccc2020reading";
            }
            const hashArray = Convert.sha512(Convert.encodeUtf8(token));
            const pageKey = hashArray.slice(0, 32);
            const pageIv = hashArray.slice(15, 31);
            const decryptedKey = new Uint8Array(Convert.decryptAesCbc(encryptedKey, pageKey, pageIv));
            const padLen = decryptedKey[decryptedKey.length - 1];
            const [key, iv] = Convert.decodeUtf8(decryptedKey.slice(0, decryptedKey.length - padLen).buffer).split(":");
            return {
                url: `https://storage.googleapis.com/ccc-www/fs/chapter_content/encrypt/${url}/2`,
                onResponse: function (buffer) {
                    function hexToBytes(hex) {
                        if (hex.length % 2 !== 0) {
                            throw new Error("Invalid hex string");
                        }
                        const bytes = new Uint8Array(hex.length / 2);
                        for (let i = 0; i < hex.length; i += 2) {
                            bytes[i / 2] = parseInt(hex.substr(i, 2), 16);
                        }
                        return bytes.buffer;
                    }
                    const decrypted = new Uint8Array(Convert.decryptAesCbc(buffer, hexToBytes(key), hexToBytes(iv)));
                    const padLen_ = decrypted[decrypted.length - 1];
                    const base64 = Convert.decodeUtf8(decrypted.slice(0, decrypted.length - padLen_).buffer);
                    const base64Data = base64.split(',')[1] || base64;
                    return Convert.decodeBase64(base64Data);
                }
            }
        },
        /**
         * [Optional] load comments
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
         * @returns {{action: string, keyword: string, param: string?}}
         */
    }

}
