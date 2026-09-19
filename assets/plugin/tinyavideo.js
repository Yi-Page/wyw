// description: tinyavideo 视频源（搜索 + 详情 + 播放）
// type: video
//
// 安装方式：
//   1) 把本文件复制到 {appSupportDir}/plugins/tinyavideo.js
//   2) 重启 App，在插件管理页刷新即可看到 "Hanime1" tab
//
// 接口约定：
//   search(keyword)  → List<UI.Card>，每张含封面 + 标题 + 时长/点赞/观看
//   play(url)        → resolve 惰性解析：播放器开播前回调 resolvePlayUrl(url)，
//                      先请求 /video/{id} 播放页，从 <script type="application/ld+json">
//                      的 VideoObject.contentUrl 提取 m3u8/mp4 直链直连播放；
//                      提取失败回退为播放页嗅探（type='page'）
//   （视频站无需详情页：搜索结果卡片直接进播放）
//   getCategory()    → 浏览页 Tab，两个 parts：
//                      「首页」：分类"首页" = 主页各板块（h2.ftpp + front_block 视频网格）
//                      「热门搜索」：主页 #block-search-stats 热搜词，点击即搜该词（分页）
//   loadCategory / loadCategoryPage / getCategoryOptions  → 分类浏览配套
//
// 站点 URL 模式：
//   搜索：/search?fulltext={keyword}&page={page}
//   详情：/video/{id}
//
// 注意：hanime1.me 有 Cloudflare 反爬，Dio 直连会 403，
// 统一用 Network.getHtml（系统 WebView 加载渲染后取 HTML）。
// 已接入 waitFor（等结果渲染/明确无结果再返回，避免 SPA 半成品 HTML）与
// 结构化错误（e.kind 区分 timeout/webview 等）。

class tinyavideo extends PluginSource {
    name = 'tinyavideo'
    key = 'tinyavideo'
    version = '1.2.0'

    baseUrl = 'https://tinyavideo.com/';

    // 分类浏览状态：主页缓存（10 分钟 TTL）+ 热搜词
    _homeCache = null            // { time, sections: [{title, videos}], hotSearches }
    _homeCacheTtl = 10 * 60 * 1000
    _hotSearches = []

    /// 源网站地址（插件管理页「网站」菜单调用）
    getUrl() {
        return this.baseUrl;
    }

    /// 统一请求头
    _headers() {
        return {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
            'Referer': this.baseUrl + '/',
        };
    }

    // ============================================================
    // 工具
    // ============================================================

    _abs(href) {
        if (!href) return '';
        if (href.startsWith('http://') || href.startsWith('https://')) return href;
        if (href.startsWith('//')) return 'https:' + href;
        if (href.startsWith('/')) return this.baseUrl + href;
        return this.baseUrl + '/' + href;
    }

    // ============================================================
    // 搜索
    // ============================================================

    /**
     * 构造单个搜索结果卡片（两列：封面 + 信息）。
     */
    _buildResultCard({ cover, title, epInfo, id }) {
        const coverWidget = cover ? UI.Image({ src: cover, width: 80, height: 116 }) : null;
        const infoRows = [];
        infoRows.push(UI.Text({ content: title, style: { fontSize: 14, weight: 'bold' }, maxLines: 2 }));
        const playButton = UI.IconButton({
            icon: 'play_circle_filled',
            tooltip: '播放',
            color: '#e53935',
            size: 20,
            onTap: UI.Action({ method: 'play', args: [`${this.baseUrl}/video/${id}`, title, cover] }),
        });
        if (epInfo) {
            infoRows.push(UI.Row({
                crossAxisAlignment: 'center',
                children: [
                    UI.Expanded({
                        child: UI.Text({ content: epInfo, style: { fontSize: 12, color: '#666666' }, maxLines: 3 }),
                    }),
                    playButton
                ],
            }));
        }
        return UI.Card({
            elevation: 0,
            shapeRadius: 16,
            color: '@theme:surfaceContainerLow',
            padding: 4,
            child: UI.Row({
                crossAxisAlignment: 'start',
                children: [
                    coverWidget,
                    UI.SizedBox({ width: 6 }),
                    UI.Expanded({
                        child: UI.Column({
                            crossAxisAlignment: 'start',
                            mainAxisAlignment: 'start',
                            children: infoRows,
                        }),
                    }),
                ].filter(c => c != null),
            }),
        });
    }

