#include <metal_stdlib>
using namespace metal;

// Watercolor's sheet (painting-company row 373), drawn from PaintCore's `WatercolorSim`: the
// pigment as the water left it, the target solve per area, Beer–Lambert over the paper's color,
// granulation in the paper's fine valleys, cold-press paper lit from the top left, the wet sheen,
// graphite fading under paint and the numbers fading once their area is painted. Colors are
// linear Display P3, into an sRGB-curved target. `pbn watercolor`'s raster is this pass on the
// CPU (without sheen or numbers); keep the two in step.

// Mirrored by `WatercolorUniforms` in WatercolorRenderer.swift: change both in the same order.
struct WatercolorUniforms {
    float2 offset;        // canvas units at the target's top-left pixel
    float unitsPerPixel;  // canvas units per target pixel
    float time;           // the simulation's seconds
    float2 canvasSize;    // canvas units
    float2 paperTexel;    // one texel of the fine paper, in uv
    float2 simTexel;      // one cell of the simulation, in uv
    float2 film;          // the Making Of's (zero on the painting screen): x, the pencil gone from
                          // under painted areas; y, the numbers hidden
    float4 paper;         // the paper's color
    float4 background;    // around the sheet
    float4 numberInk;
    float4 sheet;         // the sheet's paper past the canvas: x its side and top margin, y its bottom one (canvas units)
};

// Mirrored by `WatercolorRegion`: per area, the target solve's gain (w: when it was painted,
// seconds, or a far future) and the density its rims cap toward.
struct WatercolorRegion {
    float4 gain;
    float4 aim;
};

struct WatercolorOut {
    float4 position [[position]];
};

