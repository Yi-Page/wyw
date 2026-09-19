// description: 再漫画 漫画源 — 搜索/分类/详情/阅读（由 venera zaimanhua.js v1.0.2 移植，转换脚本自动生成）
// type: manga
//
// 由 venera 源自动转换：
// - 保留原站点的搜索/分类/详情/阅读核心逻辑（_searchApi/_categoryApi/_comicApi/_categoryData 内部对象）
// - 类开头的「wyw 适配层」将其包装为 wyw 插件接口（search/getDetail/openReader/分类四件套/浏览历史回放）
// - 已移除 wyw 无对应支撑的功能：账号登录/网络收藏/评论/点赞/评分/缩略图墙/外链识别/探索页(未映射部分)
// - Network 调用已改写为 wyw 原生风格：Network.get/post 直接返回 body 字符串，失败抛结构化异常（e.status/e.kind）

class zaimanhua extends PluginSource {
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
                Promise.resolve(this.init()).catch((e) => console.warn('[zaimanhua]', 'init 失败:', e))
            } catch (e) {
                console.warn('[zaimanhua]', 'init 失败:', e)
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
            console.error('[zaimanhua]', '搜索失败:', e)
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
        // wyw 适配：排行分类只显示第 5 组（人气/吐槽/订阅），普通分类只显示前 4 组（venera 的 showWhen 语义）
        const groups = category && category.includes('排行')
            ? this._categoryApi.optionList.filter((g, i) => i === 4)
            : this._categoryApi.optionList.filter((g, i) => i <= 3)
        return groups.map((group) => ({
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
            // venera 鐨?chapters 鍏佽鏅€氬璞℃垨 Map锛泎aimanhua 绛夋簮浼氫紶宓屽 Map<鍒嗙粍鍚? Map<epId, 鏍囬>>
            const pushFlat = (mapLike, prefix) => {
                const add = (epId, title) => {
                    chapters.push({ id: String(epId), title: prefix ? prefix + ' 路 ' + String(title) : String(title) })
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
        console.log('[zaimanhua]', '详情:', title, '章节数:', isGallery ? 0 : chapters.length)

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
            plugin: 'zaimanhua',
            method: 'loadChapterImages',
            args: [this._comicId, ep.id],
        }))
        Navigator.navigateToReader({
            comicId: this._comicId,
            comicTitle: this._comicTitle,
            chapters: chapters,
            sourceKey: 'zaimanhua',
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
            console.error('[zaimanhua]', '章节图片解析为空: comicId=' + comicId + ' epId=' + epId)
            throw '章节图片解析为空'
        }
        console.log('[zaimanhua]', '图片数:', urls.length)
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

  // 基础信息
  name = "再漫画";
  key = "zaimanhua";
  version = "1.0.2";
  url =
    "https://cdn.jsdelivr.net/gh/venera-app/venera-configs@main/zaimanhua.js";

  // 初始化请求头（wyw：无 token 时不带 authorization，匿名浏览可用）
  init() {
    this.headers = {
      "User-Agent": "Mozilla/5.0 (Linux; Android) Mobile",
    };
    const token = this.loadData("token");
    if (token) this.headers["authorization"] = `Bearer ${token}`;
  }
  // 构建 URL
  buildUrl(path) {
    this.signTask();
    return `https://v4api.zaimanhua.com/app/v1/${path}`;
  }
  // 每日签到
  async signTask() {
    if (!this.isLogged) {
      return;
    }
    if (this.loadSetting("signTask") !== '1') {
      return;
    }
    const lastSign = this.loadData("lastSign");
    const newTime = new Date().toISOString().split("T")[0];
    if (lastSign == newTime) {
      return;
    }
    const res = await Network.post("https://i.zaimanhua.com/lpi/v1/task/sign_in", this.headers);
    if (res.status !== 200) {
      return;
    }
    this.saveData("lastSign", newTime);
    if (JSON.parse(res)["errno"] == 0) {
      Dialog.showToast("签到成功");
    }
  }

  //账户管理
;

  // 状态检查
  checkResponseStatus(res) {
    
    
  }

  // 漫画解析
  parseComic(comic) {
    // const safeString = (value) => (value || "").toString().trim();
    const safeString = (value) => (value != null ? value.toString() : "");
    const resolveId = () =>
      [comic.comic_id, comic.id].find((id) => id && id !== "0") || "";
    const resolveTags = () =>
      [comic.status, ...safeString(comic.types).split("/")].filter(Boolean);
    const resolveDescription = () => {
      const candidates = [
        comic.description,
        comic.last_update_chapter_name,
        comic.last_name,
      ];
      return candidates.find((text) => text) || "";
    };

    return {
      id: safeString(resolveId()),
      title: comic.title || comic.name,
      subTitle: comic.authors,
      cover: comic.cover,
      tags: resolveTags(),
      description: resolveDescription(),
    };
  }

  //探索页面
  _explore = [
    {
      title: "再漫画 更新",
      type: "multiPageComicList",
      load: async (page) => {
        const res = await Network.get(
          this.buildUrl(`comic/update/list/0/${page}`),
          this.headers
        );
        const data = JSON.parse(res).data;
        return {
          comics: data.map((item) => this.parseComic(item)),
        };
      },
    },
  ];

  static categoryParamMap = {
    "全部": "0",
    "冒险": "4",
    "欢乐向": "5",
    "格斗": "6",
    "科幻": "7",
    "爱情": "8",
    "侦探": "9",
    "竞技": "10",
    "魔法": "11",
    "神鬼": "12",
    "校园": "13",
    "惊悚": "14",
    "其他": "16",
    "四格": "17",
    "亲情": "3242",
    "百合": "3243",
    "秀吉": "3244",
    "悬疑": "3245",
    "纯爱": "3246",
    "热血": "3248",
    "泛爱": "3249",
    "历史": "3250",
    "战争": "3251",
    "萌系": "3252",
    "宅系": "3253",
    "治愈": "3254",
    "励志": "3255",
    "武侠": "3324",
    "机战": "3325",
    "音乐舞蹈": "3326",
    "美食": "3327",
    "职场": "3328",
    "西方魔幻": "3365",
    "高清单行": "4459",
    "TS": "4518",
    "东方": "5077",
    "魔幻": "5806",
    "奇幻": "5848",
    "节操": "6219",
    "轻小说": "6316",
    "颜艺": "6437",
    "搞笑": "7568",
    "仙侠": "23388",
    "舰娘": "7900",
    "动画": "13627",
    "AA": "17192",
    "福瑞": "18522",
    "生存": "23323",
    "日常": "23388",
    "画集": "30788",
    "C100": "31137",
  };

  //分类页面
  _categoryData = {
    title: "再漫画",
    parts: [
      {
        name: "排行榜",
        type: "fixed",
        categories: ["日排行", "周排行", "月排行", "总排行"],
        itemType: "category",
        categoryParams: ["0", "1", "2", "3"],
      },
      {
        name: "分类",
        type: "fixed",
        categories: Object.keys(zaimanhua.categoryParamMap),
        categoryParams: Object.values(zaimanhua.categoryParamMap),
        itemType: "category",
      },
    ],
  };

  //分类漫画加载
  _categoryApi = {
    load: async (category, param, options, page) => {
      // wyw 适配：options 为筛选选中值数组，首次进入可能为空/缺项，全部给默认值兜底
      const d = (v, def) => (v === undefined || v === null || v === "" ? def : v);
      if (category.includes("排行")) {
        let res = await Network.get(
          this.buildUrl(
            `comic/rank/list?page=${page}&rank_type=${d(options && options[0], "0")}&by_time=${d(param, "0")}`
          ),
          this.headers
        );
        const json = JSON.parse(res);
        if (json.errno !== 0) throw "再漫画排行加载失败: " + (json.errmsg || "errno=" + json.errno);
        const list = Array.isArray(json.data) ? json.data : [];
        if (list.length === 0) console.warn("[zaimanhua]", "排行为空: category=" + category);
        return {
          comics: list.map((item) => this.parseComic(item)),
          maxPage: 10,
        };
      } else {
        param = zaimanhua.categoryParamMap[category] || "0";
        let res = await Network.get(
          this.buildUrl(
            `comic/filter/list?status=${d(options && options[2], "0")}&theme=${param}&zone=${d(options && options[3], "0")}&cate=${d(options && options[1], "0")}&sortType=${d(options && options[0], "1")}&page=${page}&size=20`
          ),
          this.headers
        );
        const json = JSON.parse(res);
        if (json.errno !== 0 || !json.data) throw "再漫画分类加载失败: " + (json.errmsg || "errno=" + json.errno);
        const data = json.data;
        const list = data.comicList || [];
        if (list.length === 0) console.warn("[zaimanhua]", "分类无结果: category=" + category + " page=" + page);
        return {
          comics: list.map((item) => this.parseComic(item)),
          maxPage: data.totalNum ? Math.ceil(data.totalNum / 20) : 200,
        };
      }
    },
    optionList: [
      {
        label: "排序",
        options: ["1-更新", "2-人气"],
        notShowWhen: null,
        showWhen: Object.keys(zaimanhua.categoryParamMap),
      },
      {
        label: "类型",
        options: [
          "0-全部",
          "3262-少年漫画",
          "3263-少女漫画",
          "3264-青年漫画",
          "13626-女青漫画",
        ],
        notShowWhen: null,
        showWhen: Object.keys(zaimanhua.categoryParamMap),
      },
      {
        label: "状态",
        options: ["0-全部", "2309-连载中", "2310-已完结", "29205-短篇"],
        notShowWhen: null,
        showWhen: Object.keys(zaimanhua.categoryParamMap),
      },
      {
        label: "地区",
        options: [
          "0-全部",
          "2304-日本",
          "2305-韩国",
          "2306-欧美",
          "2307-港台",
          "2308-内地",
          "8435-其他",
        ],
        notShowWhen: null,
        showWhen: Object.keys(zaimanhua.categoryParamMap),
      },
      {
        label: "排行维度",
        options: ["0-人气", "1-吐槽", "2-订阅"],
        notshowWhen: null,
        showWhen: ["日排行", "周排行", "月排行", "总排行"],
      },
    ],
  };

  //搜索
  _searchApi = {
    load: async (keyword, options, page) => {
      const res = await Network.get(
        this.buildUrl(
          `search/index?keyword=${encodeURIComponent(
            keyword
          )}&page=${page}&sort=0&size=20`
        ),
        this.headers
      );
      const json = JSON.parse(res);
      if (json.errno !== 0) throw "再漫画搜索失败: " + (json.errmsg || "errno=" + json.errno);
      const list = (json.data && json.data.list) || [];
      return {
        comics: list.map((item) => this.parseComic(item)),
      };
    },
    optionList: [],
  };

  //收藏
;

  // 时间戳转换
  formatTimestamp(ts) {
    const date = new Date(ts * 1000);
    return date.toISOString().split("T")[0];
  }

  //漫画详情
  _comicApi = {
    loadInfo: async (id) => {
      const getFavoriteStatus = async (id) => {
        // wyw 已移除账号：收藏状态接口容错，失败不影响详情加载
        try {
          let res = await Network.get(
            this.buildUrl(`comic/sub/checkIsSub?objId=${id}&source=1`),
            this.headers
          );
          const json = JSON.parse(res);
          return (json.data || {}).isSub === true;
        } catch (_) {
          return false;
        }
      };
      let results = await Promise.all([
        Network.get(
          this.buildUrl(`comic/detail/${id}?channel=android`),
          this.headers
        ),
        getFavoriteStatus.bind(this)(id),
      ]);
      const response = JSON.parse(results[0]);
      if (response.errno !== 0) throw new Error(response.errmsg || "加载失败");
      const data = response.data.data;

      function processChapters(groups) {
        return (groups || []).reduce((result, group) => {
          const groupTitle = group.title || "默认";
          const chapters = (group.data || [])
            .reverse()
            .map((ch) => [
              String(ch.chapter_id),
              `${ch.chapter_title.replace(
                /^(?:连载版?)?(\d+\.?\d*)([话卷])?$/,
                (_, n, t) => `第${n}${t || "话"}`
              )}`,
            ]);
          result.set(groupTitle, new Map(chapters));
          return result;
        }, new Map());
      }
      // 分类标签
      const { authors, status, types } = data;
      const tagMapper = (arr) => arr.map((t) => t.tag_name);
      return {
        title: data.title,
        cover: data.cover,
        description: data.description,
        tags: {
          "作者": tagMapper(authors),
          "状态": [...tagMapper(status), data.last_update_chapter_name],
          "标签": tagMapper(types),
        },
        updateTime: this.formatTimestamp(data.last_updatetime),
        chapters: processChapters(data.chapters),
        isFavorite: results[1],
        subId: id,
      };
    },
    loadEp: async (comicId, epId) => {
      const res = await Network.get(
        this.buildUrl(`comic/chapter/${comicId}/${epId}`),
        this.headers
      );
      const json = JSON.parse(res);
      const data = json.data && json.data.data;
      if (!data || (!data.page_url_hd && !data.page_url)) {
        console.error("[zaimanhua]", "章节图片解析失败: comicId=" + comicId + " epId=" + epId + " body=" + String(res).slice(0, 150));
        throw "再漫画章节加载失败: " + (json.errmsg || "未返回图片数据");
      }
      return { images: data.page_url_hd || data.page_url };
    },
    
  
    // 发送评论, 返回任意值表示成功.
    // 点赞
  };

  settings = {
    signTask: {
      title: "每日签到",
      type: "select",
      options: [
        { value: '1', text: '开' },
        { value: '0', text: '关' },
      ],
      default: '0'
    }
  };
}
