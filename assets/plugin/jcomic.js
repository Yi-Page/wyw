// description: jcomic.net 漫画源 — 搜索/分类/详情/阅读（由 venera jcomic.js v1.0.0 移植，转换脚本自动生成）
// type: manga
//
// 由 venera 源自动转换：
// - 保留原站点的搜索/分类/详情/阅读核心逻辑（_searchApi/_categoryApi/_comicApi/_categoryData 内部对象）
// - 类开头的「wyw 适配层」将其包装为 wyw 插件接口（search/getDetail/openReader/分类四件套/浏览历史回放）
// - 已移除 wyw 无对应支撑的功能：账号登录/网络收藏/评论/点赞/评分/缩略图墙/外链识别/探索页(未映射部分)
// - Network 调用已改写为 wyw 原生风格：Network.get/post 直接返回 body 字符串，失败抛结构化异常（e.status/e.kind）


const JCOMIC_BASE = "https://jcomic.net";
const JCOMIC_REFERER = JCOMIC_BASE + "/";

function trimTitle(raw) {
  if (!raw) return "";
  const idx = raw.lastIndexOf(" (");
  if (idx > 0) return raw.slice(0, idx).trim();
  return raw.trim();
}

function parseIdFromHref(href) {
  if (!href) return null;
  try {
    const u = href.split("?")[0];
    const parts = u.split("/").filter(Boolean); // 过滤空字符串
    if (parts.length >= 2) {
      return decodeURIComponent(parts[1]);
    }
    return decodeURIComponent(parts[parts.length - 1]);
  } catch {
    return null;
  }
}

function parseEpIdFromHref(href) {
  if (!href) return null;
  const u = href.split("?")[0];
  const parts = u.split("/").filter(Boolean);
  if (parts.length >= 3) {
    return decodeURIComponent(parts[2]);
  }
  return null;
}

/**
 * 解析作品卡片 -> Comic
 * @param {Element} card
 */
function parseComicCard(card) {
  try {
    const link = card.querySelector('a[href^="/eps/"], a[href^="/page/"]');
    if (!link) return null;
    const href = link.attributes["href"];
    const id = parseIdFromHref(href);
    if (!id) return null;

    const img = card.querySelector("img.comic-thumb");
    const cover = img ? img.attributes["src"] : "";

    const titleEl = card.querySelector("p.comic-title");
    const rawTitle = titleEl ? titleEl.text.trim() : id;
    const title = trimTitle(rawTitle);

    // 作者
    const authorButtons = card.querySelectorAll('a[href^="/author/"] button');
    const authors = Array.from(authorButtons).map((b) => b.text.trim());
    const subTitle = authors.join(" ");

    // 分类标签
    const catButtons = card.querySelectorAll('a[href^="/cat/"] button');
    let tags = [];
    if (catButtons.length) {
        tags = Array.from(catButtons).map((b) => b.text.trim());
    } else {
    // 有些结构是 a[href^="/cat/..."] 包着文字
    const catAnchors = card.querySelectorAll('a[href^="/cat/"]');
    tags = Array.from(catAnchors)
    .map((a) => a.text.trim())
    .filter(Boolean);
}   

    // 最后更新
    const dateEl = card.querySelector("p.comic-date");
    const description = dateEl ? dateEl.text.trim() : "";

    return ({
      id,
      title,
      subTitle,
      cover,
      tags,
      language: "zh-Hant",
      description,
    });
  } catch (e) {
    return null;
  }
}

/**
 * 通用：解析分页最大页数
 * @param {HtmlDocument} doc
 */
function parseMaxPage(doc) {
  const pag = doc.querySelector("ul.pagination");
  if (!pag) return 1;
  const as = pag.querySelectorAll("a");
  let max = 1;
  as.forEach((a) => {
    const t = a.text.trim();
    const n = parseInt(t, 10);
    if (!Number.isNaN(n) && n > max) max = n;
  });
  return max;
}

/**
 * 通用：解析列表页所有作品
 * @param {HtmlDocument} doc
 */
function parseComicList(doc) {
  const cards = doc.querySelectorAll(
    'div.row.col-lg-4.col-md-6.col-xs-12, div.row.col-md-6.col-xs-12'
  );
  const result = [];
  cards.forEach((card) => {
    const c = parseComicCard(card);
    if (c) result.push(c);
  });
  return result;
}

