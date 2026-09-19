// description: 漫画柜 漫画源 — 搜索/分类/详情/阅读（由 venera manhuagui.js v1.2.1 移植，转换脚本自动生成）
// type: manga
//
// 由 venera 源自动转换：
// - 保留原站点的搜索/分类/详情/阅读核心逻辑（_searchApi/_categoryApi/_comicApi/_categoryData 内部对象）
// - 类开头的「wyw 适配层」将其包装为 wyw 插件接口（search/getDetail/openReader/分类四件套/浏览历史回放）
// - 已移除 wyw 无对应支撑的功能：账号登录/网络收藏/评论/点赞/评分/缩略图墙/外链识别/探索页(未映射部分)
// - Network 调用已改写为 wyw 原生风格：Network.get/post 直接返回 body 字符串，失败抛结构化异常（e.status/e.kind）

class manhuagui extends PluginSource {
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
                Promise.resolve(this.init()).catch((e) => console.warn('[manhuagui]', 'init 失败:', e))
            } catch (e) {
                console.warn('[manhuagui]', 'init 失败:', e)
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
            console.error('[manhuagui]', '搜索失败:', e)
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
        console.log('[manhuagui]', '详情:', title, '章节数:', isGallery ? 0 : chapters.length)

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
            plugin: 'manhuagui',
            method: 'loadChapterImages',
            args: [this._comicId, ep.id],
        }))
        Navigator.navigateToReader({
            comicId: this._comicId,
            comicTitle: this._comicTitle,
            chapters: chapters,
            sourceKey: 'manhuagui',
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
            console.error('[manhuagui]', '章节图片解析为空: comicId=' + comicId + ' epId=' + epId)
            throw '章节图片解析为空'
        }
        console.log('[manhuagui]', '图片数:', urls.length)
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

  name = "漫画柜";

  key = "ManHuaGui";

  version = "1.2.1";



  baseUrl = "https://www.manhuagui.com";

;

  isAppVersionAfter(target) {
    if (!APP || !APP.version) return false;
    let current = APP.version;
    let targetArr = target.split('.');
    let currentArr = current.split('.');
    for (let i = 0; i < 3; i++) {
      if (parseInt(currentArr[i]) < parseInt(targetArr[i])) {
        return false;
      }
    }
    return true;
  }

  async getHtml(url) {
    let mhg_cookie = this.loadData("mhg_cookie");
    let headers = {
      accept:
      "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
      "accept-language": "zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6",
      "cache-control": "no-cache",
      pragma: "no-cache",
      priority: "u=0, i",
      "sec-ch-ua":
        '"Microsoft Edge";v="137", "Chromium";v="137", "Not/A)Brand";v="24"',
      "sec-ch-ua-mobile": "?0",
      "sec-ch-ua-platform": '"Windows"',
      "sec-fetch-dest": "document",
      "sec-fetch-mode": "navigate",
      "sec-fetch-site": "same-origin",
      "sec-fetch-user": "?1",
      "upgrade-insecure-requests": "1",
      Referer: "https://www.manhuagui.com/",
      "Referrer-Policy": "strict-origin-when-cross-origin",
      cookie: mhg_cookie
    };
    let res = await Network.get(url, headers);
    
    let document = new HtmlDocument(res);
    return document;
  }
  parseSimpleComic(e) {
    let urlElement = e.querySelector(".ell > a");
    if (!urlElement) {
      console.warn("parseSimpleComic: Missing .ell > a element");
      return null;
    }
    let url = urlElement.attributes["href"];
    let id = url.split("/")[2];
    let title = urlElement.text.trim();

    let imgElement = e.querySelector("img");
    if (!imgElement) {
      console.warn("parseSimpleComic: Missing img element");
      return null;
    }
    let cover = imgElement.attributes["src"] || imgElement.attributes["data-src"];
    if (!cover) {
      console.warn("parseSimpleComic: Missing cover attribute");
      return null;
    }
    cover = `https:${cover}`;

    let descriptionElement = e.querySelector(".tt");
    let description = descriptionElement ? descriptionElement.text.trim() : "";

    return ({
      id,
      title,
      cover,
      description,
    });
  }

  parseComic(e) {
    let simple = this.parseSimpleComic(e);
    let sl = e.querySelector(".sl");
    let status = sl ? "连载" : "完结";
    let tmp = e.querySelector(".updateon").childNodes;
    let update = tmp[0].replace("更新于：", "").trim();
    let tags = [status, update];

    return ({
      id: simple.id,
      title: simple.title,
      cover: simple.cover,
      description: simple.description,
      tags,
      author,
    });
  }
  /**
   * [Optional] init function
   */
  init() {
    var LZString = (function () {
      var f = String.fromCharCode;
      var keyStrBase64 =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
      var baseReverseDic = {};
      function getBaseValue(alphabet, character) {
        if (!baseReverseDic[alphabet]) {
          baseReverseDic[alphabet] = {};
          for (var i = 0; i < alphabet.length; i++) {
            baseReverseDic[alphabet][alphabet.charAt(i)] = i;
          }
        }
        return baseReverseDic[alphabet][character];
      }
      var LZString = {
        decompressFromBase64: function (input) {
          if (input == null) return "";
          if (input == "") return null;
          return LZString._0(input.length, 32, function (index) {
            return getBaseValue(keyStrBase64, input.charAt(index));
          });
        },
        _0: function (length, resetValue, getNextValue) {
          var dictionary = [],
            next,
            enlargeIn = 4,
            dictSize = 4,
            numBits = 3,
            entry = "",
            result = [],
            i,
            w,
            bits,
            resb,
            maxpower,
            power,
            c,
            data = {
              val: getNextValue(0),
              position: resetValue,
              index: 1,
            };
          for (i = 0; i < 3; i += 1) {
            dictionary[i] = i;
          }
          bits = 0;
          maxpower = Math.pow(2, 2);
          power = 1;
          while (power != maxpower) {
            resb = data.val & data.position;
            data.position >>= 1;
            if (data.position == 0) {
              data.position = resetValue;
              data.val = getNextValue(data.index++);
            }
            bits |= (resb > 0 ? 1 : 0) * power;
            power <<= 1;
          }
          switch ((next = bits)) {
            case 0:
              bits = 0;
              maxpower = Math.pow(2, 8);
              power = 1;
              while (power != maxpower) {
                resb = data.val & data.position;
                data.position >>= 1;
                if (data.position == 0) {
                  data.position = resetValue;
                  data.val = getNextValue(data.index++);
                }
                bits |= (resb > 0 ? 1 : 0) * power;
                power <<= 1;
              }
              c = f(bits);
              break;
            case 1:
              bits = 0;
              maxpower = Math.pow(2, 16);
              power = 1;
              while (power != maxpower) {
                resb = data.val & data.position;
                data.position >>= 1;
                if (data.position == 0) {
                  data.position = resetValue;
                  data.val = getNextValue(data.index++);
                }
                bits |= (resb > 0 ? 1 : 0) * power;
                power <<= 1;
              }
              c = f(bits);
              break;
            case 2:
              return "";
          }
          dictionary[3] = c;
          w = c;
          result.push(c);
          while (true) {
            if (data.index > length) {
              return "";
            }
            bits = 0;
            maxpower = Math.pow(2, numBits);
            power = 1;
            while (power != maxpower) {
              resb = data.val & data.position;
              data.position >>= 1;
              if (data.position == 0) {
                data.position = resetValue;
                data.val = getNextValue(data.index++);
              }
              bits |= (resb > 0 ? 1 : 0) * power;
              power <<= 1;
            }
            switch ((c = bits)) {
              case 0:
                bits = 0;
                maxpower = Math.pow(2, 8);
                power = 1;
                while (power != maxpower) {
                  resb = data.val & data.position;
                  data.position >>= 1;
                  if (data.position == 0) {
                    data.position = resetValue;
                    data.val = getNextValue(data.index++);
                  }
                  bits |= (resb > 0 ? 1 : 0) * power;
                  power <<= 1;
                }
                dictionary[dictSize++] = f(bits);
                c = dictSize - 1;
                enlargeIn--;
                break;
              case 1:
                bits = 0;
                maxpower = Math.pow(2, 16);
                power = 1;
                while (power != maxpower) {
                  resb = data.val & data.position;
                  data.position >>= 1;
                  if (data.position == 0) {
                    data.position = resetValue;
                    data.val = getNextValue(data.index++);
                  }
                  bits |= (resb > 0 ? 1 : 0) * power;
                  power <<= 1;
                }
                dictionary[dictSize++] = f(bits);
                c = dictSize - 1;
                enlargeIn--;
                break;
              case 2:
                return result.join("");
            }
            if (enlargeIn == 0) {
              enlargeIn = Math.pow(2, numBits);
              numBits++;
            }
            if (dictionary[c]) {
              entry = dictionary[c];
            } else {
              if (c === dictSize) {
                entry = w + w.charAt(0);
              } else {
                return null;
              }
            }
            result.push(entry);
            dictionary[dictSize++] = w + entry.charAt(0);
            enlargeIn--;
            w = entry;
            if (enlargeIn == 0) {
              enlargeIn = Math.pow(2, numBits);
              numBits++;
            }
          }
        },
      };
      return LZString;
    })();

    function splitParams(str) {
      let params = [];
      let currentParam = "";
      let stack = [];

      for (let i = 0; i < str.length; i++) {
        const char = str[i];

        if (char === "(" || char === "[" || char === "{") {
          stack.push(char);
          currentParam += char;
        } else if (char === ")" && stack[stack.length - 1] === "(") {
          stack.pop();
          currentParam += char;
        } else if (char === "]" && stack[stack.length - 1] === "[") {
          stack.pop();
          currentParam += char;
        } else if (char === "}" && stack[stack.length - 1] === "{") {
          stack.pop();
          currentParam += char;
        } else if (char === "," && stack.length === 0) {
          params.push(currentParam.trim());
          currentParam = "";
        } else {
          currentParam += char;
        }
      }

      if (currentParam) {
        params.push(currentParam.trim());
      }

      return params;
    }

    function extractParams(str) {
      let params_part = str.split("}(")[1].split("))")[0];
      let params = splitParams(params_part);
      params[5] = {};
      params[3] = LZString.decompressFromBase64(params[3].split("'")[1]).split(
        "|"
      );
      return params;
    }

    function formatData(p, a, c, k, e, d) {
      e = function (c) {
        return (
          (c < a ? "" : e(parseInt(c / a))) +
          ((c = c % a) > 35 ? String.fromCharCode(c + 29) : c.toString(36))
        );
      };
      if (!"".replace(/^/, String)) {
        while (c--) d[e(c)] = k[c] || e(c);
        k = [
          function (e) {
            return d[e];
          },
        ];
        e = function () {
          return "\\w+";
        };
        c = 1;
      }
      while (c--)
        if (k[c]) p = p.replace(new RegExp("\\b" + e(c) + "\\b", "g"), k[c]);
      return p;
    }
    function extractFields(text) {
      // 创建一个对象存储提取的结果
      const result = {};

      // 提取files数组
      const filesMatch = text.match(/"files":\s*\[(.*?)\]/);
      if (filesMatch && filesMatch[1]) {
        // 提取所有文件名并去除引号和空格
        result.files = filesMatch[1]
          .split(",")
          .map((file) => file.trim().replace(/"/g, ""));
      }

      // 提取path
      const pathMatch = text.match(/"path":\s*"([^"]+)"/);
      if (pathMatch && pathMatch[1]) {
        result.path = pathMatch[1];
      }

      // 提取len
      const lenMatch = text.match(/"len":\s*(\d+)/);
      if (lenMatch && lenMatch[1]) {
        result.len = parseInt(lenMatch[1], 10);
      }

      // 提取sl对象
      const slMatch = text.match(/"sl":\s*({[^}]+})/);
      if (slMatch && slMatch[1]) {
        try {
          // 将提取的字符串转换为对象
          result.sl = JSON.parse(slMatch[1].replace(/(\w+):/g, '"$1":'));
        } catch (e) {
          console.error("解析sl字段失败:", e);
          result.sl = null;
        }
      }

      return result;
    }
    this.getImgInfos = function (script) {
      let params = extractParams(script);
      let imgData = formatData(...params);
      let imgInfos = extractFields(imgData);
      return imgInfos;
    };

    this.decodeViewState = function (viewState) {
      if (!viewState) {
        return null;
      }
      let decoded = LZString.decompressFromBase64(viewState);
      return decoded;
    };
  }

  // explore page list
  _explore = [
    {
      title: "漫画柜",
      type: "multiPartPage",
      /**
       * 参考 manhuagui_explore.html，抓取“热门漫画最新更新”与 tab 板块
       */
      load: async (page) => {
        let document = await this.getHtml(this.baseUrl);
        let parts = [];

        // 1. 热门漫画最新更新
        let updateSection = document.querySelector(".update-cont");
        if (updateSection) {
          let updateComics = [];
          let uls = updateSection.querySelectorAll("ul");
          for (let ul of uls) {
            let comics = ul.querySelectorAll("li").map(e => this.parseSimpleComic(e)).filter(c => c);
            updateComics.push(...comics);
          }
          if (updateComics.length > 0) {
            parts.push({ title: "热门漫画最新更新", comics: updateComics });
          }
        }

        // 2. tab 板块（热门连载漫画、经典完结漫画、最新上架漫画、2020新番漫画）
        let tabTitles = document.querySelectorAll("#cmt-tab li");
        let tabParts = document.querySelectorAll("#cmt-cont ul.cover-list");
        for (let i = 0; i < tabTitles.length; i++) {
          let title = tabTitles[i].text.trim();
          let comics = tabParts[i].querySelectorAll("li").map(e => this.parseSimpleComic(e)).filter(c => c);
          if (comics.length > 0) {
            parts.push({ title, comics });
          }
        }

        return parts;
      },
      loadNext(next) {},
    },
  ];

  // categories
  _categoryData = {
    /// title of the category page, used to identify the page, it should be unique
    title: "漫画柜",
    parts: [
      {
        name: "类型",
        type: "fixed",
        itemType: "category",
        categories: [
          "全部",
          "热血",
          "冒险",
          "魔幻",
          "神鬼",
          "搞笑",
          "萌系",
          "爱情",
          "科幻",
          "魔法",
          "格斗",
          "武侠",
          "机战",
          "战争",
          "竞技",
          "体育",
          "校园",
          "生活",
          "励志",
          "历史",
          "伪娘",
          "宅男",
          "腐女",
          "耽美",
          "百合",
          "后宫",
          "治愈",
          "美食",
          "推理",
          "悬疑",
          "恐怖",
          "四格",
          "职场",
          "侦探",
          "社会",
          "音乐",
          "舞蹈",
          "杂志",
          "黑道",
        ],
        categoryParams: [
          "",
          "rexue",
          "maoxian",
          "mohuan",
          "shengui",
          "gaoxiao",
          "mengxi",
          "aiqing",
          "kehuan",
          "mofa",
          "gedou",
          "wuxia",
          "jizhan",
          "zhanzheng",
          "jingji",
          "tiyu",
          "xiaoyuan",
          "shenghuo",
          "lizhi",
          "lishi",
          "weiniang",
          "zhainan",
          "funv",
          "danmei",
          "baihe",
          "hougong",
          "zhiyu",
          "meishi",
          "tuili",
          "xuanyi",
          "kongbu",
          "sige",
          "zhichang",
          "zhentan",
          "shehui",
          "yinyue",
          "wudao",
          "zazhi",
          "heidao",
        ],
      },
    ],
    // enable ranking page
    enableRankingPage: false,
  };

  /// category comic loading related
  _categoryApi = {
    /**
     * load comics of a category
     * @param category {string} - category name
     * @param param {string?} - category param
     * @param options {string[]} - options from optionList
     * @param page {number} - page number
     * @returns {Promise<{comics: Comic[], maxPage: number}>}
     */
    load: async (category, param, options, page) => {
      let area = options[0];
      let genre = param;
      let age = options[1];
      let status = options[2];
      let sort = options[3] || "index";
      // log(
      //   "info",
      //   this.name,
      //   ` 加载分类漫画: ${area} | ${genre} | ${age} | ${status}`
      // );
      // 字符串之间用“_”连接，空字符串除外
      let params = [area, genre, age, status].filter((e) => e != "").join("_");

      let url = `${this.baseUrl}/list/${params}/${sort}_p${page}.html`;

      let document = await this.getHtml(url);
      let maxPage = document
        .querySelector(".result-count")
        .querySelectorAll("strong")[1].text;
      maxPage = parseInt(maxPage);
      let comics = document
        .querySelectorAll("#contList > li")
        .map((e) => this.parseSimpleComic(e))
        .filter((comic) => comic !== null); // 过滤掉 null 值
      return {
        comics,
        maxPage,
      };
    },
    // provide options for category comic loading
    optionList: [
      {
        label: "地区",
        options: [
          "-全部",
          "japan-日本",
          "hongkong-港台",
          "other-其它",
          "europe-欧美",
          "china-内地",
          "korea-韩国",
        ],
      },
      {
        label: "类型",
        options: [
          "-全部",
          "shaonv-少女",
          "shaonian-少年",
          "qingnian-青年",
          "ertong-儿童",
          "tongyong-通用",
        ],
      },
      {
        label: "状态",
        options: ["-全部", "lianzai-连载", "wanjie-完结"],
      },
      {
        label: "排序",
        options: ["update-最新更新", "index-最新发布", "view-人气最旺", "rate-评分最高"],
      },
    ],
    ranking: {
      // 对于单个选项，使用“-”分隔值和文本，左侧为值，右侧为文本
      options: [
        "-最新发布",
        "update-最新更新",
        "view-人气最旺",
        "rate-评分最高",
      ],
      /**
       * 加载排行榜漫画
       * @param option {string} - 来自optionList的选项
       * @param page {number} - 页码
       * @returns {Promise<{comics: Comic[], maxPage: number}>}
       */
      load: async (option, page) => {
        let url = `${this.baseUrl}/list/${option}_p${page}.html`;
        let document = await this.getHtml(url);
        let maxPage = document
          .querySelector(".result-count")
          .querySelectorAll("strong")[1].text;
        maxPage = parseInt(maxPage);
        let comics = document
          .querySelector("#contList")
          .querySelectorAll("li")
          .map((e) => this.parseComic(e));
        return {
          comics,
          maxPage,
        };
      },
    },
  };

  /**
   * 专门解析搜索结果页面中的漫画信息
   * @param {HTMLElement} item - 搜索结果中的单个漫画项
   * @returns {Comic} - 解析后的漫画对象
   */
  parseSearchComic(item) {
    try {
      // 获取漫画链接和ID
      let linkElement = item.querySelector(".book-detail dl dt a");
      if (!linkElement) return null;
      
      let url = linkElement.attributes["href"];
      let id = url.split("/")[2];
      let title = linkElement.text.trim();
      
      // 获取封面图片
      let coverElement = item.querySelector(".book-cover .bcover img");
      let cover = coverElement ? coverElement.attributes["src"] : null;
      if (cover) {
        cover = cover.startsWith("//") ? `https:${cover}` : cover;
      }
      
      // 获取更新状态和描述
      let statusElement = item.querySelector(".tags.status span .red");
      let status = statusElement ? statusElement.text.trim() : "";
      
      let updateElement = item.querySelector(".tags.status span .red:nth-child(2)");
      let updateTime = updateElement ? updateElement.text.trim() : "";
      
      // 获取评分信息
      let scoreElement = item.querySelector(".book-score .score-avg strong");
      let score = scoreElement ? scoreElement.text.trim() : "";
      
      // 获取作者信息
      let authorElements = item.querySelectorAll(".tags a[href*='/author/']");
      let author = authorElements.length > 0 
        ? authorElements.map(a => a.text.trim()).join(", ") 
        : "";
      
      // 获取类型信息
      let typeElements = item.querySelectorAll(".tags a[href*='/list/']");
      let types = typeElements.length > 0 
        ? typeElements.map(a => a.text.trim())
        : [];
      
      // 获取简介
      let introElement = item.querySelector(".intro span");
      let description = introElement ? introElement.text.replace("简介：", "").trim() : "";
      
      // 如果简介为空，使用更新状态作为描述
      if (!description && status) {
        description = `状态: ${status}`;
        if (updateTime) description += `, 更新: ${updateTime}`;
      }
      
      return ({
        id,
        title,
        cover,
        description,
        tags: [...types, status],
        author,
        score
      });
    } catch (error) {
      console.error("解析搜索结果项时出错:", error);
      return null;
    }
  }

  /// search related
  _searchApi = {
    /**
     * load search result
     * @param keyword {string}
     * @param options {string[]} - options from optionList
     * @param page {number}
     * @returns {Promise<{comics: Comic[], maxPage: number}>}
     */
    load: async (keyword, options, page) => {
      let url = ""
      if (options[0]) {
        let type = options[0].split("-")[0];
          if (type == '0') {
              url = `${this.baseUrl}/s/${keyword}_p${page}.html`;
          } else{
            url = `${this.baseUrl}/s/${keyword}_o${type}_p${page}.html`;
          }
      }else{
          url = `${this.baseUrl}/s/${keyword}_p${page}.html`;
      }
      let document = await this.getHtml(url);
      
      // 检查是否有结果计数元素
      let resultCount = document.querySelector(".result-count");
      if (!resultCount) {
        // 没有搜索结果或页面结构不同
        return {
          comics: [],
          maxPage: 1
        };
      }
      
      let comicNum = resultCount.querySelectorAll("strong")[1].text;
      comicNum = parseInt(comicNum);
      // 每页10个
      let maxPage = Math.ceil(comicNum / 10);

      // 在搜索结果页面中，漫画列表位于 .book-result ul 下
      let comicList = document.querySelector(".book-result ul");
      if (!comicList) {
        return {
          comics: [],
          maxPage: maxPage || 1
        };
      }
      
      // 使用专门的搜索解析函数解析每个漫画项
      let comics = comicList.querySelectorAll("li.cf")
        .map(item => this.parseSearchComic(item))
        .filter(comic => comic !== null); // 过滤掉解析失败的项
      
      return {
        comics,
        maxPage,
      };
    },

    optionList: [
      {
        type: "select",
        options: ["0-最新更新", "1-最近最热","2-最新上架", "3-评分最高"],
        label: "sort",
        default: null,
      },
    ],

  };

  /// single comic related
  _comicApi = {
    /**
     * load comic info
     * @param id {string}
     * @returns {Promise<ComicDetails>}
     */
    loadInfo: async (id) => {
      let url = `${this.baseUrl}/comic/${id}/`;
      let document = await this.getHtml(url);

      // ANCHOR 基本信息
      let book = document.querySelector(".book-cont");
      let title = book
        .querySelector(".book-title")
        .querySelector("h1")
        .text.trim();
      let subtitle = book
        .querySelector(".book-title")
        .querySelector("h2")
        .text.trim();
      let cover = book.querySelector(".hcover").querySelector("img").attributes[
        "src"
      ];
      cover = `https:${cover}`;
      let description = book
        .querySelector("#intro-all")
        .querySelectorAll("p")
        .map((e) => e.text.trim())
        .join("\n");
      //   log("warn", this.name, { title, subtitle, cover, description });

      let detail_list = book.querySelectorAll(".detail-list span");

      function parseDetail(idx) {
        let ele = detail_list[idx].querySelectorAll("a");
        if (ele.length > 0) {
          return ele.map((e) => e.text.trim());
        }
        return [""];
      }
      let createYear = parseDetail(0);
      let area = parseDetail(1);
      let genre = parseDetail(3);
      let author = parseDetail(4);
      // let alias = parseDetail(5);

      //   let lastChapter = parseDetail(6);
      let status = detail_list[7].text.trim();

      let tags = {
        年代: createYear,
        状态: [status],
        作者: author,
        地区: area,
        类型: genre,
      };
      let updateTime = detail_list[8].text.trim();

      let chapterDocument = document;
      let isAdultWarning = document.querySelector("#checkAdult");
      let viewStateElement = document.querySelector("#__VIEWSTATE");
      if (isAdultWarning && viewStateElement) {
        let viewStateValue = viewStateElement.attributes["value"];
        if (viewStateValue) {
          let decodedViewState = this.decodeViewState(viewStateValue);
          if (decodedViewState) {
            let sanitized = decodedViewState.trim();
            sanitized = sanitized.replace(/^\/\/+/, "").trim();
            if (!/class=['"]chapter['"]/.test(sanitized)) {
              sanitized = `<div class="chapter">${sanitized}</div>`;
            }
            try {
              chapterDocument = new HtmlDocument(sanitized);
            } catch (error) {
              console.error("解析成人章节列表失败:", error);
              chapterDocument = document;
            }
          }
        }
      }

      // 支持多分组
      let chaptersMap = new Map();
      
      // 查找所有章节分组标题
      let chapterGroups = chapterDocument.querySelectorAll(".chapter h4 span");
      if (chapterGroups.length === 0) {
        let docGroups = document.querySelectorAll(".chapter h4 span");
        if (docGroups.length > 0) {
          chapterDocument = document;
          chapterGroups = docGroups;
        }
      }
      
      if (chapterGroups.length > 0) {
        // 处理每个分组
        for (let i = 0; i < chapterGroups.length; i++) {
          let groupName = chapterGroups[i].text.trim();
          let groupChapters = new Map();
          
          let chapterList = chapterDocument.querySelectorAll(".chapter-list")[i];
          if (chapterList) {
            let lis = chapterList.querySelectorAll("li");
            for (let li of lis) {
              let a = li.querySelector("a");
              let id = a.attributes["href"].split("/").pop().replace(".html", "");
              let title = a.querySelector("span").text.trim();
              groupChapters.set(id, title);
            }
            
            groupChapters = new Map([...groupChapters].sort((a, b) => a[0] - b[0]));
            
            chaptersMap.set(groupName, groupChapters);
          }
        }
      } else {
        // 没有分组标题的情况，直接查找章节列表
        let chapterLists = chapterDocument.querySelectorAll(".chapter-list");
        if (chapterLists.length === 0 && chapterDocument !== document) {
          chapterDocument = document;
          chapterLists = chapterDocument.querySelectorAll(".chapter-list");
        }

        if (chapterLists.length > 0) {
          let groupName = "连载";
          let groupChapters = new Map();
          
          for (let chapterList of chapterLists) {
            let lis = chapterList.querySelectorAll("li");
            for (let li of lis) {
              let a = li.querySelector("a");
              if (a) {
                let id = a.attributes["href"].split("/").pop().replace(".html", "");
                let title = a.querySelector("span").text.trim();
                groupChapters.set(id, title);
              }
            }
          }
          
          groupChapters = new Map([...groupChapters].sort((a, b) => a[0] - b[0]));
          chaptersMap.set(groupName, groupChapters);
        }
      }
      
      let chapters;
      if (this.isAppVersionAfter && this.isAppVersionAfter("1.3.0")) {
        chapters = chaptersMap;
      } else {
        chapters = new Map();
        for (let [_, groupChapters] of chaptersMap) {
          for (let [id, title] of groupChapters) {
            chapters.set(id, title);
          }
        }
        chapters = new Map([...chapters].sort((a, b) => a[0] - b[0]));
      }

      let recommend = [];
      let similar = document.querySelector(".similar-list");
      if (similar) {
        let similar_list = similar.querySelectorAll("li");
        for (let li of similar_list) {
          let comic = this.parseSimpleComic(li);
          recommend.push(comic);
        }
      }

      return ({
        title,
        subtitle,
        cover,
        description,
        tags,
        updateTime,
        chapters,
        recommend,
      });
    },

    /**
     * load images of a chapter
     * @param comicId {string}
     * @param epId {string?}
     * @returns {Promise<{images: string[]}>}
     */
    loadEp: async (comicId, epId) => {
      let url = `${this.baseUrl}/comic/${comicId}/${epId}.html`;
      let document = await this.getHtml(url);
      let script = document.querySelectorAll("script")[4].innerHTML;
      let infos = this.getImgInfos(script);

      let imgDomain = `https://us.hamreus.com`;
      let images = [];
      for (let f of infos.files) {
        let imgUrl =
          imgDomain + infos.path + f + `?e=${infos.sl.e}&m=${infos.sl.m}`;
        images.push(imgUrl);
      }
      return {
        images,
      };
    },
    /**
     * [Optional] provide configs for an image loading
     * @param url
     * @param comicId
     * @param epId
     * @returns {ImageLoadingConfig | Promise<ImageLoadingConfig>}
     */
    onImageLoad: (url, comicId, epId) => {
      return {
        headers: {
          accept:
            "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8",
          "accept-language": "zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6",
          "cache-control": "no-cache",
          pragma: "no-cache",
          priority: "i",
          "sec-ch-ua":
            '"Microsoft Edge";v="137", "Chromium";v="137", "Not/A)Brand";v="24"',
          "sec-ch-ua-mobile": "?0",
          "sec-ch-ua-platform": '"Windows"',
          "sec-fetch-dest": "image",
          "sec-fetch-mode": "no-cors",
          "sec-fetch-site": "cross-site",
          "sec-fetch-storage-access": "active",
          Referer: "https://www.manhuagui.com/",
          "Referrer-Policy": "strict-origin-when-cross-origin",
        },
      };
    },
    /**
     * [Optional] provide configs for a thumbnail loading
     * @param url {string}
     * @returns {ImageLoadingConfig | Promise<ImageLoadingConfig>}
     *
     * `ImageLoadingConfig.modifyImage` and `ImageLoadingConfig.onLoadFailed` will be ignored.
     * They are not supported for thumbnails.
     */
    
    /**
     * [Optional] load comments
     *
     * Since app version 1.0.6, rich text is supported in comments.
     * Following html tags are supported: ['a', 'b', 'i', 'u', 's', 'br', 'span', 'img'].
     * span tag supports style attribute, but only support font-weight, font-style, text-decoration.
     * All images will be placed at the end of the comment.
     * Auto link detection is enabled, but only http/https links are supported.
     * @param comicId {string}
     * @param subId {string?} - ComicDetails.subId
     * @param page {number}
     * @param replyTo {string?} - commentId to reply, not null when reply to a comment
     * @returns {Promise<{comments: Comment[], maxPage: number?}>}
     */

    
    /**
     * 处理标签点击事件
     * @param namespace {string} 标签命名空间
     * @param tag {string} 标签名称
     * @returns {Object} 跳转操作
     */
  };
  /// favorites related
;
}
