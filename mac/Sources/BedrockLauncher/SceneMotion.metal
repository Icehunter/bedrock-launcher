// Moves parts of the Play page picture: water ripples and glints, waterfalls
// stream down, clouds sway and the valley mist drifts. Everything else stays
// still. The mask says where each part is: red water, green waterfalls, blue
// sky (top 30%) and mist (below). Every motion repeats each `period` seconds,
// so the loop has no jump.
#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

[[ stitchable ]] half4 sceneMotion(float2 pos, SwiftUI::Layer layer, float time, float period,
                                   float2 size, texture2d<half> mask) {
    // Where pos lands on the 16:9 picture, which fills the view and is cut
    // at the sides or top and bottom.
    float s = max(size.x / 16.0, size.y / 9.0);
    float2 shown = float2(16.0, 9.0) * s;
    float2 uv = (pos - (size - shown) * 0.5) / shown;
    constexpr sampler linear(filter::linear, address::clamp_to_edge);
    half4 m = mask.sample(linear, uv);
    float water = m.r, falls = m.g, air = m.b;
    if (water + falls + air < 0.01) {
        return layer.sample(pos);
    }

    float px = shown.x / 1280.0;         // one mask pixel in view points
    float2 p = uv * float2(1280.0, 720.0); // position in mask pixels
    float ph = 2.0 * M_PI_F * fract(time / period);

    float2 offset = float2(0.0);
    // Water: small crossing waves.
    offset += water * float2(sin(p.y * 0.55 + ph * 3.0) * 0.9,
                             sin(p.x * 0.11 + p.y * 0.35 - ph * 2.0) * 0.6);
    // Waterfalls: a slight sideways shake.
    offset.x += falls * sin(p.y * 0.9 - ph * 12.0) * 0.5;
    // Clouds sway; mist drifts further and faster.
    bool sky = uv.y < 0.30;
    offset.x += air * (sky ? sin(ph + p.y * 0.02) * 3.0 : sin(ph * 2.0 + p.y * 0.05) * 4.0);
    half4 c = layer.sample(pos + offset * px);

    // Glints on the water.
    float glint = pow(max(0.0, sin(p.x * 0.21 + p.y * 0.47 - ph * 4.0) * sin(p.y * 0.33 + ph * 3.0)), 10.0);
    // Streaks running down the waterfalls.
    float streak = pow(0.5 + 0.5 * sin(p.y * 0.35 - ph * 16.0 + sin(p.x * 1.3) * 2.0), 6.0);
    // Slow light moving over the clouds; the mist thickens and thins.
    float light = sky ? 0.05 * sin(p.x * 0.006 - ph) : 0.06 * sin(ph * 2.0 + p.x * 0.012);
    half3 add = half3(water * glint * 0.35 + falls * streak * 0.22 + air * light);
    c.rgb = clamp(c.rgb + add * c.a, half3(0.0), c.a);
    return c;
}
