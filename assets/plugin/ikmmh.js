// description: 爱看漫 漫画源 — 搜索/分类/详情/阅读（由 venera ikmmh.js v1.0.5 移植，转换脚本自动生成）
// type: manga
//
// 由 venera 源自动转换：
// - 保留原站点的搜索/分类/详情/阅读核心逻辑（_searchApi/_categoryApi/_comicApi/_categoryData 内部对象）
// - 类开头的「wyw 适配层」将其包装为 wyw 插件接口（search/getDetail/openReader/分类四件套/浏览历史回放）
// - 已移除 wyw 无对应支撑的功能：账号登录/网络收藏/评论/点赞/评分/缩略图墙/外链识别/探索页(未映射部分)
// - Network 调用已改写为 wyw 原生风格：Network.get/post 直接返回 body 字符串，失败抛结构化异常（e.status/e.kind）


function getValidatorCookie(htmlString) {
  // 正则表达式匹配 document.cookie 设置语句
  const cookieRegex = /document\.cookie\s*=\s*"([^"]+)"/;
  const match = htmlString.match(cookieRegex);

  if (!match) {
    return null; // 没有找到 cookie 设置语句
  }

  const cookieSetting = match[1];
  const cookies = cookieSetting.split(';');
  if (cookies.length === 0) {
    return null
  }
  const nameValuePart = cookies[0].trim();
  const equalsIndex = nameValuePart.indexOf('=');

  const name = nameValuePart.substring(0, equalsIndex);
  const value = nameValuePart.substring(equalsIndex + 1);

  return { name: name, value: value, domain: "www.ikmmh.com" }
}

function needPassValidator(htmlString) {
  var cookie = getValidatorCookie(htmlString)
  if (cookie != null) {
    // wyw 无 Network.setCookies API：把校验 cookie 手动挂到静态请求头上（后续请求统一携带）
    ikmmh.webHeaders["Cookie"] = cookie.name + "=" + cookie.value
    if (ikmmh.jsonHead) ikmmh.jsonHead["Cookie"] = cookie.name + "=" + cookie.value
    return true
  }
  return false
}

