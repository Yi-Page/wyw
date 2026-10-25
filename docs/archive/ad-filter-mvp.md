# wyw 广告过滤 MVP 实现分析（修正版）

> **状态：已归档（2026-10）。** 文中描述的 Dart 侧实现（`ad_insertion_finder` /
> `ts_pts_reader` / `m3u8_ad_filter` / `ad_decision_service` / `ad_manifest_store`）
> 已从代码库移除，只在播放引擎侧保留 `hls_ad_filter` 相关注释与开关；本文作为当时的
> 分析与结论存档，不再代表当前实现。

> 本文替换此前关于 `hls_ad_filter` 的口头结论。此前的结论（"mpv 只能发现、不能跳过广告"）**是错误的**，
> 错因见第 3 节。本文全部结论基于本机可查的两类证据：
> 1. **FFmpeg 补丁源码**（本机存在，见 1.1）；
> 2. **真机观察**（直接播放整集时看不到广告）+ 实测 PTS 数字。
>
> 文中标注 **[源码]** = 补丁源码直接可读；**[实测]** = 本机对真实分片字节量出来的数字；
> **[真机]** = 你在应用里观察到的现象；**[推断]** = 由源码逻辑演绎、未直接测量。

---

## 0. 三条结论

1. **mpv 侧的广告过滤是真实有效的**：它在 FFmpeg 的 HLS demuxer 里**丢弃广告分片的 packet**，
   并小幅修正时间戳偏移。判定规则是"**视频 PTS 相对上一个正片 PTS 后退超过 1 秒**"。
2. **它的唯一开关是"播放列表里有没有 `#EXT-X-DISCONTINUITY`"**。所以任何"重写播放列表"的动作
   一旦丢掉这个标签，就等于把这道能力关掉——wyw 的播放代理此前正是这么做的（已修，见 4.1）。
3. **它不改容器的总时长**。广告 packet 被丢弃，但 HLS 的 duration 仍按 playlist 的 `EXTINF` 累加，
   所以"广告没了、进度条总时长没变"是**这套实现的正常表现**，不是 bug。要让总时长正确，
   必须真的把广告分片从列表里删掉（Dart 侧干的事）。

---

## 1. mpv 侧：`hls_ad_filter` 的真实实现

### 1.1 来源与开关

| 项 | 内容 |
|---|---|
| 补丁文件 | `D:\development\AndroidStudioProjects\Kazumi\fastlane\.libmpv-android-video-build\buildscripts\patches\ffmpeg\ffmpeg-hls-kazumi-combined.patch`（同内容另有一份在 `patches-encoders-gpl/ffmpeg/`）**[源码]** |
| 作用对象 | FFmpeg `libavformat/hls.c`（HLS demuxer） |
| 选项注册 | `{"hls_ad_filter", "Filter ad segments based on PTS discontinuity (Kazumi)", ..., AV_OPT_TYPE_BOOL, {.i64 = 0}, 0, 1}`（补丁 :297-298）**[源码]** |
| 应用侧注入 | media_kit fork 在 `demuxer-lavf-o` 里传 `hls_ad_filter=1`；由 wyw 的「广告过滤」开关决定 0/1 **[源码]** |
| Windows 构建 | DLL 内含同名选项与三条 `Kazumi:` 日志字符串，说明同一补丁也应用到了 Windows 版 libmpv **[实测]** |

**启用门槛（补丁 :57-65）**：解析播放列表时，只有**同时**满足
`hls_ad_filter=1` **且**见过至少一个 `#EXT-X-DISCONTINUITY`，才会置 `has_discontinuity=1` 并打印
`Kazumi: Stream has DISCONTINUITY tags, ad filtering enabled`。没有标签 → 整套逻辑不执行。

> 注意：补丁里给每个分片记了 `after_discontinuity` 字段（:73-75），但**运行期从未使用**。
> 也就是说：标签只用来"开机"，**判定并不限定在分片组边界上**，而是对**整条流任意位置**的后退跳变生效。

### 1.2 状态机（补丁 :154-264）