// The desk and the sheet's margins: everything past the canvas, kept apart from the pigment.
static float watercolor_hash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float watercolor_noise(float2 p) {
    float2 i = floor(p), f = p - i;
    float2 u = f * f * (3 - 2 * f);
    float a = watercolor_hash(i), b = watercolor_hash(i + float2(1, 0));
    float c = watercolor_hash(i + float2(0, 1)), d = watercolor_hash(i + float2(1, 1));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float watercolor_fbm(float2 p) {
    float v = 0, amp = 0.5;
    for (int k = 0; k < 4; k++) {
        v += amp * watercolor_noise(p);
        p = p * 2.03 + float2(17.1, 9.2);
        amp *= 0.5;
    }
    return v;
}

static float watercolor_box(float2 p, float2 lo, float2 hi) {
    float2 c = (lo + hi) * 0.5, h = (hi - lo) * 0.5;
    float2 q = abs(p - c) - h;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

/// Past the canvas: the sheet's margins, a deckled edge, its shadow and the slate desk under it,
/// all in canvas units so they move with the sheet. `paper` is the canvas's tooth, repeated.
static float4 watercolor_surround(float2 canvas, constant WatercolorUniforms &u, texture2d<half> paper) {
    constexpr sampler tiled(filter::linear, address::repeat);
    float L = max(u.canvasSize.x, u.canvasSize.y);
    float m = u.sheet.x;
    float2 lo = float2(-m), hi = u.canvasSize + float2(m, u.sheet.y);
    float sd = watercolor_box(canvas, lo, hi);
    float deckle = (watercolor_noise(canvas * 0.08) - 0.5) * 0.0035 * L + (watercolor_noise(canvas * 0.7) - 0.5) * 0.0014 * L;
    float edge = sd + deckle;
    float cover = 1 - smoothstep(-u.unitsPerPixel, u.unitsPerPixel, edge);

    // Slate, mottled a little.
    float k = 1 + 0.03 * (watercolor_noise(canvas * 0.35) - 0.5) + 0.08 * (watercolor_fbm(canvas * 0.003) - 0.5);
    float3 desk = u.background.rgb * k;
    float shadowFar = 1 - smoothstep(-0.004 * L, 0.03 * L, watercolor_box(canvas - float2(0, 0.008 * L), lo, hi));
    float shadowNear = 1 - smoothstep(0.0, 0.004 * L, sd);
    desk *= 1 - (0.30 * shadowFar + 0.18 * shadowNear);

    float2 uv = canvas / u.canvasSize;
    float sx = float(paper.sample(tiled, uv + float2(u.paperTexel.x, 0)).r - paper.sample(tiled, uv - float2(u.paperTexel.x, 0)).r);
    float sy = float(paper.sample(tiled, uv + float2(0, u.paperTexel.y)).r - paper.sample(tiled, uv - float2(0, u.paperTexel.y)).r);
    float3 sheet = u.paper.rgb * clamp(1 + 0.45 * (sx + sy), 0.85, 1.1);
    sheet *= 0.94 + 0.06 * smoothstep(0.0, 0.003 * L, -edge);
    return float4(mix(desk, sheet, cover), 1);
}

vertex WatercolorOut watercolor_vertex(uint vid [[vertex_id]]) {
    // One triangle over the whole target.
    float2 p = float2((vid << 1) & 2, vid & 2);
    WatercolorOut out;
    out.position = float4(p * float2(2, -2) + float2(-1, 1), 0, 1);
    return out;
}

fragment float4 watercolor_fragment(
    WatercolorOut in [[stage_in]],
    constant WatercolorUniforms &u [[buffer(0)]],
    const device WatercolorRegion *regions [[buffer(1)]],
    texture2d<half> density [[texture(0)]],
    texture2d<half> granulation [[texture(1)]],
    texture2d<uint, access::read> labels [[texture(2)]],
    texture2d<half> paper [[texture(3)]],
    texture2d<half> pencil [[texture(4)]],
    texture2d<half> numbers [[texture(5)]])
{
    constexpr sampler smooth(filter::linear, mip_filter::linear, address::clamp_to_edge);
    float2 canvas = u.offset + in.position.xy * u.unitsPerPixel;
    if (canvas.x < 0 || canvas.y < 0 || canvas.x >= u.canvasSize.x || canvas.y >= u.canvasSize.y) {
        return watercolor_surround(canvas, u, paper);
    }
    float2 uv = canvas / u.canvasSize;
    uint2 labelSize = uint2(labels.get_width(), labels.get_height());
    uint region = labels.read(min(uint2(uv * float2(labelSize)), labelSize - 1)).r;
    WatercolorRegion r = regions[region];

    float4 d4 = float4(density.sample(smooth, uv));
    // The target solve: the area's pigment brought to its paint, rims capped toward its own hue.
    float3 d = max(d4.rgb * r.gain.rgb, 0.0);
    // One factor for all three channels, the most any channel's cap asks for: capped one by one,
    // a neighbour's pigment sampled across the edge took on a hue of its own (cyan and magenta
    // specks along the rims, CI, November 21).
    float3 cap = max(r.aim.rgb * 1.7, 0.05);
    float3 capped = cap * tanh(d / cap);
    float3 ratio = select(capped / max(d, 1e-5), float3(1.0), d < 1e-5);
    d *= min(ratio.r, min(ratio.g, ratio.b));
    float g = float(granulation.sample(smooth, uv).r);
    float p2 = float(paper.sample(smooth, uv).r);
    d *= 1 + g * 0.6 * (0.5 - p2);
    float3 refl = u.paper.rgb * exp(-d);

    // Cold-press paper lit from the top left, quieter under paint.
    float sx = float(paper.sample(smooth, uv + float2(u.paperTexel.x, 0)).r - paper.sample(smooth, uv - float2(u.paperTexel.x, 0)).r);
    float sy = float(paper.sample(smooth, uv + float2(0, u.paperTexel.y)).r - paper.sample(smooth, uv - float2(0, u.paperTexel.y)).r);
    float under = clamp((d.r + d.g + d.b) / 3 / 1.2, 0.0, 1.0);
    refl *= clamp(1 + 0.45 * (sx + sy) * (1 - 0.6 * under), 0.85, 1.1);

    // Wet paint: a little darker, with a glint where the water's surface tilts toward the light.
    float water = d4.a;
    float wet = clamp(water / 0.6, 0.0, 1.0);
    if (wet > 0) {
        float2 step = u.simTexel * 2;
        float wx = float(density.sample(smooth, uv + float2(step.x, 0)).a - density.sample(smooth, uv - float2(step.x, 0)).a);
        float wy = float(density.sample(smooth, uv + float2(0, step.y)).a - density.sample(smooth, uv - float2(0, step.y)).a);
        refl *= 1 - 0.07 * wet;
        // A soft sheen, not a glare: brighter read as white blotches on a pale wash.
        float spec = pow(clamp(-(wx + wy) * 0.8, 0.0, 1.0), 2.0) * wet;
        refl += 0.12 * spec;
    }

    // Graphite reads on bare paper and all but disappears under a wash.
    float ink = float(pencil.sample(smooth, uv).r) * 0.75 * (1 - 0.75 * clamp(under * 2.5, 0.0, 1.0));
    ink *= 1 - u.film.x * step(r.gain.w, u.time);
    refl *= 1 - ink * (1 - float3(0.30, 0.30, 0.33));

    // A number fades once its area is painted.
    float fade = clamp(1 - (u.time - r.gain.w) / 0.35, 0.0, 1.0);
    float n = float(numbers.sample(smooth, uv).r) * fade * (1 - u.film.y);
    refl = mix(refl, u.numberInk.rgb, n * 0.9);
    return float4(refl, 1);
}
