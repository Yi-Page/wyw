// description: 黑猫动漫（bmmdmm.com）视频源（搜索 + 浏览 + 详情 + 播放）
// type: video
//
// 安装方式：
//   1) 把本文件复制到 {appSupportDir}/plugins/bmmdmm.js
//   2) 重启 App，在插件管理页刷新即可看到 "黑猫动漫" tab
//
// 接口约定：
//   search(keyword)  → List<UI.Card>，每张含封面 + 标题 + 集数信息
//   loadCategory(category, page, options) → 浏览 /list/ 列表页
//   getDetail(id)    → List<UI>，头部元信息 + 简介 + 多源剧集列表
//   play(url)        → 直接把播放页 URL 交给 wyw 视频播放器嗅探
//
// 站点 URL 模式：
//   搜索：/s_all?kw={keyword}&pagesize=24&pageindex={page}
//   浏览：/list/?order={排序}&region={地区}&genre={版本}&year={年份}&...&pagesize=24&pageindex={page}
//   详情：/show/{id}.html
//   播放：/play/{id}-{sid}-{nid}.html   （nid 0-based：nid=0 → 第1集）

class bmmdmm extends PluginSource {
    name = '黑猫动漫'
    key = 'bmmdmm'
    version = '1.0.0'

    baseUrl = 'https://www.bmmdmm.com';