```
每个 packet（只处理非 NOPTS 的 PTS）：

if (not in_ad_segment)  # 阶段 2：正常播放
    if (after_seek)                      # 刚 seek 过 → 重新基线
        last_main_* = pts ; pts_offset = 0 ; after_seek = 0
    elif (是视频包 且 已知 last_main_pts):
        if (pts - last_main_pts < -1 秒):         # ★ 判定广告
            in_ad_segment = 1
            video_resumed = audio_resumed = 0
            ad_start_*_pts = last_main_*_pts - pts_offset
            日志 "Ad detected! PTS jumped from Xms to Yms"
            丢弃本 packet; continue
    应用 pts_offset; 更新 last_main_*

else                    # 阶段 1：已在广告里
    pts_diff = pts - ad_start_video_pts          # 找不到视频则用音频
    if (-2 秒 < pts_diff < +10 秒):              # ★ 认为"回到正片"
        记录 video/audio 的 resume 点（各一次）
        日志 "Video/Audio resuming at PTS=Zms"
        当 video 与 audio **都** resume 后:
            video_gap = ad_resume_video_pts - ad_start_video_pts
            pts_offset -= video_gap
            日志 "Ad skipped! Offset adjusted by -video_gap, total offset=..."
            in_ad_segment = 0
        应用 pts_offset; 更新 last_main_*
    else:
        丢弃本 packet; continue                   # ★ 这才是"跳过广告"
```

### 1.3 规则与阈值（可直接实现）

| 参数 | 值 | 含义 |
|---|---|---|
| 判定阈值 | `pts_diff < -1s` | 视频 PTS 相对上一正片 PTS **后退超过 1 秒** → 判定进入广告 |
| 判定方向 | **只认后退** | 广告 PTS 比正片**大**（向前跳）不会被识别 |
| 复用基准 | `last_main_pts - pts_offset` | 与上一次正片 PTS 的**原始值**比较 |
| 回归窗口 | `-2s < pts_diff < +10s` | 以"广告开始前的正片 PTS"为参照，回到这个窗口内即认为广告结束 |
| 回归条件 | video **与** audio 都 resume | 少一条轨就永远退不出广告态（见 1.5） |
| 偏移修正 | `pts_offset -= (resume_video - ad_start_video)` | 只修两者的缝（通常几十毫秒）；**不减去广告时长** |
| seek 处理 | `after_seek=1` → 重新基线、`pts_offset=0` | seek 之后的第一段不会被判广告 |

### 1.4 "跳过"的确切含义

- 广告分片的 packet 在 demuxer 层被 `av_packet_unref` + `continue` 丢掉，**解码器根本收不到**。
- 因此**看不到广告画面/声音**，播放会从正片继续。
- 但**容器的 duration 不变**（仍是 playlist 里 `EXTINF` 的总和），所以进度条总时长可能还包含广告时间。
  要让总时长也正确 → 必须从**播放列表**里删掉广告分片（这正是 Dart 侧要做的事）。
- 正片时间轴本身就是连续的（广告的 PTS 没有推进正片时间轴），偏移修正只用于抹平拼接处的几十毫秒。

### 1.5 限制与失效模式

| 条件 | 结果 | 依据 |
|---|---|---|
| 播放列表无 `#EXT-X-DISCONTINUITY` | **完全失效**（例如代理重写把标签删掉） | **[源码]** 1.1 |
| 广告 PTS 比正片**大**（向前跳） | 不识别 → 广告照播，且时间轴可能被拉长 | **[源码]** 1.3 |
| 流里没有音频轨 | `audio_resumed` 永远为 0 → 退不出广告态；广告结束后约 10 秒开始丢包 → **画面卡死** | **[推断]** 1.2 |
| 广告结束后正片 PTS 与广告前相差 > 10 秒 | 同上，退不出广告态 | **[源码]** 1.3 |
| 正片本身存在合法的 PTS 后退 > 1 秒 | 会被误判为广告 → 误丢正片 | **[源码]** 1.2（判定不限定在组边界） |
| seek 到广告区间内 | 重新基线，该段广告不会被识别 | **[源码]** 1.3 |
| 加密分片（AES-128）/ fMP4 | 与补丁无关（补丁只看 packet PTS），仍可工作 | **[源码]** |

---

## 2. 这条流的真实行为推演

实测数字（本机从分片字节读出）**[实测]**：

