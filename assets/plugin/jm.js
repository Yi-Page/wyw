
// description: 禁漫天堂（JM）漫画源 — 搜索/详情/章节/阅读（含切片还原）
// type: manga
//
// 接口约定：
//   search(keyword)  → List<UI.Card>
//   getDetail(id)    → List<UI>（头部 + 简介 + 章节列表）
//   openReader(epId) → Navigator.navigateToReader（章节惰性加载）
//   loadChapterImages(comicId, epId) → 该章图片 URL 数组
//   getImageLoadingConfig(url, comicId, epId) → {headers, modifyImage}
//
// 注意：JM 正文图带 token/referer 头，且部分章节图是打乱切片，
// 需要阅读器执行 modifyImage 脚本还原（wyw 已支持）。

class jm extends PluginSource {
    name = '禁漫天堂'
    key = 'jm'
    version = '1.0.0'

    static jmVersion = '2.0.16'
    static jmPkgName = 'com.example.app'

    static fallbackServers = [
        'www.cdntwice.org',
        'www.cdnsha.org',
        'www.cdnaspa.cc',
        'www.cdnntr.cc',
    ]

    static imageUrl = 'https://cdn-msp.jmapinodeudzn.net'
    static ua = 'Mozilla/5.0 (Linux; Android 10; K; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/130.0.0.0 Mobile Safari/537.36'

    // 运行时域名列表（从字节云刷新）。null 时回退到 fallbackServers。
    static apiDomains = null

    // 域名刷新源
    static domainSourceUrl = 'https://rup4a04-c02.tos-cn-hongkong.bytepluses.com/newsvr-2025.txt'
    static domainSecret = 'diosfjckwpqpdfjkvnqQjsik'

    /// 源网站地址（插件管理页「网站」菜单调用）
    getUrl() {
        return this.baseUrl
    }

    // 分类映射：week=每週必看（期数/类型）；category=用 slug 调 categories/filter；
    // 未列出的分类默认走搜索接口（search?search_query=分类名）。
    static categoryMap = {
        '每週必看': { type: 'week' },
        '最新A漫': { type: 'category', slug: '0' },
        '同人': { type: 'category', slug: 'doujin' },
        '單本': { type: 'category', slug: 'single' },
        '短篇': { type: 'category', slug: 'short' },
        '其他類': { type: 'category', slug: 'another' },
        '韓漫': { type: 'category', slug: 'hanman' },
        '美漫': { type: 'category', slug: 'meiman' },
        'Cosplay': { type: 'category', slug: 'another_cosplay' },
        '3D': { type: 'category', slug: '3D' },
        '禁漫漢化組': { type: 'category', slug: '禁漫漢化組' },
    }

    settings = {
        apiDomain: {
            title: 'Api域名',
            type: 'select',
            options: [
                { value: '1', text: '线路 1' },
                { value: '2', text: '线路 2' },
                { value: '3', text: '线路 3' },
                { value: '4', text: '线路 4' },
            ],
            default: '1',
        },
        imageStream: {
            title: '图片分流',
            type: 'select',
            options: [
                { value: '1', text: '分流 1' },
                { value: '2', text: '分流 2' },
                { value: '3', text: '分流 3' },
                { value: '4', text: '分流 4' },
            ],
            default: '1',
        },
    }

    // ============ 域名 / 图片域名 ============

    get ua() {
        return jm.ua
    }

    get baseUrl() {
        let index = parseInt(this.loadSetting('apiDomain')) - 1
        let domains = jm.apiDomains || jm.fallbackServers
        if (index < 0 || index >= domains.length) index = 0
        return 'https://' + domains[index]
    }

    get imageUrl() {
        return jm.imageUrl
    }

    overwriteImgUrl(url) {
        if (url && url.length !== 0) jm.imageUrl = url
    }

    _imgUrlRefreshed = false

    _domainsRefreshed = false

