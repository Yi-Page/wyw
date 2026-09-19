/*
Venera JavaScript Library

This library provides a set of APIs for interacting with the Venera app.
*/

/**
 * @function sendMessage
 * @global
 * @param {Object} message
 * @returns {any}
 */

/**
 * Set a timeout to execute a callback function after a specified delay.
 * @param callback {Function}
 * @param delay {number} - delay in milliseconds
 */
function setTimeout(callback, delay) {
    sendMessage({
        method: 'delay',
        time: delay,
    }).then(callback);
}

/// encode, decode, hash, decrypt
let Convert = {
    /**
     * @param str {string}
     * @returns {ArrayBuffer}
     */
    encodeUtf8: (str) => {
        return sendMessage({
            method: "convert",
            type: "utf8",
            value: str,
            isEncode: true
        });
    },

    /**
     * @param value {ArrayBuffer}
     * @returns {string}
     */
    decodeUtf8: (value) => {
        return sendMessage({
            method: "convert",
            type: "utf8",
            value: value,
            isEncode: false
        });
    },

    /**
     * @param str {string}
     * @returns {ArrayBuffer}
     */
    encodeGbk: (str) => {
        return sendMessage({
            method: "convert",
            type: "gbk",
            value: str,
            isEncode: true
        });
    },

    /**
     * @param value {ArrayBuffer}
     * @returns {string}
     */
    decodeGbk: (value) => {
        return sendMessage({
            method: "convert",
            type: "gbk",
            value: value,
            isEncode: false
        });
    },

    /**
     * @param {ArrayBuffer} value
     * @returns {string}
     */
    encodeBase64: (value) => {
        return sendMessage({
            method: "convert",
            type: "base64",
            value: value,
            isEncode: true
        });
    },

    /**
     * @param {string} value
     * @returns {ArrayBuffer}
     */
    decodeBase64: (value) => {
        return sendMessage({
            method: "convert",
            type: "base64",
            value: value,
            isEncode: false
        });
    },

    /**
     * @param {ArrayBuffer} value
     * @returns {ArrayBuffer}
     */
    md5: (value) => {
        return sendMessage({
            method: "convert",
            type: "md5",
            value: value,
            isEncode: true
        });
    },

    /**
     * @param {ArrayBuffer} value
     * @returns {ArrayBuffer}
     */
    sha1: (value) => {
        return sendMessage({
            method: "convert",
            type: "sha1",
            value: value,
            isEncode: true
        });
    },

    /**
     * @param {ArrayBuffer} value
     * @returns {ArrayBuffer}
     */
    sha256: (value) => {
        return sendMessage({
            method: "convert",
            type: "sha256",
            value: value,
            isEncode: true
        });
    },

    /**
     * @param {ArrayBuffer} value
     * @returns {ArrayBuffer}
     */
    sha512: (value) => {
        return sendMessage({
            method: "convert",
            type: "sha512",
            value: value,
            isEncode: true
        });
    },

    /**
     * @param key {ArrayBuffer}
     * @param value {ArrayBuffer}
     * @param hash {string} - md5, sha1, sha256, sha512
     * @returns {ArrayBuffer}
     */
    hmac: (key, value, hash) => {
        return sendMessage({
            method: "convert",
            type: "hmac",
            value: value,
            key: key,
            hash: hash,
            isEncode: true
        });
    },

    /**
     * @param key {ArrayBuffer}
     * @param value {ArrayBuffer}
     * @param hash {string} - md5, sha1, sha256, sha512
     * @returns {string} - hex string
     */
    hmacString: (key, value, hash) => {
        return sendMessage({
            method: "convert",
            type: "hmac",
            value: value,
            key: key,
            hash: hash,
            isEncode: true,
            isString: true
        });
    },

    /**
     * @param {ArrayBuffer} value
     * @param {ArrayBuffer} key
     * @returns {ArrayBuffer}
     */
    encryptAesEcb: (value, key) => {
        return sendMessage({
            method: "convert",
            type: "aes-ecb",
            value: value,
            key: key,
            isEncode: true
        });
    },

    /**
     * @param {ArrayBuffer} value
     * @param {ArrayBuffer} key
     * @returns {ArrayBuffer}
     */
    decryptAesEcb: (value, key) => {
        return sendMessage({
            method: "convert",
            type: "aes-ecb",
            value: value,
            key: key,
            isEncode: false
        });
    },

    /**
     * @param {ArrayBuffer} value
     * @param {ArrayBuffer} key
     * @param {ArrayBuffer} iv
     * @returns {ArrayBuffer}
     */
    encryptAesCbc: (value, key, iv) => {
        return sendMessage({
            method: "convert",
            type: "aes-cbc",
            value: value,
            key: key,
            iv: iv,
            isEncode: true
        });
    },

    /**
     * @param {ArrayBuffer} value
     * @param {ArrayBuffer} key
     * @param {ArrayBuffer} iv
     * @returns {ArrayBuffer}
     */
    decryptAesCbc: (value, key, iv) => {
        return sendMessage({
            method: "convert",
            type: "aes-cbc",
            value: value,
            key: key,
            iv: iv,
            isEncode: false
        });
    },

    /**
     * @param {ArrayBuffer} value
     * @param {ArrayBuffer} key
     * @param {ArrayBuffer} iv
     * @param {number} blockSize
     * @returns {ArrayBuffer}
     */
    encryptAesCfb: (value, key, iv, blockSize) => {
        return sendMessage({
            method: "convert",
            type: "aes-cfb",
            value: value,
            key: key,
            iv: iv,
            blockSize: blockSize,
            isEncode: true
        });
    },

    /**
     * @param {ArrayBuffer} value
     * @param {ArrayBuffer} key
     * @param {ArrayBuffer} iv
     * @param {number} blockSize
     * @returns {ArrayBuffer}
     */
    decryptAesCfb: (value, key, iv, blockSize) => {
        return sendMessage({
            method: "convert",
            type: "aes-cfb",
            value: value,
            key: key,
            iv: iv,
            blockSize: blockSize,
            isEncode: false
        });
    },

    /**
     * @param {ArrayBuffer} value
     * @param {ArrayBuffer} key
     * @param {number} blockSize
     * @returns {ArrayBuffer}
     */
    encryptAesOfb: (value, key, blockSize) => {
        return sendMessage({
            method: "convert",
            type: "aes-ofb",
            value: value,
            key: key,
            blockSize: blockSize,
            isEncode: true
        });
    },

    /**
     * @param {ArrayBuffer} value
     * @param {ArrayBuffer} key
     * @param {number} blockSize
     * @returns {ArrayBuffer}
     */
    decryptAesOfb: (value, key, blockSize) => {
        return sendMessage({
            method: "convert",
            type: "aes-ofb",
            value: value,
            key: key,
            blockSize: blockSize,
            isEncode: false
        });
    },

    /**
     * @param {ArrayBuffer} value
     * @param {ArrayBuffer} key
     * @returns {ArrayBuffer}
     */
    decryptRsa: (value, key) => {
        return sendMessage({
            method: "convert",
            type: "rsa",
            value: value,
            key: key,
            isEncode: false
        });
    },
    /** Encode bytes to hex string
     * @param bytes {ArrayBuffer}
     * @return {string}
     */
    hexEncode: (bytes) => {
        const hexDigits = '0123456789abcdef';
        const view = new Uint8Array(bytes);
        let charCodes = new Uint8Array(view.length * 2);
        let j = 0;

        for (let i = 0; i < view.length; i++) {
            let byte = view[i];
            charCodes[j++] = hexDigits.charCodeAt((byte >> 4) & 0xF);
            charCodes[j++] = hexDigits.charCodeAt(byte & 0xF);
        }

        return String.fromCharCode(...charCodes);
    },
}

/**
 * create a time-based uuid
 *
 * Note: the engine will generate a new uuid every time it is called
 *
 * To get the same uuid, please save it to the local storage
 *
 * @returns {string}
 */
function createUuid() {
    return sendMessage({
        method: "uuid"
    });
}

/**
 * Generate a random integer between min and max
 * @param min {number}
 * @param max {number}
 * @returns {number}
 */
function randomInt(min, max) {
    return sendMessage({
        method: 'random',
        type: 'int',
        min: min,
        max: max
    });
}

/**
 * Generate a random double between min and max
 * @param min {number}
 * @param max {number}
 * @returns {number}
 */
function randomDouble(min, max) {
    return sendMessage({
        method: 'random',
        type: 'double',
        min: min,
        max: max
    });
}

class _Timer {
    delay = 0;

    callback = () => { };

    status = false;