| 分片 | 视频首 PTS | 视频尾 PTS |
|---|---|---|
| `c62332e4182000073.ts`（广告前最后一片） | 294.766 s | 297.454 s |
| `c62332e41820355616.ts`（广告 1 首片） | 1.467 s | 5.311 s |
| `c62332e41820355622.ts`（广告 1 末片） | 25.467 s | 27.100 s |
| `c62332e4182000074.ts`（广告后首片） | 297.566 s | 301.518 s |

按 1.2 的状态机推演（04:56 处，第一次广告）**[推断]**：

1. 广告首包 PTS ≈ 1.467 s，`last_main_pts` ≈ 297.45 s → `pts_diff ≈ -296 s < -1 s`
   → 判定进入广告，打印 `Ad detected! PTS jumped from 297454ms to 1467ms`，丢弃该包。
2. 广告的 7 个分片（25.7 秒）PTS 在 1.467~27.1 s，全部落在回归窗口外 → **全部丢弃**（这就是"看不到广告"）。
3. 正片 `000074` 首包 PTS = 297.566 s，相对 `ad_start`(297.45 s) 的差是 **+0.116 s**，落在 `(-2s, +10s)` 内
   → 触发 resume；video 与 audio 都 resume 后打印 `Ad skipped! Offset adjusted by -116ms, total offset=-116ms`，
   广告态退出，正片继续（时间轴只平移了 116 毫秒）。
4. 33:22 处的第二段广告同理会经历同样的判定。
5. 整集的可播放内容变成 2521.4 − 51.4 = **2470 秒（41:10）**，但 HLS duration 仍是 **2521.4 秒（42:01）**
   → 这正是你观察到的"**广告没了、总时长没变**"。

---

## 3. 我此前错在哪（撤回旧结论）

旧结论"mpv 只发现、不跳过"来自一次**无效实验**。当时的配置与真实播放差三处：

| 我的实验 | 真实播放 | 影响 |
|---|---|---|
| 把列表裁剪到 21 片，且**首片就带 `#EXT-X-DISCONTINUITY`** | 完整 630 片 | 决定了 demuxer 如何重排时间戳（见下） |
| `--audio=no` | 有音频 | 命中 1.5 的"缺轨退不出广告态"分支 |
| `--untimed=yes` | 正常计时 | 只影响播放节奏，非主因 |

**关键错因（时间戳方向被反转）**：在那份裁剪列表里，广告段的 PTS 被 demuxer 抬到了
26.4 小时（日志：`Invalid video timestamp: 18.879967 -> 95166.538100`，
`Ad detected! PTS jumped from 95470817ms to 297566ms`）。也就是说 patch 看到的不是
"1.467 s（后退）"而是"95166 s（前进）"，于是它在**广告→正片交界处**反向触发了判定：
把**广告之后的正片**当成广告开始丢弃，而广告本身被当作正片播完。
播放最终停在 95192 s（广告那段被抬升的时间轴末端），我据此得出"检测到了但没跳过"——
**这是实验配置造成的假象，不是实现的行为。**

因此：**"mpv 不能跳过广告"这一结论作废**。真实整集播放中，它是能跳过的（与你的真机观察一致）。

---

## 4. MVP 实现方案

目标：用最小改动拿到"广告不出现 + 起播不卡 + 总时长正确"，并且不把判定放在会拖垮播放的位置。

### 4.1 M1｜mpv 侧：绝不破坏 HLS 时间轴元数据（最高优先级）

- **任何交给 mpv 的播放列表都必须保留 `#EXT-X-DISCONTINUITY`**（代理重写、本地列表、任何缓存）。
- 同理不要丢 `#EXT-X-KEY` / `#EXT-X-MAP` / `#EXT-X-BYTERANGE` / `#EXT-X-PROGRAM-DATE-TIME`。
- 保持 `hls_ad_filter=1`（即 `adBlockerEnabled`）——这是**免费**的一道过滤。
- 现状：`playback_proxy_service.dart` 已修（重写时补回标签）✅；`m3u8_parser.buildLocalM3u8` 本来就写标签 ✅。
- 验收：合流播放时控制台能搜到 `Kazumi: Stream has DISCONTINUITY tags, ad filtering enabled`。

### 4.2 M2｜Dart 侧判据：与 patch 对齐，而不是自创一套

把 Dart 的广告判定改成**同一套规则**（分片粒度版），保证两层判定一致：

