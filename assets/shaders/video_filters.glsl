// wyw 画面调节滤镜（eq + unsharp 的 GPU 着色器实现）
//
// 这台机器的 libmpv 构建没有编入内部 vf_eq / vf_unsharp，lavfi 桥在运行时
// 黑屏；改用用户着色器（mpv 已验证 Anime4K 机制可用）。
//
// 参数用 `#define` 静态烘焙：播放器每次参数变化会重写本文件，再用
// `change-list glsl-shaders remove` + `append` 强制 mpv 重新加载
// （路径不变时 `set` 会被 mpv 判定为"无变化"而跳过重载）。
// 本文件是参数中性版（全部默认值=原样），作为首次安装的分发种子。

//!DESC wyw 画面调节滤镜
//!HOOK MAIN
//!BIND HOOKED

// libmpv 的旧 GPU renderer 会把 sampler 默认声明为 mediump，复杂运算下会
// 出现全局偏色（见 media-kit#1438 / Kazumi#1547）；可用 highp 时显式提升。
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
precision highp sampler2D;
#endif

#define WYW_SHARPNESS 0.0
#define WYW_CONTRAST 1.0
#define WYW_SATURATION 1.0
#define WYW_BRIGHTNESS 0.0
#define WYW_GAMMA 1.0

vec4 hook() {
    vec4 c = HOOKED_tex(HOOKED_pos);
    vec3 rgb = c.rgb;

    // 亮度（加法，与 ffmpeg eq 同序、先做）
    rgb += WYW_BRIGHTNESS;

    // 对比度（围绕 0.5 缩放）
    rgb = (rgb - 0.5) * WYW_CONTRAST + 0.5;

    // 饱和度（按 luma 混合）
    float luma = dot(vec3(0.299, 0.587, 0.114), rgb);
    rgb = mix(vec3(luma), rgb, WYW_SATURATION);

    // 伽马（ffmpeg eq 语义：pow(1/gamma)，>1 变亮）
    rgb = pow(max(rgb, vec3(0.0)), vec3(1.0 / WYW_GAMMA));

    // 锐化（unsharp mask：原图 − 3×3 盒式模糊后按系数加回）
    if (WYW_SHARPNESS > 0.0001) {
        vec2 pt = vec2(1.0) / HOOKED_size;
        vec3 blurred =
            HOOKED_tex(HOOKED_pos + vec2(-pt.x, -pt.y)).rgb +
            HOOKED_tex(HOOKED_pos + vec2(0.0, -pt.y)).rgb +
            HOOKED_tex(HOOKED_pos + vec2(pt.x, -pt.y)).rgb +
            HOOKED_tex(HOOKED_pos + vec2(-pt.x, 0.0)).rgb +
            c.rgb +
            HOOKED_tex(HOOKED_pos + vec2(pt.x, 0.0)).rgb +
            HOOKED_tex(HOOKED_pos + vec2(-pt.x, pt.y)).rgb +
            HOOKED_tex(HOOKED_pos + vec2(0.0, pt.y)).rgb +
            HOOKED_tex(HOOKED_pos + vec2(pt.x, pt.y)).rgb;
        blurred /= 9.0;
        rgb += (rgb - blurred) * WYW_SHARPNESS;
    }

    return vec4(rgb, c.a);
}
