
// description: Hanime1.me 视频源（搜索 + 详情 + 播放，经 WebView 绕过反爬）
// type: video
//
// 安装方式：
//   1) 把本文件复制到 {appSupportDir}/plugins/hanime.js
//   2) 重启 App，在插件管理页刷新即可看到 "Hanime1" tab
//
// 接口约定：
//   search(keyword)  → List<UI.Card>，每张含封面 + 标题 + 时长/点赞/观看
//   play(url)        → 直接把播放页 URL 交给 wyw 视频播放器嗅探
//   （视频站无需详情页：搜索结果卡片直接进播放）
//
// 站点 URL 模式：
//   搜索：/search?query={keyword}&page={page}
//   详情：/watch?v={id}
//
// 注意：hanime1.me 有 Cloudflare 反爬，Dio 直连会 403，
// 统一用 Network.getHtml（系统 WebView 加载渲染后取 HTML）。
// 已接入 waitFor（等结果渲染/明确无结果再返回，避免 SPA 半成品 HTML）与
// 结构化错误（e.kind 区分 timeout/webview 等）。

class hanime extends PluginSource {
    name = 'Hanime1'
    key = 'hanime'
    version = '1.1.0'

    baseUrl = 'https://hanime1.me';

    /// 源网站地址（插件管理页「网站」菜单调用）
    getUrl() {
        return this.baseUrl;
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

    /// 经系统 WebView 加载页面（绕过 Cloudflare 反爬）。
    /// 支持 waitFor（等结果渲染出来再取 HTML，避免 SPA 半成品）；
    /// 失败抛**结构化错误**：e.kind 为 timeout / webview / ...，e.retryable 表示是否可重试。
    async _getHtml(url, waitFor) {
        return await Network.getHtml(url, {
            timeout: 50,
            waitFor: waitFor,
        });
    }

    _text(el) {
        return el ? (el.text || '').replace(/\s+/g, ' ').trim() : '';
    }

    // ============================================================
    // 搜索
    // ============================================================

    /**
     * 构造单个搜索结果卡片（两列：封面 + 信息）。
     */
    _buildResultCard({ cover, title, epInfo, author, id }) {
        const coverWidget = cover ? UI.Image({ src: cover, width: 80, height: 116 }) : null;
        const infoRows = [];
        infoRows.push(UI.Text({ content: title, style: { fontSize: 14, weight: 'bold' }, maxLines: 2 }));
        if (epInfo) {
            infoRows.push(UI.Row({
                crossAxisAlignment: 'center',
                children: [
                    UI.Icon({ name: 'play_circle_outline', size: 14, color: '#666666' }),
                    UI.SizedBox({ width: 4 }),
                    UI.Expanded({
                        child: UI.Text({ content: epInfo, style: { fontSize: 12, color: '#666666' }, maxLines: 2 }),
                    }),
                ],
            }));
        }
        if (author) {
            infoRows.push(UI.Text({ content: author, style: { fontSize: 11, color: '#888888' }, maxLines: 1 }));
        }
        const playButton = UI.IconButton({
            icon: 'play_circle_filled',
            tooltip: '播放',
            color: '#e53935',
            size: 20,
            onTap: UI.Action({ method: 'play', args: [`${this.baseUrl}/watch?v=${id}`, title, cover] }),
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
                    UI.Expanded({
                        child: UI.Column({
                            crossAxisAlignment: 'start',
                            mainAxisAlignment: 'start',
                            children: infoRows,
                        }),
                    }),
                    UI.SizedBox({ width: 8 }),
                    playButton,
                ].filter(c => c != null),
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
    _parseSearchHtml(html) {
        const doc = new HtmlDocument(html);
        const items = [];
        const containers1 = doc.querySelectorAll('.video-item-container');
        for (const item of containers1) {
            try {
                const link = item.querySelector('a.video-link');
                if (!link) continue;
                const href = link.attributes.href || '';
                const m = href.match(/\/watch\?v=(\d+)/);
                if (!m) continue;
                const id = m[1];
                const title = (item.attributes.title || this._text(item.querySelector('.title')) || '').trim();
                if (!title) continue;
                const img = item.querySelector('img.main-thumb');
                const cover = img ? (img.attributes.src || '') : '';
                const duration = this._text(item.querySelector('.duration'));
                const stats = this._text(item.querySelector('.stats-container'));
                const author = this._text(item.querySelector('.subtitle a'));
                const epInfo = [duration, stats].filter(Boolean).join(' · ');
                items.push(this._buildResultCard({ cover, title, epInfo, author, id }));
            } catch (e) {
                continue;
            }
        }
        const containers2 = doc.querySelectorAll('a[style="text-decoration: none;"]');
        for (const item of containers2) {
            try {
                const href = item.attributes.href || '';
                const m = href.match(/\/watch\?v=(\d+)/);
                if (!m) continue;
                const id = m[1];
                const title = this._text(item.querySelector('div.home-rows-videos-title'));
                if (!title) continue;
                const img = item.querySelector('img');
                const cover = img ? (img.attributes.src || '') : '';
                const duration = '';  // 根据需要添加
                const stats = '';     // 根据需要添加
                const author = '';    // 根据需要添加
                const epInfo = [duration, stats].filter(Boolean).join(' · ');
                items.push(this._buildResultCard({ cover, title, epInfo, author, id }));
            } catch (e) {
                continue;
            }
        }
        doc.dispose();
        return items;
    }

    /// 搜索/分类页的等待条件：等出结果卡片（任何 /watch?v= 链接），
    /// 或页面明确提示无结果，二者其一即认为页面已渲染完成，避免 SPA 半成品。
    static _waitSearchSettled() {
        return {
            type: 'js',
            value: 'document.querySelectorAll("a[href*=\\\"/watch?v=\\\"]").length > 0 '
                + '|| /(沒有找到|没有找到|找不到|無結果|无结果|no result|nothing found)/i.test(document.body ? document.body.innerText : "")',
        };
    }

    async search(keyword, page = 1) {
        const url = `${this.baseUrl}/search?query=${encodeURIComponent(keyword)}&page=${page}`;
        let html;
        try {
            html = await this._getHtml(url, hanime._waitSearchSettled());
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

    /// 分类结构（venera 的 category）。
    getCategory() {
        return {
            title: 'Hanime1',
            parts: [
                { name: '分类',  categories: ['里番', '泡面番', 'Motion Anime', '3DCG', '2.5D', '2D动画', 'AI生成', 'MMD', 'Cosplay']},
            ],
        }
    }

    static categoryMap = {
        '里番': '裏番',
        '泡面番': '泡麵番',
        'Motion Anime': 'Motion%20Anime',
        '3DCG': '3DCG',
        '2.5D': '2.5D',
        '2D动画': '2D動畫',
        'AI生成': 'AI生成',
        'MMD': 'MMD',
        'Cosplay': 'Cosplay',
    }

    /// 分类无预置筛选选项：选择分类后由 loadCategory 弹窗输入搜索词
    async getCategoryOptions(category) {
        return [
            {
                label: '关键字',
                type: 'input',
            }
        ]
    }

    /// 加载某分类：弹窗输入搜索词后返回分页容器。
    /// URL 形态：/search?query={词}&genre={分类}&page={页码}
    async loadCategory(category, page = 1, options = []) {
        return [
            UI.Pagination({
                page: page,
                maxPage: 200,
                pageMethod: 'loadCategoryPage',
                pageArgs: [category, 1, options],
            }),
        ]
    }

    /// 加载某分类指定页：返回**单纯的结果列表**（UI.Pagination 换页时调用）。
    async loadCategoryPage(category, page = 1, options = []) {
        const keyword = (options && options.length > 0) ? options[0] : ''
        const type = hanime.categoryMap[category]
        const url = `${this.baseUrl}/search?query=${encodeURIComponent(keyword)}&genre=${encodeURIComponent(type)}&page=${page}`
        let html
        try {
            html = await this._getHtml(url, hanime._waitSearchSettled())
        } catch (e) {
            console.error(`分类请求失败: ${e}${e && e.kind ? ' (kind=' + e.kind + ')' : ''}`)
            return []
        }
        if (!html) return []
        return this._parseSearchHtml(html)
    }

    // ============================================================
    // 播放（直接交给 wyw 视频播放器嗅探）
    // ============================================================

    /**
     * 进入播放：结构化传参（单源单集，page 类型交给播放器嗅探）。
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
                episodes: [{ name: t, url: url, type: 'page' }],
            }],
        })
    }
}
