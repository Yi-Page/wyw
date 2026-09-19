// description: 热辣漫画（manga2024）漫画源 — 搜索/详情/阅读/分类浏览
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
// 注意：
//   - 接口为 JSON API，Network.get 直接返回 body 字符串
//   - 章节接口有访问频率限制（210），插件内自动等待重试
//   - 原 venera 的登录/收藏/首页推荐在 wyw 中无对应支撑，已移除

class hot_manga extends PluginSource {
    name = '热辣漫画'
    key = 'hot_manga'
    version = '1.0.0'

    static defaultImageQuality = '1500'
    static defaultApiUrl = 'api.2024manga.com'

    /// 作者名 → path_word 映射（venera 在 init() 里初始化，wyw 引擎不调用 init，直接实例字段）
    author_path_word_dict = {}

    get headers() {
        return {
            "Authorization": this.loadData('token') ? `Token ${this.loadData('token')}` : '',
            "Accept": "application/json",
            "webp": "1",
            "platform": "3",
            "version": "2024.04.28",
            "X-Requested-With": "com.manga2020.app",
        }
    }

    get apiUrl() {
        // 设置未保存过时 loadSetting 返回空值，兜底到默认 API 地址
        let base = this.loadSetting('base_url')
        if (!base) base = hot_manga.defaultApiUrl
        return `https://${base}`
    }

    get imageQuality() {
        return this.loadSetting('image_quality') || hot_manga.defaultImageQuality
    }

    /// 源网站地址（插件管理页「网站」菜单调用）
    getUrl() {
        return this.apiUrl
    }

    // ============ 工具 ============

    /// 统一 JSON 请求（Network.get 返回 body 字符串；非 2xx 由 Dio 抛异常）
    async _getJson(url) {
        let res = await Network.get(url, this.headers)
        if (res == null || res.trim().length === 0) {
            throw '空响应'
        }
        return JSON.parse(res)
    }

    /// 解析漫画对象（兼容列表/排名两种格式）
    _parseComic(comic) {
        let sort = null
        let popular = 0
        let rise_sort = 0
        if (comic['sort'] !== null && comic['sort'] !== undefined) {
            sort = comic['sort']
            rise_sort = comic['rise_sort']
            popular = comic['popular']
        }
        if (comic['comic'] !== null && comic['comic'] !== undefined) {
            comic = comic['comic']
        }
        let tags = []
        if (comic['theme'] !== null && comic['theme'] !== undefined) {
            tags = comic['theme'].map((t) => t['name'])
        }
        let author = null
        let author_num = 0
        if (Array.isArray(comic['author']) && comic['author'].length > 0) {
            author = comic['author'][0]['name']
            author_num = comic['author'].length
        }
        let description = comic['datetime_updated'] || ''
        if (sort !== null) {
            description = `${sort} ${rise_sort > 0 ? '▲' : rise_sort < 0 ? '▽' : '-'} · ${author_num > 1 ? `${author} 等${author_num}位` : author} · 🔥${(popular / 10000).toFixed(1)}W`
        }
        return {
            id: comic['path_word'],
            title: comic['name'],
            subTitle: author,
            cover: comic['cover'],
            tags: tags,
            description: description,
        }
    }

