// description: Komga 漫画源 — 搜索/分类/详情/阅读（由 venera komga.js v1.0.0 移植，转换脚本自动生成）
// type: manga
//
// 由 venera 源自动转换：
// - 保留原站点的搜索/分类/详情/阅读核心逻辑（_searchApi/_categoryApi/_comicApi/_categoryData 内部对象）
// - 类开头的「wyw 适配层」将其包装为 wyw 插件接口（search/getDetail/openReader/分类四件套/浏览历史回放）
// - 已移除 wyw 无对应支撑的功能：账号登录/网络收藏/评论/点赞/评分/缩略图墙/外链识别/探索页(未映射部分)
// - Network 调用已改写为 wyw 原生风格：Network.get/post 直接返回 body 字符串，失败抛结构化异常（e.status/e.kind）

class komga extends PluginSource {
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
                Promise.resolve(this.init()).catch((e) => console.warn('[komga]', 'init 失败:', e))
            } catch (e) {
                console.warn('[komga]', 'init 失败:', e)
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
            console.error('[komga]', '搜索失败:', e)
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
        console.log('[komga]', '详情:', title, '章节数:', isGallery ? 0 : chapters.length)

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
            plugin: 'komga',
            method: 'loadChapterImages',
            args: [this._comicId, ep.id],
        }))
        Navigator.navigateToReader({
            comicId: this._comicId,
            comicTitle: this._comicTitle,
            chapters: chapters,
            sourceKey: 'komga',
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
            console.error('[komga]', '章节图片解析为空: comicId=' + comicId + ' epId=' + epId)
            throw '章节图片解析为空'
        }
        console.log('[komga]', '图片数:', urls.length)
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

	name = "Komga"

	key = "komga"

	version = "1.0.0"



	settings = {
		base_url: {
			title: "服务器地址",
			type: "input",
			default: "https://demo.komga.org",
			validator: "^(https?:\\/\\/).+$"
		},
		default_username: {
			title: "服务器账号",
			type: "input",
			default: ""
		},
		default_password: {
			title: "服务器密码",
			type: "input",
			default: ""
		}
	}

	get baseUrl() {
		let raw = this.loadSetting('base_url')
		if (typeof raw !== 'string' || !raw.trim()) {
			raw = this.settings.base_url.default
		}
		let value = raw.trim()
		if (!/^https?:\/\//i.test(value)) {
			value = `https://${value}`
		}
		return value.replace(/\/$/, '')
	}

	get authToken() {
		const stored = this.loadData('komga_auth')
		if (stored) {
			return stored
		}
		const username = this.loadSetting('default_username')
		const password = this.loadSetting('default_password')
		if (!username || !password) {
			return null
		}
		const encoded = Convert.encodeBase64(Convert.encodeUtf8(`${username}:${password}`))
		return typeof encoded === 'string' ? encoded : Convert.decodeUtf8(encoded)
	}

	get headers() {
		const headers = { "Accept": "application/json" }
		const token = this.authToken
		if (token) headers["Authorization"] = `Basic ${token}`
		return headers
	}

	get imageHeaders() {
		const token = this.authToken
		return token ? { "Authorization": `Basic ${token}` } : {}
	}

	async init() {
		try {
			await this.refreshReferenceData(false)
		} catch (_) {
		}
	}


	_explore = [
		{
			title: "Komga",
			type: "singlePageWithMultiPart",
			load: async () => {
				await this.refreshReferenceData(false)
				const feeds = {}
				const latest = await this.fetchSeriesList('/api/v1/series/latest', { size: 12, page: 0 })
				if (latest.comics.length) feeds["最新上架"] = latest.comics
				const updated = await this.fetchSeriesList('/api/v1/series/updated', { size: 12, page: 0 })
				if (updated.comics.length) feeds["最近更新"] = updated.comics
				const libraries = this.loadData('komga_libraries')
				if (Array.isArray(libraries)) {
					for (const library of libraries.slice(0, 4)) {
						const list = await this.fetchSeriesList('/api/v1/series', {
							page: 0,
							size: 12,
							sort: ['metadata.lastModified,desc'],
							library_id: [library.id]
						})
						if (list.comics.length) feeds[`书库 ${library.name}`] = list.comics
					}
				}
				if (!Object.keys(feeds).length) {
					throw '未找到可展示的数据，请确认已登录且服务器可用'
				}
				return feeds
			}
		}
	]

	_categoryData = {
		title: "Komga",
		parts: [
			{
				name: "常用",
				type: "dynamic",
				loader: () => (
					[
						{
							label: "all",
							target: {
								page: 'category',
								attributes: {
									category: 'all',
									param: null,
								},
							},
						}
					]
				)
			},
			{
				name: "书库",
				type: "dynamic",
				loader: () => {
					const libraries = this.loadData('komga_libraries')
					if (!Array.isArray(libraries) || !libraries.length) {
						return []
					}
					return libraries.map((library) => ({
						label: library.name,
						target: {
							page: 'category',
							attributes: {
								category: 'library',
								param: library.id,
							},
						},
					}))
				}
			},
			{
				name: "合集",
				type: "dynamic",
				loader: () => {
					const collections = this.loadData('komga_collections')
					if (!Array.isArray(collections) || !collections.length) {
						return []
					}
					return collections.map((collection) => ({
						label: collection.name,
						target: {
							page: 'category',
							attributes: {
								category: 'collection',
								param: collection.id,
							},
						},
					}))
				}
			},
			{
				name: "标签",
				type: "dynamic",
				loader: () => {
					const tags = this.loadData('komga_tags')
					if (!Array.isArray(tags) || !tags.length) {
						return []
					}
					return tags.map((tag) => ({
						label: tag,
						target: {
							page: 'category',
							attributes: {
								category: 'tag',
								param: tag,
							},
						},
					}))
				}
			},
			{
				name: "语言",
				type: "dynamic",
				loader: () => {
					const languages = this.loadData('komga_languages')
					if (!Array.isArray(languages) || !languages.length) {
						return []
					}
					return languages.map((lang) => ({
						label: lang,
						target: {
							page: 'category',
							attributes: {
								category: 'language',
								param: lang,
							},
						},
					}))
				}
			},
			{
				name: "题材",
				type: "dynamic",
				loader: () => {
					const genres = this.loadData('komga_genres')
					if (!Array.isArray(genres) || !genres.length) {
						return []
					}
					return genres.map((genre) => ({
						label: genre,
						target: {
							page: 'category',
							attributes: {
								category: 'genre',
								param: genre,
							},
						},
					}))
				}
			}
		],
		enableRankingPage: false,
	}

	_categoryApi = {
		load: async (category, param, options, page) => {
			await this.refreshReferenceData(false)
			const pageIndex = Math.max(0, (page || 1) - 1)
			const defaultSort = category === 'all' ? 'created,desc' : 'metadata.lastModified,desc'
			const sortValue = this.extractOption(options, 0, defaultSort)
			const query = {
				page: pageIndex,
				size: 30,
				sort: [sortValue]
			}
			if (category === 'all') {
				// const list = await this.fetchBookList('/api/v1/books', query)
				// return {
				// 	comics: list.comics,
				// 	maxPage: Math.max(1, list.totalPages)
				// }
				const list = await this.fetchSeriesList('/api/v1/series', query)
				return {
					comics: list.comics,
					maxPage: Math.max(1, list.totalPages)
				}
			}
			if (category === 'library' && param) {
				query.library_id = [param]
				const list = await this.fetchSeriesList('/api/v1/series', query)
				return {
					comics: list.comics,
					maxPage: Math.max(1, list.totalPages)
				}				
			}
			if (category === 'collection' && param) {
				const list = await this.fetchSeriesList(`/api/v1/collections/${param}/series`, query)
				return {
					comics: list.comics,
					maxPage: Math.max(1, list.totalPages)
				}
			}


			if (category === 'tag' && param) {
				query.tag = [param]
				const list = await this.fetchSeriesList('/api/v1/series', query)
				return {
					comics: list.comics,
					maxPage: Math.max(1, list.totalPages)
				}
			}


			if (category === 'language' && param){
				query.language = [param]
				const list = await this.fetchSeriesList('/api/v1/series', query)
				return {
					comics: list.comics,
					maxPage: Math.max(1, list.totalPages)
				}
			}

			// if (category === 'genre' && param) query.genre = [param]
			query.genre = [param]
			const list = await this.fetchSeriesList('/api/v1/series', query)

			return {
				comics: list.comics,
				maxPage: Math.max(1, list.totalPages)
			}
		},
		optionList: [
			{
				label: "排序",
				options: [
					'*created,desc-添加时间(新→旧)',
					'created,asc-添加时间(旧→新)',
					'metadata.lastModified,desc-更新时间(新→旧)',
					'metadata.lastModified,asc-更新时间(旧→新)',
					'metadata.titleSort,asc-标题(A-Z)',
					'metadata.titleSort,desc-标题(Z-A)'
				],
				notShowWhen: null,
				showWhen: null
			}
		]
	}

	_searchApi = {
		load: async (keyword, options, page) => {
			const pageIndex = Math.max(0, (page || 1) - 1)
			const sortValue = this.extractOption(options, 0, 'metadata.lastModified,desc')
			const query = {
				page: pageIndex,
				size: 30,
				sort: [sortValue]
			}
			let term = (keyword || '').trim()
			const colonIdx = term.indexOf(':')
			if (colonIdx > 0) {
				const prefix = term.slice(0, colonIdx).toLowerCase()
				const value = term.slice(colonIdx + 1).trim()
				if (value) {
					if (prefix === 'tag') query.tag = [value]
					else if (prefix === 'author') query.author = [`${value},`]
					else if (prefix === 'language') query.language = [value]
					else if (prefix === 'genre') query.genre = [value]
					else if (prefix === 'publisher') query.publisher = [value]
					else query.search = value
				}
				term = ''
			}
			if (term) query.search = term
			const list = await this.fetchSeriesList('/api/v1/series', query)
			return {
				comics: list.comics,
				maxPage: Math.max(1, list.totalPages)
			}
		},
		optionList: [
			{
				type: 'select',
				options: [
					'*metadata.lastModified,desc-更新时间(新→旧)',
					'metadata.lastModified,asc-更新时间(旧→新)',
					'metadata.titleSort,asc-标题(A-Z)',
					'metadata.titleSort,desc-标题(Z-A)'
				],
				label: '排序',
				default: null
			}
		]
	}

	_comicApi = {
		loadInfo: async (id) => {
			const bookId = this.extractBookId(id)
			if (bookId) {
				return await this.loadBookDetails(bookId)
			}
			const [series, booksPage] = await Promise.all([
				this.getJson(`/api/v1/series/${id}`),
				this.getJson(`/api/v1/series/${id}/books`, {
					unpaged: true,
					sort: ['metadata.numberSort,asc']
				})
			])
			const books = Array.isArray(booksPage?.content) ? booksPage.content : []
			const readable = books.filter((book) => this.isSupportedBook(book))
			readable.sort((a, b) => this.compareBooks(a, b))
			const chapters = new Map()
			readable.forEach((book, index) => {
				chapters.set(book.id, this.formatBookTitle(book, index))
			})
			const metadata = series?.metadata || {}
			const summary = series?.booksMetadata?.summary || metadata.summary || ''
			const authors = this.collectAuthors(series?.booksMetadata?.authors)
			const genres = Array.isArray(metadata.genres) ? metadata.genres : []
			const tags = Array.isArray(series?.booksMetadata?.tags) ? series.booksMetadata.tags : []
			const description = summary || '暂无简介'
			const tagSections = {}
			if (authors.length) tagSections['作者'] = authors
			if (genres.length) tagSections['类型'] = this.uniqueArray(genres)
			if (tags.length) tagSections['标签'] = this.uniqueArray(tags)
			if (!readable.length && books.length) {
				tagSections['提示'] = ['该系列包含的项目暂不支持阅读']
			}
			const info = ({
				title: metadata.title || series?.name || id,
				subTitle: authors.slice(0, 3).join(', '),
				cover: this.buildUrl(`/api/v1/series/${id}/thumbnail`),
				description,
				tags: tagSections,
				chapters,
				updateTime: this.formatDate(series?.lastModified),
				uploadTime: this.formatDate(series?.created),
				url: series?.url || this.buildUrl(`/series/${id}`)
			})
			return info
		},
		loadEp: async (comicId, epId) => {
				let bookId = epId || comicId
				if (typeof bookId === 'string' && bookId.startsWith('book:')) {
					bookId = bookId.slice(5)
				}
				if (typeof comicId === 'string' && comicId.startsWith('book:') && !epId) {
					bookId = comicId.slice(5)
				}
			const pages = await this.getJson(`/api/v1/books/${bookId}/pages`)
			const list = Array.isArray(pages) ? pages : []
			list.sort((a, b) => (a?.number ?? 0) - (b?.number ?? 0))
			const zeroBased = list.some((page) => (page?.number ?? 1) === 0)
			const images = list
				.filter((page) => this.isPageRenderable(page))
				.map((page) => {
					const number = page?.number ?? 0
					return this.buildUrl(`/api/v1/books/${bookId}/pages/${number}`, zeroBased ? { zero_based: true } : null)
				})
			return { images }
		},
		onImageLoad: (url) => {
			return {
				headers: this.imageHeaders
			}
		},
	}

	async refreshReferenceData(force) {
		const token = this.authToken
		if (!token) {
			this.saveData('komga_libraries', [])
			this.saveData('komga_tags', [])
			this.saveData('komga_genres', [])
			this.saveData('komga_languages', [])
			this.saveData('komga_collections', [])
			return
		}
		const now = Date.now()
		const last = this.loadData('komga_meta_ts')
		if (!force && last && now - last < 5 * 60 * 1000) return
		try {
			const [libraries, tags, languages, collections, genres] = await Promise.all([
				this.getJson('/api/v1/libraries'),
				this.getJson('/api/v1/tags/series'),
				this.getJson('/api/v1/languages'),
				this.getJson('/api/v1/collections', { unpaged: true, sort: ['name,asc'] }),
				this.getJson('/api/v1/genres')
			])
			const libraryList = Array.isArray(libraries) ? libraries.filter((library) => library && library.id) : []
			const collectionPage = collections && typeof collections === 'object' ? collections : null
			const collectionList = Array.isArray(collectionPage?.content) ? collectionPage.content : Array.isArray(collections) ? collections : []
			this.saveData('komga_libraries', libraryList)
			this.saveData('komga_tags', Array.isArray(tags) ? tags : [])
			this.saveData('komga_genres', Array.isArray(genres) ? genres : [])
			this.saveData('komga_languages', Array.isArray(languages) ? languages : [])
			this.saveData('komga_collections', collectionList)
			this.saveData('komga_meta_ts', now)
		} catch (error) {
			this.saveData('komga_libraries', [])
			this.saveData('komga_tags', [])
			this.saveData('komga_genres', [])
			this.saveData('komga_languages', [])
			this.saveData('komga_collections', [])
			if (String(error) === 'Login expired') throw error
		}
	}

	async fetchSeriesList(path, query) {
		const data = await this.getJson(path, query)
		const content = Array.isArray(data?.content) ? data.content : []
		const comics = content.map((item) => this.parseSeries(item)).filter(Boolean)
		return {
			comics,
			totalPages: data?.totalPages ?? 1
		}
	}

	async fetchBookList(path, query) {
		const data = await this.getJson(path, query)
		const content = Array.isArray(data?.content) ? data.content : []
		const comics = content.map((item) => this.parseBook(item)).filter(Boolean)
		return {
			comics,
			totalPages: data?.totalPages ?? 1
		}
	}

	parseBook(book) {
		if (!book || !this.isSupportedBook(book)) return null
		const metadata = book.metadata || {}
		const title = metadata.title || book.name || book.id
		const authors = this.collectAuthors(metadata.authors)
		const tags = Array.isArray(metadata.tags) ? metadata.tags : []
		const description = metadata.summary || ''
		const subtitleParts = []
		if (book.seriesTitle) subtitleParts.push(book.seriesTitle)
		if (authors.length) subtitleParts.push(authors[0])
		return ({
			id: `book:${book.id}`,
			title,
			subTitle: subtitleParts.join(' · '),
			cover: this.buildUrl(`/api/v1/books/${book.id}/thumbnail`),
			tags: this.uniqueArray(tags).slice(0, 12),
			description,
		})
	}

	extractBookId(id) {
		if (typeof id !== 'string') return null
		return id.startsWith('book:') ? id.slice(5) : null
	}

	async loadBookDetails(bookId) {
		const book = await this.getJson(`/api/v1/books/${bookId}`)
		if (!book) throw '未找到该图书'
		const metadata = book.metadata || {}
		const authors = this.collectAuthors(metadata.authors)
		const tags = this.uniqueArray(Array.isArray(metadata.tags) ? metadata.tags : [])
		const description = metadata.summary || '暂无简介'
		const tagSections = {}
		if (authors.length) tagSections['作者'] = authors
		if (tags.length) tagSections['标签'] = tags
		if (book.seriesTitle) tagSections['系列'] = [book.seriesTitle]
		if (!this.isSupportedBook(book)) tagSections['提示'] = ['该图书暂不支持阅读']
		const chapters = new Map()
		const chapterTitle = metadata.title || book.name || '立即阅读'
		chapters.set(book.id, chapterTitle)
		return ({
			title: metadata.title || book.name || bookId,
			subTitle: book.seriesTitle || authors.slice(0, 3).join(', '),
			cover: this.buildUrl(`/api/v1/books/${bookId}/thumbnail`),
			description,
			tags: tagSections,
			chapters,
			updateTime: this.formatDate(book.lastModified),
			uploadTime: this.formatDate(book.created),
			url: book.url || this.buildUrl(`/books/${bookId}`)
		})
	}

	parseSeries(series) {
		if (!series) return null
		const metadata = series.metadata || {}
		const title = metadata.title || series.name || series.id
		const authors = this.collectAuthors(series?.booksMetadata?.authors)
		const tags = []
		if (Array.isArray(metadata.genres)) tags.push(...metadata.genres)
		if (Array.isArray(series?.booksMetadata?.tags)) tags.push(...series.booksMetadata.tags)
		const description = series?.booksMetadata?.summary || metadata.summary || ''
		return ({
			id: series.id,
			title,
			subTitle: authors.slice(0, 2).join(', '),
			cover: this.buildUrl(`/api/v1/series/${series.id}/thumbnail`),
			tags: this.uniqueArray(tags).slice(0, 12),
			description,
		})
	}

	collectAuthors(authors) {
		if (!Array.isArray(authors)) return []
		return this.uniqueArray(authors.map((author) => author?.name).filter(Boolean))
	}

	uniqueArray(list) {
		if (!Array.isArray(list)) return []
		const set = new Set()
		const result = []
		for (const item of list) {
			const value = typeof item === 'string' ? item.trim() : ''
			if (!value) continue
			const key = value.toLowerCase()
			if (set.has(key)) continue
			set.add(key)
			result.push(value)
		}
		return result
	}

	isSupportedBook(book) {
		if (!book || !book.media) return false
		const status = String(book.media.status || '').toUpperCase()
		if (status && status !== 'READY') return false
		const mediaType = String(book.media.mediaType || '').toLowerCase()
		if (!mediaType) return false
		if (mediaType.includes('epub') || mediaType.includes('pdf') || mediaType.includes('mobi')) return false
		if ((book.media.pagesCount || 0) <= 0) return false
		return true
	}

	isPageRenderable(page) {
		if (!page) return false
		const mediaType = String(page.mediaType || '').toLowerCase()
		if (!mediaType) return true
		return mediaType.startsWith('image/') || mediaType.includes('jpeg') || mediaType.includes('png') || mediaType.includes('webp')
	}

	compareBooks(a, b) {
		const aSort = typeof a?.metadata?.numberSort === 'number' ? a.metadata.numberSort : NaN
		const bSort = typeof b?.metadata?.numberSort === 'number' ? b.metadata.numberSort : NaN
		if (!Number.isNaN(aSort) && !Number.isNaN(bSort)) return aSort - bSort
		const aNumber = parseFloat(a?.metadata?.number)
		const bNumber = parseFloat(b?.metadata?.number)
		if (!Number.isNaN(aNumber) && !Number.isNaN(bNumber)) return aNumber - bNumber
		return (a?.metadata?.title || a?.name || '').localeCompare(b?.metadata?.title || b?.name || '')
	}

	formatBookTitle(book, index) {
		const metadata = book?.metadata || {}
		if (metadata.title) return metadata.title
		if (metadata.number) return `第${metadata.number}卷`
		if (book?.number != null) return `第${book.number}卷`
		return `章节 ${index + 1}`
	}

	extractOption(options, index, fallback) {
		if (!Array.isArray(options) || options.length <= index) return fallback
		let value = options[index]
		if (typeof value !== 'string') return fallback
		if (value.startsWith('*')) value = value.slice(1)
		const idx = value.indexOf('-')
		return idx > -1 ? value.slice(0, idx) : value
	}

	async getJson(path, query) {
		const res = await Network.get(this.buildUrl(path, query), this.headers)
		this.ensureOk(res)
		const text = res
		if (!text) return null
		return JSON.parse(text)
	}

	ensureOk(res) {
		if (!res) throw '请求失败'
				if (res.status < 200 || res.status >= 300) throw `请求失败: ${res.status}`
	}

	buildUrl(path, query) {
		let url = path
		if (!/^https?:\/\//i.test(path)) {
			url = `${this.baseUrl}${path.startsWith('/') ? '' : '/'}${path}`
		}
		const qs = this.buildQuery(query)
		return qs ? `${url}?${qs}` : url
	}

	buildQuery(query) {
		if (!query) return ''
		const parts = []
		for (const key of Object.keys(query)) {
			const value = query[key]
			if (value === undefined || value === null) continue
			if (Array.isArray(value)) {
				for (const item of value) {
					if (item === undefined || item === null) continue
					parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(String(item))}`)
				}
			} else {
				parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(String(value))}`)
			}
		}
		return parts.join('&')
	}

	formatDate(value) {
		if (!value) return null
		try {
			const date = new Date(value)
			if (Number.isNaN(date.getTime())) return null
			return date.toISOString().split('T')[0]
		} catch (_) {
			return null
		}
	}
}