    constructor(delay, callback) {
        this.delay = delay;
        this.callback = callback;
    }

    run() {
        this.status = true;
        this._interval();
    }

    _interval() {
        if (!this.status) {
            return;
        }
        this.callback();
        setTimeout(this._interval.bind(this), this.delay);
    }

    cancel() {
        this.status = false;
    }
}

function setInterval(callback, delay) {
    let timer = new _Timer(delay, callback);
    timer.run();
    return timer;
}

/**
 * Network 工具类：统一的 HTTP 请求 / WebView 取 HTML 入口。
 *
 * 对应 Dart 侧 JsNetwork（sendMessage({method: 'http' | 'webview_html'})）：
 *   - `_request` — 内部请求核心（sendRequest / fetchBytes / http / get / post 等共用）
 *   - sendRequest / fetchBytes — 返回完整响应 {status, headers, body}
 *   - get / post / put / patch / delete / http — 直接返回响应 body 字符串
 *   - fetch — 浏览器 fetch 风格（返回 {ok, status, headers, arrayBuffer/text/json}）
 *   - getHtml — 经系统 WebView 加载页面并返回渲染后的 HTML（适用于 JS 渲染 / 反爬页面）
 * @namespace Network
 */
let Network = {
    /**
     * 内部请求核心（Dart 侧 JsNetwork.request 处理）。
     *
     * @param {string} method - HTTP 方法（如 GET、POST），会转大写
     * @param {string} url - 请求地址
     * @param {Object} headers - 请求头
     * @param data - 请求体（可为 null）
     * @param {Object} extra - 扩展参数（透传给 Dart 侧，暂不处理）
     * @param {boolean} bytes - true 时响应 body 为原始字节（ArrayBuffer），否则为字符串
     * @returns {Promise<{status: number, headers: {}, body: string|ArrayBuffer}>}
     */
    async _request(method, url, headers, data, extra, bytes) {
        return await sendMessage({
            method: 'http',
            url: url,
            httpMethod: method,
            headers: headers || {},
            body: data || null,
            bytes: bytes === true,
            extra: extra,
        });
    },
    /**
     * 把 Dart 侧返回的 `{error: {message, kind, retryable, status, headers}}`
     * 转成带结构化属性的 JS Error：
     *   - e.kind      — timeout / connect / dns / ssl / http / cancel / webview / other
     *   - e.retryable — 是否值得重试（5xx/429/408/超时/断连 → true）
     *   - e.status    — HTTP 状态码（0 表示非 HTTP 错误）
     *   - e.headers   — 失败响应的响应头（manual 重定向时读 location 用）
     * @param {Object} err - Dart 侧 error 对象
     * @returns {Error}
     */
    _toError(err) {
        const e = new Error((err && err.message) || String(err));
        if (err && typeof err === 'object') {
            e.kind = err.kind || 'other';
            e.retryable = !!err.retryable;
            e.status = err.status || 0;
            if (err.headers) e.headers = err.headers;
        }
        return e;
    },
    /**
     * Sends an HTTP request and returns the full response.
     * @param {string} method - The HTTP method (e.g., GET, POST, PUT, PATCH, DELETE).
     * @param {string} url - The URL to send the request to.
     * @param {Object} headers - The headers to include in the request.
     * @param data - The data to send with the request.
     * @param {Object} extra - Extra options to pass to the interceptor.
     * @returns {Promise<{status: number, headers: {}, body: ArrayBuffer}>} The response from the request.
     */
    async fetchBytes(method, url, headers, data, extra) {
        let result = await Network._request(method, url, headers, data, extra, true);

        if (result.error) {
            throw Network._toError(result.error);
        }

        return result;
    },

    /**
     * Sends an HTTP request and returns the full response.
     * @param {string} method - The HTTP method (e.g., GET, POST, PUT, PATCH, DELETE).
     * @param {string} url - The URL to send the request to.
     * @param {Object} headers - The headers to include in the request.
     * @param data - The data to send with the request.
     * @param {Object} extra - Extra options:
     *     timeout {number}        超时毫秒数（connect/send/receive 均生效）
     *     retries {number}        失败重试次数 0-5（仅可重试错误时重试）
     *     redirect {'follow'|'manual'}  是否跟随重定向（manual 时从错误 e.headers.location 读）
     *     backend {'http'|'webview'|'auto'} 默认 http；webview 强制渲染；auto 疑似反爬自动降级
     *     webviewTimeout {number} webview/auto 的总超时秒数（默认 20）
     *     waitFor {Object|string} webview/auto 的等待条件（同 getHtml）
     *     session {string}        会话键（默认 ''），独立 Cookie 库 + 串行化 WebView
     * @returns {Promise<{status: number, headers: {}, body: string, finalUrl?: string, via?: string}>} The response from the request.
     */
    async sendRequest(method, url, headers, data, extra) {
        let result = await Network._request(method, url, headers, data, extra, false);

        if (result.error) {
            throw Network._toError(result.error);
        }

        return result;
    },

    /**
     * Sends an HTTP GET request and returns the response body string.
     * @param {string} url - The URL to send the request to.
     * @param {Object} headers - The headers to include in the request.
     * @param {Object} extra - Extra options to pass to the interceptor.
     * @returns {Promise<string>} The response body.
     */
    async get(url, headers, extra) {
        return (await this.sendRequest('GET', url, headers, null, extra)).body;
    },

    /**
     * Sends an HTTP POST request and returns the response body string.
     * @param {string} url - The URL to send the request to.
     * @param {Object} headers - The headers to include in the request.
     * @param data - The data to send with the request.
     * @param {Object} extra - Extra options to pass to the interceptor.
     * @returns {Promise<string>} The response body.
     */
    async post(url, headers, data, extra) {
        return (await this.sendRequest('POST', url, headers, data, extra)).body;
    },

    /**
     * Sends an HTTP PUT request and returns the response body string.
     * @param {string} url - The URL to send the request to.
     * @param {Object} headers - The headers to include in the request.
     * @param data - The data to send with the request.
     * @param {Object} extra - Extra options to pass to the interceptor.
     * @returns {Promise<string>} The response body.
     */
    async put(url, headers, data, extra) {
        return (await this.sendRequest('PUT', url, headers, data, extra)).body;
    },

    /**
     * Sends an HTTP PATCH request and returns the response body string.
     * @param {string} url - The URL to send the request to.
     * @param {Object} headers - The headers to include in the request.
     * @param data - The data to send with the request.
     * @param {Object} extra - Extra options to pass to the interceptor.
     * @returns {Promise<string>} The response body.
     */
    async patch(url, headers, data, extra) {
        return (await this.sendRequest('PATCH', url, headers, data, extra)).body;
    },

    /**
     * Sends an HTTP DELETE request and returns the response body string.
     * @param {string} url - The URL to send the request to.
     * @param {Object} headers - The headers to include in the request.
     * @param {Object} extra - Extra options to pass to the interceptor.
     * @returns {Promise<string>} The response body.
     */
    async delete(url, headers, extra) {
        return (await this.sendRequest('DELETE', url, headers, null, extra)).body;
    },

    /**
     * Sends an HTTP request with options style and returns the response body string.
     * @param {string} url - The URL to send the request to.
     * @param {Object} [options] - { method, headers, body }
     * @returns {Promise<string>} The response body.
     */
    async http(url, options) {
        let result = await this._request(
            (options && options.method) || 'GET',
            url,
            (options && options.headers) || {},
            (options && options.body) || null,
            null,
            false
        );
        if (result.error) {
            throw Network._toError(result.error);
        }
        return result.body;
    },

    /**
     * Sends an HTTP request with the browser fetch style.
     * @param {string} url - The URL to send the request to.
     * @param {Object} [options] - { method, headers, body }
     * @returns {Promise<{ok: boolean, status: number, statusText: string, headers: {}, arrayBuffer: (function(): Promise<ArrayBuffer>), text: (function(): Promise<string>), json: (function(): Promise<any>)}>}
     */
    async fetch(url, options) {
        let method = 'GET';
        let headers = {};
        let data = null;

        if (options) {
            method = options.method || method;
            headers = options.headers || headers;
            data = options.body || data;
        }

        let result = await this.fetchBytes(method, url, headers, data);

        return {
            ok: result.status >= 200 && result.status < 300,
            status: result.status,
            statusText: '',
            headers: result.headers,
            arrayBuffer: async () => result.body,
            text: async () => Convert.decodeUtf8(result.body),
            json: async () => JSON.parse(Convert.decodeUtf8(result.body)),
        }
    },

    /**
     * 经系统 WebView 加载 URL 并返回渲染后的完整 HTML。
     *
     * 适用于需要 JS 渲染、或直接 HTTP 请求拿不到完整内容的页面（如部分反爬站点）。
     * Dart 侧由 JsNetwork.webviewHtml 经 CaptchaWebviewController 实现。
     *
     * 兼容三种签名：
     *   Network.getHtml(url)                          → Promise<string>（默认 50s 超时）
     *   Network.getHtml(url, 30)                      → Promise<string>（旧签名：超时秒数）
     *   Network.getHtml(url, {timeout, waitFor})      → Promise<string>（新签名：options）
     *
     * options:
     *   - timeout {number}  总超时秒数（默认 50）
     *   - waitFor {Object|string}  等待条件，满足后才返回渲染后的 HTML：
     *       {type:'selector', value:'.comic-contain amp-img'}  等某个选择器出现
     *       {type:'text',    value:'寻找救援'}                 等 body 文本包含
     *       {type:'js',      value:'<JS 布尔表达式>'}          等 JS 表达式为真
     *       字符串简写：'selector:.x' / 'text:xxx' / 'js:<expr>'
     *       不传则等页面出现有意义内容（默认行为）
     *   - session {string}  会话键（默认 ''）。不同会话持独立 Cookie 库、串行化执行，
     *     可隔离不同源的登录态/验证 Cookie
     * @param {string} url - 要加载的页面地址
     * @param {number|Object} [options] - 超时秒数（旧）或 options 对象（新）
     * @returns {Promise<string>}
     */
    async getHtml(url, options) {
        if (typeof options === 'number') {
            options = { timeout: options };
        }
        const opts = options || {};
        const result = await sendMessage({
            method: 'webview_html',
            url: url,
            timeout: opts.timeout,
            waitFor: opts.waitFor,
            session: opts.session,
        });
        if (result.error) throw Network._toError(result.error);
        return result.html;
    },

    /**
     * 同 getHtml，但返回 {html, finalUrl}：finalUrl 是跟随跳转（302 / JS location）后的
     * 落地地址，可用于判断 page_direct 之类跳转最终到达的站点/域。
     * @param {string} url - 要加载的页面地址
     * @param {number|Object} [options] - 同 getHtml
     * @returns {Promise<{html: string, finalUrl: string}>}
     */
    async webview(url, options) {
        if (typeof options === 'number') {
            options = { timeout: options };
        }
        const opts = options || {};
        const result = await sendMessage({
            method: 'webview_html',
            url: url,
            timeout: opts.timeout,
            waitFor: opts.waitFor,
            session: opts.session,
        });
        if (result.error) throw Network._toError(result.error);
        return result;
    },

    /**
     * 查询指定会话已同步的 Cookie 字符串（"k1=v1; k2=v2"）。
     * 来源：HTTP 响应 Set-Cookie 自动摄入 + WebView 页面 parseHtml 后自动导入。
     * 请求侧（Network.get 等）已自动带 Cookie，一般无需手动使用；
     * 需要手动拼进 headers（如给图片 CDN 请求带 Cookie）时可调用。
     * @param {string} url - 目标地址（按域后缀 + 路径匹配）
     * @param {string} [session] - 会话键（默认 ''）
     * @returns {Promise<string>} Cookie 字符串，可能为空串
     */
    async cookies(url, session) {
        const result = await sendMessage({ method: 'get_cookies', url: url || '', session: session });
        return (result && result.cookies) || '';
    },

};