    /// 从字节云刷新 API 域名列表（JM 官方机制，域名经常变动）。
    /// 失败时静默，继续用 fallbackServers。
    async refreshApiDomains() {
        let txt
        try {
            txt = await Network.get(jm.domainSourceUrl, this.baseHeaders)
        } catch (e) {
            return
        }
        try {
            let json = JSON.parse(this.convertData(txt, jm.domainSecret))
            if (json['Server'] && json['Server'].length > 0) {
                jm.apiDomains = json['Server'].slice(0, 4)
            }
        } catch (e) {
            // 静默
        }
    }

    async ensureDomains() {
        if (this._domainsRefreshed) return
        this._domainsRefreshed = true
        await this.refreshApiDomains()
    }

    async ensureImgUrl() {
        if (this._imgUrlRefreshed) return
        this._imgUrlRefreshed = true
        try {
            let index = this.loadSetting('imageStream')
            let res = await this.get(
                this.baseUrl + '/setting?app_img_shunt=' + index + '&express='
            )
            let setting = JSON.parse(res)
            if (setting['img_host']) {
                this.overwriteImgUrl(setting['img_host'])
            }
        } catch (e) {
            // 静默：沿用默认图片域名
        }
    }

    // ============ 请求头 ============

    get baseHeaders() {
        return {
            'Accept': '*/*',
            'Accept-Encoding': 'gzip, deflate, br, zstd',
            'Accept-Language': 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
            'Connection': 'keep-alive',
            'Origin': 'https://localhost',
            'Referer': 'https://localhost/',
            'Sec-Fetch-Dest': 'empty',
            'Sec-Fetch-Mode': 'cors',
            'Sec-Fetch-Site': 'cross-site',
            'X-Requested-With': jm.jmPkgName,
        }
    }

    getApiHeaders(time) {
        const jmAuthKey = '18comicAPPContent'
        let token = Convert.md5(Convert.encodeUtf8(time + jmAuthKey))
        return {
            ...this.baseHeaders,
            'Authorization': 'Bearer',
            'Sec-Fetch-Storage-Access': 'active',
            'token': Convert.hexEncode(token),
            'tokenparam': time + ',' + jm.jmVersion,
            'User-Agent': this.ua,
        }
    }

    getImgHeaders() {
        return {
            'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
            'Accept-Encoding': 'gzip, deflate, br, zstd',
            'Accept-Language': 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
            'Connection': 'keep-alive',
            'Referer': 'https://localhost/',
            'Sec-Fetch-Dest': 'image',
            'Sec-Fetch-Mode': 'no-cors',
            'Sec-Fetch-Site': 'cross-site',
            'Sec-Fetch-Storage-Access': 'active',
            'User-Agent': this.ua,
            'X-Requested-With': jm.jmPkgName,
        }
    }

    // ============ URL 构造 ============

    getCoverUrl(id) {
        return this.imageUrl + '/media/albums/' + id + '_3x4.jpg'
    }

    getImageUrl(id, imageName) {
        return this.imageUrl + '/media/photos/' + id + '/' + imageName
    }

    // ============ 加密解密 ============

    convertData(input, secret) {
        let key = Convert.encodeUtf8(Convert.hexEncode(Convert.md5(Convert.encodeUtf8(secret))))
        let data = Convert.decodeBase64(input)
        let decrypted = Convert.decryptAesEcb(data, key)
        let res = Convert.decodeUtf8(decrypted)
        let start = 0
        while (start < res.length && res[start] !== '{' && res[start] !== '[') {
            start++
        }
        let end = res.length - 1
        while (end > start && res[end] !== '}' && res[end] !== ']') {
            end--
        }
        return res.substring(start, end + 1)
    }

    async get(url) {
        let time = Math.floor(Date.now() / 1000)
        let kJmSecret = '185Hcomic3PAPP7R'
        let res = await Network.get(url, this.getApiHeaders(time))
        // wyw 的 Network.get 直接返回 body 字符串
        let json = JSON.parse(res)
        let data = json.data
        if (typeof data !== 'string') {
            throw 'Invalid Data'
        }
        return this.convertData(data, time + kJmSecret)
    }