```
令 pts[i] = 第 i 片首个视频 PTS，dur[i] = 该片 EXTINF
参考点 ref = 上一片的“末 PTS”≈ pts[i-1] + dur[i-1]

判定：pts[i] - ref < -1.0 秒        → 第 i 片是广告起点
结束：pts[k] - ref ∈ (-2, +10) 秒   → 广告区间结束于 k-1
```

- 广告区间 = `[i, k-1]`，整段剔除。
- 这条规则**与 patch 完全同构**，因此不会出现"播放器判定和下载器判定不一致"。
- 现有的"区间不变量 + 递归定位"（`ad_insertion_finder.dart`）**保留但降级为第二判据**：它额外能识别
  **向前跳**的广告与"内容被删减"，这两种 patch 处理不了；但只有在**下载路径**（mpv 不参与）才使用。
- 阈值不要自创：`-1s` 判定、`-2s/+10s` 回归窗口，直接对齐 patch。

### 4.3 M3｜判定时机：本地数据优先，绝不在起播前做网络探测

- **代理路径（合流/边播边下）**：**立即**返回"原样列表 + 保留标签"（0 探测、0 延迟），
  让 mpv 自己丢广告；把一个后台任务写 manifest，供**下一次**播放零成本使用。
  → 这一步直接消灭"起播等 8 秒、mpv 5 秒超时打不开"的问题。
- **下载路径**：分片下载完成**之后**用本地文件做全量判定（免费、不会超时、100% 覆盖），
  再据此生成 `playlist.m3u8` 与 manifest。
- **起播前只允许读 manifest**（零成本）；manifest 未命中就不判定。

### 4.4 M4｜索引空间：让"事后判定"成为可能

- 现状：分片文件按"**过滤后**位置"命名（`seg_00000.ts`），逼着判定必须发生在下载/重写**之前**。
- MVP：改为按"**原始**位置"命名（`seg_00012.ts` 就是原始第 12 片），过滤只是"列表里少几行"。
  这样判定可以在任何时刻做，也顺手消除了"改开关后旧文件被按序号错位复用"的老问题。
- 过渡方案（不想动命名）：判定必须**先于**下载完成 → 那就必须接受 4.3 的"只读 manifest + 本地判定在下一次生效"。

### 4.5 M5｜回退阶梯与日志

| 情况 | 行为 |
|---|---|
| 有 manifest（指纹匹配） | 直接用 |
| 本地文件可读 | 用 M2 规则全量判定 |
| 本地文件不可读（加密/fMP4/缺片） | 用"区间不变量"判据 |
| 两者都失败 | 回退旧启发式（`m3u8_ad_filter.dart`，已保证不删末段） |
| 任何一块分片读不到 | **不得**因此整体放弃，只放弃该候选 |

日志要求：
- `剔除区间=N 剔除分片=M`（现在把区间数写成了"段数"，易误导）；
- 判定耗时与探测次数（用于监控是否又踩到超时）；
- 回退原因。

---

## 5. 需要改动的文件（当时的设计草案；Dart 侧已在第 7 节移除）

| 文件 | 现状 | 目标 |
|---|---|---|
| `lib/services/download/playback_proxy_service.dart` | 已保留标签 ✅，但**起播前同步跑网络探测** ❌ | 立即返回列表；判定挪到后台/只用 manifest |
| `lib/services/download/download_manager.dart` | 下载前网络判定 + 下载后校验 | 改为下载后本地全量判定（配合 M4 命名） |
| `lib/services/download/ad_decision_service.dart` | 无硬时限、一次失败即整体回退 ❌ | 硬时限；只采用已验证区间；只用本地/缓存 |
| `lib/utils/ad_insertion_finder.dart` | 区间不变量 + 递归（自创规则） | 主判据换成 patch 同构规则；不变量降级为第二判据 |
| `lib/utils/m3u8_parser.dart` | 已修嵌套 group off-by-one ✅ | 无 |
| `lib/utils/m3u8_ad_filter.dart` | 旧启发式（已保护末段）✅ | 保持为最后兜底 |
| `lib/services/download/ad_manifest_store.dart` | ✅ 可用 | 增加"判定来源/耗时/是否全量"字段 |

---

## 6. 验收清单