/**
 * 全局 [fetch] 兼容别名（与浏览器 fetch 同名）。功能已整合进 Network.fetch，此处仅转发。
 * @param url {string}
 * @param [options] {{method?: string, headers?: Object, body?: any}}
 * @returns {Promise<{ok: boolean, status: number, statusText: string, headers: {}, arrayBuffer: (function(): Promise<ArrayBuffer>), text: (function(): Promise<string>), json: (function(): Promise<any>)}>}
 */
async function fetch(url, options) {
    return Network.fetch(url, options);
}

/**
 * 全局 [http] 兼容别名。功能已整合进 Network.http，此处仅转发。
 * @param {string} url
 * @param {object} options - { method, headers, body }
 * @returns {Promise<string>} The response body string.
 */
async function http(url, options) {
    return Network.http(url, options);
}

/**
 * HtmlDocument class for parsing HTML and querying elements.
 *
 * 方法按 Dart 端 4 大类分层组织：
 *   - 解析层：constructor / dispose
 *   - 查询/导航层：querySelector / querySelectorAll / xpath / getElementById
 */
class HtmlDocument {
    static _key = 0;

    key = 0;

    // ============================================================
    // 解析层
    // ============================================================

    /**
     * Constructor for HtmlDocument.
     * @param {string} html - The HTML string to parse.
     */
    constructor(html) {
        this.key = HtmlDocument._key;
        HtmlDocument._key++;
        sendMessage({
            method: "html",
            function: "parse",
            key: this.key,
            data: html
        })
    }

    /**
     * Dispose the HTML document.
     * This should be called when the document is no longer needed.
     */
    dispose() {
        sendMessage({
            method: "html",
            function: "dispose",
            key: this.key
        })
    }

    // ============================================================
    // 查询/导航层
    // ============================================================

    /**
     * Query a single element from the HTML document.
     * @param {string} query - The query string (CSS selector or XPath starting with //).
     * @returns {HtmlElement | null} The first matching element.
     */
    xpathQuery(query) {
        if (!query || query.trim() === '') return null;
        let k;
        k = sendMessage({
            method: "html",
            function: "xpathQuery",
            key: this.key,
            query: query
        });
        if(k == null) return null;
        return new HtmlElement(k, this.key);
    }
    querySelector(query) {
        if (!query || query.trim() === '') return null;
        let k;
        k = sendMessage({
            method: "html",
            function: "querySelector",
            key: this.key,
            query: query
        });
        if(k == null) return null;
        return new HtmlElement(k, this.key);
    }

    /**
     * Query all matching elements from the HTML document.
     * @param {string} query - The query string (CSS selector or XPath starting with //).
     * @returns {HtmlElement[]} An array of matching elements.
     */
    xpathQueryAll(query) {
        if (!query || query.trim() === '') return [];
        let ks;
        ks = sendMessage({
            method: "html",
            function: "xpathQueryAll",
            key: this.key,
            query: query
        });
        return ks.map(k => new HtmlElement(k, this.key));
    }
    querySelectorAll(query) {
        if (!query || query.trim() === '') return [];
        let ks;
        ks = sendMessage({
            method: "html",
            function: "querySelectorAll",
            key: this.key,
            query: query
        });
        return ks.map(k => new HtmlElement(k, this.key));
    }

    /**
     * Query elements using XPath expression.
     * @param {string} xpath - The XPath expression.
     * @returns {HtmlElement[]} An array of matching elements.
     */
    xpath(xpath) {
        let ks = sendMessage({
            method: "html",
            function: "xpathQueryAll",
            key: this.key,
            query: xpath
        });
        return ks.map(k => new HtmlElement(k, this.key));
    }

    /**
     * Get the element by its id.
     * @param id {string}
     * @returns {HtmlElement|null}
     */
    getElementById(id) {
        let k = sendMessage({
            method: "html",
            function: "getElementById",
            key: this.key,
            id: id
        })
        if(k == null) return null;
        return new HtmlElement(k, this.key);
    }
}

/**
 * HtmlDom class for interacting with HTML elements.
 *
 * 方法按 Dart 端 4 大类分层组织：
 *   - 查询/导航层：querySelector / querySelectorAll / children / parent /
 *                  previousElementSibling / nextElementSibling / nodes
 *   - 数据提取层：text / attributes / getAttribute / classNames / id / localName
 *   - 序列化层：innerHTML
 */
class HtmlElement {
    key = 0;

    doc = 0;

    /**
     * Constructor for HtmlDom.
     * @param {number} k - The key of the element.
     * @param {number} doc - The key of the document.
     */
    constructor(k, doc) {
        this.key = k;
        this.doc = doc;
    }

    // ============================================================
    // 查询/导航层
    // ============================================================

    /**
     * Query a single element from the current element.
     * @param {string} query - The query string (CSS selector or XPath starting with //).
     * @returns {HtmlElement} The first matching element.
     */
    querySelector(query) {
        if (!query || query.trim() === '') return null;
        let k;
        k = sendMessage({
            method: "html",
            function: "dom_xpathQuery",
            key: this.key,
            query: query,
            doc: this.doc,
        });
        if(k == null) return null;
        return new HtmlElement(k, this.doc);
    }
    querySelector(query) {
        if (!query || query.trim() === '') return null;
        let k;
        k = sendMessage({
            method: "html",
            function: "dom_querySelector",
            key: this.key,
            query: query,
            doc: this.doc,
        });
        if(k == null) return null;
        return new HtmlElement(k, this.doc);
    }

