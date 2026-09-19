// description: MYCOMIC 漫画源 — 搜索/分类/详情/阅读（由 venera mycomic.js v1.1.0 移植，转换脚本自动生成）
// type: manga
//
// 由 venera 源自动转换：
// - 保留原站点的搜索/分类/详情/阅读核心逻辑（_searchApi/_categoryApi/_comicApi/_categoryData 内部对象）
// - 类开头的「wyw 适配层」将其包装为 wyw 插件接口（search/getDetail/openReader/分类四件套/浏览历史回放）
// - 已移除 wyw 无对应支撑的功能：账号登录/网络收藏/评论/点赞/评分/缩略图墙/外链识别/探索页(未映射部分)
// - Network 调用已改写为 wyw 原生风格：Network.get/post 直接返回 body 字符串，失败抛结构化异常（e.status/e.kind）


const BASE_URL = "https://mycomic.com/cn";
const CDN_URL = "https://biccam.com";
const REFERER = "https://mycomic.com/";

const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36";

const headers = {
    "User-Agent": UA,
    "Referer": REFERER,
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
    "Accept-Language": "zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7",
    "Accept-Encoding": "gzip, deflate, br",
    "Connection": "keep-alive",
    "Upgrade-Insecure-Requests": "1",
    "Sec-Fetch-Dest": "document",
    "Sec-Fetch-Mode": "navigate",
    "Sec-Fetch-Site": "none",
    "Sec-Fetch-User": "?1",
    "Sec-Ch-Ua": '"Chromium";v="131", "Not_A Brand";v="24"',
    "Sec-Ch-Ua-Mobile": "?0",
    "Sec-Ch-Ua-Platform": '"Windows"',
};

/**
 * Check if the response is a Cloudflare challenge page
 * @param {number} status
 * @param {string} body
 * @returns {boolean}
 */
function isCloudflareChallenge(status, body) {
    if (status === 403 || status === 503) {
        if (body && (body.indexOf("challenge-platform") !== -1 ||
            body.indexOf("cf-browser-verification") !== -1 ||
            body.indexOf("Just a moment") !== -1 ||
            body.indexOf("__cf_chl_") !== -1)) {
            return true;
        }
        return true;
    }
    if (body && body.indexOf("challenge-platform") !== -1) {
        return true;
    }
    return false;
}

/**
 * Wrapper for Network.get that detects Cloudflare challenges
 * and throws a user-friendly error guiding them to login
 * @param {string} url
 * @returns {Promise<{status: number, headers: object, body: string}>}
 */
async function fetchWithCFCheck(url) {
    // backend:'auto'：HTTP 疑似被 Cloudflare 拦截时自动降级 WebView 渲染，并自动同步 CF Cookie
    const resp = await Network.get(url, headers, { backend: 'auto', webviewTimeout: 45 });
    if (isCloudflareChallenge(resp.status, resp)) {
        throw "Cloudflare 验证拦截：请稍后重试（wyw 会自动尝试 WebView 渲染），或更换网络环境。";
    }
    return resp;
}

/**
 * Extract meta tag content from raw HTML
 * @param {string} html
 * @param {string} name - meta name or property (e.g. "description", "og:title")
 * @returns {string|null}
 */
function getMetaContent(html, name) {
    // pattern 1: <meta name="x" content="y"> or <meta property="x" content="y">
    let m = new RegExp(
        "<meta[^>]*?(?:name|property)=['\"]" + escapeRegex(name) + "['\"][^>]*?content=['\"]([^'\"]*)['\"]",
        "i"
    ).exec(html);
    if (m) return m[1];
    // pattern 2: <meta content="y" name="x"> or <meta content="y" property="x">
    m = new RegExp(
        "<meta[^>]*?content=['\"]([^'\"]*)['\"][^>]*?(?:name|property)=['\"]" + escapeRegex(name) + "['\"]",
        "i"
    ).exec(html);
    if (m) return m[1];
    return null;
}