    /**
     * 紧凑横版视频卡片（分类浏览「首页」板块网格用，封面 16:9）。
     * 外层 Container 定宽进 Wrap；Card 渲染固定 margin 8/6，内容区宽 = 158-16-12 = 130。
     */
    _buildGridCard({ id, title, cover, epInfo }) {
        const playButton = UI.IconButton({
            icon: 'play_circle_filled',
            tooltip: '播放',
            color: '#e53935',
            size: 20,
            onTap: UI.Action({ method: 'play', args: [`${this.baseUrl}/video/${id}`, title, cover] }),
        });
        return UI.Container({
            width: 158,
            child: UI.Card({
                elevation: 0,
                shapeRadius: 12,
                color: '@theme:surfaceContainerLow',
                padding: 6,
                child: UI.Column({
                    crossAxisAlignment: 'start',
                    mainAxisAlignment: 'start',
                    mainAxisSize: 'min',
                    children: [
                        UI.Image({ src: cover, width: 130, height: 73 }),
                        UI.SizedBox({ height: 4 }),
                        UI.Text({ content: title, style: { fontSize: 12 }, maxLines: 2 }),
                        epInfo
                            ? UI.Row({
                                crossAxisAlignment: 'center',
                                children: [
                                    UI.Expanded({ child: UI.Text({ content: epInfo, style: { fontSize: 10, color: '#666666' }, maxLines: 1 }) }),
                                    playButton,
                                ],
                            })
                            : playButton,
                    ].filter(c => c != null),
                }),
            }),
        });
    }

    /**
     * 搜索入口。
     *
     * 搜索页结构（hanime1.me/search?query=xx&page=N）：
     *   div.video-item-container > div.horizontal-card
     *     a.video-link[href="/watch?v={id}"]
     *       img.main-thumb（封面）
     *       div.duration（时长）
     *       div.stats-container > div.stat-item（点赞 / 观看数）
     *       div.title（标题）
     *     div.subtitle > a（作者）
     * 广告卡片（erolabs 外链）不匹配 /watch?v= 直接跳过。
     */
    /// 解析搜索结果 HTML → 卡片列表（search / 分类浏览共用）
    /// 解析搜索结果 HTML → 卡片列表（search / 分类浏览共用）
    _parseSearchHtml(html) {
        const doc = new HtmlDocument(html);
        const items = [];

        // 根据实际HTML结构：div#views-bootstrap-search-page-1 .grid .cf
        const containers = doc.querySelectorAll('#views-bootstrap-search-page-1 .cf');

        for (const item of containers) {
            try {
                // 获取链接和ID
                const link = item.querySelector('a[href*="/video/"]');
                if (!link) continue;

                const href = link.attributes.href || '';
                // slug 兼容纯数字（/video/72188）与字母数字连字符（/video/zc-095、/video/fc2ppv-3061625-chinese-subtitle）
                const m = href.match(/\/video\/([\w-]+)/);
                if (!m) continue;
                const id = m[1];

                // 获取标题
                const titleElement = item.querySelector('.videotitle a');
                const title = titleElement ? titleElement.text.trim() : '';
                if (!title) continue;

                // 获取封面（添加域名前缀）
                const img = item.querySelector('img');
                let cover = img ? (img.attributes.src || '') : '';
                if (cover && !cover.startsWith('http://') && !cover.startsWith('https://')) {
                    // 如果是以 / 开头的相对路径，直接拼接域名
                    if (cover.startsWith('/')) {
                        cover = this.baseUrl + cover.slice(1);
                    } else {
                        cover = this.baseUrl + cover;
                    }
                }

                // 获取热度（🔥 数字）
                const badge = item.querySelector('.video-badge .count-number');
                const epInfo = badge ? badge.text.trim() : '';


                items.push(this._buildResultCard({ cover, title, epInfo, id }));
            } catch (e) {
                console.warn('解析单个视频项失败:', e);
                continue;
            }
        }

        doc.dispose();
        return items;
    }

    async search(keyword, page = 1) {
        const url = `${this.baseUrl}/search?fulltext=${encodeURIComponent(keyword)}&page=${page}`;
        let html;
        try {
            html = await Network.get(url, this._headers());
        } catch (e) {
            console.error(`搜索请求失败: ${e}${e && e.kind ? ' (kind=' + e.kind + ')' : ''}`);
            if (e && (e.kind === 'timeout' || e.kind === 'webview')) {
                Dialog.showToast('搜索超时或页面加载失败，请重试');
            }
            return [];
        }
        if (!html) return [];

        const items = this._parseSearchHtml(html);
        if (items.length === 0 && page <= 1) {
            Dialog.showToast('未找到结果，请检查关键词');
        }
        return items;
    }

    // ============================================================
    // 分类浏览（浏览页 Tab：「首页」板块 + 「热门搜索」关键词）
    // ============================================================