    /**
     * Query all matching elements from the current element.
     * @param {string} query - The query string (CSS selector or XPath starting with // or .//).
     * @returns {HtmlElement[]} An array of matching elements.
     */
    querySelectorAll(query) {
        if (!query || query.trim() === '') return [];
        let ks;
        ks = sendMessage({
            method: "html",
            function: "dom_xpathQueryAll",
            key: this.key,
            query: query,
            doc: this.doc,
        });
        return ks.map(k => new HtmlElement(k, this.doc));
    }
    querySelectorAll(query) {
        if (!query || query.trim() === '') return [];
        let ks;
        ks = sendMessage({
            method: "html",
            function: "dom_querySelectorAll",
            key: this.key,
            query: query,
            doc: this.doc,
        });
        return ks.map(k => new HtmlElement(k, this.doc));
    }

    /**
     * Get the children of the current element.
     * @returns {HtmlElement[]} An array of child elements.
     */
    get children() {
        let ks = sendMessage({
            method: "html",
            function: "getChildren",
            key: this.key,
            doc: this.doc,
        })
        return ks.map(k => new HtmlElement(k, this.doc));
    }

   /**
    * Get all child nodes as structured data.
    *
    * 返回结构（按 DOM 顺序）：
    *   - `{type: "element", text: "...", elementKey: <int>}` — 可用 `elementKey` 包成 HtmlElement
    *   - `{type: "text", text: "..."}` — 文本节点
    *   - `{type: "comment", text: "..."}` — 注释节点
    *   - `{type: "document" | "unknown", text: ""}` — 其它节点
    *
    * 设计：Text/Comment/Document 不持久化在 Dart 端，
    * 因此这里返回的是一次性结构化数据，**不需要 HtmlNode 类**。
    *
    * @returns {Array<{type: string, text: string, elementKey?: number}>}
    */
   get childrenInfo() {
       return sendMessage({
           method: "html",
           function: "getChildrenInfo",
           key: this.key,
           doc: this.doc,
       })
   }

    /**
     * Get parent element of the element. If the element has no parent, return null.
     * @returns {HtmlElement|null}
     */
    get parent() {
        let k = sendMessage({
            method: "html",
            function: "getParent",
            key: this.key,
            doc: this.doc,
        })
        if(k == null) return null;
        return new HtmlElement(k, this.doc);
    }



    /**
     * Get the previous sibling element of the element. If the element has no previous sibling, return null.
     * @returns {HtmlElement|null}
     */
    get previousElementSibling() {
        let k = sendMessage({
            method: "html",
            function: "getPreviousSibling",
            key: this.key,
            doc: this.doc,
        })
        if(k == null) return null;
        return new HtmlElement(k, this.doc);
    }

    /**
     * Get the next sibling element of the element. If the element has no next sibling, return null.
     * @returns {HtmlElement|null}
     */
    get nextElementSibling() {
        let k = sendMessage({
            method: "html",
            function: "getNextSibling",
            key: this.key,
            doc: this.doc,
        })
        if (k == null) return null;
        return new HtmlElement(k, this.doc);
    }


    // ============================================================
    // 数据提取层
    // ============================================================

    /**
     * Get the text content of the element.
     * @returns {string} The text content.
     */
    get text() {
        return sendMessage({
            method: "html",
            function: "getText",
            key: this.key,
            doc: this.doc,
        })
    }

    /**
     * Get the attributes of the element.
     * @returns {Object} The attributes.
     */
    get attributes() {
        return sendMessage({
            method: "html",
            function: "getAttributes",
            key: this.key,
            doc: this.doc,
        })
    }

    /**
     * Get a specific attribute value.
     * @param {string} name - The attribute name.
     * @returns {string|null} The attribute value or null.
     */
    getAttribute(name) {
        let attrs = sendMessage({
            method: "html",
            function: "getAttributes",
            key: this.key,
            doc: this.doc,
        });
        return attrs ? attrs[name] : null;
    }

    /**
     * Get class names of the element.
     * @returns {string[]} An array of class names.
     */
    get classNames() {
        return sendMessage({
            method: "html",
            function: "getClassNames",
            key: this.key,
            doc: this.doc,
        })
    }

    /**
     * Get id of the element.
     * @returns {string | null} The id of the element.
     */
    get id() {
        return sendMessage({
            method: "html",
            function: "getId",
            key: this.key,
            doc: this.doc,
        })
    }

    /**
     * Get local name of the element.
     * @returns {string} The tag name of the element.
     */
    get localName() {
        return sendMessage({
            method: "html",
            function: "getLocalName",
            key: this.key,
            doc: this.doc,
        })
    }

    // ============================================================
    // 序列化层
    // ============================================================

    /**
     * Get inner HTML of the element.
     * @returns {string} The inner HTML.
     */
    get innerHTML() {
        return sendMessage({
            method: "html",
            function: "getInnerHTML",
            key: this.key,
            doc: this.doc,
        })
    }
}

function log(message, level) {
    sendMessage({
        method: 'log',
        message: String(message),
        level: level || 'info'
    });
}

let console = {
    log: (content) => {
        log(content, 'info');
    },
    warn: (content) => {
        log(content, 'warn');
    },
    error: (content) => {
        log(content, 'error');
    },
};

/**
 * Create a comic object
 * @param id {string}
 * @param title {string}
 * @param subtitle {string}
 * @param subTitle {string} - equal to subtitle
 * @param cover {string}
 * @param tags {string[]}
 * @param description {string}
 * @param maxPage {number?}
 * @param language {string?}
 * @param favoriteId {string?} - Only set this field if the comic is from favorites page
 * @param stars {number?} - 0-5, double
 * @constructor
 */
function Comic({id, title, subtitle, subTitle, cover, tags, description, maxPage, language, favoriteId, stars}) {
    this.id = id;
    this.title = title;
    this.subtitle = subtitle;
    this.subTitle = subTitle;
    this.cover = cover;
    this.tags = tags;
    this.description = description;
    this.maxPage = maxPage;
    this.language = language;
    this.favoriteId = favoriteId;
    this.stars = stars;
}

/**
 * Create a comic details object
 * @param title {string}
 * @param subtitle {string}
 * @param subTitle {string} - equal to subtitle
 * @param cover {string}
 * @param description {string?}
 * @param tags {Map<string, string[]> | {} | null | undefined}
 * @param chapters {Map<string, string> | {} | null | undefined} - key: chapter id, value: chapter title
 * @param isFavorite {boolean | null | undefined} - favorite status.
 * @param subId {string?} - a param which is passed to comments api
 * @param thumbnails {string[]?} - for multiple page thumbnails, set this to null, and use `loadThumbnails` api to load thumbnails
 * @param recommend {Comic[]?} - related comics
 * @param commentCount {number?}
 * @param likesCount {number?}
 * @param isLiked {boolean?}
 * @param uploader {string?}
 * @param updateTime {string?}
 * @param uploadTime {string?}
 * @param url {string?}
 * @param stars {number?} - 0-5, double
 * @param maxPage {number?}
 * @param comments {Comment[]?}- `since 1.0.7` App will display comments in the details page.
 * @constructor
 */
function ComicDetails({title, subtitle, subTitle, cover, description, tags, chapters, isFavorite, subId, thumbnails, recommend, commentCount, likesCount, isLiked, uploader, updateTime, uploadTime, url, stars, maxPage, comments}) {
    this.title = title;
    this.subtitle = subtitle ?? subTitle;
    this.cover = cover;
    this.description = description;
    this.tags = tags;
    this.chapters = chapters;
    this.isFavorite = isFavorite;
    this.subId = subId;
    this.thumbnails = thumbnails;
    this.recommend = recommend;
    this.commentCount = commentCount;
    this.likesCount = likesCount;
    this.isLiked = isLiked;
    this.uploader = uploader;
    this.updateTime = updateTime;
    this.uploadTime = uploadTime;
    this.url = url;
    this.stars = stars;
    this.maxPage = maxPage;
    this.comments = comments;
}

/**
 * Create a comment object
 * @param userName {string}
 * @param avatar {string?}
 * @param content {string}
 * @param time {string?}
 * @param replyCount {number?}
 * @param id {string?}
 * @param isLiked {boolean?}
 * @param score {number?}
 * @param voteStatus {number?} - 1: upvote, -1: downvote, 0: none
 * @constructor
 */