function escapeRegex(s) {
    return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/**
 * Parse comic list from an HtmlDocument
 * Finds all <a> links to /cn/comics/{id} that contain an <img> with a CDN cover
 * @param {HtmlDocument} doc
 * @returns {Comic[]}
 */
function parseComicList(doc) {
    const links = doc.querySelectorAll("a[href*='/cn/comics/']");
    const comics = [];
    const seen = new Set();

    links.forEach((a) => {
        const href = a.attributes["href"] || "";
        const match = /\/cn\/comics\/(\d+)/.exec(href);
        if (!match) return;
        const id = match[1];
        if (seen.has(id)) return;

        const img = a.querySelector("img");
        if (!img) return;

        // Cover: prefer data-src (lazy-loaded), fallback to src
        let cover = img.attributes["data-src"] || img.attributes["src"] || "";
        if (!cover || cover.indexOf("biccam.com/comics/") === -1) return;

        // Title from alt attribute
        const title = (img.attributes["alt"] || "").trim() || id;

        // Latest chapter info
        let description = "";
        const chapterDiv = a.querySelector("div.truncate");
        if (chapterDiv) {
            description = chapterDiv.text.trim();
        }

        seen.add(id);
        comics.push(
            ({
                id: id,
                title: title,
                cover: cover,
                description: description,
                language: "zh-Hans",
            })
        );
    });

    return comics;
}

/**
 * Extract max page number from pagination links in raw HTML
 * @param {string} html
 * @returns {number}
 */
function parseMaxPage(html) {
    const pageMatches = html.match(/(?:href="[^"]*page=)(\d+)/g);
    if (!pageMatches) return 1;
    let max = 1;
    pageMatches.forEach((m) => {
        const n = parseInt(m.replace(/.*page=/, ""), 10);
        if (!isNaN(n) && n > max) max = n;
    });
    return max;
}

/**
 * Build a comics listing URL with optional filters
 * @param {number} page
 * @param {string} sort - sort param (e.g. "-update", "-views", "-id")
 * @param {string} q - search keyword
 * @param {string} filterType - "tag" | "country" | "audience" | "year" | "end"
 * @param {string} filterValue - filter value
 * @returns {string}
 */
function buildComicsUrl(page, sort, q, filterType, filterValue) {
    const params = [];
    if (q) params.push("q=" + encodeURIComponent(q));
    if (sort) params.push("sort=" + sort);
    if (filterType && filterValue) {
        params.push("filter[" + filterType + "]=" + filterValue);
    }
    if (page && page > 1) params.push("page=" + page);
    const query = params.join("&");
    return BASE_URL + "/comics" + (query ? "?" + query : "");
}