    /**
     * 分类结构（浏览页 Tab）。
     * part「首页」→ 单分类"首页"：抓主页按板块渲染；
     * part「热门搜索」→ 主页 #block-search-stats 的热搜词，每个词一个分类，点击即搜。
     */
    async getCategory() {
        if (!this._hotSearches.length) {
            const cached = this.loadData('hot_searches');
            if (Array.isArray(cached) && cached.length) this._hotSearches = cached;
        }
        if (!this._hotSearches.length) {
            try {
                const home = await this._fetchHome();
                if (home.hotSearches.length) this._hotSearches = home.hotSearches;
            } catch (e) {
                console.warn('[tinyavideo] 分类页获取主页失败: ' + e);
            }
        }
        if (!this._hotSearches.length) {
            // 主页抓取失败且无缓存时的兜底（不写入缓存，成功后自动覆盖）
            this._hotSearches = ['巨乳', '無碼流出', 'fc2', '中文字幕', 'cos'];
        }
        return {
            title: 'TinyAV',
            parts: [
                { name: '首页', categories: ['首页'] },
                { name: '热门搜索', categories: this._hotSearches },
            ],
        };
    }

    getCategoryOptions(category) {
        return null;
    }

    /**
     * 抓取并解析主页（10 分钟缓存），产出板块列表 + 热搜关键词。
     * 主页结构：
     *   #block-search-stats ul li a          → 热搜词（/search?fulltext={词}）
     *   article.node--type-full-page 内：
     *     h2.ftpp（板块标题）× 5 与
     *     .view-front-block .views-view-grid（视频网格）× 5 按文档顺序一一配对
     */
    async _fetchHome() {
        const now = Date.now();
        if (this._homeCache && now - this._homeCache.time < this._homeCacheTtl) {
            return this._homeCache;
        }
        let html = '';
        try {
            // backend:'auto'：疑似反爬自动降级 WebView 渲染
            html = await Network.get(this.baseUrl, this._headers(), { backend: 'auto' });
        } catch (e) {
            console.warn('[tinyavideo] 主页请求失败: ' + e + (e && e.kind ? ' (kind=' + e.kind + ')' : ''));
            throw e;
        }
        if (!html) throw '主页返回为空: ' + this.baseUrl;
        console.log('[tinyavideo] 主页返回: 页长=' + html.length);

        const doc = new HtmlDocument(html);
        const hotSearches = [];
        try {
            const seen = new Set();
            for (const a of doc.querySelectorAll('#block-search-stats li a')) {
                const t = (a.text || '').trim();
                if (!t || seen.has(t)) continue;
                seen.add(t);
                hotSearches.push(t);
            }

            const article = doc.querySelector('article.node--type-full-page') || doc.querySelector('#block-stack-content');
            const sections = [];
            if (article) {
                const headers = article.querySelectorAll('h2.ftpp');
                const grids = article.querySelectorAll('.view-front-block .views-view-grid');
                console.log('[tinyavideo] 主页板块: h2=' + headers.length + ' grid=' + grids.length + ' 热搜=' + hotSearches.length);
                const n = Math.min(headers.length, grids.length);
                for (let i = 0; i < n; i++) {
                    const title = (headers[i].text || '').trim();
                    const videos = this._parseCardItems(grids[i]);
                    if (title && videos.length) sections.push({ title: title, videos: videos });
                }
            } else {
                console.warn('[tinyavideo] 主页未找到 article/#block-stack-content 容器');
            }

            this._homeCache = { time: now, sections: sections, hotSearches: hotSearches };
            if (hotSearches.length) {
                this._hotSearches = hotSearches;
                this.saveData('hot_searches', hotSearches);
            }
            return this._homeCache;
        } finally {
            doc.dispose();
        }
    }

    /**
     * 解析一个视频网格容器（.cf 卡片）→ [{id, title, cover, epInfo}]
     * 与搜索结果卡片同构，slug 兼容纯数字与字母数字连字符。
     */
    _parseCardItems(container) {
        const videos = [];
        for (const item of container.querySelectorAll('.cf')) {
            try {
                const link = item.querySelector('a[href*="/video/"]');
                if (!link) continue;
                const href = link.attributes.href || '';
                const m = href.match(/\/video\/([\w-]+)/);
                if (!m) continue;
                const titleEl = item.querySelector('.videotitle a');
                const title = titleEl ? titleEl.text.trim() : '';
                if (!title) continue;
                const img = item.querySelector('img');
                const cover = img ? this._abs(img.attributes.src || '') : '';
                const badge = item.querySelector('.video-badge .count-number');
                videos.push({ id: m[1], title: title, cover: cover, epInfo: badge ? badge.text.trim() : '' });
            } catch (e) {
                console.warn('[tinyavideo] 解析单个主页卡片失败:', e);
                continue;
            }
        }
        return videos;
    }

