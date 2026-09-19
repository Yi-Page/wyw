// description: pornhub 视频源（搜索 + 外部浏览器播放）
// type: video
//
// 安装方式：
//   1) 把本文件复制到 {appSupportDir}/plugins/pornhub.js
//   2) 重启 App，在插件管理页刷新即可看到 "pornhub" tab
//
// 接口约定：
//   search(keyword, page) → List<UI.Card>，每张含封面 + 标题 + 时长/观看
//   play(url)             → 确认后在外部浏览器打开该视频页
//
// 站点 URL 模式（cn.pornhub.com）：
//   搜索：/video/search?search={keyword}&page={page}
//   详情页（外部浏览器打开）：/view_video.php?viewkey={viewkey}
//
// 结构化错误（e.kind 区分 timeout/webview 等）。

class pornhub extends PluginSource {
    name = 'pornhub'
    key = 'pornhub'
    version = '1.0.0'

    baseUrl = 'https://cn.pornhub.com/';

    /// 源网站地址（插件管理页「网站」菜单调用）
    getUrl() {
        return this.baseUrl;
    }

    /// 统一请求头
    _headers() {
        return {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
            'Referer': this.baseUrl.replace(/\/+$/, '') + '/',
        };
    }

    // ============================================================
    // 工具
    // ============================================================

    /// 相对/协议相对/绝对 URL → 绝对 URL（baseUrl 尾部斜杠已容错）
    _abs(href) {
        if (!href) return '';
        if (href.startsWith('http://') || href.startsWith('https://')) return href;
        if (href.startsWith('//')) return 'https:' + href;
        const root = this.baseUrl.replace(/\/+$/, '');
        if (href.startsWith('/')) return root + href;
        return root + '/' + href;
    }

    // ============================================================
    // 搜索
    // ============================================================

    /**
     * 构造单个搜索结果卡片（两列：封面 + 信息）。
     */
    _buildResultCard({ cover, title, epInfo, href }) {
        const coverWidget = cover ? UI.Image({ src: cover, width: 80, height: 116 }) : null;
        const infoRows = [];
        infoRows.push(UI.Text({ content: title, style: { fontSize: 14, weight: 'bold' }, maxLines: 2 }));
        const playButton = UI.IconButton({
            icon: 'play_circle_filled',
            tooltip: '播放',
            color: '#e53935',
            size: 20,
            onTap: UI.Action({ method: 'play', args: [href] }),
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
     * 解析搜索结果 HTML → 卡片列表（search / 分类浏览共用）。
     *
     * 实际页面结构（cn.pornhub.com/video/search）：
     *   ul#videoSearchResult > li.pcVideoListItem
     *     a[href="/view_video.php?viewkey=xxx"]（链接）
     *       img（封面，src 为完整 https）
     *       div.marker-overlays > var.duration（时长）
     *     span.title > a（标题）
     *     span.views > var（观看数）
     */
    _parseSearchHtml(html) {
        const doc = new HtmlDocument(html);
        const items = [];

        // 桌面版：li.pcVideoListItem（#videoSearchResult 内，已在下方选择器限定）
        const containers = doc.querySelectorAll('#videoSearchResult .pcVideoListItem');

        for (const item of containers) {
            try {
                // 获取链接（相对路径 → 绝对 URL）
                const link = item.querySelector('a[href*="/view_video.php?viewkey="]');
                if (!link) continue;
                const href = this._abs(link.attributes.href || '');
                if (!href) continue;

                // 获取标题
                const titleElement = item.querySelector('.title a');
                const title = titleElement ? titleElement.text.trim() : '';
                if (!title) continue;

                // 获取封面（完整 URL 原样返回）
                const img = item.querySelector('img');
                const cover = img ? this._abs(img.attributes.src || '') : '';

                // 副信息：时长 + 观看数
                const duration = item.querySelector('.marker-overlays .duration');
                const views = item.querySelector('.views var');
                const epInfo = [
                    duration ? duration.text.trim() : '',
                    views ? views.text.trim() : '',
                ].filter(s => s).join(' · ');

                items.push(this._buildResultCard({ cover, title, epInfo, href }));
            } catch (e) {
                console.warn('解析单个视频项失败: ' + (e && e.message || e));
                continue;
            }
        }

        // 移动端结构（.videoWrapper）——当前站点无此节点时为空循环，兼容保留
        const containersAndroid = doc.querySelectorAll('#videoSearchResult .videoWrapper');

        for (const item of containersAndroid) {
            try {
                const link = item.querySelector('a[href*="/view_video.php?viewkey="]');
                if (!link) continue;
                const href = this._abs(link.attributes.href || '');
                if (!href) continue;

                const titleElement = item.querySelector('.title a');
                const title = titleElement ? titleElement.text.trim() : '';
                if (!title) continue;

                const img = item.querySelector('img');
                const cover = img ? this._abs(img.attributes.src || '') : '';

                const duration = item.querySelector('.marker-overlays .duration');
                const views = item.querySelector('.views var');
                const epInfo = [
                    duration ? duration.text.trim() : '',
                    views ? views.text.trim() : '',
                ].filter(s => s).join(' · ');

                items.push(this._buildResultCard({ cover, title, epInfo, href }));
            } catch (e) {
                console.warn('解析单个视频项失败: ' + (e && e.message || e));
                continue;
            }
        }

        doc.dispose();
        return items;
    }

    async search(keyword, page = 1) {
        if(keyword === null || keyword === ''){
            return [];
        }
        const url = `${this.baseUrl}video/search?search=${encodeURIComponent(keyword)}&page=${page}`;
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

    /**
     * 外部浏览器打开。
     */
    async play(url) {
        Dialog.openExternalBrowser(url);
    }
}
