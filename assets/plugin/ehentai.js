
// description: E-Hentai 漫画源 — 搜索/详情/阅读（图片经 API 分页获取）
// type: manga
//
// 接口约定：
//   search(keyword, page)  → List<UI.Card>
//   getDetail(id)          → List<UI>（头部 + 简介 + 阅读按钮）
//   openReader(epId)       → Navigator.navigateToReader（章节惰性加载）
//   loadChapterImages(comicId, epId) → 该章图片 URL 数组（经 showpage/imagedispatch API 获取）
//   getImageLoadingConfig(url, comicId, epId) → {headers}（referer）
//
// 注意：
//   - id 为完整画廊 URL（https://e-hentai.org/g/{gid}/{token}/）
//   - 图片原图地址需逐页调用 API（带临时 token），首次进入阅读器时按页顺序预取
//   - exhentai 域需要登录 Cookie 才能访问，wyw 暂无 Cookie API，请使用 e-hentai.org 域

class ehentai extends PluginSource {
    name = 'E-Hentai'
    key = 'ehentai'
    version = '1.0.0'

    settings = {
        domain: {
            title: '域名',
            type: 'select',
            options: [
                { value: 'e-hentai.org' ,text: 'e-hentai' },
                { value: 'exhentai.org' ,text: 'exhentai' },
            ],
            default: 'e-hentai.org',
        },
    }

    // 运行时缓存（getDetail 时填充，loadChapterImages 复用）
    _comicId = null
    _maxPage = 0
    _apikey = null
    _uid = null

    get baseUrl() {
        // 设置未保存过时 loadSetting 返回空值，兜底到默认域名
        let domain = this.loadSetting('domain')
        if (!domain) domain = 'e-hentai.org'
        return 'https://' + domain
    }

    get apiUrl() {
        return this.baseUrl.includes('exhentai')
            ? 'https://exhentai.org/api.php'
            : 'https://api.e-hentai.org/api.php'
    }

    /// 源网站地址（插件管理页「网站」菜单调用）
    getUrl() {
        return this.baseUrl
    }

    // ============ 工具 ============

    /// 解析画廊 URL → {id, token}
    parseUrl(url) {
        let segments = url.split('/')
        return {
            id: segments[4],
            token: segments[5],
        }
    }

    /// 从 CSS background-position 解析星级（0.5 - 5）
    getStarsFromPosition(position) {
        let i = 0
        while (position[i] !== ';' && i < position.length) i++
        switch (position.substring(0, i)) {
            case 'background-position:0px -1px': return 5
            case 'background-position:0px -21px': return 4.5
            case 'background-position:-16px -1px': return 4
            case 'background-position:-16px -21px': return 3.5
            case 'background-position:-32px -1px': return 3
            case 'background-position:-32px -21px': return 2.5
            case 'background-position:-48px -1px': return 2
            case 'background-position:-48px -21px': return 1.5
            case 'background-position:-64px -1px': return 1
            case 'background-position:-64px -21px': return 0.5
        }
        return 0.5
    }

    /// 请求 HTML（wyw 的 Network.get 直接返回 body 字符串）
    async _getHtml(url) {
        let res = await Network.get(url, {})
        if (res == null || res.trim().length === 0) {
            throw '空响应，可能没有权限访问该页面'
        }
        if (res.trim()[0] !== '<') {
            if (res.includes('IP')) throw '您的 IP 已被封禁'
            throw '页面加载失败'
        }
        return res
    }

    // ============ 搜索 ============

    /// 解析单个搜索结果（兼容四种列表模式）
    _parseGalleryItem(item) {
        let link = item.querySelector('a[href*="/g/"]')
        if (!link) return null
        let cover = null
        let img = item.querySelector('img')
        if (img) {
            cover = img.attributes['src'] || ''
            if (cover[0] === 'd') cover = img.attributes['data-src'] || ''
        }
        let title = link.attributes['title'] || ''
        if (!title) {
            let glink = item.querySelector('div.glink')
            if (glink) title = glink.text || ''
        }
        if (!title) title = item.attributes['title'] || ''
        if (!title) return null

        let stars = null
        let starsEl = item.querySelector('div.ir')
        if (starsEl) stars = this.getStarsFromPosition(starsEl.attributes['style'] || '')

        let pages = 0
        for (let d of item.querySelectorAll('div')) {
            if (d.text && d.text.includes('page')) {
                let m = d.text.match(/\d+/)
                if (m) { pages = Number(m[0]); break }
            }
        }
        let time = null
        for (let d of item.querySelectorAll('div')) {
            if (d.text && !isNaN(Date.parse(d.text))) { time = d.text; break }
        }
        let tags = []
        for (let e of item.querySelectorAll('div.gt, div.gtl')) {
            tags.push(e.attributes['title'] || '')
        }
        return {
            id: link.attributes['href'] || '',
            title: title,
            cover: cover,
            stars: stars,
            pages: pages,
            time: time,
            tags: tags,
        }
    }