    /**
     * 进入分类：
     *   「首页」→ 主页各板块（ExpansionTile + 横版网格），无分页；
     *   热搜词  → 该词的搜索结果（UI.Pagination 分页）。
     */
    async loadCategory(category, page = 1, options = []) {
        if (category === '首页') {
            return this._buildHomeItems();
        }
        // 热门搜索关键词 → 搜索结果分页（先探测最大页码）
        let maxPage = 1;
        try {
            const url = `${this.baseUrl}/search?fulltext=${encodeURIComponent(category)}&page=1`;
            const html = await Network.get(url, this._headers());
            if (html) maxPage = this._extractSearchMaxPage(html);
        } catch (e) {
            console.warn('[tinyavideo] 分类最大页探测失败: ' + e);
        }
        return [
            UI.Pagination({
                page: Math.min(Math.max(1, page), maxPage),
                maxPage: maxPage,
                pageMethod: 'loadCategoryPage',
                pageArgs: [category, 1, options],
            }),
        ];
    }

    /**
     * 分类某页内容（UI.Pagination 换页时调用）：
     *   「首页」→ 无分页，仅第 1 页返回板块内容；
     *   热搜词  → /search?fulltext={词}&page={page} 的结果卡片。
     */
    async loadCategoryPage(category, page = 1, options = []) {
        if (category === '首页') {
            return page <= 1 ? this._buildHomeItems() : [];
        }
        const url = `${this.baseUrl}/search?fulltext=${encodeURIComponent(category)}&page=${page}`;
        let html;
        try {
            html = await Network.get(url, this._headers());
        } catch (e) {
            console.error(`[tinyavideo] 热门搜索结果请求失败: ${e}${e && e.kind ? ' (kind=' + e.kind + ')' : ''}`);
            Dialog.showToast('加载失败，请检查网络');
            return [];
        }
        if (!html) return [];
        const items = this._parseSearchHtml(html);
        if (items.length === 0 && page <= 1) {
            Dialog.showToast('该关键词暂无结果');
        }
        return items;
    }

    /// 首页内容（单页展示全部板块，第一个板块默认展开）
    async _buildHomeItems() {
        let sections;
        try {
            sections = (await this._fetchHome()).sections;
        } catch (e) {
            console.error('[tinyavideo] 主页加载失败: ' + e);
            Dialog.showToast('主页加载失败，请重试');
            return [UI.Text({ content: '主页加载失败: ' + e, style: { fontSize: 12, color: '#FF0000' } })];
        }
        if (!sections.length) {
            return [UI.Text({ content: '主页解析为空，请重试', style: { fontSize: 12, color: '#FF0000' } })];
        }
        const items = [];
        sections.forEach((sec, i) => {
            items.push(UI.ExpansionTile({
                title: UI.Text({ content: `${sec.title}（${sec.videos.length}）`, style: { fontSize: 14, weight: 'bold' }, maxLines: 1 }),
                initiallyExpanded: i === 0,
                shapeRadius: 0,
                children: [
                    UI.Container({
                        padding: 6,
                        child: UI.Wrap({
                            spacing: 6,
                            runSpacing: 6,
                            children: sec.videos.map(v => this._buildGridCard(v)),
                        }),
                    }),
                ],
            }));
        });
        return items;
    }

    /// 从搜索结果页 HTML 提取最大页码（扫描所有 page=N 链接，含 &amp; 转义形态）
    _extractSearchMaxPage(html) {
        let max = 1;
        const re = /(?:[?&]|&amp;)page=(\d+)/g;
        let m;
        while ((m = re.exec(html)) !== null) {
            const n = parseInt(m[1], 10);
            if (!isNaN(n) && n + 1 > max) max = n + 1;
        }
        return Math.min(max, 999);
    }

    // ============================================================
    // 播放（播放前先请求播放页，从 JSON-LD 提取直链）
    // ============================================================