function Comment({userName, avatar, content, time, replyCount, id, isLiked, score, voteStatus}) {
    this.userName = userName;
    this.avatar = avatar;
    this.content = content;
    this.time = time;
    this.replyCount = replyCount;
    this.id = id;
    this.isLiked = isLiked;
    this.score = score;
    this.voteStatus = voteStatus;
}

/**
 * Create image loading config
 * @param url {string?}
 * @param method {string?} - http method, uppercase
 * @param data {any} - request data, may be null
 * @param headers {Object?} - request headers
 * @param onResponse {((ArrayBuffer) => ArrayBuffer)?} - modify response data
 * @param modifyImage {string?}
 *  A js script string.
 *  The script will be executed in a new Isolate.
 *  A function named `modifyImage` should be defined in the script, which receives an [Image] as the only argument, and returns an [Image]..
 * @param onLoadFailed {(() => ImageLoadingConfig)?} - called when the image loading failed
 * @constructor
 * @since 1.0.5
 *
 * To keep the compatibility with the old version, do not use the constructor. Consider creating a new object with the properties directly.
 */
function ImageLoadingConfig({url, method, data, headers, onResponse, modifyImage, onLoadFailed}) {
    this.url = url;
    this.method = method;
    this.data = data;
    this.headers = headers;
    this.onResponse = onResponse;
    this.modifyImage = modifyImage;
    this.onLoadFailed = onLoadFailed;
}

class PluginSource {
    name = ""

    key = ""

    version = ""

    /**
     * load data with its key
     * @param {string} dataKey
     * @returns {any}
     */
    loadData(dataKey) {
        return sendMessage({
            method: 'load_data',
            key: this.key,
            data_key: dataKey
        })
    }

    /**
     * load a setting with its key
     * @param key {string}
     * @returns {any}
     */
    loadSetting(key) {
        return sendMessage({
            method: 'load_setting',
            key: this.key,
            setting_key: key
        })
    }

    /**
     * save a setting with its key
     * @param {string} settingKey
     * @param value
     */
    saveSetting(settingKey, value) {
        return sendMessage({
            method: 'save_setting',
            key: this.key,
            setting_key: settingKey,
            data: value
        })
    }

    /**
     * get settings schema declared by the plugin
     * @returns {Object} settings
     */
    getSettings() {
        return this.settings || {}
    }

    /**
     * Get image loading config for an image.
     *
     * 插件可覆写此方法为阅读器下载的每张图提供自定义配置（与 venera 的
     * `comic.onImageLoad` 对应）。返回值：
     *   - url {string?} — 覆盖请求地址
     *   - method {string?} — 覆盖请求方法（大写）
     *   - data {any?} — 请求体
     *   - headers {Object?} — 自定义请求头（如鉴权 token / referer）
     *   - modifyImage {string?} — JS 脚本字符串，在独立 Isolate 中执行，
     *     脚本需定义 `function modifyImage(image) { ... return newImage; }`
     *     用于切片打乱还原
     *
     * @param {string} url 图片地址
     * @param {string} comicId 漫画 id
     * @param {string} epId 章节 id
     * @returns {Object} 图片加载配置
     */
    getImageLoadingConfig(url, comicId, epId) {
        return {}
    }

    /**
     * Get category browse data for this source (venera 的 `category` 对应)。
     *
     * 返回值结构：
     *   - title {string} — 分类页标题
     *   - parts {Array} — 分组列表，每项 `{name, categories: string[]}`
     *
     * @returns {Object|null} 不支持分类浏览时返回 null
     */
    getCategory() {
        return null
    }

    /**
     * Get filter options for a category (venera 的 `categoryComics.optionLoader` 对应)。
     *
     * 用于需要额外筛选的分类（如每週必看按期数/类型）。无选项时返回 null。
     *
     * @param {string} category 分类名
     * @returns {Array|null} `[{label, options: [{value, text}]}]`，无选项返回 null
     */
    getCategoryOptions(category) {
        return null
    }

    /**
     * Load comics of a category (venera 的 `categoryComics.load` 对应)。
     *
     * @param {string} category 分类名
     * @param {number} [page] 页码（1-based）
     * @returns {Array} List<UI.Card>
     */
    loadCategory(category, page = 1) {
        return []
    }

    /**
     * save data
     * @param {string} dataKey
     * @param data
     */
    saveData(dataKey, data) {
        return sendMessage({
            method: 'save_data',
            key: this.key,
            data_key: dataKey,
            data: data
        })
    }

    /**
     * delete data
     * @param {string} dataKey
     */
    deleteData(dataKey) {
        return sendMessage({
            method: 'delete_data',
            key: this.key,
            data_key: dataKey,
        })
    }

    /**
     *
     * @returns {boolean}
     */
    get isLogged() {
        return sendMessage({
            method: 'isLogged',
            key: this.key,
        });
    }

    translation = {}

    /**
     * Translate given string with the current locale using the translation object.
     * @param key {string}
     * @returns {string}
     * @since 1.2.5
     */
    translate(key) {
        let locale = APP.locale;
        return this.translation[locale]?.[key] ?? key;
    }

    init() { }

    static sources = {}
}

/// A reference to dart object.
/// The api can only be used in the comic.onImageLoad.modifyImage function
class Image {
    key = 0;

    constructor(key) {
        this.key = key;
    }

    /**
     * Copy the specified range of the image
     * @param x
     * @param y
     * @param width
     * @param height
     * @returns {Image|null}
     */
    copyRange(x, y, width, height) {
        let key = sendMessage({
            method: "image",
            function: "copyRange",
            key: this.key,
            x: x,
            y: y,
            width: width,
            height: height
        })
        if(key == null) return null;
        return new Image(key);
    }

    /**
     * Copy the image and rotate 90 degrees
     * @returns {Image|null}
     */
    copyAndRotate90() {
        let key = sendMessage({
            method: "image",
            function: "copyAndRotate90",
            key: this.key
        })
        if(key == null) return null;
        return new Image(key);
    }

    /**
     * fill [image] to this image at (x, y)
     * @param x
     * @param y
     * @param image
     */
    fillImageAt(x, y, image) {
        sendMessage({
            method: "image",
            function: "fillImageAt",
            key: this.key,
            x: x,
            y: y,
            image: image.key
        })
    }

    /**
     * fill [image] with range(srcX, srcY, width, height) to this image at (x, y)
     * @param x
     * @param y
     * @param image
     * @param srcX
     * @param srcY
     * @param width
     * @param height
     */
    fillImageRangeAt(x, y, image, srcX, srcY, width, height) {
        sendMessage({
            method: "image",
            function: "fillImageRangeAt",
            key: this.key,
            x: x,
            y: y,
            image: image.key,
            srcX: srcX,
            srcY: srcY,
            width: width,
            height: height
        })
    }

    get width() {
        return sendMessage({
            method: "image",
            function: "getWidth",
            key: this.key
        })
    }

    get height() {
        return sendMessage({
            method: "image",
            function: "getHeight",
            key: this.key
        })
    }

    static empty(width, height) {
        let key = sendMessage({
            method: "image",
            function: "emptyImage",
            width: width,
            height: height
        })
        return new Image(key);
    }
}

/**
 * Dialog related apis
 * @since 1.0.0
 */