    /// 构造结果卡片（参照 jm）
    _comicCard(c) {
        let metaLines = []
        if (c.subTitle) metaLines.push(c.subTitle)
        if (c.tags && c.tags.length > 0) metaLines.push(c.tags.slice(0, 3).join('、'))
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
                                UI.Text({ content: c.title, style: { fontSize: 14, weight: 'bold' }, maxLines: 1 }),
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
                        onTap: UI.Navigate({ page: 'descriptor', method: 'getDetail', args: [c.id], title: c.title }),
                    }),
                ].filter((x) => x != null),
            }),
        })
    }

    // ============ 搜索 ============

    async search(keyword, page = 1) {
        let res
        try {
            let author
            if (keyword.startsWith('作者:')) {
                author = keyword.substring('作者:'.length).trim()
            }
            if (author && author in this.author_path_word_dict) {
                let path_word = encodeURIComponent(this.author_path_word_dict[author])
                res = await this._getJson(
                    `${this.apiUrl}/api/v3/comics?limit=30&offset=${(page - 1) * 30}&ordering=-datetime_updated&author=${path_word}`
                )
            } else {
                res = await this._getJson(
                    `${this.apiUrl}/api/v3/search/comic?platform=3&q=${encodeURIComponent(keyword)}&limit=20&offset=${(page - 1) * 20}&free_type=1&_update=true`
                )
            }
        } catch (e) {
            Dialog.showToast('搜索请求失败: ' + e)
            console.error('搜索请求失败: ' + e)
            return []
        }
        let list = (res['results'] && res['results']['list']) || []
        let cards = list.map((comic) => this._comicCard(this._parseComic(comic)))
        if (cards.length === 0 && page <= 1) {
            Dialog.showToast('未找到结果，请检查关键词')
        }
        return cards
    }

    // ============ 分类浏览 ============

    static category_param_dict = {
        "全部": "",
        "愛情": "aiqing",
        "歡樂向": "huanlexiang",
        "冒險": "maoxian",
        "奇幻": "qihuan",
        "百合": "baihe",
        "校园": "xiaoyuan",
        "科幻": "kehuan",
        "東方": "dongfang",
        "耽美": "danmei",
        "生活": "shenghuo",
        "格鬥": "gedou",
        "轻小说": "qingxiaoshuo",
        "其他": "qita",
        "悬疑": "xuanyi",
        "TL": "teenslove",
        "萌系": "mengxi",
        "神鬼": "shengui",
        "职场": "zhichang",
        "治愈": "zhiyu",
        "节操": "jiecao",
        "四格": "sige",
        "長條": "changtiao",
        "舰娘": "jianniang",
        "搞笑": "gaoxiao",
        "竞技": "jingji",
        "伪娘": "weiniang",
        "魔幻": "mohuan",
        "热血": "rexue",
        "性转换": "xingzhuanhuan",
        "美食": "meishi",
        "励志": "lizhi",
        "彩色": "COLOR",
        "後宮": "hougong",
        "侦探": "zhentan",
        "惊悚": "jingsong",
        "AA": "aa",
        "音乐舞蹈": "yinyuewudao",
        "异世界": "yishijie",
        "战争": "zhanzheng",
        "历史": "lishi",
        "机战": "jizhan",
        "都市": "dushi",
        "穿越": "chuanyue",
        "恐怖": "kongbu",
        "生存": "shengcun",
        "武侠": "wuxia",
        "宅系": "zhaixi",
        "转生": "zhuansheng",
        "無修正": "Uncensored",
        "仙侠": "xianxia",
        "LoveLive": "loveLive",
        "玄幻": "xuanhuan",
        "異能": "yineng",
        "遊戲": "youxi",
        "真人": "zhenren",
        "雜誌附贈寫真集": "zazhifuzengxiezhenji",
        "FATE": "fate",
    }

    static homepage_param_dict = {
        "全彩": "color",
        "韩漫": "korea",
        "单行本": "volume",
        "已完结": "finish",
        "同志": "yaoi",
    }

    /// 分类结构（venera 的 category）。
    getCategory() {
        return {
            title: '热辣漫画',
            parts: [
                { name: '免费漫画排行', categories: ['排行'] },
                { name: '免费漫画主题', categories: Object.keys(hot_manga.category_param_dict) },
                { name: '主页', categories: Object.keys(hot_manga.homepage_param_dict) },
            ],
        }
    }

    /// 分类筛选选项（venera 的 optionLoader 对应）
    getCategoryOptions(category) {
        let sortOptions = [
            { value: '*popular', text: '热度高' },
            { value: 'popular', text: '热度低' },
            { value: '*datetime_updated', text: '最新' },
            { value: 'datetime_updated', text: '历史' },
        ]
        if (category === '排行') {
            return [
                {
                    label: '地区',
                    options: [
                        { value: '-', text: '非韩漫' },
                        { value: '1', text: '韩漫' },
                    ],
                },
                {
                    label: '周期',
                    options: [
                        { value: 'week', text: '最近7天' },
                        { value: 'month', text: '最近30天' },
                        { value: 'total', text: '總榜單' },
                        { value: 'day', text: '上升最快' },
                    ],
                },
            ]
        }
        if (Object.keys(hot_manga.homepage_param_dict).includes(category)) {
            return [{ label: '排序', options: sortOptions }]
        }
        if (Object.keys(hot_manga.category_param_dict).includes(category)) {
            return [{ label: '排序', options: sortOptions }]
        }
        return null
    }

    /// 请求分类列表并解析（venera 的 categoryComics.load 逻辑）
    async _fetchCategoryComics(category, page = 1, options = []) {
        let category_url
        if (category === '排行') {
            let region = (options && options[0]) || '-'
            let date_type = (options && options[1]) || 'day'
            category_url = `${this.apiUrl}/api/v3/ranks?free_type=1&limit=30&offset=${(page - 1) * 30}&_update=true&type=1&region=${region}&date_type=${date_type}`
        } else if (Object.keys(hot_manga.homepage_param_dict).includes(category)) {
            let top = hot_manga.homepage_param_dict[category]
            let ordering = (options && options[0]) || '-datetime_updated'
            category_url = `${this.apiUrl}/api/v3/h5/homeIndex/comics?limit=20&offset=${(page - 1) * 20}&top=${top}&ordering=${ordering}`
        } else {
            let param = hot_manga.category_param_dict[category] || ''
            let ordering = (options && options[0]) || '-datetime_updated'
            ordering = ordering.replace('*', '-')
            category_url = `${this.apiUrl}/api/v3/comics?free_type=1&limit=30&offset=${(page - 1) * 30}&ordering=${ordering}&theme=${param}`
        }

        let data = await this._getJson(category_url)
        let results = data['results'] || {}
        let comics = (results['list'] || []).map((comic) => this._comicCard(this._parseComic(comic)))
        let total = results['total'] || 0
        let maxPage = (total - (total % 21)) / 21 + 1
        return { comics: comics, maxPage: maxPage }
    }

    /// 加载某分类第一页：返回分页容器（分页控制 + 声明单页数据来源）。
    async loadCategory(category, page = 1, options = []) {
        let { maxPage } = await this._fetchCategoryComics(category, page, options)
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
        let { comics } = await this._fetchCategoryComics(category, page, options)
        return comics
    }

    // ============ 详情 ============

    _comicId = ''
    _comicTitle = ''
    _chapters = []

    async getDetail(id) {
        let data
        try {
            data = await this._getJson(`${this.apiUrl}/api/v3/comic2/${id}?in_mainland=true&platform=3`)
            data = data['results']
        } catch (e) {
            Dialog.showToast('详情请求失败: ' + e)
            console.error('详情请求失败: ' + e)
            return []
        }
        let comicData = data['comic']

        let title = comicData['name']
        let cover = comicData['cover']
        let authors = (comicData['author'] || []).map((e) => e['name'])
        // author_path_word_dict 长度限制为最大 100
        if (Object.keys(this.author_path_word_dict).length > 100) {
            this.author_path_word_dict = {}
        }
        ;(comicData['author'] || []).forEach((e) => (this.author_path_word_dict[e['name']] = e['path_word']))
        let tags = (comicData['theme'] || []).map((e) => e && e['name']).filter((n) => n !== undefined && n !== null)
        let updateTime = comicData['datetime_updated'] ? comicData['datetime_updated'] : ''
        let description = comicData['brief'] || ''
        let status = (comicData['status'] && comicData['status']['display']) || ''

        // 章节：合并所有分组（venera 的新版多分组展示在 wyw 中简化合并）
        let chapters = []
        for (let group of Object.keys(data['groups'] || {})) {
            let path = data['groups'][group]['path_word']
            let eps = await this._fetchChapters(id, path)
            for (let e of eps) {
                chapters.push(e)
            }
        }

        this._comicId = id
        this._comicTitle = title
        this._chapters = chapters

        let items = []

        // 头部
        let metaLines = []
        if (authors.length > 0) metaLines.push('作者: ' + authors.join('、'))
        if (tags.length > 0) metaLines.push('标签: ' + tags.slice(0, 6).join('、'))
        if (status) metaLines.push('状态: ' + status)
        if (updateTime) metaLines.push('更新: ' + updateTime)
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
                        ...metaLines.map((m) => UI.Text({ content: m, style: { fontSize: 12, color: '#888888' }, maxLines: 1 })),
                    ],
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
            let epButtons = chapters.map((ep) =>
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

        PluginBrowse.open('hot_manga', {
            id: id,
            title: title,
            cover: cover,
            kv: { id: id },
        })

        return items
    }

    /// 拉取某分组章节（分页，最多 100/页）
    async _fetchChapters(id, path) {
        let eps = []
        let offset = 0
        let total = 0
        do {
            let res = await this._getJson(
                `${this.apiUrl}/api/v3/comic/${id}/group/${path}/chapters?limit=100&offset=${offset}`
            )
            let list = (res['results'] && res['results']['list']) || []
            for (let e of list) {
                eps.push({ id: e['uuid'], title: e['name'] })
            }
            total = res['results'] ? res['results']['total'] : 0
            offset += 100
        } while (offset < total)
        return eps
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
        let chapters = this._chapters.map((ep) => ({
            id: ep.id,
            title: ep.title,
            plugin: 'hot_manga',
            method: 'loadChapterImages',
            args: [this._comicId, ep.id],
        }))
        Navigator.navigateToReader({
            comicId: this._comicId,
            comicTitle: this._comicTitle,
            chapters: chapters,
            sourceKey: 'hot_manga',
            initialChapter: initialChapter,
            initialPage: 1,
        })
    }

    // ============ 章节图片（阅读器惰性加载） ============

    async loadChapterImages(comicId, epId) {
        let attempt = 0
        const maxAttempts = 5
        while (attempt < maxAttempts) {
            try {
                let res = await Network.get(
                    `${this.apiUrl}/api/v3/comic/${comicId}/chapter/${epId}?platform=3&_update=true`,
                    this.headers
                )
                let data = JSON.parse(res)
                let chapter = data['results'] && data['results']['chapter']
                if (!chapter) {
                    // 访问频繁（210）：响应体带 message，按提示等待后重试
                    let msg = data['message'] || ''
                    let waitTime = 40000
                    let match = msg.match(/(\d+)\s*seconds/)
                    if (match && match[1]) {
                        waitTime = parseInt(match[1]) * 1000
                    }
                    console.log(`章节 ${epId} 访问频繁，等待 ${waitTime / 1000}s`)
                    await new Promise((resolve) => setTimeout(resolve, waitTime))
                    attempt++
                    continue
                }
                let imagesUrls = chapter['contents'].map((e) => e['url'])
                // 替换为所选质量的图片地址
                return imagesUrls.map((url) =>
                    url.replace(/\.jpg\.h\d+x\.jpg$/, `.jpg.h${this.imageQuality}x.jpg`)
                )
            } catch (e) {
                if (attempt >= maxAttempts - 1) throw e
                attempt++
            }
        }
        throw '章节图片获取失败'
    }

    // ============ 浏览历史回放 ============

    async onOpenBrowseEntry(entry) {
        if (!entry || !entry.kv || !entry.kv.id) {
            Dialog.showToast('浏览历史无效')
            return
        }
        Navigator.navigateToDescriptor('hot_manga', {
            method: 'getDetail',
            args: [entry.kv.id],
            title: entry.title || '',
        })
    }

    // ============ 设置 ============

    settings = {
        image_quality: {
            title: '图片质量',
            type: 'select',
            options: [
                { value: '800', text: '低 (800)' },
                { value: '1200', text: '中 (1200)' },
                { value: '1500', text: '高 (1500)' },
            ],
            default: hot_manga.defaultImageQuality,
        },
        base_url: {
            title: 'API地址',
            type: 'input',
            validator: '^(?!:\\/\\/)(?=.{1,253})([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\\.)+[a-zA-Z]{2,}$',
            default: hot_manga.defaultApiUrl,
        },
    }
}