    // ============ 工具 ============

    _parseComic(comic) {
        let id = comic.id.toString()
        let tags = []
        if (comic['category'] && comic['category']['title']) tags.push(comic['category']['title'])
        if (comic['category_sub'] && comic['category_sub']['title']) tags.push(comic['category_sub']['title'])
        return {
            id: id,
            title: comic.name,
            subTitle: comic.author || '',
            cover: this.getCoverUrl(id),
            tags: tags,
            description: comic.description || '',
        }
    }

    _absUrl(url) {
        if (!url) return ''
        if (url.startsWith('http://') || url.startsWith('https://')) return url
        return 'https:' + url
    }

    // ============ 搜索 ============

    async search(keyword, page = 1) {
        await this.ensureDomains()
        await this.ensureImgUrl()
        keyword = keyword.trim()
        keyword = encodeURIComponent(keyword).replace(/%20/g, '+')
        let url = this.baseUrl + '/search?search_query=' + keyword + '&o=mr'
        if (page > 1) {
            url += '&page=' + page
        }
        let res
        try {
            res = await this.get(url)
        } catch (e) {
            console.error('搜索请求失败: ' + e)
            return []
        }
        let data = JSON.parse(res)
        let list = data.content || []
        let cards = []
        for (let comic of list) {
            let c = this._parseComic(comic)
            let cover = this._absUrl(c.cover)
            cards.push(
                UI.Card({
                    elevation: 0,
                    shapeRadius: 16,
                    color: '@theme:surfaceContainerLow',
                    padding: 4,
                    child: UI.Row({
                        crossAxisAlignment: 'start',
                        children: [
                            cover ? UI.Image({ src: cover, width: 80, height: 116, headers: this.getImgHeaders() }) : null,
                            UI.SizedBox({ width: 12 }),
                            UI.Expanded({
                                child: UI.Column({
                                    crossAxisAlignment: 'start',
                                    mainAxisAlignment: 'start',
                                    children: [
                                        UI.Text({ content: c.title, style: { fontSize: 14, weight: 'bold' }, maxLines: 2 }),
                                        c.subTitle ? UI.Text({ content: c.subTitle, style: { fontSize: 12, color: '#888888' }, maxLines: 1 }) : null,
                                        c.tags.length > 0 ? UI.Text({ content: c.tags.join('、'), style: { fontSize: 11, color: '#666666' }, maxLines: 2 }) : null,
                                    ].filter((x) => x != null),
                                }),
                            }),
                            UI.SizedBox({ width: 8 }),
                            UI.IconButton({
                                icon: 'open_in_new',
                                tooltip: '详情',
                                color: '#666666',
                                size: 20,
                                onTap: UI.Navigate({
                                    page: 'descriptor',
                                    method: 'getDetail',
                                    args: [c.id],
                                    title: c.title,
                                }),
                            }),
                        ].filter((x) => x != null),
                    }),
                })
            )
        }
        if (cards.length === 0 && page <= 1) {
            Dialog.showToast('未找到结果，请检查关键词')
        }
        return cards
    }

    // ============ 分类浏览 ============