    /// 站点 /list/ 页的全部筛选维度（顺序即 getCategoryOptions 返回顺序）。
    /// 每项 { key, label, values }：values 不含「全部」，「全部」由 getCategoryOptions 生成。
    static filterGroups = [
        { key: 'order',  label: '排序',   values: ['更新时间', '名称', '点击量'] },
        { key: 'region', label: '地区',   values: ['日本', '中国', '美国', '韩国', '其他'] },
        { key: 'genre',  label: '版本',   values: ['TV', '剧场版', 'OVA', 'WEB', '其他'] },
        { key: 'letter', label: '首字母', values: ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z'] },
        { key: 'year',   label: '年份',   values: ['2026', '2025', '2024', '2023', '2022', '2021', '2020', '2019', '2018', '2017', '2016', '2015', '2014', '2013', '2012', '2011', '2010', '2009', '2008', '2007', '2006', '2005', '2004', '2003', '2002', '2001', '2000', '其他'] },
        { key: 'season', label: '季度',   values: ['1', '4', '7', '10'] },
        { key: 'status', label: '状态',   values: ['连载', '完结', '未播放'] },
        { key: 'label',  label: '类型',   values: ['搞笑', '冒险', '热血', '励志', '奇幻', '亲子', '亲情', '悬疑', '推理', '犯罪', '科幻', '战斗', '机战', '恋爱', '后宫', '治愈', '百合', '日常', '特摄', '竞技', '校园', '运动', '都市', '战争', '恐怖', '猎奇', '历史', '青春', '欢乐向', '萝莉', '血腥', '吸血鬼', '社会', '智斗', '动作', '偶像', '伪娘', '教育', '武侠', '音乐', '职场', '玄幻', '穿越', '生存', '芳文社', '美食', '乙女', '耽美', '女性向', '宠物', '格斗', '古风', '性转', '异世界', '灵异', '修真', '剧情', '真人', '美少女', '泡面番', '游戏', '其他'] },
    ]

    /// 源网站地址（插件管理页「网站」菜单调用）
    getUrl() {
        return this.baseUrl;
    }

    // ============================================================
    // 工具
    // ============================================================

    /// 绝对 URL
    _abs(href) {
        if (!href) return '';
        if (href.startsWith('http://') || href.startsWith('https://')) return href;
        if (href.startsWith('//')) return 'https:' + href;
        if (href.startsWith('/')) return this.baseUrl + href;
        return this.baseUrl + '/' + href;
    }

    /// 统一请求头
    _headers() {
        return {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
            'Referer': this.baseUrl + '/',
        };
    }

    // ============================================================
    // 搜索
    // ============================================================

    /**
     * 提取标题：<h2><a title="..."> 优先，否则 alt
     */
    _extractTitle(item) {
        const h2 = item.querySelector('h2 a');
        if (h2) {
            const t = (h2.attributes.title || h2.text || '').trim();
            if (t) return t;
        }
        const img = item.querySelector('img');
        if (img) {
            const alt = (img.attributes.alt || '').trim();
            if (alt) return alt;
        }
        return '';
    }

    /**
     * 提取封面图：<img src="...">（不用 data-original，因为是真实 URL）
     */
    _extractCover(item) {
        const img = item.querySelector('img');
        return img ? (img.attributes.src || '') : '';
    }

    /**
     * 提取副标题信息：<font color="red"> 中的文字
     *   - "第52集"（更新到 N 集）
     *   - "HD中字" / "HD"（单集/电影/OVA）
     */
    _extractEpisodeInfo(item) {
        const font = item.querySelector('font[color="red"]');
        if (font) {
            const t = (font.text || '').trim();
            if (t) return t;
        }
        return '';
    }

    /**
     * 提取类型标签（去除 "类型：" 前缀）
     */
    _extractGenre(item) {
        const spans = item.querySelectorAll('span');
        for (const sp of spans) {
            const t = (sp.text || '').trim();
            if (t.startsWith('类型：')) {
                return t.substring(3).trim();
            }
        }
        return '';
    }

    /**
     * 提取上映日期（去除 "上映：" 前缀）
     */
    _extractRelease(item) {
        const spans = item.querySelectorAll('span');
        for (const sp of spans) {
            const t = (sp.text || '').trim();
            if (t.startsWith('上映：')) {
                return t.substring(3).trim();
            }
        }
        return '';
    }

    /**
     * 提取简介（<p> 中的剧情文字，可能为空）
     */
    _extractDescription(item) {
        const p = item.querySelector('p');
        if (!p) return '';
        const t = (p.text || '').trim();
        // 过滤掉空简介（只有一个 &nbsp; 的情况）
        if (!t || t === '&nbsp;') return '';
        return t;
    }

    /**
     * 构造单个搜索结果卡片。
     *
     * 布局（两列：封面 + 信息）：
     *   ┌────────┐  标题（粗体）              ┌────┐
     *   │ 封面   │  第52集（灰）             │详情│
     *   │ 80×116 │  类型: 热血 · 上映: 2016  │    │
     *   └────────┘                          └────┘
     */
    _buildResultCard({ cover, title, epInfo, genre, release, description, id }) {
        // 左栏：封面
        const coverWidget = cover ? UI.Image({
            src: cover,
            width: 80,
            height: 116,
        }) : null;

        // 右栏：标题 + 元信息行（堆叠）
        const infoRows = [];

        // 标题
        infoRows.push(UI.Text({
            content: title,
            style: { fontSize: 14, weight: 'bold' },
            maxLines: 1,
        }));

        // 集数信息行：▶ + 文字
        if (epInfo) {
            infoRows.push(UI.Row({
                crossAxisAlignment: 'center',
                children: [
                    UI.Icon({
                        name: 'play_circle_outline',
                        size: 14,
                        color: '#666666',
                    }),
                    UI.SizedBox({ width: 4 }),
                    UI.Text({
                        content: epInfo,
                        style: { fontSize: 12, color: '#666666' },
                        maxLines: 1,
                    }),
                ],
            }));
        }

        // 类型 + 上映（合并到一行）
        const meta = [genre, release].filter(Boolean).join(' · ');
        if (meta) {
            infoRows.push(UI.Text({
                content: meta,
                style: { fontSize: 11, color: '#888888' },
                maxLines: 1,
            }));
        }

        // 简介（可选，最多 1 行）
        if (description) {
            infoRows.push(UI.Text({
                content: description,
                style: { fontSize: 11, color: '#666666' },
                maxLines: 1,
            }));
        }

        const middleColumn = UI.Column({
            crossAxisAlignment: 'start',
            mainAxisAlignment: 'start',
            children: infoRows,
        });

        // 右下角：详情按钮
        const detailButton = UI.IconButton({
            icon: 'open_in_new',
            tooltip: '详情',
            color: '#666666',
            size: 20,
            onTap: UI.Navigate({
                page: 'descriptor',
                method: 'getDetail',
                args: [id],
                title: title,
            }),
        });

        return UI.Card({
            elevation: 0,
            shapeRadius: 16,
            color: '@theme:surfaceContainerLow',
            padding: 4,
            child: UI.Row({
                crossAxisAlignment: 'start',
                children: [
                    coverWidget,
                    UI.SizedBox({ width: 12 }),
                    UI.Expanded({ child: middleColumn }),
                    UI.SizedBox({ width: 8 }),
                    detailButton,
                ].filter(c => c != null),
            }),
        });
    }

    /**
     * 解析「搜索结果 / 列表页」为卡片列表。
     *
     * bmmdmm 的搜索结果页与 /list/ 列表页卡片结构一致：
     *   ul > li（卡片）
     *     a[href="/show/{id}.html"]（详情链接）
     *     h2 > a[title] 或 img[alt]（标题）
     *     img（封面）
     *     font[color="red"]（集数 / 更新信息）
     *     span（类型：xxx / 上映：xxx）
     *     p（简介）
     */
    _parseCards(html) {
        const doc = new HtmlDocument(html);
        const cards = [];
        const seenIds = new Set();

        const allLi = doc.querySelectorAll('li');
        for (const item of allLi) {
            try {
                // 必须是包含 /show/{id}.html 链接的卡片 li（兼容相对/绝对地址）
                const link = item.querySelector('a[href*="/show/"]');
                if (!link) continue;
                const href = link.attributes.href || '';
                const idMatch = href.match(/\/show\/(\d+)\.html/);
                if (!idMatch) continue;
                const id = idMatch[1];
                if (seenIds.has(id)) continue;
                seenIds.add(id);

                const title = this._extractTitle(item);
                if (!title) continue;
                const epInfo = this._extractEpisodeInfo(item);
                const cover = this._extractCover(item);
                const genre = this._extractGenre(item);
                const release = this._extractRelease(item);
                const description = this._extractDescription(item);

                cards.push(this._buildResultCard({
                    cover, title, epInfo, genre, release, description, id
                }));
            } catch (e) {
                continue;
            }
        }

        doc.dispose();
        return cards;
    }

    /**
     * 搜索入口
     * @param {string} keyword
     * @param {number} page 页码（从 1 起）
     * @returns {Promise<Array>}
     */
    async search(keyword, page = 1) {
        if(keyword === null || keyword === ''){
            return [];
        }
        const url = `${this.baseUrl}/s_all?kw=${encodeURIComponent(keyword)}&pagesize=24&pageindex=${page - 1}`;
        let html;
        try {
            html = await Network.get(url, this._headers());
        } catch (e) {
            console.error(`搜索请求失败: ${e}`);
            return [];
        }
        if (!html) return [];

        const items = this._parseCards(html);

        if (items.length === 0 && page <= 1) {
            Dialog.showToast('未找到结果，请检查关键词');
        }
        return items;
    }

    // ============================================================
    // 分类浏览（/list/?order=...&pagesize=24&pageindex=...）
    // ============================================================

    /**
     * 分类结构（venera 的 category）。
     *
     * bmmdmm 的「影片列表」页支持多维度筛选，统一放在一个
     * 「综合筛选」入口里，点击后在弹窗中组合条件：
     *   /list/?order={排序}&region={地区}&genre={版本}&year={年份}&...&pagesize=24&pageindex={page}
     */
    getCategory() {
        return {
            title: '黑猫动漫',
            parts: [
                { name: '全部影片', categories: ['综合筛选', '最近更新'] },
            ],
        }
    }

    /**
     * 筛选条件组（每个维度一个下拉，单选）：
     *   排序 / 地区 / 版本 / 首字母 / 年份 / 季度 / 状态 / 类型
     * 不同维度可以组合；未选择的维度默认「全部」（排序默认「更新时间」）。
     */
    getCategoryOptions(category) {
        if (category === '最近更新') {
            return null
        }else{
            return bmmdmm.filterGroups.map((g) => {
                const values = g.values.map((v) => ({ value: v, text: v }))
                const options = g.key === 'order'
                    ? values
                    : [{ value: '全部', text: '全部' }, ...values]
                return { label: g.label, options }
            })
        }
    }

    /**
     * 加载「综合筛选」第一页：返回分页容器。
     * 本页内容由 renderer 首次渲染时调用 pageMethod 加载。
     */
    async loadCategory(category, page = 1, options = []) {
        return [
            UI.Pagination({
                page: page,
                maxPage: 1000,
                pageMethod: 'loadCategoryPage',
                pageArgs: [category, 1, options],
            }),
        ]
    }

    /**
     * 按筛选条件构造 /list/ URL。
     * options 顺序与 filterGroups 一致；值为「全部」或空 的维度不参与（排序恒带默认值）。
     */
    _buildListUrl(category, page, options) {
        if (category === '最近更新') {
            return `${this.baseUrl}/list/?order=${encodeURIComponent('更新时间')}&pagesize=24&pageindex=${page - 1}`
        }else{
            const groups = bmmdmm.filterGroups
            const params = []
            for (let i = 0; i < groups.length; i++) {
                const g = groups[i]
                const val = options && i < options.length && options[i] != null
                    ? String(options[i]).trim()
                    : ''
                if (g.key === 'order') {
                    // 排序无「全部」选项，缺省用第一个（更新时间）
                    params.push(`order=${encodeURIComponent(val || g.values[0])}`)
                } else if (val && val !== '全部') {
                    params.push(`${g.key}=${encodeURIComponent(val)}`)
                }
            }
            params.push('pagesize=24')
            params.push(`pageindex=${page - 1}`)
            return `${this.baseUrl}/list/?${params.join('&')}`
        }
    }

    /**
     * 加载列表页指定页：返回结果卡片列表（UI.Pagination 换页时调用）。
     */
    async loadCategoryPage(category, page = 1, options = []) {
        const url = this._buildListUrl(category, page, options)
        let html
        try {
            html = await Network.get(url, this._headers())
        } catch (e) {
            console.error(`浏览请求失败: ${e}`)
            return []
        }
        if (!html) return []

        const cards = this._parseCards(html)
        if (cards.length === 0 && page <= 1) {
            Dialog.showToast('暂无影片')
        }
        return cards
    }

    // ============================================================
    // 详情页（剧集列表）
    // ============================================================

    /**
     * 从详情页提取所有剧集。
     *
     * bmmdmm 详情页结构：
     *   .movurl (多个，每个源一个)
     *     ul > li > a[href="/play/{id}-{sid}-{nid}.html"]   (nid 是 0-based)
     *       text 或 title = "第N集"
     *
     * 注意：所有 .movurl 都有相同的剧集列表（只是 sid 不同），
     *       用 nid 作 key 去重。
     *
     * @param {string} id
     * @returns {Promise<Array>}
     */
    async getDetail(id) {
        const url = `${this.baseUrl}/show/${id}.html`;
        let html;
        try {
            html = await Network.get(url, this._headers());
        } catch (e) {
            Dialog.showToast(`详情页请求失败: ${e}`);
            console.error(`详情页请求失败: ${e}`);
            return [];
        }
        if (!html) return [];

        const doc = new HtmlDocument(html);
        const items = [];

        // ===== 1. 提取元数据 =====
        const titleEl = doc.querySelector('h1');
        const title = titleEl ? (titleEl.text || '').trim() : '';

        // 封面：.thumb img
        const coverImg = doc.querySelector('.thumb img');
        const cover = coverImg
            ? (coverImg.attributes.src || coverImg.attributes['data-original'] || '')
            : '';

        // 详情页的元信息（label: value 配对）
        const infoSpans = doc.querySelectorAll('.sinfo span');
        let year = '', region = '', genre = '', status = '';
        for (const sp of infoSpans) {
            const labelEl = sp.querySelector('label');
            if (!labelEl) continue;
            const label = (labelEl.text || '').trim();
            // 取第一个 <a> 的文字作为值（可能没有 a，就用 text）
            const valueEl = sp.querySelector('a');
            const value = valueEl
                ? (valueEl.text || '').trim()
                : (sp.text || '').replace(label, '').trim();

            if (label.startsWith('上映')) year = value;
            else if (label.startsWith('地区')) region = value;
            else if (label.startsWith('类型')) genre = value;
            else if (label.startsWith('标签')) status = value;  // TV/4月/完结
        }

        // 更新到 X 集
        const epCountEl = doc.querySelector('.sinfo p');
        const epCountText = epCountEl ? (epCountEl.text || '').trim() : '';

        // 简介
        const descEl = doc.querySelector('.tabs .info');
        const description = descEl ? (descEl.text || '').trim() : '';

        // ===== 2. 头部卡片：封面 + 标题 + 元信息 =====
        if (cover || title) {
            const headerChildren = [];
            if (cover) {
                headerChildren.push(
                    UI.Image({ src: cover, width: 110, height: 150 })
                );
                headerChildren.push(UI.SizedBox({ width: 12 }));
            }
            headerChildren.push(
                UI.Expanded({
                    child: UI.Column({
                        crossAxisAlignment: 'start',
                        mainAxisAlignment: 'start',
                        children: [
                            UI.Text({
                                content: title,
                                style: { fontSize: 16, weight: 'bold' },
                                maxLines: 2,
                            }),
                            ...(year || region ? [UI.SizedBox({ height: 6 })] : []),
                            UI.Text({
                                content: [year, region].filter(Boolean).join(' · '),
                                style: { fontSize: 12, color: '#888888' },
                                maxLines: 1,
                            }),
                            genre ? UI.Text({
                                content: genre,
                                style: { fontSize: 12, color: '#888888' },
                                maxLines: 1,
                            }) : null,
                            status ? UI.Text({
                                content: status,
                                style: { fontSize: 12, color: '#888888' },
                                maxLines: 1,
                            }) : null,
                            ...(epCountText ? [UI.SizedBox({ height: 6 })] : []),
                            epCountText ? UI.Text({
                                content: epCountText,
                                style: { fontSize: 13, color: '#FF6B6B', weight: 'bold' },
                                maxLines: 1,
                            }) : null,
                        ].filter(c => c != null),
                    }),
                })
            );

            items.push(
                UI.Card({
                    padding: 12,
                    shapeRadius: 8,
                    child: UI.Row({
                        crossAxisAlignment: 'start',
                        children: headerChildren,
                    }),
                })
            );
        }

        // ===== 3. 简介卡片 =====
        if (description) {
            items.push(
                UI.Card({
                    padding: 12,
                    shapeRadius: 8,
                    child: UI.Text({
                        content: description,
                        style: { fontSize: 13, color: '#555555' },
                        maxLines: 6,
                    }),
                })
            );
        }

        // ===== 4. 剧集列表（每个源一组 ExpansionTile） =====
        // 提取源名（从 .menu0 的 li 文字）
        const sourceItems = doc.querySelectorAll('.menu0 li');
        const sourceNames = [];
        for (const tab of sourceItems) {
            const name = (tab.text || '').trim();
            if (name) sourceNames.push(name);
        }

        // 遍历所有 .movurl 面板（一个源一个面板）
        const allPanels = doc.querySelectorAll('.movurl');
        const sourcesWithEps = [];

        // 结构化播放源缓存（play 时整份传给播放页，支持自由选集/续播）
        this._playSources = { videoId: String(id), title: title, cover: cover, sources: [] }

        for (let i = 0; i < allPanels.length; i++) {
            const panel = allPanels[i];
            const episodes = panel.querySelectorAll('a[href^="/play/"]');
            if (episodes.length === 0) continue;

            // 用 nid 去重（所有源的 nid 都是 0~N-1，相同 nid 表示同一集）
            const seenNids = new Set();
            const epButtons = [];
            const sourceEpisodes = [];
            for (const a of episodes) {
                const href = a.attributes.href || '';
                if (!href) continue;

                // 从 URL 提取 nid 用于去重
                const nidMatch = href.match(/\/play\/[\w-]+-[\w-]+-(\d+)\.html/);
                const nid = nidMatch ? nidMatch[1] : '';
                if (nid && seenNids.has(nid)) continue;
                if (nid) seenNids.add(nid);

                // 剧集名：优先用 a 内的文字（"第1集"），其次用 title 属性
                const text = (a.text || a.attributes.title || '').trim()
                    || ('第 ' + (epButtons.length + 1) + ' 集');

                epButtons.push(
                    UI.Button({
                        label: text,
                        style: 'text',
                        onTap: UI.Action({
                            method: 'play',
                            args: [href, title + '(' + text + ')', cover],
                        }),
                    })
                );
                sourceEpisodes.push({
                    name: text,
                    type: 'resolve',
                    plugin: this.key,
                    method: 'resolvePlayUrl',
                    args: [href],
                });
            }

            const sourceName = sourceNames[i] || ('线路 ' + (i + 1));
            sourcesWithEps.push({ name: sourceName, eps: epButtons });
            this._playSources.sources.push({ name: sourceName, episodes: sourceEpisodes });
        }

        if (sourcesWithEps.length === 0) {
            const allLinks = doc.querySelectorAll('a');
            const playLinks = [];
            for (const a of allLinks) {
                const h = a.attributes.href || '';
                if (/\/play\//.test(h)) playLinks.push(h);
            }
            console.log(
                '[bmmdmm] 详情页未找到剧集' +
                '总链接:' + allLinks.length +
                '含 /play/ 的:'+ playLinks.length +
                '激活面板数:' + allPanels.length +
                '源 tab 数:' + sourceItems.length ,
            );
            items.push(
                UI.Text({
                    content: `未找到剧集（${allLinks.length} 链接）`,
                    style: { fontSize: 12, color: '#FF0000' },
                })
            );
        } else {
            // 每个源一个 ExpansionTile：title=源名，children=剧集 Wrap
            sourcesWithEps.forEach((src, i) => {
                items.push(
                    UI.ExpansionTile({
                        title: UI.Text({
                            content: `${src.name}（${src.eps.length} 集）`,
                            style: { fontSize: 14, weight: 'bold' },
                            maxLines: 1,
                        }),
                        initiallyExpanded: i === 0,
                        shapeRadius: 0,
                        children: [
                            UI.Container({
                                padding: 8,
                                child: UI.Wrap({
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: src.eps,
                                }),
                            }),
                        ],
                    })
                );
            });
        }

        PluginBrowse.open('bmmdmm',{
            id:url,
            title: title,
            cover:cover,
            kv:{id: id}
        });

        doc.dispose();
        return items;
    }

    // ============================================================
    // 播放（直接交给 wyw 视频播放器嗅探）
    // ============================================================

    /**
     * 进入播放：直接把播放页 URL 交给 wyw 视频播放器（isPage=true），
     * 由播放器自带资源嗅探能力自动提取 iframe / m3u8 / mp4 并加载原生播放器。
     *
     * @param {string} href  相对或绝对播放页 URL
     */
    /// 解析单集播放地址（供播放页 resolve 调用）。
    /// 本站无直链提取，直接返回播放页由播放器嗅探。
    async resolvePlayUrl(url) {
        return { url: this._abs(url), type: 'page' }
    }

    /// 进入播放：结构化传参（整部剧 sources + 当前集）。
    async play(href, title, cover) {
        const cache = this._playSources
        if (cache && cache.sources && cache.sources.length) {
            let initialSource = 0
            let initialEpisode = 0
            let found = false
            for (let s = 0; s < cache.sources.length && !found; s++) {
                const eps = cache.sources[s].episodes || []
                for (let e = 0; e < eps.length; e++) {
                    if ((eps[e].args && eps[e].args[0]) === href) {
                        initialSource = s
                        initialEpisode = e
                        found = true
                        break
                    }
                }
            }
            Navigator.navigateToVideo({
                videoId: cache.videoId,
                title: title || cache.title,
                cover: cover || cache.cover,
                sourceKey: this.key,
                initialSource: initialSource,
                initialEpisode: initialEpisode,
                sources: cache.sources,
            })
            return
        }
        // 无缓存兜底：单源单集（播放页嗅探）
        const playUrl = this._abs(href)
        const resolvedTitle = title || href
        Navigator.navigateToVideo({
            videoId: href,
            title: resolvedTitle,
            cover: cover || '',
            sourceKey: this.key,
            initialSource: 0,
            initialEpisode: 0,
            sources: [{
                name: '默认线路',
                episodes: [{ name: resolvedTitle, url: playUrl, type: 'page' }],
            }],
        })
    }

    /**
     * 浏览历史回放入口（由 PluginController.openBrowseEntry 调用）
     *
     * 入参 entry（来自 PluginHistoryEntry.toJson）：
     *   {
     *     pluginName, id, title, cover, visitTime, kv
     *   }
     *
     * 行为：跳到详情页继续选集（与首次进入一致）。
     *   - id 即 bmmdmm 资源 ID
     *   - title/cover 直接复用
     */
    async onOpenBrowseEntry(entry) {
        if (!entry || !entry.id) {
            Dialog.showToast('浏览历史无效');
            return;
        }
        Navigator.navigateToDescriptor('bmmdmm', {
            method: 'getDetail',
            args: [entry.kv.id],
            title: entry.title || '',
        })
    }
}