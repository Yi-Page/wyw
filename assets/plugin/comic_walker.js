// description: カドコミ 漫画源 — 搜索/分类/详情/阅读（由 venera comic_walker.js v1.0.0 移植，转换脚本自动生成）
// type: manga
//
// 由 venera 源自动转换：
// - 保留原站点的搜索/分类/详情/阅读核心逻辑（_searchApi/_categoryApi/_comicApi/_categoryData 内部对象）
// - 类开头的「wyw 适配层」将其包装为 wyw 插件接口（search/getDetail/openReader/分类四件套/浏览历史回放）
// - 已移除 wyw 无对应支撑的功能：账号登录/网络收藏/评论/点赞/评分/缩略图墙/外链识别/探索页(未映射部分)
// - Network 调用已改写为 wyw 原生风格：Network.get/post 直接返回 body 字符串，失败抛结构化异常（e.status/e.kind）

class comic_walker extends PluginSource {
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
                Promise.resolve(this.init()).catch((e) => console.warn('[comic_walker]', 'init 失败:', e))
            } catch (e) {
                console.warn('[comic_walker]', 'init 失败:', e)
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
            console.error('[comic_walker]', '搜索失败:', e)
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
        console.log('[comic_walker]', '详情:', title, '章节数:', isGallery ? 0 : chapters.length)

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
            plugin: 'comic_walker',
            method: 'loadChapterImages',
            args: [this._comicId, ep.id],
        }))
        Navigator.navigateToReader({
            comicId: this._comicId,
            comicTitle: this._comicTitle,
            chapters: chapters,
            sourceKey: 'comic_walker',
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
            console.error('[comic_walker]', '章节图片解析为空: comicId=' + comicId + ' epId=' + epId)
            throw '章节图片解析为空'
        }
        console.log('[comic_walker]', '图片数:', urls.length)
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

  name = "カドコミ";
  key = "comic_walker";
  version = "1.0.0";
  url =
    "https://cdn.jsdelivr.net/gh/venera-app/venera-configs@main/comic_walker.js";

  api_key = "ytBrdQ2ZYdRQguqEusVLxQVUgakNnVht";

  latestVersion = "1.4.13";

  api_base = "https://mobileapp.comic-walker.com";

  get headers() {
    const headers = {
      "X-API-Environment-Key": this.api_key,
      "User-Agent": `BookWalkerApp/${this.latestVersion} (Android 13)`,
      "Host": "mobileapp.comic-walker.com",
      "Content-Type": "application/json"
    };
    const token = this.loadData("token");
    if (token) {
      headers["Authorization"] = `Bearer ${token}`;
    }
    return headers;
  }

  async refreshToken() {
    const res = await this.request(
      `${this.api_base}/v1/users`,
      this.headers,
      "POST",
    );

    this.saveData("token", res.resources.access_token);
    return res.resources.access_token;
  }

  async request(url, headers, method = "GET", data) {
    let response;
    if (method === "GET") {
      response = await Network.get(url, headers);
    } else if (method === "POST") {
      response = await Network.post(url, headers, data);
    } else {
      throw new Error(`Unsupported method: ${method}`);
    }
    if (
      response.status === 204
    ) {
      return response;
    }
    response = JSON.parse(response);
    if (
      response.code === "invalid_request_parameter" ||
      response.code === "free_daily_reward_quota_exceeded" ||
      response.code === "unauthorized"
    ) {
      await this.refreshToken();
      if (method === "GET") {
        response = await Network.get(url, this.headers);
      } else if (method === "POST") {
        response = await Network.post(url, this.headers, data);
      } else {
        throw new Error(`Unsupported method: ${method}`);
      }
      if (
        response.status === 204
      ) {
        return response;
      }
      response = JSON.parse(response);
    }
    return response;
  }

  async init() {
    const itunes_api = "https://itunes.apple.com/lookup?bundleId=jp.co.bookwalker.cwapp.ios&country=jp";

    const resp = await Network.get(itunes_api);

    if (resp.status == 200) {
      response = JSON.parse(resp);
      this.latestVersion = response.version;
    }

    await this.refreshToken();
  }

  _explore = [
    {
      title: "カドコミ",
      type: "singlePageWithMultiPart",
      load: async () => {
        const res = await this.request(
          `${this.api_base}/v2/screens/home`,
          this.headers,
        );

        const result = {};

        const newArrivals = res.resources.new_arrival_comics.map((item) =>
          ({
            id: item.id,
            title: item.title,
            cover: item.thumbnail_1x1 || "",
            tags: item.comic_labels?.map((l) => l.name) || [],
          }),
        );
        result["今日の更新"] = newArrivals;

        const attention = res.resources.attention_comics.map((item) =>
          ({
            id: item.comic_id,
            title: item.title,
            cover: item.image_url || "",
            tags: item.comic_labels?.map((l) => l.name) || [],
          }),
        );
        result["注目作品"] = attention;

        for (const pickup of res.resources.pickup_comics) {
            const comics = pickup.comics.map((item) =>
                ({
                    id: item.id,
                    title: item.title,
                    cover: item.thumbnail_1x1 || "",
                    tags: item.comic_labels?.map((l) => l.name) || [],
                }),
            );
            result[pickup.name] = comics;
        }

        const newSerialization = res.resources.new_serialization_comics.map((item) =>
            ({
                id: item.id,
                title: item.title,
                cover: item.thumbnail_1x1 || "",
                tags: item.comic_labels?.map((l) => l.name) || [],
            }),
        );
        result["新連載"] = newSerialization;


        return result;
      },
    },
  ];

  // —— wyw 分类：由 venera explore（singlePageWithMultiPart）映射 ——
  // 探索页板块是动态数据：这里合并所有板块作为「首页推荐」分类（单页）
  getCategory() {
    return { title: this.name, parts: [{ name: '探索', categories: ['首页推荐'] }] }
  }
  getCategoryOptions(category) {
    return null
  }
  async _fetchCategoryComics(category, page = 1, options = []) {
    if (page > 1) return { comics: [], maxPage: 1 }
    const data = await this._explore[0].load.call(this)
    const comics = []
    for (const k of Object.keys(data || {})) comics.push(...(data[k] || []))
    return { comics: comics, maxPage: 1 }
  }
  async loadCategory(category, page = 1, options = []) {
    const res = await this._fetchCategoryComics(category, page, options)
    return [UI.Pagination({ page: 1, maxPage: 1, pageMethod: 'loadCategoryPage', pageArgs: [category, 1, options] })]
  }
  async loadCategoryPage(category, page = 1, options = []) {
    const res = await this._fetchCategoryComics(category, page, options)
    return ((res && res.comics) || []).map((c) => this._comicCard(c)).filter((x) => x != null)
  }

  _searchApi = {
    load: async (keyword, _, page) => {
      const res = await this.request(
        `${this.api_base}/v1/search/comics?keyword=${keyword}&limit=20&offset=${
          (page - 1) * 20
        }`,
        this.headers,
      );

      const comics = res.resources.map((item) =>
        ({
          id: item.id,
          title: item.title,
          cover: item.thumbnail_1x1 || "",
          tags: [
            ...(item.authors?.map((a) => a.name) || []),
            ...(item.comic_labels?.map((l) => l.name) || []),
          ],
        })
      );
      const pageInfo = {
        hasNextPage: res.resources.length === 20,
        endCursor: null,
      };

      return {
        comics,
        maxPage: pageInfo.hasNextPage ? (page || 1) + 1 : (page || 1),
        endCursor: pageInfo.endCursor,
      };
    },
  };

  _comicApi = {
    loadInfo: async (id) => {
      const res = await this.request(
        `${this.api_base}/v2/screens/comics/${id}`,
        this.headers,
      );
      const detail = res.resources.detail;

      const totalCount = res.resources.episode_total_count || 0;
      let episodes = { resources: [] };
      for (let offset = 0; offset < totalCount; offset += 100) {
        const chunk = await this.request(
          `${this.api_base}/v1/comics/${id}/episodes?offset=${offset}&limit=100&sort=asc`,
          this.headers,
        );
        episodes.resources.push(...(chunk.resources || []));
      }

      const tags = new Map();

      if (detail.authors) {
        detail.authors.forEach((a) => {
          if (!tags.has(a.role)) tags.set(a.role, []);
          tags.get(a.role).push(a.name);
        });
      }

      if (detail.comic_labels) {
        detail.comic_labels.forEach((l) => {
          if (!tags.has("Labels")) tags.set("Labels", []);
          tags.get("Labels").push(l.name);
        });
      }

      if (detail.tags) {
        detail.tags.forEach((t) => {
          if (!tags.has(t.type)) tags.set(t.type, []);
          tags.get(t.type).push(t.name);
        });
      }

      const chapters = new Map();
      for (const ep of episodes.resources) {
        let canRent = false;
        const plans = (ep.plans || []).filter((plan) =>
      plan.type !== "paid"
        );
        if (Array.isArray(plans) && plans.length > 0) {
      canRent = true;
        }
        const title = canRent ? ep.title : `❌ ${ep.title}`;
        chapters.set(ep.id, title);
      }

      return ({
        title: detail.title,
        subtitle: detail.authors?.map((a) => a.name).join("・") || "",
        cover: detail.thumbnail_1x1 || "",
        description: detail.story?.replace(/<br\s*\/?>/gi, "\n") || "",
        tags,
        chapters,
        updateTime: detail.next_update_at,
        url: detail.share_url,
        maxPage: totalCount,
      });
    },

    loadEp: async (comicId, epId) => {
      let detail = await this.request(
        `${this.api_base}/v1/episodes/${epId}`,
        this.headers,
      );
      const plans = (detail.plans || []).filter((plan) =>
        // plan.type !== "daily_video_free" &&
        plan.type !== "paid"
      );
      if (
        !Array.isArray(plans) ||
        plans.length === 0
      ) {
        throw new Error("No available rental plans after filtering");
      }
      console.log(plans);
      const freePlan = plans.find((plan) => plan.type === "free");
      if (!freePlan) {
        const plan = plans[randomInt(0, plans.length - 1)];
        await this.request(
          `${this.api_base}/v1/users/me/rental_episodes`,
          this.headers,
          "POST",
          { episode_id: epId, reading_method: plan.type },
        );
      }
      let res = await this.request(
        `${this.api_base}/v1/screens/comics/${comicId}/episodes/${epId}/viewer`,
        this.headers,
      );
      const manuscripts = res.resources.manuscripts || [];
      return {
        images: manuscripts.map((m) =>
          `${m.drm_image_url}&drm_hash=${m.drm_hash}`
        ),
      };
    },

    onImageLoad: (url) => {
      let drm_hash = null;
      let cleanUrl = url;
      const drmHashMatch = url.match(/[?&]drm_hash=([^&]+)/);
      if (drmHashMatch) {
        drm_hash = decodeURIComponent(drmHashMatch[1]);
        cleanUrl = url.replace(/([?&])drm_hash=[^&]+(&)?/, (match, p1, p2) => {
          if (p2) return p1;
          return "";
        }).replace(/[?&]$/, "");
      }
      cleanUrl = cleanUrl.replace(/([?&])weight=[^&]+(&)?/, (match, p1, p2) => {
        if (p2) return p1;
        return "";
      }).replace(/[?&]$/, "");

      cleanUrl = cleanUrl.replace(/([?&])height=[^&]+(&)?/, (match, p1, p2) => {
        if (p2) return p1;
        return "";
      }).replace(/[?&]$/, "");

      if (drm_hash.length < 2) {
        throw new Error(
          "drm_hash must be at least 2 characters long",
        );
      }
      var version = drm_hash.slice(0, 2);
      if (version !== "01") {
        throw new Error("Unsupported version: " + version);
      }
      var key_part = drm_hash.slice(2);
      if (key_part.length < 16) {
        throw new Error(
          "Key part must be 16 characters long (8 hex numbers)",
        );
      }
      var key = [];
      for (var i = 0; i < 8; i++) {
        key.push(parseInt(key_part.slice(i * 2, i * 2 + 2), 16));
      }

      const keyArray = key;
      const onResponseScript = `
        function onResponse(buffer) {
          var key = [${keyArray.join(',')}];
          var view = new Uint8Array(buffer);
          for (var i = 0; i < view.length; i++) {
        view[i] ^= key[i % key.length];
          }
          return buffer;
        }
        onResponse;
      `;
      return {
        url: cleanUrl,
        headers: this.headers,
        onResponse: async (buffer)  => {
          return await compute(onResponseScript, buffer);
        }
      };
    },

  };
}
