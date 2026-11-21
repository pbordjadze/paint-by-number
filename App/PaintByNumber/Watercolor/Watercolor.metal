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
    float2 pad;
    float4 paper;         // the paper's color
    float4 background;    // around the sheet
    float4 numberInk;
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
        return u.background;
    }
    float2 uv = canvas / u.canvasSize;
    uint2 labelSize = uint2(labels.get_width(), labels.get_height());
    uint region = labels.read(min(uint2(uv * float2(labelSize)), labelSize - 1)).r;
    WatercolorRegion r = regions[region];

    float4 d4 = float4(density.sample(smooth, uv));
    // The target solve: the area's pigment brought to its paint, rims capped toward its own hue.
    float3 d = d4.rgb * r.gain.rgb;
    float3 cap = max(r.aim.rgb * 1.7, 0.05);
    d = cap * tanh(d / cap);
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
        float spec = pow(clamp(-(wx + wy) * 1.1, 0.0, 1.0), 2.0) * wet;
        refl += 0.35 * spec;
    }

    // Graphite reads on bare paper and all but disappears under a wash.
    float ink = float(pencil.sample(smooth, uv).r) * 0.75 * (1 - 0.75 * clamp(under * 2.5, 0.0, 1.0));
    refl *= 1 - ink * (1 - float3(0.30, 0.30, 0.33));

    // A number fades once its area is painted.
    float fade = clamp(1 - (u.time - r.gain.w) / 0.35, 0.0, 1.0);
    float n = float(numbers.sample(smooth, uv).r) * fade;
    refl = mix(refl, u.numberInk.rgb, n * 0.9);
    return float4(refl, 1);
}