let Dialog = {
    /**
     * Show a message
     * @param message {string}
     */
    showToast: (message) => {
        sendMessage({
            method: 'dialog',
            function: 'showToast',
            message: message,
        })
    },

    /**
     * Confirm and open a URL in the external browser.
     * The app shows a confirmation dialog before launching the default browser.
     * @param {string} url - The URL to open
     * @since 1.5.x
     */
    openExternalBrowser: (url) => {
        sendMessage({
            method: 'openExternalBrowser',
            url: url,
        })
    },

    /**
     * Show a dialog. Any action will close the dialog.
     * @param title {string}
     * @param content {string}
     * @param actions {{text:string, callback: () => void | Promise<void>, style: "text"|"filled"|"danger"}[]} - If callback returns a promise, the button will show a loading indicator until the promise is resolved.
     * @returns {Promise<void>} - Resolved when the dialog is closed.
     * @since 1.2.1
     */
    showDialog: (title, content, actions) => {
        sendMessage({
            method: 'dialog',
            function: 'showDialog',
            title: title,
            content: content,
            actions: actions,
        })
    },

    /**
     * Show a loading dialog.
     * @param onCancel {() => void | null | undefined} - Called when the loading dialog is canceled. If [onCancel] is null, the dialog cannot be canceled by the user.
     * @returns {number} - A number that can be used to cancel the loading dialog.
     * @since 1.2.1
     */
    showLoading: (onCancel) => {
        return sendMessage({
            method: 'dialog',
            function: 'showLoading',
            onCancel: onCancel
        })
    },

    /**
     * Cancel a loading dialog.
     * @param id {number} - returned by [showLoading]
     * @since 1.2.1
     */
    cancelLoading: (id) => {
        sendMessage({
            method: 'dialog',
            function: 'cancelLoading',
            id: id
        })
    },

    /**
     * Show an input dialog
     * @param title {string}
     * @param validator {(string) => string | null | undefined} - A function that validates the input. If the function returns a string, the dialog will show the error message.
     * @param image {string | ArrayBuffer | null | undefined} - Since 1.4.6, you can pass an image url to show an image in the dialog. Since 1.5.3, you can also pass an ArrayBuffer to show a custom image.
     * @returns {Promise<string | null>} - The input value. If the dialog is canceled, return null.
     */
    showInputDialog: (title, validator, image) => {
        return sendMessage({
            method: 'dialog',
            function: 'showInputDialog',
            title: title,
            image: image,
            validator: validator
        })
    },

    /**
     * Show a select dialog
     * @param title {string}
     * @param options {string[]}
     * @param initialIndex {number?}
     * @returns {Promise<number | null>} - The selected index. If the dialog is canceled, return null.
     */
    showSelectDialog: (title, options, initialIndex) => {
        return sendMessage({
            method: 'dialog',
            function: 'showSelectDialog',
            title: title,
            options: options,
            initialIndex: initialIndex
        })
    }
}

/**
 * App related apis
 * @since 1.2.1
 */
let APP = {
    /**
     * Get the app version
     * @returns {string} - The app version
     */
    get version() {
        // 引擎可能未注入 appVersion（历史遗漏）：typeof 对未声明变量安全，取不到返回空串
        return typeof appVersion !== 'undefined' ? appVersion : ''
    },

    /**
     * Get current app locale
     * @returns {string} - The app locale, in the format of [languageCode]_[countryCode]
     */
    get locale() {
        return sendMessage({
            method: 'getLocale'
        })
    },

    /**
     * Get current running platform
     * @returns {string} - The platform name, "android", "ios", "windows", "macos", "linux"
     */
    get platform() {
        return sendMessage({
            method: 'getPlatform'
        })
    }
}

/**
 * Navigator related apis for page navigation
 * @since 1.5.x
 */
let Navigator = {
    /**
     * Navigate to video player page（结构化进入）
     * @param {Object} options
     *   { videoId, title, cover?, sourceKey?, initialSource?, initialEpisode?, sources: [
     *       { name: '线路名', episodes: [
     *           { name: '集名', url: '播放页网址/直链/本地路径', type: 'direct'|'page'|'local' }
     *           // 或惰性：{ name, type:'resolve', plugin:'插件key', method:'方法名', args:[...] }
     *       ] }
     *   ] }
     */
    navigateToVideo: (options) => {
        sendMessage({
            method: 'navigateToVideo',
            videoId: options.videoId,
            title: options.title,
            cover: options.cover || '',
            sourceKey: options.sourceKey || '',
            initialSource: options.initialSource || 0,
            initialEpisode: options.initialEpisode || 0,
            sources: options.sources || [],
        })
    },

    /**
     * Navigate to webview page
     * @param {string} url - The URL to load in webview
     */
    navigateToWebview: (url) => {
        sendMessage({
            method: 'navigateToWebview',
            url: url
        })
    },

    /**
     * Navigate to manga reader page
     * @param {Object} options - 跳转参数
     * @param {string} options.comicId - 漫画唯一 id
     * @param {string} options.comicTitle - 漫画名
     * @param {Array} options.chapters - 章节列表，每项两种形态：
     *   - 预加载：{id, title, images:[url,...]}
     *   - 惰性加载：{id, title, plugin:'插件名', method:'方法名', args:[...]}（切章时调用插件方法取图片）
     * @param {string} [options.sourceKey] - 漫画源标识（用于图片缓存隔离）
     * @param {number} [options.initialChapter] - 起始章节（1-based）
     * @param {number} [options.initialPage] - 起始页（1-based）
     */
    navigateToReader: (options) => {
        sendMessage({
            method: 'navigateToReader',
            comicId: options.comicId,
            comicTitle: options.comicTitle,
            chapters: options.chapters,
            sourceKey: options.sourceKey,
            initialChapter: options.initialChapter ?? 1,
            initialPage: options.initialPage ?? 1
        })
    },

    /**
     * 跳转到小说阅读器页面
     * @param {Object} options - 跳转参数
     * @param {string} options.novelId - 小说唯一 id
     * @param {string} options.novelTitle - 小说名
     * @param {Array} options.chapters - 章节列表，每项两种形态：
     *   - 预加载：{id, title, content:'正文文本'}
     *   - 惰性加载：{id, title, plugin:'插件名', method:'方法名', args:[...]}（切章时调用插件方法取正文）
     * @param {string} [options.sourceKey] - 小说源标识
     * @param {number} [options.initialChapter] - 起始章节（1-based）
     */
    navigateToNovelReader: (options) => {
        sendMessage({
            method: 'navigateToNovelReader',
            novelId: options.novelId,
            novelTitle: options.novelTitle,
            chapters: options.chapters,
            sourceKey: options.sourceKey,
            initialChapter: options.initialChapter ?? 1,
        })
    },

    /**
     * 跳转到 descriptor 详情页（替代旧 UI.Navigate）。
     *
     * @param {string} plugin   - 目标插件名（对应 JS 类名）
     * @param {Object} options
     * @param {string} options.method   - 详情页要调用的方法（如 'getDetail'）
     * @param {Array}  [options.args]   - 方法参数
     * @param {string} [options.title]  - 详情页标题
     * @param {Array}  [options.actions] - AppBar 右侧 IconButton 列表
     */
    navigateToDescriptor: (plugin, { method, args, title, actions } = {}) => {
        sendMessage({
            method: 'navigateToDescriptor',
            plugin: plugin,
            initMethod: String(method ?? ''),
            args: Array.isArray(args) ? args : [],
            title: title ?? null,
            actions: Array.isArray(actions) ? actions : [],
        })
    },
}

/**
 * Set clipboard text
 * @param text {string}
 * @returns {Promise<void>}
 *
 * @since 1.3.4
 */
function setClipboard(text) {
    return sendMessage({
        method: 'setClipboard',
        text: text
    })
}

/**
 * Get clipboard text
 * @returns {Promise<string>}
 *
 * @since 1.3.4
 */
function getClipboard() {
    return sendMessage({
        method: 'getClipboard'
    })
}

/**
 * Compute a function with arguments. The function will be executed in the engine pool which is not in the main thread.
 * @param func {string} - A js code string which can be evaluated to a function. The function will receive the args as its only argument.
 * @param args {any[]} - The arguments to pass to the function.
 * @returns {Promise<any>} - The result of the function.
 * @since 1.5.0
 */
function compute(func, ...args) {
    return sendMessage({
        method: 'compute',
        function: func,
        args: args
    })
}

