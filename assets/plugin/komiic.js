// description: Komiic 漫画源 — 搜索/分类/详情/阅读（由 venera komiic.js v1.0.3 移植，转换脚本自动生成）
// type: manga
//
// 由 venera 源自动转换：
// - 保留原站点的搜索/分类/详情/阅读核心逻辑（_searchApi/_categoryApi/_comicApi/_categoryData 内部对象）
// - 类开头的「wyw 适配层」将其包装为 wyw 插件接口（search/getDetail/openReader/分类四件套/浏览历史回放）
// - 已移除 wyw 无对应支撑的功能：账号登录/网络收藏/评论/点赞/评分/缩略图墙/外链识别/探索页(未映射部分)
// - Network 调用已改写为 wyw 原生风格：Network.get/post 直接返回 body 字符串，失败抛结构化异常（e.status/e.kind）

class komiic extends PluginSource {
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
                Promise.resolve(this.init()).catch((e) => console.warn('[komiic]', 'init 失败:', e))
            } catch (e) {
                console.warn('[komiic]', 'init 失败:', e)
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
            console.error('[komiic]', '搜索失败:', e)
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
        console.log('[komiic]', '详情:', title, '章节数:', isGallery ? 0 : chapters.length)

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
            plugin: 'komiic',
            method: 'loadChapterImages',
            args: [this._comicId, ep.id],
        }))
        Navigator.navigateToReader({
            comicId: this._comicId,
            comicTitle: this._comicTitle,
            chapters: chapters,
            sourceKey: 'komiic',
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
            console.error('[komiic]', '章节图片解析为空: comicId=' + comicId + ' epId=' + epId)
            throw '章节图片解析为空'
        }
        console.log('[komiic]', '图片数:', urls.length)
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


    // 此漫画源的名称
    name = "Komiic"

    // 唯一标识符
    key = "Komiic"

    version = "1.0.3"


    // 更新链接

    get headers() {
        let token = this.loadData('token')
        let headers = {
            'Referer': 'https://komiic.com/',
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            'Content-Type': 'application/json'
        }
        if (token) {
            headers['Authorization'] = `Bearer ${token}`
        }
        return headers
    }

    async queryJson(query) {
        let res = await Network.post(
            'https://komiic.com/api/query',
            this.headers,
            query
        )

        

        let json = JSON.parse(res)

        if (json.errors != undefined) {
            const errorInfo = json.errors[0].message.toString();
            if ((errorInfo.indexOf('token is expired') >= 0) || (errorInfo.indexOf('no token') >= 0)) {
                throw '登录态失效（wyw 版未实现账号登录，匿名模式不受影响）: ' + errorInfo
            }
            throw json.errors[0].message
        }

        return json
    }

    async queryComics(query) {
        let operationName = query["operationName"]
        let json = await this.queryJson(query)

        function parseComic(comic) {
            let author = ''
            if (comic.authors.length > 0) {
                author = comic.authors[0].name
            }
            let tags = []
            comic.categories.forEach((c) => {
                tags.push(c.name)
            })

            function getTimeDifference(date) {
                const now = new Date();
                const timeDifference = now - date;

                const millisecondsPerHour = 1000 * 60 * 60;
                const millisecondsPerDay = millisecondsPerHour * 24;

                if (timeDifference < millisecondsPerHour) {
                    return '剛剛更新';
                } else if (timeDifference < millisecondsPerDay) {
                    const hours = Math.floor(timeDifference / millisecondsPerHour);
                    return `${hours}小時前更新`;
                } else {
                    const days = Math.floor(timeDifference / millisecondsPerDay);
                    return `${days}天前更新`;
                }
            }

            let updateTime = new Date(comic.dateUpdated)
            let description = getTimeDifference(updateTime)
            let formatedTime = `${updateTime.getFullYear()}-${updateTime.getMonth() + 1}-${updateTime.getDate()}`

            return {
                id: comic.id,
                title: comic.title,
                subTitle: author,
                cover: comic.imageUrl,
                tags: tags,
                description: description,
                updateTime: formatedTime
            }
        }

        return {
            comics: json.data[operationName].map(parseComic),
            // 没找到最大页数的接口
            maxPage: null
        }
    }

    /// 账号
    /// 设置为null禁用账号功能

    /// 探索页面
    /// 一个漫画源可以有多个探索页面
    _explore = [
        {
            /// 标题
            /// 标题同时用作标识符, 不能重复
            title: "Komiic",

            /// singlePageWithMultiPart 或者 multiPageComicList
            type: "multiPageComicList",

            load: async (page) => {
                return await this.queryComics({ "operationName": "recentUpdate", "variables": { "pagination": { "limit": 20, "offset": (page - 1) * 20, "orderBy": "DATE_UPDATED", "status": "", "asc": true } }, "query": "query recentUpdate($pagination: Pagination!) {\n  recentUpdate(pagination: $pagination) {\n    id\n    title\n    status\n    year\n    imageUrl\n    authors {\n      id\n      name\n      __typename\n    }\n    categories {\n      id\n      name\n      __typename\n    }\n    dateUpdated\n    monthViews\n    views\n    favoriteCount\n    lastBookUpdate\n    lastChapterUpdate\n    __typename\n  }\n}" })
            }
        }
    ]

    _categoryData = {
        title: "Komiic",
        enableRankingPage: true,
        parts: [
            {
                name: "主题",

                type: "fixed",

                categories: ['全部', '愛情', '神鬼', '校園', '搞笑', '生活', '懸疑', '冒險', '職場', '魔幻', '後宮', '魔法', '格鬥', '宅男', '勵志', '耽美', '科幻', '百合', '治癒', '萌系', '熱血', '競技', '推理', '雜誌', '偵探', '偽娘', '美食', '恐怖', '四格', '社會', '歷史', '戰爭', '舞蹈', '武俠', '機戰', '音樂', '體育', '黑道'],

                itemType: "category",

                // 若提供, 数量需要和`categories`一致, `categoryComics.load`方法将会收到此参数
                categoryParams: ['0', '1', '3', '4', '5', '6', '7', '8', '10', '11', '2', '12', '13', '14', '15', '16', '17', '18', '19', '20', '21', '22', '23', '24', '25', '26', '27', '9', '28', '31', '32', '33', '34', '35', '36', '37', '40', '42']
            }
        ]
    }

    /// 分类漫画页面, 即点击分类标签后进入的页面
    _categoryApi = {
        load: async (category, param, options, page) => {
          let variables = {
              pagination: {
                  limit: 30,
                  offset: (page - 1) * 30,
                  orderBy: options[0],
                  asc: false,
                  status: options[1]
              }
          };
          
          if (param !== '0') {
              variables.categoryId = [param];
          } else {
              variables.categoryId = [];
          }

          return await this.queryComics({ 
              "operationName": "comicByCategories",
              "variables": variables,
              "query": `query comicByCategories($categoryId: [ID!]!, $pagination: Pagination!) {
                  comicByCategories(categoryId: $categoryId, pagination: $pagination) {
                      id
                      title
                      status
                      year
                      imageUrl
                      authors { id name __typename }
                      categories { id name __typename }
                      dateUpdated
                      monthViews
                      views
                      favoriteCount
                      lastBookUpdate
                      lastChapterUpdate
                      __typename
                  }
              }`
          })
        },
        // 提供选项
        optionList: [
            {
                label: "排序",
                options: [
                    "DATE_UPDATED-更新",
                    "VIEWS-觀看數",
                    "FAVORITE_COUNT-喜愛數",
                ],
                notShowWhen: null,
                showWhen: null
            },
            {
                label: "状态",
                options: [
                    "-全部",
                    "ONGOING-連載中",
                    "END-完結",
                ],
                notShowWhen: null,
                showWhen: null
            },
        ],
        ranking: {
            options: [
                "MONTH_VIEWS-月",
                "VIEWS-綜合"
            ],
            load: async (option, page) => {
                return this.queryComics({ "operationName": "hotComics", "variables": { "pagination": { "limit": 20, "offset": (page - 1) * 20, "orderBy": option, "status": "", "asc": true } }, "query": "query hotComics($pagination: Pagination!) {\n  hotComics(pagination: $pagination) {\n    id\n    title\n    status\n    year\n    imageUrl\n    authors {\n      id\n      name\n      __typename\n    }\n    categories {\n      id\n      name\n      __typename\n    }\n    dateUpdated\n    monthViews\n    views\n    favoriteCount\n    lastBookUpdate\n    lastChapterUpdate\n    __typename\n  }\n}" })
            }
        }
    }

    /// 搜索
    _searchApi = {
        load: async (keyword, options, page) => {
            let json = await this.queryJson({ "operationName": "searchComicAndAuthorQuery", "variables": { "keyword": keyword }, "query": "query searchComicAndAuthorQuery($keyword: String!) {\n  searchComicsAndAuthors(keyword: $keyword) {\n    comics {\n      id\n      title\n      status\n      year\n      imageUrl\n      authors {\n        id\n        name\n        __typename\n      }\n      categories {\n        id\n        name\n        __typename\n      }\n      dateUpdated\n      monthViews\n      views\n      favoriteCount\n      lastBookUpdate\n      lastChapterUpdate\n      __typename\n    }\n    authors {\n      id\n      name\n      chName\n      enName\n      wikiLink\n      comicCount\n      views\n      __typename\n    }\n    __typename\n  }\n}" })

            function parseComic(comic) {
                let author = ''
                if (comic.authors.length > 0) {
                    author = comic.authors[0].name
                }
                let tags = []
                comic.categories.forEach((c) => {
                    tags.push(c.name)
                })

                function getTimeDifference(date) {
                    const now = new Date();
                    const timeDifference = now - date;

                    const millisecondsPerHour = 1000 * 60 * 60;
                    const millisecondsPerDay = millisecondsPerHour * 24;

                    if (timeDifference < millisecondsPerHour) {
                        return '剛剛更新';
                    } else if (timeDifference < millisecondsPerDay) {
                        const hours = Math.floor(timeDifference / millisecondsPerHour);
                        return `${hours}小時前更新`;
                    } else {
                        const days = Math.floor(timeDifference / millisecondsPerDay);
                        return `${days}天前更新`;
                    }
                }

                let updateTime = new Date(comic.dateUpdated)
                let description = getTimeDifference(updateTime)

                return {
                    id: comic.id,
                    title: comic.title,
                    subTitle: author,
                    cover: comic.imageUrl,
                    tags: tags,
                    description: description
                }
            }

            return {
                comics: json.data.searchComicsAndAuthors.comics.map(parseComic),
                // 没找到最大页数的接口
                maxPage: 1
            }
        },

        optionList: []
    }

    /// 收藏

    /// 单个漫画相关
    _comicApi = {
        // 加载漫画信息
        loadInfo: async (id) => {
            let json1 = await this.queryJson({ "operationName": "recommendComicById", "variables": { "comicId": id }, "query": "query recommendComicById($comicId: ID!) {\n  recommendComicById(comicId: $comicId)\n}" })
            let recommend = json1.data.recommendComicById
            recommend.push(id)

            let getFavoriteStatus = async () => {
                let token = this.loadData('token')
                if (!token) {
                    return false
                }
                let json = await this.queryJson({ "operationName": "comicInAccountFolders", "variables": { "comicId": id }, "query": "query comicInAccountFolders($comicId: ID!) {\n  comicInAccountFolders(comicId: $comicId)\n}" })
                let folders = json.data.comicInAccountFolders
                return folders.length !== 0
            }

            let getChapter = async () => {
                let json = await this.queryJson({ "operationName": "chapterByComicId", "variables": { "comicId": id }, "query": "query chapterByComicId($comicId: ID!) {\n  chaptersByComicId(comicId: $comicId) {\n    id\n    serial\n    type\n    dateCreated\n    dateUpdated\n    size\n    __typename\n  }\n}" })
                let all = json.data.chaptersByComicId
                let books = [], chapters = []
                all.forEach((c) => {
                    if(c.type === 'book') {
                        books.push(c)
                    } else {
                        chapters.push(c)
                    }
                })
                let res = new Map()
                books.forEach((c) => {
                    let name = '卷' + c.serial
                    res.set(c.id, name)
                })
                chapters.forEach((c) => {
                    let name = c.serial
                    res.set(c.id, name)
                })
                return res
            }

            let results = await Promise.all([
                this.queryComics({ "operationName": "comicByIds", "variables": { "comicIds": recommend }, "query": "query comicByIds($comicIds: [ID]!) {\n  comicByIds(comicIds: $comicIds) {\n    id\n    title\n    status\n    year\n    imageUrl\n    authors {\n      id\n      name\n      __typename\n    }\n    categories {\n      id\n      name\n      __typename\n    }\n    dateUpdated\n    monthViews\n    views\n    favoriteCount\n    lastBookUpdate\n    lastChapterUpdate\n    __typename\n  }\n}" }),
                getChapter.call()
            ])

            let info = results[0].comics.pop()

            return {
                // string 标题
                title: info.title,
                // string 封面url
                cover: info.cover,
                // map<string, string[]> 标签
                tags: {
                    "作者": [info.subTitle],
                    "标签": info.tags
                },
                // map<string, string>?, key为章节id, value为章节名称
                chapters: results[1],
                recommend: results[0].comics,
                updateTime: info.updateTime,
            }
        },
        // 获取章节图片
        loadEp: async (comicId, epId) => {
            let json = await this.queryJson({ "operationName": "imagesByChapterId", "variables": { "chapterId": epId }, "query": "query imagesByChapterId($chapterId: ID!) {\n  imagesByChapterId(chapterId: $chapterId) {\n    id\n    kid\n    height\n    width\n    __typename\n  }\n}" })
            return {
                images: json.data.imagesByChapterId.map((i) => {
                    return `https://komiic.com/api/image/${i.kid}`
                })
            }
        },
        // 可选, 调整图片加载的行为
        onImageLoad: (url, comicId, epId) => {
            return {
                headers: {
                    'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
                    'referer': `https://komiic.com/comic/${comicId}/chapter/${epId}/images/all`
                }
            }
        },
        // 加载评论
        // 发送评论, 返回任意值表示成功
    }
}