    /// 构造漫画卡片（搜索/分类共用）。
    _comicCard(c) {
        let cover = this._absUrl(c.cover)
        return UI.Card({
            elevation: 0,
            shapeRadius: 16,
            color: '@theme:surfaceContainerLow',
            padding: 4,
            child: UI.Row({
                crossAxisAlignment: 'start',
                children: [
                    cover ? UI.Image({ src: cover, width: 80, height: 116, headers: this.getImgHeaders() }) : null,
                    UI.SizedBox({ width: 12 }),
                    UI.Expanded({
                        child: UI.Column({
                            crossAxisAlignment: 'start',
                            mainAxisAlignment: 'start',
                            children: [
                                UI.Text({ content: c.title, style: { fontSize: 14, weight: 'bold' }, maxLines: 2 }),
                                c.subTitle ? UI.Text({ content: c.subTitle, style: { fontSize: 12, color: '#888888' }, maxLines: 1 }) : null,
                                c.tags.length > 0 ? UI.Text({ content: c.tags.join('、'), style: { fontSize: 11, color: '#666666' }, maxLines: 2 }) : null,
                            ].filter((x) => x != null),
                        }),
                    }),
                    UI.SizedBox({ width: 8 }),
                    UI.IconButton({
                        icon: 'open_in_new',
                        tooltip: '详情',
                        color: '#666666',
                        size: 20,
                        onTap: UI.Navigate({
                            page: 'descriptor',
                            method: 'getDetail',
                            args: [c.id],
                            title: c.title,
                        }),
                    }),
                ].filter((x) => x != null),
            }),
        })
    }

    /// 分类结构（venera 的 category）。
    getCategory() {
        return {
            title: '禁漫天堂',
            parts: [
                { name: '每週必看', categories: ['每週必看'] },
                { name: '成人A漫', categories: ['最新A漫', '同人', '單本', '短篇', '其他類', '韓漫', '美漫', 'Cosplay', '3D', '禁漫漢化組'] },
                { name: '主題A漫', categories: ['無修正', '劇情向', '青年漫', '校服', '純愛', '人妻', '教師', '百合', 'Yaoi', '性轉', 'NTR', '女裝', '癡女', '全彩', '女性向', '完結', '禁漫漢化組'] },
                { name: '角色扮演', categories: ['御姐', '熟女', '巨乳', '貧乳', '女性支配', '教師', '女僕', '護士', '泳裝', '眼鏡', '連褲襪', '其他制服', '兔女郎'] },
                { name: '特殊PLAY', categories: ['群交', '足交', '束縛', '肛交', '阿黑顏', '藥物', '扶他', '調教', '野外露出', '催眠', '自慰', '觸手', '獸交', '亞人', '怪物女孩', '皮物', 'ryona', '騎大車'] },
                { name: '特殊PLAY', categories: ['CG', '重口', '獵奇', '非H', '血腥暴力', '站長推薦'] },
            ],
        }
    }

    /// 获取某分类的筛选选项（venera 的 optionLoader 对应）。
    /// 每週必看：期数 + 类型；其他分类：排序。
    async getCategoryOptions(category) {
        if (category !== '每週必看') {
            return [
                {
                    label: '排序',
                    options: [
                        { value: 'mr', text: '最新' },
                        { value: 'mv', text: '總排行' },
                        { value: 'mv_m', text: '月排行' },
                        { value: 'mv_w', text: '周排行' },
                        { value: 'mv_t', text: '日排行' },
                        { value: 'mp', text: '最多圖片' },
                        { value: 'tf', text: '最多喜歡' },
                    ],
                },
            ]
        }
        let res = await this.get(`${this.baseUrl}/week`)
        let data = JSON.parse(res)
        let periodOptions = (data.categories || []).map((e) => ({
            value: e.id,
            text: e.time,
        }))
        if (periodOptions.length === 0) return null
        return [
            {
                label: '期数',
                options: periodOptions,
            },
            {
                label: '类型',
                options: [
                    { value: 'manga', text: '日漫' },
                    { value: 'hanman', text: '韓漫' },
                    { value: 'another', text: '其他' },
                ],
            },
        ]
    }