    /**
     * 从播放页 HTML 提取 JSON-LD（application/ld+json）VideoObject.contentUrl。
     *
     * 页面结构（tinyavideo /video/{id}）：
     *   <script type="application/ld+json">{
     *     "@context": "https://schema.org",
     *     "@graph": [{ "@type": "VideoObject", ..., "contentUrl": "https://.../index.m3u8" }]
     *   }</script>
     * 兼容三种形态：@graph 数组 / 顶层 VideoObject / 顶层数组。
     * JSON 解析全部失败时兜底正则直接抓 "contentUrl" 字段。
     */
    _extractJsonLdVideoUrl(html) {
        const re = /<script[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi;
        let blockCount = 0;
        let m;
        while ((m = re.exec(html)) !== null) {
            blockCount++;
            try {
                const data = JSON.parse(m[1].trim());
                const nodes = [];
                const collect = (node) => {
                    if (!node) return;
                    if (Array.isArray(node)) { node.forEach(collect); return; }
                    if (typeof node === 'object') {
                        nodes.push(node);
                        if (node['@graph']) collect(node['@graph']);
                    }
                };
                collect(data);
                for (const node of nodes) {
                    const t = node['@type'];
                    const types = Array.isArray(t) ? t : [t];
                    if (types.some(x => String(x).toLowerCase() === 'videoobject') && node.contentUrl) {
                        console.log('[tinyavideo] JSON-LD 命中 VideoObject（第' + blockCount + '块）');
                        return String(node.contentUrl);
                    }
                }
            } catch (e) {
                console.warn('[tinyavideo] 第' + blockCount + '块 ld+json 解析失败，跳过: ' + e);
            }
        }
        // 兜底：不依赖 JSON 结构，直接抓 contentUrl 字段（含 \/ 转义场景）
        const m2 = html.match(/"contentUrl"\s*:\s*"([^"]+)"/);
        if (m2 && m2[1]) {
            console.log('[tinyavideo] JSON-LD 结构化解析未命中，正则兜底提取 contentUrl');
            return m2[1].replace(/\\\//g, '/');
        }
        console.warn('[tinyavideo] 页面中未找到 ld+json/contentUrl（ld+json 块数=' + blockCount + '）');
        return '';
    }

    /**
     * 解析单集真实播放地址（供播放器开播前 resolve 调用）：
     * 请求 /video/{id} 播放页 → 提取 JSON-LD VideoObject.contentUrl（m3u8/mp4 直链）。
     * 返回 { url, type }：type 为 'direct'（直链）/ 'page'（回退给播放器嗅探）。
     */
    async resolvePlayUrl(url) {
        // 兼容旧版 /watch?v={id}（模板遗留格式），统一转成播放页 /video/{id}
        let pageUrl = this._abs(url);
        const wv = pageUrl.match(/\/watch\?v=(\d+)/);
        if (wv) pageUrl = this.baseUrl + '/video/' + wv[1];
        console.log('[tinyavideo] resolvePlayUrl 请求播放页: ' + pageUrl);

        let html = '';
        try {
            // backend:'auto'：HTTP 疑似反爬（403/429/5xx/超时/断连）自动降级 WebView 渲染
            html = await Network.get(pageUrl, this._headers(), { backend: 'auto' });
        } catch (e) {
            console.warn('[tinyavideo] 播放页请求失败: ' + e + (e && e.kind ? ' (kind=' + e.kind + ')' : ''));
        }
        if (html) console.log('[tinyavideo] 播放页返回: 页长=' + html.length);

        const videoUrl = html ? this._extractJsonLdVideoUrl(html) : '';
        if (videoUrl) {
            // m3u8/mp4 等媒体直链 → direct；异常情况（contentUrl 是网页）→ page 嗅探
            const direct = /\.(m3u8|mp4|flv|mkv|ts|webm)(\?|$)/i.test(videoUrl) || videoUrl.indexOf('.m3u8') >= 0;
            console.log('[tinyavideo] 提取到直链(' + (direct ? 'direct' : 'page') + '): ' + videoUrl);
            return { url: videoUrl, type: direct ? 'direct' : 'page' };
        }
        // 提取失败：回退为播放页嗅探（保持旧行为，尽量能播）
        console.warn('[tinyavideo] 未提取到 contentUrl，回退播放页嗅探: ' + pageUrl);
        Dialog.showToast('未解析到直链，已回退播放器嗅探');
        return { url: pageUrl, type: 'page' };
    }

    /**
     * 进入播放：结构化传参（单源单集，resolve 惰性解析 ——
     * 播放器开播前调用 resolvePlayUrl 请求播放页提取直链）。
     */
    async play(url, title, cover) {
        const t = (title && title !== '') ? title : url
        Navigator.navigateToVideo({
            videoId: url,
            title: t,
            cover: cover || '',
            sourceKey: this.key,
            initialSource: 0,
            initialEpisode: 0,
            sources: [{
                name: '默认线路',
                episodes: [{
                    name: t,
                    type: 'resolve',
                    plugin: this.key,
                    method: 'resolvePlayUrl',
                    args: [url],
                }],
            }],
        })
    }
}