class jcomic extends PluginSource {
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
                Promise.resolve(this.init()).catch((e) => console.warn('[jcomic]', 'init 失败:', e))
            } catch (e) {
                console.warn('[jcomic]', 'init 失败:', e)
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
            console.error('[jcomic]', '搜索失败:', e)
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
        console.log('[jcomic]', '详情:', title, '章节数:', isGallery ? 0 : chapters.length)

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
            plugin: 'jcomic',
            method: 'loadChapterImages',
            args: [this._comicId, ep.id],
        }))
        Navigator.navigateToReader({
            comicId: this._comicId,
            comicTitle: this._comicTitle,
            chapters: chapters,
            sourceKey: 'jcomic',
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
            console.error('[jcomic]', '章节图片解析为空: comicId=' + comicId + ' epId=' + epId)
            throw '章节图片解析为空'
        }
        console.log('[jcomic]', '图片数:', urls.length)
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

  name = "jcomic.net";
  key = "jcomic";

  version = "1.0.0";

  url =
    "https://cdn.jsdelivr.net/gh/venera-app/venera-configs@main/jcomic.js";

  currentComic = null;

  _buildUrl(path) {
    if (path.startsWith("http://") || path.startsWith("https://")) return path;
    if (!path.startsWith("/")) path = "/" + path;
    return JCOMIC_BASE + path;
  }

  /**
   * [Optional] init
   */
  init() {}

  /// explore
  _explore = [
    {
      title: "JComic",
      type: "multiPageComicList",
      load: async (page) => {
        if (!page) page = 1;
        const cat = "最近更新";
        const encoded = encodeURI(cat);
        const path = page === 1 ? `/cat/${encoded}` : `/cat/${encoded}/${page}`;
        const url = this._buildUrl(path);

        const resp = await Network.get(url, { referer: JCOMIC_REFERER });
        ;

        const doc = new HtmlDocument(resp);
        const comics = parseComicList(doc);
        const maxPage = parseMaxPage(doc);

        return { comics, maxPage };
      },
      loadNext(next) {},
    },
  ];

  // 分类列表
  _categoryData = {
    title: "jcomic.net",
    parts: [
      {
        name: "分類",
        type: "fixed",
        categories: [
          "最近更新",
          "隨機",
          "全彩",
          "長篇",
          "單行本",
          "同人",
          "短篇",
          "Cosplay",
          "歐美",
          "WEBTOON",
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
          "姐姐系",
          "妹妹系",
          "SM",
          "性轉換",
          "足の恋",
          "重口地帶",
          "人妻",
          "NTR",
          "強暴",
          "非人類",
          "艦隊收藏",
          "Love Live",
          "SAO 刀劍神域",
          "Fate",
          "東方",
          "禁書目錄",
        ],
        itemType: "category",
        categoryParams: [
          "最近更新",
          "隨機",
          "全彩",
          "長篇",
          "單行本",
          "同人",
          "短篇",
          "Cosplay",
          "歐美",
          "WEBTOON",
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
          "姐姐系",
          "妹妹系",
          "SM",
          "性轉換",
          "足の恋",
          "重口地帶",
          "人妻",
          "NTR",
          "強暴",
          "非人類",
          "艦隊收藏",
          "Love Live",
          "SAO 刀劍神域",
          "Fate",
          "東方",
          "禁書目錄",
        ],
      },
    ],
    enableRankingPage: false,
  };

  _categoryApi = {
    /**
     * @param category {string}
     * @param param {string} 
     * @param options {string[]}
     * @param page {number}
     */
    load: async (category, param, options, page) => {
      if (!page) page = 1;
      const encoded = encodeURI(param);
      const path = page === 1 ? `/cat/${encoded}` : `/cat/${encoded}/${page}`;
      const url = this._buildUrl(path);

      const resp = await Network.get(url, { referer: JCOMIC_REFERER });
      ;

      const doc = new HtmlDocument(resp);
      const comics = parseComicList(doc);
      const maxPage = parseMaxPage(doc);

      return { comics, maxPage };
    },
    optionList: [],
    ranking: null,
  };

  /// 搜索
  _searchApi = {
    /**
     * @param keyword {string}
     * @param options {string[]}
     * @param page {number}
     */
    load: async (keyword, options, page) => {
      if (!page) page = 1;
      const kw = (keyword || "").trim();
      if (!kw) {
        return { comics: [], maxPage: 1 };
      }
      const encoded = encodeURIComponent(kw);
      const path = page === 1 ? `/search/${encoded}` : `/search/${encoded}/${page}`;
      const url = this._buildUrl(path);

      const resp = await Network.get(url, { referer: JCOMIC_REFERER });
      ;

      const doc = new HtmlDocument(resp);
      const comics = parseComicList(doc);
      const maxPage = parseMaxPage(doc);

      return { comics, maxPage };
    },
    loadNext: async (keyword, options, next) => {},
    optionList: [
      {
        type: "select",
        options: ["0-Default"],
        label: "sort",
        default: null,
      },
    ],
  };

  /// 单本漫画
  _comicApi = {
    /**
     * 载入漫画信息和章节列表
     * @param id {string} - 原始标题字符串
     * @returns {Promise<ComicDetails>}
     */
    loadInfo: async (id) => {
      const encodedId = encodeURI(id);
      const url = this._buildUrl(`/eps/${encodedId}`);
      const resp = await Network.get(url, { referer: JCOMIC_REFERER });
      ;

      const doc = new HtmlDocument(resp);

      const infoBlock = doc.querySelector(
        'div.row.col-md-6.col-xs-12'
      );
      if (!infoBlock) {
        throw new Error("failed to parse comic info");
      }

      // 标题和总页数
      const titleEl = infoBlock.querySelector("p.comic-title");
      const rawTitle = titleEl ? titleEl.text.trim() : id;
      const title = trimTitle(rawTitle);
      let totalPages = 1;
      const pageMatch = /\((\d+)\)/.exec(rawTitle);
      if (pageMatch) {
        totalPages = parseInt(pageMatch[1], 10) || 1;
      }

      // 封面
      const img = infoBlock.querySelector("img.comic-thumb");
      const cover = img ? img.attributes["src"] : "";

      // 作者
      const authorButtons = infoBlock.querySelectorAll(
        'a[href^="/author/"] button'
      );
      const authors = Array.from(authorButtons).map((b) => b.text.trim());

      // 分类标签
      const catButtons = infoBlock.querySelectorAll('a[href^="/cat/"] button');
      const categories = Array.from(catButtons).map((b) => b.text.trim());

      // 更新时间
      const dateEl = infoBlock.querySelector("p.comic-date");
      const uploadTime = dateEl ? dateEl.text.trim() : "";

      // 章节列表
      const allPageLinks = doc.querySelectorAll('a[href^="/page/"]');
      let eps = [];
      
      allPageLinks.forEach((a) => {
        const href = a.attributes["href"];
        // 检查这个链接是否属于当前漫画
        const linkComicId = parseIdFromHref(href);
        if (linkComicId === id) {
          const epId = parseEpIdFromHref(href);
          if (epId) {
            let text = a.text.trim();
            if (!text) {
              const btn = a.querySelector("button");
              if (btn) text = btn.text.trim();
            }
            eps.push({
              id: epId,
              title: text || `第${epId}話`,
            });
          }
        }
      });

      // tags Map
      const tags = new Map();
      if (authors.length) tags.set("authors", authors);
      if (categories.length) tags.set("categories", categories);

      // 构建 chapters Map
      const chapters = new Map();
      eps.forEach((ep) => {
        chapters.set(ep.id, ep.title);
      });

      this.currentComic = {
        id,
        title,
        cover,
        authors,
        categories,
        eps,
      };

      return ({
        title,
        cover,
        tags,
        chapters,
        maxPage: totalPages,
        thumbnails: [cover],
        uploadTime,
        url: url,
        recommend: undefined,
      });
    },

    /**
     * 载入章节图片
     * @param comicId {string}
     * @param epId {string}
     * @returns {Promise<{images: string[]}>}
     */
    loadEp: async (comicId, epId) => {
      const encodedComicId = encodeURI(comicId);
      let path = `/page/${encodedComicId}`;
      if (epId) {
        // epId 里可能有 11.5、14.2 等，直接当原始字符串 encode 一下
        path += "/" + encodeURIComponent(epId);
      }
      const url = JCOMIC_BASE + path;

      const resp = await Network.get(url, { referer: JCOMIC_REFERER });
      ;

      const doc = new HtmlDocument(resp);
      const imgs = doc.querySelectorAll("img.comic-thumb");
      const images = Array.from(imgs).map((img) => img.attributes["src"]);

      return { images };
    },

    onImageLoad: (url, comicId, epId) => {
      return {
        url,
        headers: {
          referer: JCOMIC_REFERER,
        },
      };
    },



  };
}