    /// 加载某分类的漫画（venera 的 categoryComics.load 逻辑）。
    /// 返回 `{comics, maxPage}`，供 [loadCategory] / [loadCategoryPage] 共用。
    ///
    /// 分类分三种请求方式（见 [categoryMap]）：
    ///   - week：每週必看（单页，忽略 page）
    ///   - category：categories/filter 需用英文 slug（中文名会被接口忽略返回默认）
    ///   - search（默认）：search?search_query=分类名
    async _fetchCategoryComics(category, page = 1, options = []) {
        await this.ensureDomains()
        let comics = []
        let maxPage = 1
        const meta = jm.categoryMap[category] || { type: 'search' }
        if (meta.type === 'week') {
            // 每週必看是单页数据（接口忽略 page 参数），page > 1 无更多
            if (page > 1) return { comics: [], maxPage: 1 }
            let id = (options && options.length > 0) ? options[0] : '0'
            let type = (options && options.length > 1) ? options[1] : 'manga'
            let res = await this.get(`${this.baseUrl}/week/filter?id=${id}&type=${type}&page=0`)
            let data = JSON.parse(res)
            comics = data.list || []
        } else {
            // category（用 slug 调 categories/filter）与 search（用搜索接口）共用排序参数
            let order = (options && options.length > 0) ? options[0] : 'mv'
            let res
            if (meta.type === 'category') {
                res = await this.get(`${this.baseUrl}/categories/filter?o=${order}&c=${encodeURIComponent(meta.slug)}&page=${page}`)
            } else {
                res = await this.get(`${this.baseUrl}/search?search_query=${encodeURIComponent(category)}&o=${order}&page=${page}`)
            }
            let data = JSON.parse(res)
            comics = data.content || []
            maxPage = Math.ceil((data.total || 0) / 80)
        }
        return { comics: comics, maxPage: maxPage }
    }

    /// 加载某分类第一页：返回分页容器（分页控制 + 声明单页数据来源）。
    /// 本页内容由 renderer 首次渲染时调用 `pageMethod` 加载，无需传 children。
    async loadCategory(category, page = 1, options = []) {
        const { maxPage } = await this._fetchCategoryComics(category, page, options)
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
        const { comics } = await this._fetchCategoryComics(category, page, options)
        return comics.map((e) => this._comicCard(this._parseComic(e)))
    }

    // ============ 详情 ============

    _comicId = ''
    _comicTitle = ''
    _chapters = []