// ============================================================================
// UI 命名空间：描述符构造原语（search 卡片渲染用）
// ----------------------------------------------------------------------------
// 用法：
//   return [
//     UI.Card({ child: UI.Column({ children: [
//       UI.Image({ src: cover, type: 'cover' }),
//       UI.Text({ content: title, style: { fontSize: 16, weight: 'bold' } }),
//       UI.Row({ children: [ UI.Text({ content: author }), UI.Spacer() ] }),
//       UI.Button({ label: '查看', onTap: UI.Action({ method: 'open', args: [id] }) }),
//     ]})})
//   ];
//
// 约定：
//   - 描述符 = 普通 JS 对象，Dart 端按 __type 字段渲染
//   - __type 一律小写：card / column / row / stack / image / text / icon /
//     button / tag / spacer / divider / action
//   - 容器类：child (单节点) / children (多节点)
//   - UI.Action 仅作为 Button.onTap 值携带跨语言回调，不进渲染树
//   - 所有原语不抛异常；非法入参降级为默认（必要时 console.warn）
// ============================================================================
let UI = {

    // ---------- 容器 ----------

    /**
     * Card 容器
     * @param props {{ child?: object, padding?: number, elevation?: number, color?: string, shapeRadius?: number }}
     */
    Card({ child, padding, elevation, color, shapeRadius } = {}) {
        return __ui_wrap_('card', {
            child: child ?? null,
            padding: padding ?? 12,
            elevation: elevation ?? 2,
            color: color ?? null,
            shapeRadius: shapeRadius ?? 12,
        });
    },

    /**
     * Column 纵向布局
     */
    Column({ children, mainAxisAlignment, crossAxisAlignment, mainAxisSize } = {}) {
        return __ui_wrap_('column', {
            children: __ui_children_(children),
            mainAxisAlignment: mainAxisAlignment ?? 'start',
            crossAxisAlignment: crossAxisAlignment ?? 'center',
            mainAxisSize: mainAxisSize ?? 'max',
        });
    },

    /**
     * Row 横向布局
     */
    Row({ children, mainAxisAlignment, crossAxisAlignment, mainAxisSize } = {}) {
        return __ui_wrap_('row', {
            children: __ui_children_(children),
            mainAxisAlignment: mainAxisAlignment ?? 'start',
            crossAxisAlignment: crossAxisAlignment ?? 'center',
            mainAxisSize: mainAxisSize ?? 'max',
        });
    },

    /**
     * Stack 重叠布局
     */
    Stack({ children, alignment } = {}) {
        return __ui_wrap_('stack', {
            children: __ui_children_(children),
            alignment: alignment ?? 'topStart',
        });
    },

    // ---------- 叶子 ----------

    /**
     * Image 网络图片（src 为空时 Dart 端走占位图）
     */
    Image({ src, width, height, fit, type } = {}) {
        return __ui_wrap_('image', {
            src: (src == null || src === '') ? null : String(src),
            width: Number(width) || 0,
            height: Number(height) || 0,
            fit: fit ?? 'cover',
            type: type ?? null,
        });
    },

    /**
     * Text 文本
     * 支持简写：UI.Text('hello') 等价 UI.Text({ content: 'hello' })
     */
    Text(content, { style, maxLines, overflow } = {}) {
        let p;
        if (typeof content === 'string') {
            p = { content };
        } else if (content && typeof content === 'object') {
            p = content;
        } else {
            p = { content: '' };
        }
        return __ui_wrap_('text', {
            content: String(p.content ?? ''),
            style: style ?? p.style ?? null,
            maxLines: maxLines ?? p.maxLines ?? null,
            overflow: overflow ?? p.overflow ?? 'ellipsis',
        });
    },

    /**
     * Icon Material Icons
     * name 接受 'search' 等字符串，或 { name, size, color } 对象
     */
    Icon(name, { size, color } = {}) {
        let n, s, c;
        if (typeof name === 'string') {
            n = name; s = size; c = color;
        } else if (name && typeof name === 'object') {
            n = name.name; s = name.size; c = name.color;
        } else {
            n = 'help_outline';
        }
        return __ui_wrap_('icon', {
            name: String(n ?? 'help_outline'),
            size: Number(s) || 24,
            color: c ?? null,
        });
    },

    /**
     * Button 按钮
     * onTap 必须是 UI.Action 描述符；否则降级为不可点击
     */
    Button({ label, onTap, style } = {}) {
        const onTapValid = onTap && typeof onTap === 'object' && (onTap.__type === 'action' ||onTap.__type === 'navigate');
        if (onTap != null && !onTapValid) {
            console.warn('[UI] Button.onTap must be a UI.Action descriptor; click disabled.');
        }
        return __ui_wrap_('button', {
            label: String(label ?? ''),
            onTap: onTapValid ? onTap : null,
            style: style ?? 'filled',
        });
    },

    /**
     * Pagination 分页容器（分页控制 + 单页数据来源声明）。
     *
     * @param page {number} 当前页码（1-based）
     * @param maxPage {number} 总页数
     * @param pageMethod {string} 获取某页内容的方法名（返回**单纯的结果列表**）
     * @param pageArgs {Array} 该方法参数模板，页码位于 args[1]（换页时更新）
     *
     * Dart 端首次渲染/换页时按 pageArgs 更新页码后调用 pageMethod，
     * 用返回的纯结果列表作为本页内容。
     */
    Pagination({ page, maxPage, pageMethod, pageArgs } = {}) {
        return __ui_wrap_('pagination', {
            page: Number(page) || 1,
            maxPage: Number(maxPage) || 1,
            pageMethod: pageMethod ?? null,
            pageArgs: Array.isArray(pageArgs) ? pageArgs : [],
        });
    },

    /**
     * IconButton 可点击图标按钮
     *
     * @param icon      字符串（Material Icon 名如 'delete_outline'）或 UI.Icon 描述符
     * @param onTap     UI.Action / UI.Navigate 描述符（必填，缺失则 disabled）
     * @param tooltip   悬浮提示（可选）
     * @param color     图标颜色（可选，会覆盖 icon 自身的 color）
     * @param size      图标尺寸（可选，默认 24）
     *
     * 示例：
     *   UI.IconButton({
     *       icon: 'delete_outline',
     *       tooltip: '删除',
     *       color: '#FF0000',
     *       onTap: UI.Action({ method: 'delete', args: [id] }),
     *   })
     */
    IconButton({ icon, onTap, tooltip, color, size } = {}) {
        const onTapValid = onTap && typeof onTap === 'object' && (onTap.__type === 'action' ||onTap.__type === 'navigate');
        if (onTap != null && !onTapValid) {
            console.warn('[UI] IconButton.onTap must be UI.Action or UI.Navigate; click disabled.');
        }
        return __ui_wrap_('iconButton', {
            icon: typeof icon === 'string' ? icon : (icon ?? null),
            onTap: onTapValid ? onTap : null,
            tooltip: tooltip ?? null,
            color: color ?? null,
            size: size ?? null,
        });
    },

    /**
     * Tag 标签/徽章
     */
    Tag({ text, color, textColor } = {}) {
        return __ui_wrap_('tag', {
            text: String(text ?? ''),
            color: color ?? null,
            textColor: textColor ?? null,
        });
    },

    /**
     * Spacer 弹性空间
     */
    Spacer({ flex } = {}) {
        return __ui_wrap_('spacer', {
            flex: Number(flex) || 1,
        });
    },

    // ---------- 布局工具（新增 10 个） ----------

    /**
     * Container 多功能容器
     * padding/margin: number | [all] | [top,right,bottom,left]
     * width/height: number | 'fill' (double.infinity)
     * decoration: { color, borderRadius, border: {color, width} }
     */
    Container({ child, padding, margin, color, width, height, alignment, decoration } = {}) {
        return __ui_wrap_('container', {
            child: child ?? null,
            padding: padding ?? null,
            margin: margin ?? null,
            color: color ?? null,
            width: width ?? null,
            height: height ?? null,
            alignment: alignment ?? null,
            decoration: decoration ?? null,
        });
    },

    /**
     * Padding 纯内边距
     * padding: number | [all] | [top,right,bottom,left]
     */
    Padding({ padding = 8, child } = {}) {
        return __ui_wrap_('padding', { padding, child });
    },

    /**
     * SizedBox 固定尺寸/间距
     * width/height: 0 = 该方向不约束
     */
    SizedBox({ width = 0, height = 0 } = {}) {
        return __ui_wrap_('sizedBox', { width, height });
    },

    /**
     * Center 居中
     * widthFactor: 0 = 自适应子节点宽度
     */
    Center({ child, widthFactor = 1.0 } = {}) {
        return __ui_wrap_('center', { child, widthFactor });
    },

    /**
     * Align 对齐
     * alignment: 'topLeft'/'topCenter'/'topRight'/'centerLeft'/'center'/'centerRight'/...
     */
    Align({ alignment = 'center', child } = {}) {
        return __ui_wrap_('align', { alignment, child });
    },

    /**
     * Expanded Flex 中撑开
     */
    Expanded({ flex = 1, child } = {}) {
        return __ui_wrap_('expanded', { flex, child });
    },

    /**
     * Wrap 流式布局
     * direction: 'horizontal'|'vertical'
     */
    Wrap({ children, direction = 'horizontal', spacing = 0, runSpacing = 0, alignment = 'start' } = {}) {
        return __ui_wrap_('wrap', {
            children: __ui_children_(children),
            direction, spacing, runSpacing, alignment,
        });
    },

    /**
     * AspectRatio 比例容器
     */
    AspectRatio({ aspectRatio = 1.0, child } = {}) {
        return __ui_wrap_('aspectRatio', { aspectRatio, child });
    },

    /**
     * ListView 滚动列表
     */
    ListView({ children, direction = 'vertical', padding } = {}) {
        return __ui_wrap_('listView', {
            children: __ui_children_(children),
            direction, padding: padding ?? null,
        });
    },

    /**
     * SingleChildScrollView 单子滚动（详情页 body 用）
     */
    SingleChildScrollView({ child, direction = 'vertical', padding } = {}) {
        return __ui_wrap_('singleChildScrollView', {
            child, direction, padding: padding ?? null,
        });
    },

    /**
     * ExpansionTile 折叠面板：点击 title 展开/收起 children
     *
     * @param title {object}       必填：标题（描述符，如 UI.Text）
     * @param subtitle {object=}   副标题（描述符）
     * @param children {Array=}    展开后的内容（描述符列表）
     * @param initiallyExpanded {boolean=}  是否初始展开
     * @param shapeRadius {number=}        边框圆角（不传 = 无圆角矩形边框）
     */
    ExpansionTile({ title, subtitle, children, initiallyExpanded, shapeRadius } = {}) {
        if (!title || typeof title !== 'object' || !title.__type) {
            console.warn('[UI] ExpansionTile.title is required and must be a descriptor');
        }
        return __ui_wrap_('expansionTile', {
            title: title ?? null,
            subtitle: subtitle ?? null,
            children: __ui_children_(children),
            initiallyExpanded: initiallyExpanded === true,
            shapeRadius: shapeRadius ?? null,
        });
    },

    /**
     * Divider 分隔线
     */
    Divider({ thickness, color, indent, endIndent } = {}) {
        return __ui_wrap_('divider', {
            thickness: Number(thickness) || 1,
            color: color ?? null,
            indent: Number(indent) || 0,
            endIndent: Number(endIndent) || 0,
        });
    },

    // ---------- 动作（不进渲染树） ----------

    /**
     * Action 点击动作描述符
     * plugin='__self__' 表示调用当前 search 所属插件
     */
    Action({ plugin, method, args, payload, icon } = {}) {
        return {
            __type: 'action',
            plugin: plugin ?? '__self__',
            method: String(method ?? ''),
            args: Array.isArray(args) ? args : [],
            payload: payload ?? null,
            icon: icon ?? null,
        };
    },

    /**
     * Navigate 导航描述符
     * 触发 Dart 路由跳转 + 自动 invokeWidgets(method, args) 拿内容
     *
     * page: 目标页标识（当前只支持 'descriptor'）
     * method: 跳转后调用的 plugin 方法
     * args: 方法参数
     * title: AppBar 标题
     * actions: AppBar 右侧 IconButton 列表（每项是 UiAction 描述符）
     */
    Navigate({ page = 'descriptor', method, args, title, actions } = {}) {
        return __ui_wrap_('navigate', {
            page,
            method: String(method ?? ''),
            args: Array.isArray(args) ? args : [],
            title: title ?? null,
            actions: Array.isArray(actions) ? actions : [],
        });
    },

    // ---------- 校验（开发期） ----------

    /**
     * 校验描述符树，错误时 throw Error
     * EntityInvokeException 捕获后回传 Dart，便于定位
     */
    validate(node, path = '$') {
        const errors = __ui_validate_(node, path, 0);
        if (errors.length) {
            throw new Error('UI.validate failed:\n  ' + errors.join('\n  '));
        }
        return true;
    },
};

