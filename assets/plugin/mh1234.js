// description: 漫画1234 漫画源 — 搜索/分类/详情/阅读（由 venera mh1234.js v1.0.0 移植，转换脚本自动生成）
// type: manga
//
// 由 venera 源自动转换：
// - 保留原站点的搜索/分类/详情/阅读核心逻辑（_searchApi/_categoryApi/_comicApi/_categoryData 内部对象）
// - 类开头的「wyw 适配层」将其包装为 wyw 插件接口（search/getDetail/openReader/分类四件套/浏览历史回放）
// - 已移除 wyw 无对应支撑的功能：账号登录/网络收藏/评论/点赞/评分/缩略图墙/外链识别/探索页(未映射部分)
// - Network 调用已改写为 wyw 原生风格：Network.get/post 直接返回 body 字符串，失败抛结构化异常（e.status/e.kind）

class mh1234 extends PluginSource {
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
                Promise.resolve(this.init()).catch((e) => console.warn('[mh1234]', 'init 失败:', e))
            } catch (e) {
                console.warn('[mh1234]', 'init 失败:', e)
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
            console.error('[mh1234]', '搜索失败:', e)
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
        console.log('[mh1234]', '详情:', title, '章节数:', isGallery ? 0 : chapters.length)

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
            plugin: 'mh1234',
            method: 'loadChapterImages',
            args: [this._comicId, ep.id],
        }))
        Navigator.navigateToReader({
            comicId: this._comicId,
            comicTitle: this._comicTitle,
            chapters: chapters,
            sourceKey: 'mh1234',
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
            console.error('[mh1234]', '章节图片解析为空: comicId=' + comicId + ' epId=' + epId)
            throw '章节图片解析为空'
        }
        console.log('[mh1234]', '图片数:', urls.length)
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

    // name of the source
    name = "漫画1234"

    // unique id of the source
    key = "mh1234"

    version = "1.0.0"


    // update url

    settings = {
        domains: {
            title: "域名",
            type: "input",
            default: "amh1234.com"
        }
    }

    get baseUrl() {
        return `https://b.${this.loadSetting('domains')}`;
    }

    // explore page list
    _explore = [{
        title: "漫画1234",
        type: "singlePageWithMultiPart",
        load: async () => {
            const result = {};
            const res = await Network.get(this.baseUrl);
            
            const doc = new HtmlDocument(res);
            const mangaLists = doc.querySelectorAll("div.imgBox");
            for (let list of mangaLists) {
                const tabTitle = list.querySelector(".Title").text;
                const items = [];
                for (let item of list.querySelectorAll("li.list-comic")) {
                    const info = item.querySelectorAll("a")[1];
                    items.push(({
                        id: item.attributes["data-key"],
                        title: item.querySelector("a.txtA").text,
                        cover: item.querySelector("img").attributes["src"]
                    }));
                }
                result[tabTitle] = items;
            }
            return result;
        }
    }];

    // categories
    _categoryData = {
        /// title of the category page, used to identify the page, it should be unique
        title: "漫画1234",
        parts: [
            {
                name: "题材",
                type: "fixed",
                categories: [
                    "全部", "少年热血", "武侠格斗", "科幻魔幻", "竞技体育", "爆笑喜剧", "侦探推理", "恐怖灵异", "耽美人生",
                    "少女爱情", "恋爱生活", "生活漫画", "战争漫画", "故事漫画", "其他漫画", "爱情", "唯美", "武侠", "玄幻",
                    "后宫", "治愈", "励志", "古风", "校园", "虐心", "魔幻", "冒险", "欢乐向", "节操", "悬疑", "历史", "职场",
                    "神鬼", "明星", "穿越", "百合", "西方魔幻", "纯爱", "音乐舞蹈", "轻小说", "侦探", "伪娘", "仙侠", "四格",
                    "剧情", "萌系", "东方", "性转换", "宅系", "美食", "脑洞", "惊险", "爆笑", "都市", "蔷薇", "恋爱", "格斗",
                    "科幻", "魔法", "奇幻", "热血", "其他", "搞笑", "生活", "恐怖", "架空", "竞技", "战争", "搞笑喜剧", "青春",
                    "浪漫", "爽流", "神话", "轻松", "日常", "家庭", "婚姻", "动作", "战斗", "异能", "内涵", "同人", "惊奇",
                    "正剧", "推理", "宠物", "温馨", "异世界", "颜艺", "惊悚", "舰娘","机战", "彩虹", "耽美", "轻松搞笑",
                    "修真恋爱架空", "复仇", "霸总", "段子", "逆袭", "烧脑", "娱乐圈", "纠结", "感动", "豪门", "体育", "机甲",
                    "末世", "灵异", "僵尸", "宫廷", "权谋", "未来", "科技", "商战", "乡村", "震撼", "游戏", "重口味", "血腥",
                    "逗比", "丧尸", "神魔", "修真", "社会", "召唤兽", "装逼", "新作", "漫改", "真人", "运动", "高智商", "悬疑推理",
                    "机智", "史诗", "萝莉", "宫斗", "御姐", "恶搞", "精品", "日更", "小说改编", "防疫", "吸血", "暗黑", "总裁",
                    "重生", "大女主", "系统", "神仙", "末日", "怪物", "妖怪", "修仙", "宅斗", "神豪", "高甜", "电竞", "豪快",
                    "猎奇", "多世界", "性转", "少女", "改编", "女生", "乙女", "男生", "兄弟情", "智斗", "少男", "连载", "奇幻冒险",
                    "古风穿越", "浪漫爱情", "古装", "幽默搞笑", "偶像", "小僵尸", "BL", "少年", "橘味", "情感", "经典",
                    "腹黑", "都市大女主", "致郁", "美少女", "少儿", "暖萌", "长条", "限制级", "知音漫客", "氪金", "独家",
                    "亲情", "现代", "武侠仙侠", "西幻", "超级英雄", "女神", "幻想", "欧风", "养成", "动作冒险", "GL", "橘调",
                    "悬疑灵异", "古代宫廷", "欧式宫廷", "游戏竞技", "橘系", "奇幻爱情", "架空世界", "ゆり", "福瑞", "秀吉", "现代言情",
                    "古代言情", "豪门总裁", "现言萌宝", "玄幻言情", "虐渣", "团宠", "古言萌宝", "现言甜宠", "古言脑洞", "AA", "金手指",
                    "玄幻脑洞", "都市脑洞", "甜宠", "伦理", "生存", "TL", "悬疑脑洞", "黑暗", "独特", "成长", "幻想言情", "直播",
                    "游戏体育", "现言脑洞", "音乐", "双男主", "迪化", "LGBTQ+", "正能量", "军事", "ABO", "悬疑恐怖",
                    "玄幻科幻", "投稿", "种田", "经营", "反套路", "无节操", "强强", "克苏鲁", "无敌流", "冒险热血", "畅销",
                    "大人系", "宅向", "萌娃", "宠兽", "异形", "撒糖", "诡异", "言情", "西方", "滑稽搞笑", "同居", "人外",
                    "白切黑", "并肩作战", "救赎", "戏精", "美强惨", "非人类", "原创", "黑白漫", "无限流",
                    "升级", "爽", "轻橘", "女帝", "偏执", "自由", "星际", "可盐可甜", "反差萌", "聪颖", "智商在线",
                    "倔强", "狼人", "欢喜冤家", "吸血鬼", "萌宠", "学校", "台湾作品", "彩色", "武术", "短篇", "契约", "魔王",
                    "无敌", "美女", "暧昧", "网游", "宅男", "追逐梦想", "冒险奇幻", "疯批", "中二", "召唤", "法宝", "钓系", "鬼怪",
                    "占有欲", "阳光", "元气", "强制爱", "黑道", "马甲", "阴郁", "忧郁", "哲理", "病娇", "喜剧", "江湖恩怨",
                    "相爱相杀", "萌", "SM", "精选", "生子", "年下", "18+限制", "日久生情", "梦想", "多攻", "竹马", "骨科", "gnbq"
                  ],
                itemType: "category",
                categoryParams: [
                    "", "shaonianrexue", "wuxiagedou", "kehuanmohuan", "jingjitiyu", "baoxiaoxiju", "zhentantuili", "kongbulingyi",
                    "danmeirensheng", "shaonvaiqing", "lianaishenghuo", "shenghuomanhua", "zhanzhengmanhua", "gushimanhua",
                    "qitamanhua", "aiqing", "weimei", "wuxia", "xuanhuan", "hougong", "zhiyu", "lizhi", "gufeng", "xiaoyuan", "nuexin",
                    "mohuan", "maoxian", "huanlexiang", "jiecao", "xuanyi", "lishi", "zhichang", "shengui", "mingxing", "chuanyue",
                    "baihe", "xifangmohuan", "chunai", "yinyuewudao", "qingxiaoshuo", "zhentan", "weiniang", "xianxia", "sige", "juqing",
                    "mengxi", "dongfang", "xingzhuanhuan", "zhaixi", "meishi", "naodong", "jingxian", "baoxiao", "dushi", "qiangwei",
                    "lianai", "gedou", "kehuan", "mofa", "qihuan", "rexue", "qita", "gaoxiao", "shenghuo", "kongbu", "jiakong", "jingji",
                    "zhanzheng", "gaoxiaoxiju", "qingchun", "langman", "shuangliu", "shenhua", "qingsong", "richang", "jiating", "hunyin",
                    "dongzuo", "zhandou", "yineng", "neihan", "tongren", "jingqi", "zhengju", "tuili", "chongwu", "wenxin", "yishijie",
                    "yanyi", "jingsong", "jianniang", "jizhan", "caihong", "danmei", "qingsonggaoxiao", "xiuzhenlianaijiakong", "fuchou",
                    "bazong", "duanzi", "nixi", "shaonao", "yulequan", "jiujie", "gandong", "haomen", "tiyu", "jijia", "moshi", "lingyi",
                    "jiangshi", "gongting", "quanmou", "weilai", "keji", "shangzhan", "xiangcun", "zhenhan", "youxi",
                    "zhongkouwei", "xuexing", "doubi", "sangshi", "shenmo", "xiuzhen", "shehui", "zhaohuanshou", "zhuangbi",
                    "xinzuo", "mangai", "zhenren", "yundong", "gaozhishang", "xuanyituili", "jizhi", "shishi", "luoli","gongdou",
                    "yujie", "egao", "jingpin", "rigeng", "xiaoshuogaibian", "fangyi", "xixie", "anhei", "zongcai", "zhongsheng",
                    "danvzhu", "xitong", "shenxian", "mori", "guaiwu", "yaoguai", "xiuxian", "zhaidou", "shenhao", "gaotian",
                    "dianjing", "haokuai", "lieqi", "duoshijie", "xingzhuan", "shaonv", "gaibian", "nvsheng", "yinv", "nansheng",
                    "xiongdiqing", "zhidou", "shaonan", "lianzai", "qihuanmaoxian", "gufengchuanyue", "langmanaiqing", "guzhuang",
                    "youmogaoxiao", "ouxiang", "xiaojiangshi", "BL", "shaonian", "juwei", "qinggan", "jingdian",
                    "fuhei", "dushidanvzhu", "zhiyu2", "meishaonv", "shaoer", "nuanmeng", "changtiao", "xianzhiji", "zhiyinmanke",
                    "kejin", "dujia", "qinqing", "xiandai", "wuxiaxianxia", "xihuan", "chaojiyingxiong", "nvshen", "huanxiang",
                    "oufeng", "yangcheng", "dongzuomaoxian", "GL", "judiao", "xuanyilingyi", "gudaigongting", "oushigongting",
                    "youxijingji", "juxi", "qihuanaiqing", "jiakongshijie", "unknown", "furui", "xiuji", "xiandaiyanqing", "gudaiyanqing",
                    "haomenzongcai", "xianyanmengbao", "xuanhuanyanqing", "nuezha", "tuanchong", "guyanmengbao", "xianyantianchong",
                    "guyannaodong", "AA", "jinshouzhi", "xuanhuannaodong", "dushinaodong", "tianchong", "lunli", "shengcun", "TL",
                    "xuanyinaodong", "heian", "dute", "chengzhang", "huanxiangyanqing", "zhibo", "youxitiyu", "xianyannaodong",
                    "yinyue", "shuangnanzhu", "dihua", "LGBTQ", "zhengnengliang", "junshi", "ABO", "xuanyikongbu", "xuanhuankehuan", "tougao",
                    "zhongtian", "jingying", "fantaolu", "wujiecao", "qiangqiang", "kesulu", "wudiliu", "maoxianrexue", "changxiao",
                    "darenxi", "zhaixiang", "mengwa", "chongshou", "yixing", "satang", "guiyi", "yanqing", "xifang", "huajigaoxiao", "tongju",
                    "renwai", "baiqiehei", "bingjianzuozhan", "jiushu", "xijing", "meiqiangcan", "feirenlei", "yuanchuang", "heibaiman",
                    "wuxianliu", "shengji", "shuang", "qingju", "nvdi", "pianzhi", "ziyou", "xingji", "keyanketian", "fanchameng", "congying",
                    "zhishangzaixian", "juejiang", "langren", "huanxiyuanjia", "xixiegui", "mengchong", "xuexiao", "taiwanzuopin", "caise",
                    "wushu", "duanpian", "qiyue", "mowang", "wudi", "meinv", "aimei", "wangyou", "zhainan", "zhuizhumengxiang", "maoxianqihuan",
                    "fengpi", "zhonger", "zhaohuan", "fabao", "diaoxi", "guiguai", "zhanyouyu", "yangguang", "yuanqi", "qiangzhiai", "heidao",
                    "majia", "yinyu", "youyu", "zheli", "bingjiao", "xiju", "jianghuenyuan", "xiangaixiangsha", "meng", "SM", "jingxuan", "shengzi",
                    "nianxia", "18xianzhi", "rijiushengqing", "mengxiang", "duogong", "zhuma", "guke", "gnbq"
                ],
            }
        ],
        // enable ranking page
        enableRankingPage: false,
    }

    parseComics(html, onePage = false) {
        const doc = new HtmlDocument(html);
        const comics = [];
        for (let comic of doc.querySelectorAll(".itemBox")) {
            comics.push(({
                id: comic.attributes["data-key"],
                title: comic.querySelector(".title").text,
                cover: comic.querySelector("img").attributes["src"]
            }));
        }
        return {comics: comics, maxPage: onePage ? 1 : parseInt(doc.querySelector("#total-page").attributes["value"])};
    }

    parseList(doc) {
        const comics = [];
        for (let comic of doc.querySelectorAll(".list-comic")) {
            comics.push(({
                id: comic.attributes["data-key"],
                title: comic.querySelector(".txtA").text,
                cover: comic.querySelector("img").attributes["src"]
            }));
        }
        return comics;
    }

    /// category comic loading related
    _categoryApi = {
        load: async (category, params, options, page) => {
            const d = (v, def) => (v === undefined || v === null || v === "" ? def : v)
            options = Array.isArray(options) ? options : []
            if (params.endsWith(".html")) {
                const res = await Network.get(`${this.baseUrl}${params}`);
                
                return this.parseComics(res, true);
            } else {
                const res = await Network.get(`${this.baseUrl}/list/?filter=${params}-${d(options[0], '0')}-${d(options[1], '0')}-${d(options[2], '0')}&sort=${d(options[3], '0')}&page=${page}`);
                console.warn(`${this.baseUrl}/list/?filter=${params}-${d(options[0], '0')}-${d(options[1], '0')}-${d(options[2], '0')}&sort=${d(options[3], '0')}&page=${page}`)
                
                const doc = new HtmlDocument(res);
                return {comics: this.parseList(doc),
                    maxPage: parseInt(doc.querySelector("#total-page").attributes["value"])};
            }
        },
        optionLoader: async (category, params) => {
            if (!params.endsWith(".html")) {
                return [
                    {
                        options: [
                            "-全部",
                            "ertong-儿童漫画",
                            "shaonian-少年漫画",
                            "shaonv-少女漫画",
                            "qingnian-青年漫画",
                            "bailingmanhua-白领漫画",
                            "tongrenmanhua-同人漫画"
                        ]
                    },
                    {
                        options: [
                            "-全部",
                            "wanjie-已完结",
                            "lianzai-连载中",
                        ]
                    },
                    {
                        options: [
                            "-全部",
                            "rhmh-日韩",
                            "dlmh-大陆",
                            "gtmh-港台",
                            "taiwan-台湾",
                            "ommh-欧美",
                            "hanguo-韩国",
                            "qtmg-其他",
                        ]
                    },
                    {
                        options: [
                            "update-更新",
                            "post-发布",
                            "click-点击",
                        ]
                    },
                ];
            }
            return [];
        }
    }

    /// search related
    _searchApi = {
        load: async (keyword, options, page) => {
            const res = await Network.get(`${this.baseUrl}/search/?keywords=${keyword}&sort=${options[0]}&page=${page}`);
            
            return this.parseComics(res);
        },

        // provide options for search
        optionList: [
            {
                options: [
                    "update-更新",
                    "post-发布",
                    "click-点击",
                ],
                label: "排序"
            }
        ],

        // enable tags suggestions
    }

    /// single comic related
    _comicApi = {
        loadInfo: async (id) => {
            const res = await Network.get(`${this.baseUrl}/comic/${id}.html`);
            
            const doc = new HtmlDocument(res);
            const title = doc.querySelector(".BarTit").text;
            const cover = doc.querySelector(".pic").querySelector("img").attributes["src"];
            const description = doc.querySelector("#full-des")?.text;
            const infos = doc.querySelectorAll(".txtItme");
            const tags = [];
            for (let tag of doc.querySelector(".sub_r").querySelectorAll("a")) {
                const tag_name = tag.text;
                if (tag_name.length > 0) {
                    tags.push(tag_name);
                }
            }
            const chapters = {};
            const chapterElements = doc.querySelector(".chapter-warp")?.querySelectorAll("li");
            if (chapterElements) {
                for (let ch of chapterElements) {
                    const id = ch.querySelector("a").attributes["href"].replace("/comic/", "").replace(".html", "").split("/").join("_");
                    chapters[id] = ch.querySelector("span").text;
                }
            }
            return {
                title: title,
                cover: cover,
                description: description,
                tags: {
                    "作者": [infos[0].text.replaceAll("\n", "").replaceAll("\r", "").trim()],
                    "更新": [infos[3].querySelector(".date").text],
                    "标签": tags.slice(0,-1)
                },
                chapters: chapters,
                recommend: this.parseList(doc)
            };

        },

        loadEp: async (comicId, epId) => {
            const ids = epId.split("_");
            const res = await Network.get(`${this.baseUrl}/comic/${ids[0]}/${ids[1]}.html`);
            
            const html = res;
            const start = html.search(`var chapterImages = `) + 22;
            const end = html.search(`;var chapterPath = `) - 2;
            const end2 = html.search(`;var chapterPrice`) - 1;
            const images = html.substring(start, end).split(`","`);
            const cpath = html.substring(end + 22, end2);
            for (let i = 0; i < images.length; i++) {
                images[i] = "https://gmh1234.wszwhg.net/" + cpath + images[i].replaceAll("\\", "");
                images[i] = images[i].replaceAll("//", "/");
            }
            return { images };
        },

        // enable tags translate
    }
}