1. **合流起播**：不得再出现 `Failed to open http://127.0.0.1:.../m3u8?...`；从点击到出画面 < 2 秒。
2. **直接播放 / 合流都不出现广告**（04:56、33:22 两处）。
3. **总时长**：走"列表里真的删掉广告段"的路径时，总时长应为 **2470 秒（41:10）**；
   仅靠 mpv 丢包时仍是 2521 秒（42:01）——这是预期差异，需在文档/UI 上说明。
4. **mpv 侧确认（真机 1 分钟可做）**：
   - 设置 → 播放器 → 打开「播放器调试模式」，日志等级设「简略」或「详细」；
   - 播放该集，在控制台搜 `MPV 日志`，应看到
     `Kazumi: Stream has DISCONTINUITY tags, ad filtering enabled`、
     `Kazumi: Ad detected! PTS jumped from ... to ...`、
     `Kazumi: Ad skipped! Offset adjusted by ... total offset=...`；
   - 出现 `Ad skipped!` 即证明 mpv 侧成功丢包。
5. **下载路径**：`flutter test` 全绿；`ad_manifest.json` 写入且指纹正确；
   重复播放时日志显示 `source=manifest` 且 **0 探测**。

---

## 7. 落地状态（本次决定：广告过滤统一交给引擎）

按"**统一而不是分散**"的目标，Dart 侧的广告过滤已全部移除，只保留引擎侧那一条链路：

**已删除**
- `lib/utils/ts_pts_reader.dart`、`lib/utils/ad_insertion_finder.dart`（PTS 读取与区间定位）
- `lib/services/download/ad_decision_service.dart`、`lib/services/download/ad_manifest_store.dart`（判定入口与判定记录）
- `lib/utils/m3u8_ad_filter.dart`（从 Kazumi 抄来的旧启发式）
- 对应测试与开发脚本：`test/ts_pts_reader_test.dart`、`test/ad_insertion_finder_test.dart`、`tools/verify_ad_live.dart`

**现在的唯一机制**
- 播放引擎（media_kit → libmpv → 打过 Kazumi 补丁的 FFmpeg）的 `hls_ad_filter`；
- 开关：设置里的「广告过滤」（`SettingsKeys.forceAdBlocker`）→ `adBlockerEnabled` → `hls_ad_filter=0/1`；
- 下载端不再判定，只把列表原样落盘；**本地 `playlist.m3u8` 与代理重写都保留 `#EXT-X-DISCONTINUITY`**（引擎侧过滤的启用条件）。

**由此带来的已知后果（尚待处理）**

| # | 后果 | 说明 |
|---|---|---|
| 1 | ~~离线播放不过滤广告~~ **已对齐** | 本地播放改为读同一个开关（`video_controller.dart` 的 `playLocalFile`，原先写死 `false`）→ 离线播放也启用 `hls_ad_filter`；仓库里已无写死的 `adBlockerEnabled: false` |
| 2 | 广告分片会被下载 | 下载端不再剔除 → 磁盘上留着广告字节（示例集两段广告约 13MB） |
| 3 | 进度条总时长仍含广告 | 补丁丢包但不改容器 duration；示例集显示 42:01、实际内容 41:10 |
| 4 | 插件级开关仍缺失 | Kazumi 支持插件声明 `adBlocker`（`forceAdBlocker \|\| plugin.adBlocker`），wyw 只认全局开关 |

**注意**：补丁的判定依赖 demuxer 呈现的时间戳（见 1.5、3 节），无音轨的流会卡死、向前跳的广告不识别；第 4 节的 M2/M4（Dart 侧判据与索引空间）在本次决定下**暂不实施**。

---

## 8. 证据清单

- 补丁源码：`...\libmpv-android-video-build\buildscripts\patches\ffmpeg\ffmpeg-hls-kazumi-combined.patch`（303 行）
  - 门槛 :57-65；状态机 :154-264；判定阈值 :237；回归窗口 :181；双轨要求 :195-201；seek 处理 :273-277；选项注册 :297-298
- 本机诊断工具：`tools/ts_pts.ps1`（读分片首/末 PTS）、`tools/mpv_adtest.ps1`（libmpv 复现，支持 `-AdFilter 0/1`）
- 实测数字来源：本机对 `v.lzcdn31.com` 该集分片的直接下载与解析（第 2 节表格）
- 真机现象：直接播放整集无广告；代理（旧版）会播广告 ← 与 1.1 的"标签门槛"完全一致