// ---------- 内部工具（IIFE 隔离） ----------
(function () {
    const KNOWN_TYPES = new Set([
        'card', 'column', 'row', 'stack',
        'image', 'text', 'icon', 'button', 'iconButton', 'tag', 'spacer', 'divider',
        'container', 'padding', 'sizedBox', 'center', 'align', 'expanded', 'wrap', 'aspectRatio',
        'listView', 'singleChildScrollView',
        'expansionTile',
        'pagination',
        'action', 'navigate',
    ]);
    const ALIAS = { 'vbox': 'column', 'hbox': 'row', 'view': 'column' };

    function __ui_wrap_(type, fields) {
        const t = ALIAS[type] || type;
        if (!KNOWN_TYPES.has(t)) {
            console.warn('[UI] unknown __type:', type, '-> fallback to text');
            return { __type: 'text', content: '[unknown:' + type + ']' };
        }
        return Object.assign({ __type: t }, fields);
    }

    function __ui_children_(children) {
        if (children == null) return [];
        if (Array.isArray(children)) return children.filter(c => c != null);
        return [children];
    }

    function __ui_validate_(node, path, depth, errors) {
        const errs = errors || [];
        if (depth > 32) {
            errs.push(path + ': depth > 32 (truncated)');
            return errs;
        }
        if (!node || typeof node !== 'object' || Array.isArray(node)) {
            errs.push(path + ': not an object');
            return errs;
        }
        if (!node.__type) {
            errs.push(path + ': missing __type');
            return errs;
        }
        if (!KNOWN_TYPES.has(node.__type)) {
            errs.push(path + ': unknown __type "' + node.__type + '"');
        }
        if (node.__type === 'column' || node.__type === 'row' || node.__type === 'stack') {
            const kids = Array.isArray(node.children) ? node.children : [];
            if (kids.length > 200) {
                errs.push(path + '.children: length ' + kids.length + ' > 200 (will be truncated)');
            }
            for (let i = 0; i < Math.min(kids.length, 200); i++) {
                __ui_validate_(kids[i], path + '.children[' + i + ']', depth + 1, errs);
            }
        }
        if (node.__type === 'card' && node.child != null) {
            __ui_validate_(node.child, path + '.child', depth + 1, errs);
        }
        if (node.__type === 'button' && node.onTap != null) {
            if (!node.onTap.__type || node.onTap.__type !== 'action') {
                errs.push(path + '.onTap: must be UI.Action descriptor');
            }
        }
        if (node.__type === 'iconButton') {
            // icon 必须是字符串或描述符
            if (node.icon != null && typeof node.icon !== 'string'
                && (typeof node.icon !== 'object' || !node.icon.__type)) {
                errs.push(path + '.icon: must be string or descriptor');
            }
            // onTap 可选（缺失则 disabled）
            if (node.onTap != null && (typeof node.onTap !== 'object'
                || (node.onTap.__type !== 'action' && node.onTap.__type !== 'navigate'))) {
                errs.push(path + '.onTap: must be UI.Action or UI.Navigate');
            }
        }
        if (node.__type === 'expansionTile') {
            // title 必填
            if (!node.title || typeof node.title !== 'object' || !node.title.__type) {
                errs.push(path + '.title: required descriptor');
            } else {
                __ui_validate_(node.title, path + '.title', depth + 1, errs);
            }
            // subtitle 可选
            if (node.subtitle != null) {
                if (typeof node.subtitle !== 'object' || !node.subtitle.__type) {
                    errs.push(path + '.subtitle: must be a descriptor');
                } else {
                    __ui_validate_(node.subtitle, path + '.subtitle', depth + 1, errs);
                }
            }
            // children 复用 column/row 校验逻辑
            if (node.children != null) {
                const kids = Array.isArray(node.children) ? node.children : [];
                for (let i = 0; i < Math.min(kids.length, 200); i++) {
                    __ui_validate_(kids[i], path + '.children[' + i + ']', depth + 1, errs);
                }
            }
        }
        return errs;
    }

    globalThis.__ui_wrap_ = __ui_wrap_;
    globalThis.__ui_children_ = __ui_children_;
    globalThis.__ui_validate_ = __ui_validate_;

    // =================================================================
    // PluginBrowse — 插件浏览历史桥
    // -----------------------------------------------------------------
    // 插件在用户进入详情页时调 `open` 记录一条浏览历史。
    // 其他操作（list/remove/clearAll）由 Dart 端直接调 PluginHistoryRepository。
    // pluginName 由插件通过 `this.name` 显式传入，不用全局 mutable 状态。
    // =================================================================
    class PluginBrowse {
        async open(pluginName, { id, title, cover = '', kv = {} }) {
            if (!pluginName) throw new Error('PluginBrowse.open: pluginName required');
            if (!id) throw new Error('PluginBrowse.open: id required');
            const r = await sendMessage({
                method: 'plugin_history', function: 'upsert',
                pluginName, id, title, cover, kv,
            });
            if (!r || !r.ok) throw new Error(r && r.error || 'unknown error');
        }

        async find(pluginName, id) {
            if (!pluginName) throw new Error('PluginBrowse.find: pluginName required');
            if (!id) throw new Error('PluginBrowse.find: id required');
            const r = await sendMessage({
                method: 'plugin_history', function: 'find',
                pluginName, id,
            });
            if (!r || !r.ok) throw new Error(r && r.error || 'unknown error');
            return r.data || null;
        }
    }

    globalThis.PluginBrowse = new PluginBrowse();
})();