class mycomic extends PluginSource {
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
                Promise.resolve(this.init()).catch((e) => console.warn('[mycomic]', 'init 失败:', e))
            } catch (e) {
                console.warn('[mycomic]', 'init 失败:', e)
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
            console.error('[mycomic]', '搜索失败:', e)
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
        console.log('[mycomic]', '详情:', title, '章节数:', isGallery ? 0 : chapters.length)

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
            plugin: 'mycomic',
            method: 'loadChapterImages',
            args: [this._comicId, ep.id],
        }))
        Navigator.navigateToReader({
            comicId: this._comicId,
            comicTitle: this._comicTitle,
            chapters: chapters,
            sourceKey: 'mycomic',
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
            console.error('[mycomic]', '章节图片解析为空: comicId=' + comicId + ' epId=' + epId)
            throw '章节图片解析为空'
        }
        console.log('[mycomic]', '图片数:', urls.length)
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

    name = "MYCOMIC";

    key = "mycomic";

    version = "1.1.0";



    init() {
        // wyw 无 getCookies API：如遇 Cloudflare 拦截，请求带 {backend:'auto'} 会自动降级 WebView 并同步 Cookie
        console.log("[MyComic] init ok (wyw: CF Cookie 由 WebView 自动同步)");
    }

    // ==================== Account：wyw 已移除，CF Cookie 由 WebView 自动同步 ====================

    // ==================== Explore ====================

    _explore = [
        {
            title: "最新上架",
            type: "multiPageComicList",
            load: async (page) => {
                if (!page) page = 1;
                const url = buildComicsUrl(page, "-id");
                const resp = await fetchWithCFCheck(url);
                ;
                const doc = new HtmlDocument(resp);
                const comics = parseComicList(doc);
                const maxPage = parseMaxPage(resp);
                return { comics, maxPage };
            },
        },
        {
            title: "最近更新",
            type: "multiPageComicList",
            load: async (page) => {
                if (!page) page = 1;
                const url = buildComicsUrl(page, "-update");
                const resp = await fetchWithCFCheck(url);
                ;
                const doc = new HtmlDocument(resp);
                const comics = parseComicList(doc);
                const maxPage = parseMaxPage(resp);
                return { comics, maxPage };
            },
        },
        {
            title: "最高人气",
            type: "multiPageComicList",
            load: async (page) => {
                if (!page) page = 1;
                const url = buildComicsUrl(page, "-views");
                const resp = await fetchWithCFCheck(url);
                ;
                const doc = new HtmlDocument(resp);
                const comics = parseComicList(doc);
                const maxPage = parseMaxPage(resp);
                return { comics, maxPage };
            },
        },
    ];

    // ==================== Category ====================

    _categoryData = {
        title: "MYCOMIC",
        parts: [
            {
                name: "作品类型",
                type: "fixed",
                categories: [
                    "魔幻", "魔法", "热血", "冒险", "悬疑", "侦探", "爱情",
                    "校园", "搞笑", "四格", "科幻", "神鬼", "舞蹈", "音乐",
                    "百合", "后宫", "机战", "格斗", "恐怖", "萌系", "武侠",
                    "社会", "历史", "耽美", "励志", "职场", "生活", "治愈",
                    "伪娘", "黑道", "战争", "竞技", "体育", "美食", "腐女",
                    "宅男", "推理", "杂志",
                ],
                itemType: "category",
                categoryParams: [
                    "tag:mohuan", "tag:mofa", "tag:rexue", "tag:maoxian",
                    "tag:xuanyi", "tag:zhentan", "tag:aiqing", "tag:xiaoyuan",
                    "tag:gaoxiao", "tag:sige", "tag:kehuan", "tag:shengui",
                    "tag:wudao", "tag:yinyue", "tag:baihe", "tag:hougong",
                    "tag:jizhan", "tag:gedou", "tag:kongbu", "tag:mengxi",
                    "tag:wuxia", "tag:shehui", "tag:lishi", "tag:danmei",
                    "tag:lizhi", "tag:zhichang", "tag:shenghuo", "tag:zhiyu",
                    "tag:weiniang", "tag:heidao", "tag:zhanzheng", "tag:jingji",
                    "tag:tiyu", "tag:meishi", "tag:funv", "tag:zhainan",
                    "tag:tuili", "tag:zazhi",
                ],
            },
            {
                name: "作品地区",
                type: "fixed",
                categories: ["日本", "港台", "欧美", "内地", "韩国", "其他"],
                itemType: "category",
                categoryParams: [
                    "country:japan", "country:hongkong", "country:europe",
                    "country:china", "country:korea", "country:other",
                ],
            },
            {
                name: "适合受众",
                type: "fixed",
                categories: ["少女", "少年", "青年", "儿童", "通用"],
                itemType: "category",
                categoryParams: [
                    "audience:shaonv", "audience:shaonian", "audience:qingnian",
                    "audience:ertong", "audience:tongyong",
                ],
            },
            {
                name: "出品年份",
                type: "fixed",
                categories: [
                    "2026", "2025", "2024", "2023", "2022", "2021",
                    "2020", "2019", "2018", "2017", "2016", "2015",
                    "2014", "2013", "2012", "2011", "2010",
                    "00年代", "90年代", "80年代", "70年代或更早",
                ],
                itemType: "category",
                categoryParams: [
                    "year:2026", "year:2025", "year:2024", "year:2023",
                    "year:2022", "year:2021", "year:2020", "year:2019",
                    "year:2018", "year:2017", "year:2016", "year:2015",
                    "year:2014", "year:2013", "year:2012", "year:2011",
                    "year:2010", "year:200x", "year:199x", "year:198x",
                    "year:197x",
                ],
            },
            {
                name: "目前进度",
                type: "fixed",
                categories: ["连载中", "已完结"],
                itemType: "category",
                categoryParams: ["end:0", "end:1"],
            },
        ],
        enableRankingPage: true,
    // —— wyw 适配：mycomic 排序值格式为 "-key-文本"（值含前导短横线），按最后一个 "-" 拆分为 value/text ——
    getCategoryOptions(category) {
        if (!this._categoryApi || !Array.isArray(this._categoryApi.optionList)) return null
        return this._categoryApi.optionList.map((group) => ({
            label: group.label || '筛选',
            options: (group.options || []).map((s) => {
                const i = String(s).lastIndexOf('-')
                return i <= 0 ? { value: s, text: String(s) } : { value: String(s).slice(0, i), text: String(s).slice(i + 1) }
            }),
        }))
    }

    };

    // ==================== Category Comics ====================

    _categoryApi = {
        load: async (category, param, options, page) => {
            if (!page) page = 1;

            // Parse filter type and value from param (format: "type:value")
            let filterType = null;
            let filterValue = null;
            let sort = "-id";

            if (param) {
                const parts = param.split(":");
                if (parts.length >= 2) {
                    filterType = parts[0];
                    filterValue = parts.slice(1).join(":");
                }
            }

            // Get sort option
            if (options && options.length > 0 && options[0]) {
                sort = options[0];
            }

            const url = buildComicsUrl(page, sort, null, filterType, filterValue);
            const resp = await fetchWithCFCheck(url);
            ;

            const doc = new HtmlDocument(resp);
            const comics = parseComicList(doc);
            const maxPage = parseMaxPage(resp);

            return { comics, maxPage };
        },

        optionList: [
            {
                label: "排序",
                options: [
                    "-id-最新上架",
                    "-update-最近更新",
                    "-views-最高人气",
                ],
            },
        ],

        ranking: {
            options: [
                "-views-历史排行",
                "-week-週排行",
                "-month-月排行",
            ],
            load: async (option, page) => {
                if (!page) page = 1;
                const sort = option || "-views";
                const url =
                    BASE_URL +
                    "/rank?sort=" +
                    sort +
                    (page > 1 ? "&page=" + page : "");
                const resp = await fetchWithCFCheck(url);
                ;

                const doc = new HtmlDocument(resp);
                const comics = parseComicList(doc);
                const maxPage = parseMaxPage(resp);

                return { comics, maxPage };
            },
        },
    };

    // ==================== Search ====================

    _searchApi = {
        load: async (keyword, options, page) => {
            if (!page) page = 1;
            const kw = (keyword || "").trim();
            if (!kw) return { comics: [], maxPage: 1 };

            let sort = null;
            if (options && options.length > 0 && options[0]) {
                sort = options[0];
            }

            const url = buildComicsUrl(page, sort, kw);
            const resp = await fetchWithCFCheck(url);
            ;

            const doc = new HtmlDocument(resp);
            const comics = parseComicList(doc);
            const maxPage = parseMaxPage(resp);

            return { comics, maxPage };
        },

        optionList: [
            {
                type: "select",
                options: [
                    "-id-最新上架",
                    "-update-最近更新",
                    "-views-最高人气",
                ],
                label: "排序",
                default: null,
            },
        ],

    };

    // ==================== Comic Detail ====================

    _comicApi = {
        loadInfo: async (id) => {
            const url = BASE_URL + "/comics/" + id;
            const resp = await fetchWithCFCheck(url);
            ;

            const html = resp;
            const doc = new HtmlDocument(html);

            // Parse meta tags
            let title = getMetaContent(html, "og:title") || id;
            title = title.replace(/\s*-\s*MYCOMIC.*$/, "").trim();

            const description = getMetaContent(html, "description") || "";
            const author = getMetaContent(html, "author") || "";
            const cover =
                getMetaContent(html, "og:image") ||
                CDN_URL + "/comics/" + id + ".jpg";
            const keywords = getMetaContent(html, "keywords") || "";

            // Parse tags from filter links on the page
            const tags = new Map();
            const tagLinks = doc.querySelectorAll(
                "a[href*='filter%5Btag%5D']"
            );
            const tagNames = [];
            tagLinks.forEach((a) => {
                const text = a.text.trim();
                if (text) tagNames.push(text);
            });
            if (tagNames.length) tags.set("类型", tagNames);

            // Parse additional info from keywords
            const keywordList = keywords
                .split(",")
                .map((s) => s.trim())
                .filter(Boolean);
            if (author) tags.set("作者", [author]);

            // Try to extract country and audience from keywords
            const countryMap = {
                日本: "日本",
                内地: "内地",
                韩国: "韩国",
                欧美: "欧美",
                港台: "港台",
                其他: "其他",
            };
            const audienceMap = {
                少年: "少年",
                少女: "少女",
                青年: "青年",
                儿童: "儿童",
                通用: "通用",
            };
            const countries = [];
            const audiences = [];
            keywordList.forEach((kw) => {
                if (countryMap[kw]) countries.push(kw);
                if (audienceMap[kw]) audiences.push(kw);
            });
            if (countries.length) tags.set("地区", countries);
            if (audiences.length) tags.set("受众", audiences);

            // Parse chapter list from Alpine.js x-data
            // The x-data attribute contains: chapters: [{"id":96338,"title":"第16回"}, ...]
            const chapters = new Map();
            const chapterMatch = /chapters:\s*(\[[\s\S]*?\])/.exec(html);
            if (chapterMatch) {
                try {
                    const chapterList = JSON.parse(chapterMatch[1]);
                    chapterList.forEach((ch) => {
                        chapters.set(String(ch.id), ch.title);
                    });
                } catch (e) {
                    // Fallback: try to find chapter links in the page
                    const chapterLinks = doc.querySelectorAll(
                        "a[href*='/cn/chapters/']"
                    );
                    chapterLinks.forEach((a) => {
                        const href = a.attributes["href"] || "";
                        const m = /\/cn\/chapters\/(\d+)/.exec(href);
                        if (m) {
                            const chTitle = a.text.trim();
                            if (chTitle && !chapters.has(m[1])) {
                                chapters.set(m[1], chTitle);
                            }
                        }
                    });
                }
            }

            return ({
                title: title,
                cover: cover,
                description: description,
                tags: tags,
                chapters: chapters,
                thumbnails: [cover],
                url: url,
                uploader: author || undefined,
            });
        },

        loadEp: async (comicId, epId) => {
            if (!epId) {
                throw "No episode id";
            }
            const url = BASE_URL + "/chapters/" + epId;
            const resp = await fetchWithCFCheck(url);
            ;

            const doc = new HtmlDocument(resp);
            // Chapter images have class "page" and src or data-src from biccam.com/chapters/
            const imgs = doc.querySelectorAll("img.page");
            const images = [];

            if (imgs.length > 0) {
                imgs.forEach((img) => {
                    let src =
                        img.attributes["data-src"] ||
                        img.attributes["src"] ||
                        "";
                    if (src && src.indexOf("biccam.com/chapters/") !== -1) {
                        images.push(src);
                    }
                });
            }

            // Fallback: find all imgs with src containing biccam.com/chapters/
            if (images.length === 0) {
                const allImgs = doc.querySelectorAll("img");
                allImgs.forEach((img) => {
                    let src =
                        img.attributes["data-src"] ||
                        img.attributes["src"] ||
                        "";
                    if (src && src.indexOf("biccam.com/chapters/") !== -1) {
                        images.push(src);
                    }
                });
            }

            return { images: images };
        },

        onImageLoad: (url, comicId, epId) => {
            return {
                url: url,
                headers: {
                    "Referer": REFERER,
                    "User-Agent": UA,
                    "Accept": "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
                    "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
                    "Sec-Fetch-Dest": "image",
                    "Sec-Fetch-Mode": "no-cors",
                    "Sec-Fetch-Site": "cross-site",
                },
            };
        },



    };
}