class ikmmh extends PluginSource {
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
                Promise.resolve(this.init()).catch((e) => console.warn('[ikmmh]', 'init 失败:', e))
            } catch (e) {
                console.warn('[ikmmh]', 'init 失败:', e)
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
            console.error('[ikmmh]', '搜索失败:', e)
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
        console.log('[ikmmh]', '详情:', title, '章节数:', isGallery ? 0 : chapters.length)

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
            plugin: 'ikmmh',
            method: 'loadChapterImages',
            args: [this._comicId, ep.id],
        }))
        Navigator.navigateToReader({
            comicId: this._comicId,
            comicTitle: this._comicTitle,
            chapters: chapters,
            sourceKey: 'ikmmh',
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
            console.error('[ikmmh]', '章节图片解析为空: comicId=' + comicId + ' epId=' + epId)
            throw '章节图片解析为空'
        }
        console.log('[ikmmh]', '图片数:', urls.length)
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

  // 基础配置
  name = "爱看漫";
  key = "ikmmh";
  version = "1.0.5";
  // 常量定义
  static baseUrl = "https://www.ikmmh.com";
  static Mobile_UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1 Edg/140.0.0.0";
  static webHeaders = {
    "User-Agent": ikmmh.Mobile_UA,
    "Accept":
      "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
  };
  static jsonHead = {
    "User-Agent": ikmmh.Mobile_UA,
    "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
    "Accept": "application/json, text/javascript, */*; q=0.01",
    "Accept-Encoding": "gzip",
    "X-Requested-With": "XMLHttpRequest",
  };
  // 统一缩略图加载配置
  static thumbConfig = (url) => ({
    headers: {
      ...ikmmh.webHeaders,
      "referer": ikmmh.baseUrl,
    },
  });
  // 账号系统
;
  // 探索页面
  _explore = [
    {
      title: this.name,
      type: "singlePageWithMultiPart",
      load: async () => {
        try {
          let res = await Network.get(`${ikmmh.baseUrl}/`, ikmmh.webHeaders);
          ;

          if (needPassValidator(res)) {
            // rePost
            res = await Network.get(`${ikmmh.baseUrl}/`, ikmmh.webHeaders);
          }

          let document = new HtmlDocument(res);
          let parseComic = (e) => {
            let title = e.querySelector("div.title").text.split("~")[0];
            let cover = e.querySelector("div.thumb_img").attributes["data-src"];
            let link = `${ikmmh.baseUrl}${
              e.querySelector("a").attributes["href"]
            }`;
            return {
              title,
              cover,
              id: link,
            };
          };
          return {
            "本周推荐": document
              .querySelectorAll("div.module-good-fir > div.item")
              .map(parseComic),
            "今日更新": document
              .querySelectorAll("div.module-day-fir > div.item")
              .map(parseComic),
          };
        } catch (err) {
          throw new Error(`探索页面加载失败：${err.message}`);
        }
      },
    },
  ];
  // 分类页面
  _categoryData = {
    title: "爱看漫",
    parts: [
      {
        name: "更新",
        type: "fixed",
        categories: [
          "星期一",
          "星期二",
          "星期三",
          "星期四",
          "星期五",
          "星期六",
          "星期日",
        ],
        itemType: "category",
        categoryParams: ["1", "2", "3", "4", "5", "6", "7"],
      },
      {
        name: "分类",
        // fixed 或者 random
        // random用于分类数量相当多时, 随机显示其中一部分
        type: "fixed",
        // 如果类型为random, 需要提供此字段, 表示同时显示的数量
        // randomNumber: 5,
        categories: [
          "全部",
          "长条",
          "大女主",
          "百合",
          "耽美",
          "纯爱",
          "後宫",
          "韩漫",
          "奇幻",
          "轻小说",
          "生活",
          "悬疑",
          "格斗",
          "搞笑",
          "伪娘",
          "竞技",
          "职场",
          "萌系",
          "冒险",
          "治愈",
          "都市",
          "霸总",
          "神鬼",
          "侦探",
          "爱情",
          "古风",
          "欢乐向",
          "科幻",
          "穿越",
          "性转换",
          "校园",
          "美食",
          "悬疑",
          "剧情",
          "热血",
          "节操",
          "励志",
          "异世界",
          "历史",
          "战争",
          "恐怖",
          "霸总"
        ],
        // category或者search
        // 如果为category, 点击后将进入分类漫画页面, 使用下方的`categoryComics`加载漫画
        // 如果为search, 将进入搜索页面
        itemType: "category",
      }
    ],
    enableRankingPage: false,
  };
  // 分类漫画加载
  _categoryApi = {
    load: async (category, param, options, page) => {
      const d = (v, def) => (v === undefined || v === null || v === "" ? def : v)
      options = Array.isArray(options) ? options : []
      try {
        let res;
        if (param) {
          res = await Network.get(
            `${ikmmh.baseUrl}/update/${param}.html`,
            ikmmh.webHeaders
          );
          ;

          if (needPassValidator(res)) {
            // rePost
            res = await Network.get(
              `${ikmmh.baseUrl}/update/${param}.html`,
              ikmmh.webHeaders
            );
          }

          let document = new HtmlDocument(res);
          let comics = document.querySelectorAll("li.comic-item").map((e) => ({
            title: e.querySelector("p.title").text.split("~")[0],
            cover: e.querySelector("img").attributes["src"],
            id: `${ikmmh.baseUrl}${e.querySelector("a").attributes["href"]}`,
            subTitle: e.querySelector("span.chapter").text,
          }));
          return {
            comics,
            maxPage: 1
          };
        } else {
          res = await Network.post(
            `${ikmmh.baseUrl}/api/comic/index/lists`,
            ikmmh.jsonHead,
            `area=${d(options[1], '9')}&tags=${encodeURIComponent(category)}&full=${
              d(options[0], '3')
            }&page=${page}`
          );

          if (needPassValidator(res)) {
            // rePost
            res = await Network.post(
              `${ikmmh.baseUrl}/api/comic/index/lists`,
              ikmmh.jsonHead,
              `area=${d(options[1], '9')}&tags=${encodeURIComponent(category)}&full=${options[0]
              }&page=${page}`
            );
          }

          let resData = JSON.parse(res);
          return {
            comics: resData.data.map((e) => ({
              id: `${ikmmh.baseUrl}${e.info_url}`,
              title: e.name.split("~")[0],
              subTitle: e.author,
              cover: e.cover,
              tags: e.tags,
              description: e.lastchapter,
            })),
            maxPage: resData.end || 1,
          };
        }
      } catch (err) {
        throw new Error(`分类加载失败：${err.message}`);
      }
    },
    optionList: [
      {
        // 对于单个选项, 使用-分割, 左侧为用于数据加载的值, 即传给load函数的options参数; 右侧为显示给用户的文本

        options: ["3-全部", "4-连载中", "1-已完结"],
        notShowWhen: [
          "星期一",
          "星期二",
          "星期三",
          "星期四",
          "星期五",
          "星期六",
          "星期日",
        ],
        showWhen: null,
      },
      {
        options: [
          "9-全部",
          "1-日漫",
          "2-港台",
          "3-美漫",
          "4-国漫",
          "5-韩漫",
          "6-未分类",
        ],
        notShowWhen: [
          "星期一",
          "星期二",
          "星期三",
          "星期四",
          "星期五",
          "星期六",
          "星期日",
        ],
        showWhen: null,
      },
    ],
  };
  // 搜索功能
  _searchApi = {
    load: async (keyword, options, page) => {
      try {
        let res = await Network.get(
          `${ikmmh.baseUrl}/search?searchkey=${encodeURIComponent(keyword)}`,
          ikmmh.webHeaders
        );

        if (needPassValidator(res)) {
          // rePost
          res = await Network.get(
            `${ikmmh.baseUrl}/search?searchkey=${encodeURIComponent(keyword)}`,
            ikmmh.webHeaders
          );
        }

        let document = new HtmlDocument(res);
        return {
          comics: document.querySelectorAll("li.comic-item").map((e) => ({
            title: e.querySelector("p.title").text.split("~")[0],
            cover: e.querySelector("img").attributes["src"],
            id: `${ikmmh.baseUrl}${e.querySelector("a").attributes["href"]}`,
            subTitle: e.querySelector("span.chapter").text,
          })),
          maxPage: 1,
        };
      } catch (err) {
        throw new Error(`搜索失败：${err.message}`);
      }
    },
    optionList: [],
  };
  // 收藏功能
;
  // 漫画详情
  _comicApi = {
    loadInfo: async (id) => {
      // 加载收藏页并判断是否收藏
      let isFavorite = false;
      try {
        let favorites = await this.favorites.loadComics(1, null);
        isFavorite = favorites.comics.some((comic) => comic.id === id);
      } catch (error) {
        console.error("加载收藏页失败:", error);
      }
      let res = await Network.get(id, ikmmh.webHeaders);

      if (needPassValidator(res)) {
        // rePost
        res = await Network.get(id, ikmmh.webHeaders);
      }

      let document = new HtmlDocument(res);
      let comicId = id.match(/\d+/)[0];
      // 获取章节数据
      let epRes = await Network.get(
        `${ikmmh.baseUrl}/api/comic/zyz/chapterlink?id=${comicId}`,
        {
          ...ikmmh.jsonHead,
          "referer": id,
        }
      );
      let epData = JSON.parse(epRes);
      let eps = new Map();
      if (epData.data && epData.data.length > 0 && epData.data[0].list) {
        epData.data[0].list.forEach((e) => {
          let title = e.name;
          let id = `${ikmmh.baseUrl}${e.url}`;
          eps.set(id, title);
        });
      } else {
        throw new Error(`章节数据格式异常`);
      }

      let title = document.querySelector(
        "div.book-hero__detail > div.title"
      ).text;
      let escapedTitle = title.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      let thumb =
        document
          .querySelector("div.coverimg")
          .attributes["style"].match(/\((.*?)\)/)?.[1] || "";
      let desc = document
        .querySelector("article.book-container__detail")
        .text.match(
          new RegExp(
            `漫画名：${escapedTitle}(?:(?:[^。]*?(?:简介|漫画简介)\\s*[:：]?\\s*)|(?:[^。]*?))([\\s\\S]+?)\\.\\.\\.。`
          )
        );
      let intro = desc?.[1]?.trim().replace(/\s+/g, " ") || "";

      return {
        title: title.split("~")[0],
        cover: thumb,
        description: intro,
        tags: {
          "作者": [
            document
              .querySelector("div.book-container__author")
              .text.split("作者：")[1],
          ],
          "更新": [document.querySelector("div.update > a > em").text],
          "标签": document
            .querySelectorAll("div.book-hero__detail > div.tags > a")
            .map((e) => e.text.trim())
            .filter((text) => text),
        },
        chapters: eps,
        recommend: document
          .querySelectorAll("div.module-guessu > div.item")
          .map((e) => ({
            title: e.querySelector("div.title").text.split("~")[0],
            cover: e.querySelector("div.thumb_img").attributes["data-src"],
            id: `${ikmmh.baseUrl}${e.querySelector("a").attributes["href"]}`,
          })),
        isFavorite: isFavorite,
      };
    },
    loadEp: async (comicId, epId) => {
      try {
        let res = await Network.get(epId, ikmmh.webHeaders);

        if (needPassValidator(res)) {
          // rePost
          res = await Network.get(epId, ikmmh.webHeaders);
        }

        let document = new HtmlDocument(res);
        return {
          images: document
            .querySelectorAll("img.lazy")
            .map((e) => e.attributes["data-src"]),
        };
      } catch (err) {
        throw new Error(`加载章节失败：${err.message}`);
      }
    },
    onImageLoad: (url, comicId, epId) => {
      return {
        url,
        headers: {
          ...ikmmh.webHeaders,
          "referer": epId,
        },
      };
    },
  };
}
