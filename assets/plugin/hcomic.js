// description: H-Comic 漫画源 — 搜索/分类/详情/阅读（由 venera hcomic.js v1.0.0 移植，转换脚本自动生成）
// type: manga
//
// 由 venera 源自动转换：
// - 保留原站点的搜索/分类/详情/阅读核心逻辑（_searchApi/_categoryApi/_comicApi/_categoryData 内部对象）
// - 类开头的「wyw 适配层」将其包装为 wyw 插件接口（search/getDetail/openReader/分类四件套/浏览历史回放）
// - 已移除 wyw 无对应支撑的功能：账号登录/网络收藏/评论/点赞/评分/缩略图墙/外链识别/探索页(未映射部分)
// - Network 调用已改写为 wyw 原生风格：Network.get/post 直接返回 body 字符串，失败抛结构化异常（e.status/e.kind）

class hcomic extends PluginSource {
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
                Promise.resolve(this.init()).catch((e) => console.warn('[hcomic]', 'init 失败:', e))
            } catch (e) {
                console.warn('[hcomic]', 'init 失败:', e)
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
            console.error('[hcomic]', '搜索失败:', e)
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
        console.log('[hcomic]', '详情:', title, '章节数:', isGallery ? 0 : chapters.length)

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
            plugin: 'hcomic',
            method: 'loadChapterImages',
            args: [this._comicId, ep.id],
        }))
        Navigator.navigateToReader({
            comicId: this._comicId,
            comicTitle: this._comicTitle,
            chapters: chapters,
            sourceKey: 'hcomic',
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
            console.error('[hcomic]', '章节图片解析为空: comicId=' + comicId + ' epId=' + epId)
            throw '章节图片解析为空'
        }
        console.log('[hcomic]', '图片数:', urls.length)
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

    // Name of the source
    name = "H-Comic"

    // Unique id of the source
    key = "hcomic"

    version = "1.0.0"


    // Update url

    baseUrl = "https://h-comic.com"

    /**
     * [Optional] init function
     */
    init() {

    }

    async getHtml(url) {
        let res = await Network.get(url, {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
        });
        ;
        return res;
    }

    extractData(html) {
        // Look for the SvelteKit data script
        // Matches: data: [null, { ... }], form:
        let match = html.match(/data:\s*\[null,\s*(\{[\s\S]*?\})\s*\]\s*,\s*form:/);
        if (match) {
            let jsonStr = match[1];
            try {
                // Try to fix unquoted keys: { key: value } -> { "key": value }
                let fixedJsonStr = jsonStr.replace(/([{,]\s*)([a-zA-Z_][a-zA-Z0-9_]*)\s*:/g, '$1"$2":');
                let json = JSON.parse(fixedJsonStr);
                return json.data;
            } catch (e) {
                console.error("Failed to parse JSON", e);
                try {
                    // Fallback to new Function if JSON.parse fails (e.g. trailing commas)
                    let fn = new Function("return " + jsonStr);
                    let json = fn();
                    return json.data;
                } catch (e2) {
                    console.error("Failed to eval", e2);
                }
            }
        }
        return null;
    }

    extractMaxPage(html) {
        let match = html.match(/name="page"[^>]*max="(\d+)"/);
        if (match) {
            return parseInt(match[1]);
        }
        return 1;
    }

    parseComic(c) {
        let title = c.title.display || c.title.pretty || c.title.japanese;
        let tags = c.tags ? c.tags.map(t => t.name_zh || t.name) : [];
        let updateTime = null;
        if (c.upload_date) {
            let date = new Date(c.upload_date * 1000).toISOString().split('T')[0];
            tags.push(date);
            updateTime = date;
        }
        return ({
            id: `${c.id}|${title}`,
            title: title,
            subTitle: c.title.english,
            cover: c.thumbnail,
            tags: tags,
            description: "",
            updateTime: updateTime
        });
    }

    // explore page list
    _explore = [
        {
            // title of the page.
            title: "h-comic",

            /// multiPartPage or multiPageComicList or mixed
            type: "multiPartPage",

            /**
             * load function
             * @param page {number | null} - page number, null for `singlePageWithMultiPart` type
             * @returns {{}}
             */
            load: async (page) => {
                let html = await this.getHtml(this.baseUrl);
                let data = this.extractData(html);
                if (!data || !data.comics) return [];
                
                let comics = data.comics.map(c => this.parseComic(c));
                return [{ title: "随机漫画", comics }];
            }
        }
    ]

    // categories
    _categoryData = {
        /// title of the category page
        title: "H-Comic",
        parts: [
            {
                // title of the part
                name: "热门TAG",

                // fixed or random or dynamic
                type: "fixed",

                categories: [
                    { label: "全部", target: { page: "category", attributes: { category: "全部" } } },
                    { label: "全彩", target: { page: "category", attributes: { category: "全彩", param: "全彩" } } },
                    { label: "無修正", target: { page: "category", attributes: { category: "無修正", param: "無修正" } } },
                    { label: "蘿莉", target: { page: "category", attributes: { category: "蘿莉", param: "蘿莉" } } },
                    { label: "制服", target: { page: "category", attributes: { category: "制服", param: "制服" } } },
                    { label: "巨乳", target: { page: "category", attributes: { category: "巨乳", param: "巨乳" } } },
                    { label: "黑絲 / 白襪", target: { page: "category", attributes: { category: "黑絲 / 白襪", param: "黑絲 / 白襪" } } },
                    { label: "NTR", target: { page: "category", attributes: { category: "NTR", param: "netorare" } } },
                    { label: "足交 / 腳交", target: { page: "category", attributes: { category: "足交 / 腳交", param: "footjob" } } },
                    { label: "女學生", target: { page: "category", attributes: { category: "女學生", param: "女學生" } } },
                    { label: "眼鏡控", target: { page: "category", attributes: { category: "眼鏡控", param: "眼鏡控" } } },
                    { label: "口交", target: { page: "category", attributes: { category: "口交", param: "口交" } } },
                    { label: "正太控", target: { page: "category", attributes: { category: "正太控", param: "正太控" } } },
                    { label: "年上", target: { page: "category", attributes: { category: "年上", param: "年上" } } },
                    { label: "亂倫", target: { page: "category", attributes: { category: "亂倫", param: "亂倫" } } },
                    { label: "熟女 / 人妻", target: { page: "category", attributes: { category: "熟女 / 人妻", param: "熟女 / 人妻" } } },
                    { label: "同志 BL", target: { page: "category", attributes: { category: "同志 BL", param: "同志 BL" } } },
                    { label: "黑肉", target: { page: "category", attributes: { category: "黑肉", param: "黑肉" } } },
                    { label: "泳裝", target: { page: "category", attributes: { category: "泳裝", param: "泳裝" } } },
                    { label: "手淫", target: { page: "category", attributes: { category: "手淫", param: "手淫" } } },
                    { label: "肌肉", target: { page: "category", attributes: { category: "肌肉", param: "肌肉" } } },
                    { label: "姐姐 / 妹妹", target: { page: "category", attributes: { category: "姐姐 / 妹妹", param: "姐姐 / 妹妹" } } },
                    { label: "捆綁", target: { page: "category", attributes: { category: "捆綁", param: "捆綁" } } },
                    { label: "調教", target: { page: "category", attributes: { category: "調教", param: "調教" } } },
                    { label: "催眠", target: { page: "category", attributes: { category: "催眠", param: "催眠" } } },
                    { label: "露出", target: { page: "category", attributes: { category: "露出", param: "露出" } } },
                    { label: "群交", target: { page: "category", attributes: { category: "群交", param: "群交" } } },
                    { label: "肛交", target: { page: "category", attributes: { category: "肛交", param: "肛交" } } },
                    { label: "獸交", target: { page: "category", attributes: { category: "獸交", param: "獸交" } } }
                ]
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
            let sort = options[0];
            let path = sort === "random" ? "/random" : "/";
            
            let url = `${this.baseUrl}${path}?page=${page}&q=`;

            if (param) {
                url += `&tag=${encodeURIComponent(param)}`;
            } else {
                url += `&tag=`;
            }

            let html = await this.getHtml(url);
            let data = this.extractData(html);
            let maxPage = sort === "random" ? null : this.extractMaxPage(html);

            if (!data || !data.comics) return { comics: [], maxPage: page };

            let comics = data.comics.map(c => this.parseComic(c));
            
            return {
                comics: comics,
                maxPage: maxPage
            }
        },
        // [Optional] provide options for category comic loading
        optionList: [
            {
                options: [
                    "latest-最近更新",
                    "random-随机刷新"
                ]
            }
        ],
        ranking: {
            options: [],
            load: async (option, page) => {
                return { comics: [], maxPage: 0 };
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
            // Placeholder for search
            let url = `${this.baseUrl}/?q=${encodeURIComponent(keyword)}&tag=&page=${page}`;
            let html = await this.getHtml(url);
            let data = this.extractData(html);
            let maxPage = this.extractMaxPage(html);

            if (!data || !data.comics) return { comics: [], maxPage: page };

            let comics = data.comics.map(c => this.parseComic(c));

            return { comics, maxPage };
        },
        optionList: [],
    }

    /// single comic related
    _comicApi = {
        loadInfo: async (id) => {
            let realId = id;
            let title_temp = "view";
            if (id.includes('|')) {
                let parts = id.split('|');
                realId = parts[0];
                title_temp = parts.slice(1).join('|');
            }

            let url = `${this.baseUrl}/comics/${encodeURIComponent(title_temp)}/1?id=${realId}`;
            let html = await this.getHtml(url);
            let data = this.extractData(html);
            
            if (!data || !data.comic) throw "Failed to load comic info";
            let c = data.comic;

            let title = c.title.display || c.title.pretty || c.title.japanese;
            let subTitle = c.title.english;
            
            let cover = c.thumbnail;
            if (!cover && c.comic_source && c.media_id) {
                cover = `https://h-comic.link/api/${c.comic_source}/${c.media_id}/pages/1`;
            }

            let tags = {};
            if (c.tags) {
                tags["标签"] = c.tags.map(t => t.name_zh || t.name);
            }
            
            let updateTime = null;
            if (c.upload_date) {
                let date = new Date(c.upload_date * 1000).toISOString().split('T')[0];
                tags["日期"] = [date];
                updateTime = date;
            }

            let description = c.title.japanese || "";

            // Encode source, media_id, num_pages into chapter ID
            let chapterId = `${c.comic_source}|${c.media_id}|${c.num_pages}`;

            let chapters = new Map();
            let group = new Map();
            group.set(chapterId, "全一话");
            chapters.set("章节", group);

            return ({
                title: title,
                subTitle: subTitle,
                cover: cover,
                description: description,
                tags: tags,
                chapters: chapters,
                updateTime: updateTime
            });
        },
        loadEp: async (comicId, epId) => {
            let parts = epId.split('|');
            let source = parts[0];
            let mediaId = parts[1];
            let numPages = parseInt(parts[2]);

            let images = [];
            for (let i = 1; i <= numPages; i++) {
                images.push(`https://h-comic.link/api/${source}/${mediaId}/pages/${i}`);
            }

            return { images: images };
        },
    }
}
