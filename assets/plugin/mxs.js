// description: 漫小肆 漫画源 — 搜索/分类/详情/阅读（由 venera mxs.js v1.0.0 移植，转换脚本自动生成）
// type: manga
//
// 由 venera 源自动转换：
// - 保留原站点的搜索/分类/详情/阅读核心逻辑（_searchApi/_categoryApi/_comicApi/_categoryData 内部对象）
// - 类开头的「wyw 适配层」将其包装为 wyw 插件接口（search/getDetail/openReader/分类四件套/浏览历史回放）
// - 已移除 wyw 无对应支撑的功能：账号登录/网络收藏/评论/点赞/评分/缩略图墙/外链识别/探索页(未映射部分)
// - Network 调用已改写为 wyw 原生风格：Network.get/post 直接返回 body 字符串，失败抛结构化异常（e.status/e.kind）

class mxs extends PluginSource {
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
                Promise.resolve(this.init()).catch((e) => console.warn('[mxs]', 'init 失败:', e))
            } catch (e) {
                console.warn('[mxs]', 'init 失败:', e)
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
            console.error('[mxs]', '搜索失败:', e)
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
        console.log('[mxs]', '详情:', title, '章节数:', isGallery ? 0 : chapters.length)

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
            plugin: 'mxs',
            method: 'loadChapterImages',
            args: [this._comicId, ep.id],
        }))
        Navigator.navigateToReader({
            comicId: this._comicId,
            comicTitle: this._comicTitle,
            chapters: chapters,
            sourceKey: 'mxs',
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
            console.error('[mxs]', '章节图片解析为空: comicId=' + comicId + ' epId=' + epId)
            throw '章节图片解析为空'
        }
        console.log('[mxs]', '图片数:', urls.length)
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

    // 漫画源基本信息
    name = "漫小肆";
    key = "mxs";
    version = "1.0.0";

    // 漫画源设置项
    settings = {
        // 域名选择功能
        domains: {
            title: "选择域名",
            type: "select",
            options: [
                { value: "https://www.mxshm.top", text: "mxshm.top" },
                { value: "https://www.jjmhw1.top", text: "jjmhw1.top" },
                { value: "https://www.jjmh.top", text: "jjmh.top" },
                { value: "https://www.jjmh.cc", text: "jjmh.cc" },
                { value: "https://www.wzd1.cc", text: "wzd1.cc" },
                { value: "https://www.wzdhm1.cc", text: "wzdhm1.cc" },
                { value: "https://www.ikanwzd.cc", text: "ikanwzd.cc" }
            ],
            default: "https://www.mxshm.top"
        },
        
    };

    // 获取基础URL
    get baseUrl() {
        return this.loadSetting("domains");
    }

    // 解析普通漫画列表
    parseComicList(items) {
        const comics = [];
        
        for (let item of items) {
            // 提取漫画ID
            const linkElem = item.querySelector("a[href^='/book/']");
            const id = linkElem.attributes.href.split("/").pop();
            
            // 提取标题和作者
            const title = item.querySelector(".title a")?.text?.trim();
            const author = item.querySelector("span a")?.text?.trim();
            
            // 提取描述信息
            const description = item.querySelector(".chapter")?.text?.replace(/^更新/, "")?.replace(/\s+/g, " ")?.trim() || item.querySelector(".zl")?.text?.trim();

            // 验证必要字段并创建漫画对象
            if (id && title) {
                comics.push(({
                    id: id,
                    title: title,
                    subTitle: author,
                    cover: `${this.baseUrl}/static/upload/book/${id}/cover.jpg`,
                    description: description
                }));
            }
        }
        
        return comics;
    }

    // 解析热门漫画列表
    parseHotComicList(items) {
        const comics = [];
        
        for (let item of items) {
            // 提取漫画ID
            const linkElem = item.querySelector(".cover a[href^='/book/']");
            const id = linkElem.attributes.href.split("/").pop();
            
            // 提取标题、作者和点击量
            const title = item.querySelector(".info .title a")?.text?.trim();
            const author = item.querySelector(".info .desc")?.text?.trim();
            const clickCount = item.querySelector(".info .subtitle span a")?.text?.trim();

            // 提取标签信息
            const tags = [];
            const tagElems = item.querySelectorAll(".info .tag a");
            for (let tagElem of tagElems) {
                if (tagElem.text) tags.push(tagElem.text.trim());
            }

            // 验证必要字段并创建漫画对象
            if (id && title) {
                comics.push(({
                    id: id,
                    title: title,
                    subTitle: author,
                    cover: `${this.baseUrl}/static/upload/book/${id}/cover.jpg`,
                    tags: tags,
                    description: `热度: 🔥${clickCount}`
                }));
            }
        }
        
        return comics;
    }

    // 解析评论列表
    parseCommentList(items) {
        const comments = [];
        
        for (let item of items) {
            // 提取评论信息
            const userName = item.querySelector(".title")?.text?.trim();
            const content = item.querySelector(".content")?.text?.trim();
            const time = item.querySelector(".bottom")?.text?.match(/\d{4}-\d{2}-\d{2}/)?.[0]?.trim();
            const avatar = item.querySelector(".cover img")?.attributes?.src;

            // 验证必要字段并创建评论对象
            if (userName && content) {
                comments.push(({
                    userName: userName,
                    avatar: `${this.baseUrl}${avatar}`,
                    content: content,
                    time: time
                }));
            }
        }
        
        return comments;
    }

    // 执行网络请求并返回HTML文档对象
    async fetchDocument(url) {
        const res = await Network.get(url, {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        });
        
        
        
        return new HtmlDocument(res);
    }

    // === 探索页面配置 ===
    _explore = [
        {
            title: "漫小肆",
            type: "multiPartPage",
            load: async (page) => {
                const doc = await this.fetchDocument(this.baseUrl);

                // 最近更新部分
                const updateSection = {
                    title: "最近更新",
                    comics: this.parseComicList(doc.querySelectorAll(".index-manga .mh-item")),
                    viewMore: {
                        page: "category",
                        attributes: { category: "最近更新" }
                    }
                };

                // 热门漫画部分
                const hotSection = {
                    title: "热门漫画",
                    comics: this.parseHotComicList(doc.querySelectorAll(".index-original .index-original-list li")),
                    viewMore: {
                        page: "category", 
                        attributes: { category: "排行榜" }
                    }
                };

                // 完结优选部分
                const endSection = {
                    title: "完结优选",
                    comics: this.parseComicList(doc.querySelectorAll(".box-body .mh-item")),
                    viewMore: {
                        page: "category",
                        attributes: { category: "全部漫画" }
                    }
                };

                doc.dispose();
                return [updateSection, hotSection, endSection];
            }
        }
    ];

    // === 分类页面配置 ===
    _categoryData = {
        title: "漫小肆",
        parts: [
            {
                name: "推荐",
                type: "fixed",
                categories: ["最近更新", "排行榜", "全部漫画"],
                itemType: "category"
            },
            {
                name: "题材",
                type: "fixed",
                categories: [
                    "都市", "校园", "青春", "性感", "长腿", "多人", "御姐", "巨乳",
                    "新婚", "媳妇", "暧昧", "清纯", "调教", "少妇", "风骚", "同居", 
                    "淫乱", "好友", "女神", "诱惑", "偷情", "出轨", "正妹", "家教"
                ],
                itemType: "category"
            }
        ],
        enableRankingPage: false
    };

    // === 分类漫画加载配置 ===
    _categoryApi = {
        // 加载分类漫画
        load: async (category, param, options, page) => {
            // 根据分类构建不同的请求URL
            let url;
            if (category === "最近更新") {
                url = `${this.baseUrl}/update?page=${page}`;
            } else if (category === "排行榜") {
                url = `${this.baseUrl}/rank`;
            } else {
                const tag = (category !== "全部漫画") ? category : "全部";
                const area = options[0] || "-1";
                const end = options[1] || "-1";
                url = `${this.baseUrl}/booklist?tag=${encodeURIComponent(tag)}&area=${area}&end=${end}&page=${page}`;
            }

            const doc = await this.fetchDocument(url);
            let comics = [];

            // 排行榜特殊处理
            if (category === "排行榜") {
                const selectedRank = options[0] || "new";
                const rankMapping = {
                    "new": "新书榜",
                    "popular": "人气榜", 
                    "end": "完结榜",
                    "recommend": "推荐榜"
                };

                // 查找对应的排行榜列表
                const rankLists = doc.querySelectorAll(".mh-list.col3.top-cat li");
                let targetList = null;

                for (let list of rankLists) {
                    const titleElem = list.querySelector(".title");
                    if (titleElem) {
                        const title = titleElem.text.trim();
                        if (title === rankMapping[selectedRank]) {
                            targetList = list;
                            break;
                        }
                    }
                }

                if (!targetList) {
                    doc.dispose();
                    throw "未找到对应的排行榜";
                }

                comics = this.parseComicList(targetList.querySelectorAll(".mh-item.horizontal, .mh-itme-top"));
            } else {
                // 普通分类处理
                comics = this.parseComicList(doc.querySelectorAll(".mh-list.col7 .mh-item"));
            }

            // 解析最大页数（排行榜不分页）
            let maxPage = 1;
            if (category !== "排行榜") {
                const pageLinks = doc.querySelectorAll(".pagination a[href*='page=']");
                for (let link of pageLinks) {
                    const match = link.attributes.href.match(/page=(\d+)/);
                    if (match) {
                        const pageNum = parseInt(match[1]);
                        if (!isNaN(pageNum) && pageNum > maxPage) {
                            maxPage = pageNum;
                        }
                    }
                }
            }

            doc.dispose();
            return { comics, maxPage };
        },

        // 动态加载分类选项
        optionLoader: async (category, param) => {
            if (category === "最近更新") {
                return [];
            } else if (category === "排行榜") {
                return [{
                    options: [
                        "new-新书榜",
                        "popular-人气榜", 
                        "end-完结榜",
                        "recommend-推荐榜"
                    ]
                }];
            } else {
                return [
                    {
                        label: "地区",
                        options: [
                            "-全部",
                            "1-韩国", 
                            "2-日本",
                            "3-台湾"
                        ]
                    },
                    {
                        label: "状态",
                        options: [
                            "-全部",
                            "0-连载",
                            "1-完结"
                        ]
                    }
                ];
            }
        }
    };

    // === 搜索功能配置 ===
    _searchApi = {
        // 搜索漫画
        load: async (keyword, options, page) => {
            const url = `${this.baseUrl}/search?keyword=${encodeURIComponent(keyword)}`;
            const doc = await this.fetchDocument(url);
            const comics = this.parseComicList(doc.querySelectorAll(".mh-item"));
            
            doc.dispose();
            return {
                comics: comics,
                maxPage: 1
            };
        },
};

    // === 漫画详情和阅读功能配置 ===
    _comicApi = {
        // 加载漫画详情
        loadInfo: async (id) => {
            const url = `${this.baseUrl}/book/${id}`;
            const doc = await this.fetchDocument(url);

            // 提取标题信息
            const title = doc.querySelector(".info h1")?.text?.trim();

            // 提取副标题信息（别名和作者）
            let author = "";
            let subTitle = "";
            const subTitleElems = doc.querySelectorAll(".info .subtitle");
            for (let elem of subTitleElems) {
                const text = elem.text;
                if (text.includes("别名：")) subTitle = text.replace("别名：", "").trim();
                if (text.includes("作者：")) author = text.replace("作者：", "").trim();
            }
            const authors = author ? author.split("&").map(a => a.trim()).filter(a => a) : [];

            // 提取其他信息（状态、地区、更新时间、点击量和描述信息）
            let status = "";
            let area = "";
            let updateTime = "";
            let clickCount = "";
            const tipElems = doc.querySelectorAll(".info .tip span");
            for (let elem of tipElems) {
                const text = elem.text;
                if (text.includes("状态：")) status = elem.querySelector("span")?.text?.trim();
                if (text.includes("地区：")) area = elem.querySelector("a")?.text?.trim();
                if (text.includes("更新时间：")) updateTime = elem.text.replace("更新时间：", "").trim();
                if (text.includes("点击：")) clickCount = elem.text.replace("点击：", "").trim();
            }
            const description = doc.querySelector(".info .content")?.text?.trim();

            // 提取标签信息
            const tagList = [];
            const tagElems = doc.querySelectorAll(".info .tip a[href*='tag=']");
            for (let elem of tagElems) {
                const tagName = elem.text?.trim();
                if (tagName) tagList.push(tagName);
            }

            // 提取章节列表
            const chapters = {};
            const chapterElems = doc.querySelectorAll("#detail-list-select li a");
            for (let elem of chapterElems) {
                const chapterUrl = elem.attributes?.href;
                const chapterTitle = elem.text?.trim();
                if (chapterUrl && chapterTitle) {
                    const chapterId = chapterUrl.split("/").pop();
                    if (chapterId) chapters[chapterId] = chapterTitle;
                }
            }

            // 提取评论和推荐漫画
            const comments = this.parseCommentList(doc.querySelectorAll(".view-comment-main .postlist li.dashed"));
            const recommend = this.parseComicList(doc.querySelectorAll(".index-manga .mh-item"));

            doc.dispose();
            
            // 创建并返回漫画详情对象
            return ({
                title: title,
                subTitle: subTitle,
                cover: `${this.baseUrl}/static/upload/book/${id}/cover.jpg`,
                description: description,
                tags: {
                    "作者": authors,
                    "题材": tagList,
                    "地区": [area],
                    "状态": [status],
                    "热度": [`🔥${clickCount}`]
                },
                chapters: chapters,
                recommend: recommend,
                commentCount: comments.length,
                updateTime: updateTime,
                url: url,
                comments: comments
            });
        },

        // 加载章节图片
        loadEp: async (comicId, epId) => {
            const url = `${this.baseUrl}/chapter/${epId}`;
            const doc = await this.fetchDocument(url);

            // 提取懒加载图片
            const images = [];
            const imageElems = doc.querySelectorAll("img.lazy");
            for (let img of imageElems) {
                const src = img.attributes?.["data-original"];
                const image = src.replace(/https?:\/\/[^\/]+/, this.baseUrl);
                if (image) images.push(image);
            }

            if (images.length === 0) {
                doc.dispose();
                throw "本章中未找到图片";
            }

            doc.dispose();
            return {
                images: images
            };
        },

        // 加载评论列表

        // 处理标签点击事件
};
}