    async getDetail(id) {
        await this.ensureDomains()
        if (id.startsWith('jm')) {
            id = id.substring(2)
        }
        let res
        try {
            res = await this.get(this.baseUrl + '/album?id=' + id)
        } catch (e) {
            Dialog.showToast('详情请求失败: ' + e)
            console.error('详情请求失败: ' + e)
            return []
        }
        let data = JSON.parse(res)

        this._comicId = id
        this._comicTitle = data.name
        this._chapters = []

        // 章节：series 按 sort 排序
        let series = (data.series || []).sort((a, b) => a.sort - b.sort)
        let chapters = []
        for (let e of series) {
            let title = (e.name || '').trim()
            if (title.length === 0) {
                title = '第' + e['sort'] + '话'
            }
            chapters.push({ id: e.id.toString(), title: title })
        }
        if (chapters.length === 0) {
            chapters.push({ id: id, title: '第1话' })
        }
        this._chapters = chapters

        let title = data.name
        let cover = this.getCoverUrl(id)
        let authors = data.author || []
        let tags = data.tags || []
        let description = data.description || ''
        let updateDate = ''
        if (data.addtime) {
            let date = new Date(data.addtime * 1000)
            updateDate = date.getFullYear() + '-' + (date.getMonth() + 1) + '-' + date.getDate()
        }

        let items = []

        // 头部
        let headerChildren = []
        if (cover) {
            headerChildren.push(UI.Image({ src: this._absUrl(cover), width: 110, height: 150, headers: this.getImgHeaders() }))
            headerChildren.push(UI.SizedBox({ width: 12 }))
        }
        let metaLines = []
        if (authors.length > 0) metaLines.push('作者: ' + authors.join('、'))
        if (tags.length > 0) metaLines.push('标签: ' + tags.join('、'))
        if (updateDate) metaLines.push('更新: ' + updateDate)
        headerChildren.push(
            UI.Expanded({
                child: UI.Column({
                    crossAxisAlignment: 'start',
                    mainAxisAlignment: 'start',
                    children: [
                        UI.Text({ content: title, style: { fontSize: 16, weight: 'bold' }, maxLines: 2 }),
                        UI.SizedBox({ height: 6 }),
                        ...metaLines.map((m) => UI.Text({ content: m, style: { fontSize: 12, color: '#888888' }, maxLines: 3 })),
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

        PluginBrowse.open('jm', {
            id: id,
            title: title,
            cover: cover,
            kv: { id: id },
        })

        return items
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
            plugin: 'jm',
            method: 'loadChapterImages',
            args: [this._comicId, ep.id],
        }))
        Navigator.navigateToReader({
            comicId: this._comicId,
            comicTitle: this._comicTitle,
            chapters: chapters,
            sourceKey: 'jm',
            initialChapter: initialChapter,
            initialPage: 1,
        })
    }

    // ============ 章节图片（阅读器惰性加载）============

    async loadChapterImages(comicId, epId) {
        let res = await this.get(this.baseUrl + '/chapter?id=' + epId)
        let data = JSON.parse(res)
        return data.images.map((e) => this.getImageUrl(epId, e))
    }

    // ============ 图片加载配置（headers + 切片还原）============

    getImageLoadingConfig(url, comicId, epId) {
        const scrambleId = 220980
        let pictureName = ''
        for (let i = url.length - 1; i >= 0; i--) {
            if (url[i] === '/') {
                pictureName = url.substring(i + 1, url.length - 5)
                break
            }
        }
        epId = Number(epId)
        let num = 0
        if (epId < scrambleId) {
            num = 0
        } else if (epId < 268850) {
            num = 10
        } else if (epId > 421926) {
            let str = epId.toString() + pictureName
            let bytes = Convert.encodeUtf8(str)
            let hash = Convert.md5(bytes)
            let hashStr = Convert.hexEncode(hash)
            let charCode = hashStr.charCodeAt(hashStr.length - 1)
            let remainder = charCode % 8
            num = remainder * 2 + 2
        } else {
            let str = epId.toString() + pictureName
            let bytes = Convert.encodeUtf8(str)
            let hash = Convert.md5(bytes)
            let hashStr = Convert.hexEncode(hash)
            let charCode = hashStr.charCodeAt(hashStr.length - 1)
            let remainder = charCode % 10
            num = remainder * 2 + 2
        }
        if (num <= 1) {
            return {}
        }
        return {
            headers: this.getImgHeaders(),
            // gif 图片不需要修改
            modifyImage: url.endsWith('.gif') ? null : `
                let modifyImage = (image) => {
                    const num = ${num}
                    let blockSize = Math.floor(image.height / num)
                    let remainder = image.height % num
                    let blocks = []
                    for(let i = 0; i < num; i++) {
                        let start = i * blockSize
                        let end = start + blockSize + (i !== num - 1 ? 0 : remainder)
                        blocks.push({
                            start: start,
                            end: end
                        })
                    }
                    let res = Image.empty(image.width, image.height)
                    let y = 0
                    for(let i = blocks.length - 1; i >= 0; i--) {
                        let block = blocks[i]
                        let currentHeight = block.end - block.start
                        res.fillImageRangeAt(0, y, image, 0, block.start, image.width, currentHeight)
                        y += currentHeight
                    }
                    return res
                }
            `,
        }
    }

    // ============ 浏览历史回放 ============

    async onOpenBrowseEntry(entry) {
        if (!entry || !entry.kv || !entry.kv.id) {
            Dialog.showToast('浏览历史无效')
            return
        }
        Navigator.navigateToDescriptor('jm', {
            method: 'getDetail',
            args: [entry.kv.id],
            title: entry.title || '',
        })
    }
}