    /// 抓取列表页 HTML 并解析为卡片列表（search / loadCategory 共用）
    async _buildCards(url, emptyHint) {
        let html
        try {
            html = await this._getHtml(url)
        } catch (e) {
            Dialog.showToast((emptyHint || '请求') + '失败: ' + e)
            console.error((emptyHint || '请求') + '失败: ' + e)
            return []
        }
        let doc = new HtmlDocument(html)
        let cards = []

        let containers = doc.querySelectorAll('table.itg tbody tr, div.gl1t')
        for (let item of containers) {
            try {
                let parsed = this._parseGalleryItem(item)
                if (!parsed || !parsed.id) continue
                let metaLines = []
                if (parsed.stars) metaLines.push('★' + parsed.stars)
                if (parsed.pages > 0) metaLines.push(parsed.pages + ' 页')
                if (parsed.time) metaLines.push(parsed.time)
                if (parsed.tags && parsed.tags.length > 0) metaLines.push(parsed.tags.slice(0, 3).join('、'))

                cards.push(UI.Card({
                    elevation: 0,
                    shapeRadius: 16,
                    color: '@theme:surfaceContainerLow',
                    padding: 4,
                    child: UI.Row({
                        crossAxisAlignment: 'start',
                        children: [
                            parsed.cover ? UI.Image({ src: parsed.cover, width: 80, height: 116 }) : null,
                            UI.SizedBox({ width: 12 }),
                            UI.Expanded({
                                child: UI.Column({
                                    crossAxisAlignment: 'start',
                                    mainAxisAlignment: 'start',
                                    children: [
                                        UI.Text({ content: parsed.title, style: { fontSize: 14, weight: 'bold' }, maxLines: 1 }),
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
                                onTap: UI.Navigate({ page: 'descriptor', method: 'getDetail', args: [parsed.id], title: parsed.title }),
                            }),
                        ].filter((x) => x != null),
                    }),
                }))
            } catch (e) {
                continue
            }
        }

        doc.dispose()
        return cards
    }

    async search(keyword, page = 1) {
        let url = `${this.baseUrl}/?f_search=${encodeURIComponent(keyword)}`
        if (page > 1) url += `&page=${page - 1}`
        let cards = await this._buildCards(url, '搜索')
        if (cards.length === 0 && page <= 1) {
            Dialog.showToast('未找到结果，请检查关键词')
        }
        return cards
    }

    // ============ 分类浏览 ============

    /// 分类结构（venera 的 category）。
    getCategory() {
        return {
            title: 'ehentai',
            parts: [
                { name: '站点', categories: ['最新', '热门'] },
                { name: '内容分类', categories: ['Doujinshi', 'Manga', 'Artist CG', 'Game CG', 'Image Set', 'Cosplay', 'Asian Porn', 'Non-H', 'Western', 'Misc'] },
            ],
        }
    }

    /// 分类无额外筛选选项（eh 列表仅有最新/热门两种排序，已作为分类入口）
    getCategoryOptions(category) {
        return null
    }

    /// 构造分类列表页 URL（page 1-based，eh 分页 0-based）
    _categoryUrl(category, page) {
        let url
        if (category === '最新') {
            url = this.baseUrl + '/'
        } else if (category === '热门') {
            url = this.baseUrl + '/popular'
        } else {
            // f_cats 位掩码：1023=全部显示，某位清 0 即排除该分类
            let idx = ['Doujinshi', 'Manga', 'Artist CG', 'Game CG', 'Image Set', 'Cosplay', 'Asian Porn', 'Non-H', 'Western', 'Misc'].indexOf(category)
            if (idx < 0) return null
            let fcats = 1023 - (1 << idx)
            url = this.baseUrl + '/?f_cats=' + fcats
        }
        if (page > 1) {
            url += (url.includes('?') ? '&' : '?') + 'page=' + (page - 1)
        }
        return url
    }

    /// 加载某分类第一页：返回分页容器（分页控制 + 声明单页数据来源）。
    /// 本页内容由 renderer 首次渲染时调用 pageMethod 加载，无需传 children。
    async loadCategory(category, page = 1, options = []) {
        return [
            UI.Pagination({
                page: page,
                maxPage: 200,
                pageMethod: 'loadCategoryPage',
                pageArgs: [category, 1, options],
            }),
        ]
    }

    /// 加载某分类指定页：返回**单纯的结果列表**（UI.Pagination 换页时调用）。
    async loadCategoryPage(category, page = 1, options = []) {
        let url = this._categoryUrl(category, page)
        if (!url) return []
        return await this._buildCards(url, '浏览')
    }

    // ============ 详情 ============

    /// 加载画廊详情并缓存元数据/token（内部使用）
    async _loadInfo(id) {
        let html = await this._getHtml(id)
        let doc = new HtmlDocument(html)

        let maxPage = 1
        for (let element of doc.querySelectorAll('td.gdt2')) {
            if (element.text.includes('page')) {
                maxPage = Number(element.text.match(/\d+/)[0])
            }
        }

        let coverPath = null
        let coverDiv = doc.querySelector('div#gleft > div#gd1 > div')
        if (coverDiv) {
            let style = coverDiv.attributes['style'] || ''
            let m = RegExp('https?://([-a-zA-Z0-9.]+(/\\S*)?\\.(?:jpg|jpeg|gif|png|webp))').exec(style)
            if (m) coverPath = m[0]
        }

        // 元数据
        let titleEl = doc.querySelector('h1#gn')
        let title = titleEl ? (titleEl.text || '').trim() : ''
        let subtitleEl = doc.querySelector('h1#gj')
        let subtitle = subtitleEl ? (subtitleEl.text || '').trim() : ''
        if (!subtitle) subtitle = null
        let uploaderEl = doc.getElementById('gdn')
        let uploader = uploaderEl && uploaderEl.children && uploaderEl.children.length > 0
            ? (uploaderEl.children[0].text || '').trim()
            : ''
        let ratingEl = doc.getElementById('rating_label')
        let stars = null
        if (ratingEl && ratingEl.text) {
            let parts = ratingEl.text.split(':')
            if (parts.length > 1) stars = Number(parts[1].trim())
        }
        let timeEl = doc.querySelector('div#gdd > table > tbody > tr > td.gdt2')
        let time = timeEl ? (timeEl.text || '').trim() : ''

        // 标签（namespace → 标签列表）
        let tags = []
        for (let tr of doc.querySelectorAll('div#taglist > table > tbody > tr')) {
            try {
                let ns = (tr.children[0].text || '').trim()
                ns = ns.substring(0, ns.length - 1) // 去掉末尾 ':'
                for (let e of tr.children[1].children) {
                    let name = e.children[0] ? (e.children[0].text || '').trim() : ''
                    if (name) tags.push(ns + ':' + name)
                }
            } catch (e) { continue }
        }

        let script = doc.querySelectorAll('script').find((e) => e.text.includes('var token'))
        let reg = RegExp('var\\s+(\\w+)\\s*=\\s*(.*?);', 'g')
        let variables = new Map()
        if (script) {
            for (let match of script.text.matchAll(reg)) {
                variables.set(match[1], match[2])
            }
        }

        let apikey = variables.get('apikey')
        if (apikey && apikey[0] === '"') {
            apikey = apikey.substring(1, apikey.length - 1)
        }

        this._comicId = id
        this._maxPage = maxPage
        this._apikey = apikey
        this._uid = variables.get('apiuid')
        this._comicTitle = title || 'E-Hentai'
        // 切换漫画时重置图片惰性加载缓存
        this._pageImageCache = new Map()
        this._keyCache = null
        this._nl = null
        this._nlPage = -1

        doc.dispose()
        return { maxPage, coverPath, title, subtitle, uploader, stars, time, tags }
    }

    async getDetail(id) {
        let info
        try {
            info = await this._loadInfo(id)
        } catch (e) {
            Dialog.showToast('详情请求失败: ' + e)
            console.error('详情请求失败: ' + e)
            return []
        }
        let items = []
        let title = info.title || 'E-Hentai'

        // 头部：封面 + 标题 + 元信息
        let metaLines = []
        if (info.subtitle) metaLines.push(info.subtitle)
        if (info.uploader) metaLines.push('上传者: ' + info.uploader)
        if (info.stars) metaLines.push('★' + info.stars)
        metaLines.push(info.maxPage + ' 页')
        if (info.time) metaLines.push(info.time)

        let headerChildren = []
        if (info.coverPath) {
            headerChildren.push(UI.Image({ src: info.coverPath, width: 110, height: 150 }))
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

        // 标签
        if (info.tags && info.tags.length > 0) {
            items.push(
                UI.Card({
                    padding: 12,
                    shapeRadius: 8,
                    child: UI.Wrap({
                        spacing: 6,
                        runSpacing: 6,
                        children: info.tags.slice(0, 40).map((tag) =>
                            UI.Text({ content: tag, style: { fontSize: 12, color: '#666666' }, maxLines: 1 })
                        ),
                    }),
                })
            )
        }

        // 阅读按钮
        items.push(UI.Card({
            padding: 12,
            shapeRadius: 8,
            child: UI.Button({
                label: '▶ 开始阅读',
                style: 'filled',
                onTap: UI.Action({ method: 'openReader', args: [id] }),
            }),
        }))

        PluginBrowse.open('ehentai', {
            id: id,
            title: title,
            cover: info.coverPath,
            kv: { id: id },
        })

        return items
    }

    // ============ 浏览历史回放 ============

    async onOpenBrowseEntry(entry) {
        if (!entry || !entry.kv || !entry.kv.id) {
            Dialog.showToast('浏览历史无效')
            return
        }
        Navigator.navigateToDescriptor('ehentai', {
            method: 'getDetail',
            args: [entry.kv.id],
            title: entry.title || '',
        })
    }

    // ============ 进入阅读器 ============

    async openReader(epId) {
        if (!this._comicId) {
            await this._loadInfo(epId)
        }
        Navigator.navigateToReader({
            comicId: this._comicId,
            comicTitle: this._comicTitle || 'E-Hentai',
            chapters: [{
                id: this._comicId,
                title: '开始阅读',
                plugin: 'ehentai',
                method: 'loadChapterImages',
                args: [this._comicId],
            }],
            sourceKey: 'ehentai',
            initialChapter: 1,
            initialPage: 1,
        })
    }

    // ============ 章节图片（阅读器惰性加载，API 逐页获取） ============

    async _loadThumbnails(id, next) {
        let url = id
        if (next != null) url += `?p=${next}`
        let html = await this._getHtml(url)
        let doc = new HtmlDocument(html)

        let parseImageUrl = (e) => {
            let style = e.attributes['style'] || ''
            let r = style.split('background:transparent url(')[1]
            if (!r) return ''
            return r.split(')')[0]
        }

        let images = doc.querySelectorAll('div.gdtm > div').map((e) => parseImageUrl(e))
        images.push(...doc.querySelectorAll('div.gdtl > a > img').map((e) => e.attributes['src'] || ''))
        if (images.length === 0) {
            for (let e of doc.querySelectorAll('div.gt100 > a > div, div.gt200 > a > div')) {
                images.push(parseImageUrl(e))
            }
        }
        let urls = doc.querySelectorAll('table.ptb > tbody > tr > td > a').map((e) => e.attributes['href'])
        let pageNumbers = urls.map((e) => {
            let n = Number(e.split('=')[1])
            return isNaN(n) ? 0 : n
        })
        let maxPage = Math.max(...pageNumbers)
        let current = 0
        if (next) current = Number(next)
        current += 1
        current = current > maxPage ? null : current.toString()
        let _urls = doc.querySelectorAll('div#gdt a').map((e) => e.attributes['href'])
        doc.dispose()
        return { thumbnails: images, urls: _urls, next: current }
    }

    /// 从详情页 script 提取 showkey / mpvkey + imageKeys
    async _getKey(url) {
        let html = await this._getHtml(url)
        let doc = new HtmlDocument(html)
        let script = doc.querySelectorAll('script').find((e) => e.text.includes('showkey'))
        if (script) {
            let m = RegExp('showkey="(.*?)"', 'g').exec(script.text)
            doc.dispose()
            if (m) return { showkey: m[1] }
        }
        script = doc.querySelectorAll('script').find((e) => e.text.includes('mpvkey'))?.text
        doc.dispose()
        if (script) {
            let mpvkey = script.split(';').find((e) => e.includes('mpvkey')).replaceAll(' ', '').split('=')[1].replaceAll('"', '')
            let imageList = script.split(';').find((e) => e.includes('imagelist')).replaceAll(' ', '').split('=')[1]
            return {
                mpvkey: mpvkey,
                imageKeys: JSON.parse(imageList).map((e) => e['k']),
            }
        }
        throw '无法获取图片密钥'
    }

    /// 获取单页原图 URL（showpage / imagedispatch API）
    async _getPageImage(key, first, comicId, page, nl) {
        let parsed = this.parseUrl(comicId)
        if (key.mpvkey) {
            let res = await Network.post(this.apiUrl, {
                'Content-Type': 'application/json',
            }, {
                'gid': parsed.id,
                'imgkey': key.imageKeys[page],
                'method': 'imagedispatch',
                'page': page + 1,
                'mpvkey': key.mpvkey,
                'nl': nl,
            })
            let json = JSON.parse(res)
            return { url: json.i.toString(), nl: json.s.toString() }
        } else {
            let parseImageKeyFromUrl = (url) => url.split('/')[4]
            let url = ''
            if (page < first.thumbnails.length) {
                url = first.urls[page]
            } else {
                let onePageLength = first.thumbnails.length
                let shouldLoadPage = Math.floor(page / onePageLength)
                let index = page % onePageLength
                let thumbnails = await this._loadThumbnails(comicId, shouldLoadPage.toString())
                url = thumbnails.urls[index]
            }
            let res = await Network.post(this.apiUrl, {
                'Content-Type': 'application/json',
            }, {
                'gid': parsed.id,
                'imgkey': parseImageKeyFromUrl(url),
                'method': 'showpage',
                'page': page + 1,
                'showkey': key.showkey,
                'nl': nl,
            })
            let json = JSON.parse(res)
            let i6 = json.i6
            let reg = RegExp("nl\\('(.+?)'\\)").exec(i6)
            nl = reg ? reg[1] : null
            let image = json.i3
            image = image.substring(image.indexOf('src="') + 5, image.indexOf('" style'))
            return { url: image, nl: nl }
        }
    }

    async loadChapterImages(comicId, epId) {
        if (this._comicId !== comicId || this._maxPage === 0) {
            await this._loadInfo(comicId)
        }
        // 惰性加载：返回页码占位列表（1-based），每张图的真实 URL 由
        // getImageLoadingConfig 按页请求 API 获取（每页仅一次，结果缓存）。
        // 避免大画廊（数百页）全量预取导致大量请求卡死阅读器。
        return Array.from({ length: this._maxPage }, (_, i) => (i + 1).toString())
    }

    // ============ 图片加载配置（惰性获取原图 URL） ============

    /// 页码占位 → 原图 URL 缓存（pageIndex 0-based）
    _pageImageCache = new Map()

    /// 当前漫画的 {key, first} 缓存
    _keyCache = null

    /// nl 链状态：连续页码可继承上次响应中的 nl，乱序/断页时重新开始
    _nl = null
    _nlPage = -1

    async _ensureKey(comicId) {
        if (this._keyCache && this._keyCache.comicId === comicId) {
            return this._keyCache
        }
        let first = await this._loadThumbnails(comicId)
        let key = await this._getKey(first.urls[0])
        this._keyCache = { key, first, comicId }
        return this._keyCache
    }

    async _getImageUrl(pageIndex, comicId) {
        if (this._pageImageCache.has(pageIndex)) {
            return this._pageImageCache.get(pageIndex)
        }
        let { key, first } = await this._ensureKey(comicId)
        let nl = null
        if (pageIndex === this._nlPage + 1) nl = this._nl
        let r = await this._getPageImage(key, first, comicId, pageIndex, nl)
        this._nl = r.nl
        this._nlPage = pageIndex
        this._pageImageCache.set(pageIndex, r.url)
        return r.url
    }

    async getImageLoadingConfig(url, comicId, epId) {
        let pageIndex = Number(url) - 1
        let headers = {
            'referer': this.baseUrl,
        }
        if (isNaN(pageIndex) || pageIndex < 0) {
            // 非页码占位（如缩略图 URL）：仅补 referer + 域名替换
            let u = url
            if (u.includes('s.exhentai.org')) {
                u = u.replace('s.exhentai.org', 'ehgt.org')
            }
            return { url: u, headers: headers }
        }
        let imageUrl = await this._getImageUrl(pageIndex, comicId)
        return {
            url: imageUrl,
            headers: headers,
        }
    }
}
