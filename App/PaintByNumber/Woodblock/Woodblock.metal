#include <metal_stdlib>
using namespace metal;

// Woodblock's bench (painting-company row 375), drawn by `WoodblockMode` over the canvas's sheet
// and a margin of wood around it: the cherry block lit from a lamp at the top left, what stays
// standing with the drawing (or the kyōgō: the key line faint and the block's areas tinted) on
// its face, the wood carved away below it in the grooves the tool left, the ink wet on what
// stands; the damp sheet laid on it with the print showing through its back; the sheet peeling
// from a corner, its face on the flap; and the print the right way round, its paper margin on
// the bench. Everything is on PaintCore's `WoodblockBench` grid, in the block's (mirrored)
// space; the print is its mirror. Colors are linear Display P3, into an sRGB-curved target.

// The first fields of `FrameUniforms` (Shaders.metal), in its order: only these are read.
struct WoodblockFrame {
    float4 transform;   // xy: translation (px), z: px per canvas unit, w: px per point
    float4 viewport;    // xy: target size (px), zw: canvas size (units)
    float4 background;
    float4 paper;
    float4 ink;
    float4 selected;
    float4 accent;
    float4 rim;
    float4 outline;
    float4 labels;
    float4 numbers;
    float4 time;        // x: now
};

// Must match `WoodblockMode.Parameters` (WoodblockMode.swift).
struct WoodblockParameters {
    float4 grid;    // x, y: cells; z: canvas units per cell; w: the block's margin past the picture (canvas units)
    float4 view;    // x: 0 the block, 1 the sheet on it, 2 peeling, 3 the print; y: 0 key, 1 colour, 2 bokashi; z: 1 for a Display P3 sheet
    float4 ink;     // rgb: this block's ink (linear P3); w: its opacity
    float4 tint;    // rgb: the kyōgō's tint for a colour block (linear P3); w: how strong
    float4 anim;    // x: when the peel began; y: how long it takes (< 0: held, at minus it); z: when the sheet was laid; w: 1 under Reduce Motion
};

struct WoodblockOut {
    float4 position [[position]];
};

vertex WoodblockOut woodblockVertex(uint vid [[vertex_id]],
                                    constant WoodblockFrame &u [[buffer(0)]],
                                    constant float &margin [[buffer(1)]]) {
    float pad = margin * u.transform.z;
    float2 lo = u.transform.xy - pad;
    float2 hi = u.transform.xy + u.viewport.zw * u.transform.z + pad;
    float2 p = float2((vid & 1u) != 0u ? hi.x : lo.x, (vid & 2u) != 0u ? hi.y : lo.y);
    WoodblockOut o;
    o.position = float4(p.x / u.viewport.x * 2.0 - 1.0, 1.0 - p.y / u.viewport.y * 2.0, 0.0, 1.0);
    return o;
}

static float wbHash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static float wbNoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 s = f * f * (3.0 - 2.0 * f);
    float a = wbHash(i), b = wbHash(i + float2(1, 0)), c = wbHash(i + float2(0, 1)), d = wbHash(i + float2(1, 1));
    return mix(mix(a, b, s.x), mix(c, d, s.x), s.y);
}

static float3 wbDecode(float3 c) {
    return select(pow((c + 0.055) / 1.055, 2.4), c / 12.92, c <= 0.04045);
}

// sRGB's linear primaries into Display P3's.
static float3 wbToP3(float3 c) {
    return float3(0.8225 * c.r + 0.1774 * c.g,
                  0.0332 * c.r + 0.9669 * c.g,
                  0.0171 * c.r + 0.0724 * c.g + 0.9108 * c.b);
}

// The bench's textures, passed whole to each helper: shape (r: this block's signed distance in
// cells, < 0 stays), key (r: the key block's), carved (r: the gouge's direction code, 0 where
// the wood stands; g: its radius / 255), inked (r: ink; g: how much the baren pressed) and sheet
// (the sheet's face, gamma-encoded).
#define WB_TEXTURES texture2d<float> shape, texture2d<float> key, texture2d<float> carved, texture2d<float> inked, texture2d<float> sheet
#define WB_PASS shape, key, carved, inked, sheet

constexpr sampler wbLinear(filter::linear, address::clamp_to_edge);
constexpr sampler wbNearest(filter::nearest, address::clamp_to_edge);

// The wood's height at p (cells): 1 its face, lower where carved, with the grooves the tool left
// and a sloped shoulder down from what stays; the margin past the picture is carved, but for the
// kentō, an L at one corner and a bar along the same edge.
static float wbHeight(float2 c, constant WoodblockParameters &w, WB_TEXTURES) {
    float2 size = w.grid.xy;
    float2 uv = c / size;
    float m = w.grid.w / w.grid.z;
    if (any(c < 0.0) || any(c > size)) {
        float2 q = c;
        // The kentō: in the block's space, the print's bottom right corner is its bottom left.
        float2 corner = float2(-m * 0.55, size.y + m * 0.55);
        float l = (abs(q.x - corner.x) < m * 0.12 && q.y > corner.y - m * 0.9 && q.y < corner.y + m * 0.12)
            || (abs(q.y - corner.y) < m * 0.12 && q.x > corner.x - m * 0.12 && q.x < corner.x + m * 0.9) ? 1.0 : 0.0;
        float bar = abs(q.y - corner.y) < m * 0.12 && q.x > size.x * 0.45 && q.x < size.x * 0.75 ? 1.0 : 0.0;
        float grooves = 0.04 * sin(q.y * 1.7 + wbNoise(q * 0.08) * 6.0);
        return max(max(l, bar), 0.3 + grooves);
    }
    float d = shape.sample(wbLinear, uv).r;
    float shoulder = 1.0 - smoothstep(-0.5, 3.0, d);
    float4 k = carved.sample(wbNearest, uv);
    float cut = smoothstep(0.0, 0.5, carved.sample(wbLinear, uv).r * 255.0);
    if (cut <= 0.0) return 1.0;
    float angle = (k.r * 255.0 - 1.0) / 254.0 * 3.14159265;
    float2 across = float2(-sin(angle), cos(angle));
    float tool = max(k.g * 255.0, 1.0);
    float pitch = clamp(tool * 0.9, 1.6, 9.0);
    float wobble = wbNoise(c * 0.05) * 2.0;
    float groove = 0.5 + 0.5 * cos((dot(c, across) + wobble) * 6.2831853 / pitch);
    float floorH = 0.36 - 0.07 * groove - 0.03 * wbNoise(c * 0.3);
    return max(mix(1.0, floorH, cut), shoulder);
}

static float3 wbWood(float2 c, float h) {
    // Cherry, its grain running along x, a little darker and redder below the face.
    float g = wbNoise(float2(c.x * 0.012, c.y * 0.18)) * 0.6 + wbNoise(float2(c.x * 0.004, c.y * 0.06)) * 0.4;
    float rings = 0.5 + 0.5 * sin(c.y * 0.35 + g * 9.0);
    float3 light = float3(0.50, 0.25, 0.12), dark = float3(0.30, 0.13, 0.06);
    float3 wood = mix(dark, light, 0.55 + 0.35 * rings * g);
    return mix(wood * float3(0.78, 0.7, 0.66), wood, smoothstep(0.3, 1.0, h));
}

// The block: lit wood, the drawing on its face, the ink.
static float3 wbBlock(float2 c, constant WoodblockParameters &w, WB_TEXTURES, constant WoodblockFrame &u) {
    float e = 0.75;
    float h = wbHeight(c, w, WB_PASS);
    float hx = wbHeight(c + float2(e, 0), w, WB_PASS), hy = wbHeight(c + float2(0, e), w, WB_PASS);
    float3 n = normalize(float3((h - hx) * 6.0, (h - hy) * 6.0, 1.0));
    float3 lamp = normalize(float3(-0.55, -0.6, 0.6));
    float lit = 0.38 + 0.75 * saturate(dot(n, lamp));
    float3 col = wbWood(c, h) * lit;
    float2 uv = c / w.grid.xy;
    bool inside = all(c >= 0.0) && all(c <= w.grid.xy);
    if (inside && h > 0.97) {
        // The drawing on the face: the key line in ink, or for a colour block the kyōgō, the key
        // line faint and the areas this block prints tinted.
        float key = 1.0 - smoothstep(-0.6, 0.6, key.sample(wbLinear, uv).r);
        float mine = 1.0 - smoothstep(-0.6, 0.6, shape.sample(wbLinear, uv).r);
        if (w.view.y < 0.5) {
            col = mix(col, float3(0.025, 0.02, 0.02), key * 0.92);
        } else {
            col = mix(col, col * mix(float3(1.0), w.tint.rgb * 1.6, w.tint.w), mine);
            col = mix(col, float3(0.06, 0.04, 0.035), key * 0.45);
        }
        // Wet ink on what stands: the pigment, and the lamp's sheen in it.
        float ink = inked.sample(wbLinear, uv).r * mine;
        if (ink > 0.0) {
            float3 wet = w.ink.rgb * (0.55 + 0.45 * lit);
            float sheen = pow(saturate(dot(reflect(-lamp, n), float3(0, 0, 1))), 24.0) * 0.5;
            col = mix(col, wet + sheen, ink * 0.94);
        }
    }
    return col;
}

static float3 wbWashi(float2 c) {
    float fibre = wbNoise(float2(c.x * 0.9, c.y * 0.25)) * 0.5 + wbNoise(c * 0.15) * 0.5;
    return wbDecode(float3(0.95, 0.93, 0.875)) * (0.965 + 0.05 * fibre);
}

static float3 wbSheetFace(float2 c, constant WoodblockParameters &w, WB_TEXTURES) {
    float2 uv = c / w.grid.xy;
    float3 s = wbDecode(sheet.sample(wbLinear, uv).rgb);
    if (w.view.z < 0.5) s = wbToP3(s);
    float3 paper = wbWashi(c);
    // The print takes the paper's fibre.
    return s * (paper / wbDecode(float3(0.95, 0.93, 0.875)));
}

// The back of the damp sheet lying on the block: the prints before it and this block's ink, as
// far as the baren pressed it, showing through; the block's relief faintly embossed.
static float3 wbSheetBack(float2 c, constant WoodblockParameters &w, WB_TEXTURES) {
    float2 uv = c / w.grid.xy;
    float3 paper = wbWashi(c);
    float3 face = wbDecode(sheet.sample(wbLinear, uv).rgb);
    if (w.view.z < 0.5) face = wbToP3(face);
    float3 back = mix(paper, paper * (face / wbDecode(float3(0.95, 0.93, 0.875))), 0.38);
    float2 ir = inked.sample(wbLinear, uv).rg;
    float mine = 1.0 - smoothstep(-0.6, 0.6, shape.sample(wbLinear, uv).r);
    float speck = wbHash(floor(c));
    float cover = saturate(ir.g * 1.25 - speck * (1.0 - ir.g) * 0.9) * ir.r * mine * w.ink.w;
    back = mix(back, back * mix(float3(1.0), w.ink.rgb, 0.55), cover);
    float h = wbHeight(c, w, WB_PASS), hx = wbHeight(c + float2(1, 0), w, WB_PASS);
    return back * (1.0 + (h - hx) * 0.25 * ir.g);
}

fragment float4 woodblockFragment(WoodblockOut in [[stage_in]],
                                  constant WoodblockFrame &u [[buffer(0)]],
                                  constant WoodblockParameters &w [[buffer(1)]],
                                  texture2d<float> shape [[texture(0)]],
                                  texture2d<float> key [[texture(1)]],
                                  texture2d<float> carved [[texture(2)]],
                                  texture2d<float> inked [[texture(3)]],
                                  texture2d<float> sheet [[texture(4)]]) {
    float2 p = (in.position.xy - u.transform.xy) / u.transform.z;   // canvas units
    float2 c = p / w.grid.z;                                         // cells
    float2 size = w.grid.xy;
    float now = u.time.x;
    float view = w.view.x;
    bool onSheet = all(c >= 0.0) && all(c <= size);

    if (view > 2.5) {
        // The print, the right way round, on its paper with a margin.
        float2 f = float2(size.x - c.x, c.y);
        float3 col = onSheet ? wbSheetFace(f, w, WB_PASS) : wbWashi(c);
        return float4(col, 1);
    }
    if (view < 0.5) return float4(wbBlock(c, w, WB_PASS, u), 1);

    // The sheet: a little bigger than the picture, laid from above when the step began.
    float m = w.grid.w / w.grid.z;
    float drop = w.anim.w > 0.5 ? 1.0 : saturate((now - w.anim.z) / 0.45);
    float ease = 1.0 - pow(1.0 - drop, 3.0);
    float2 sc = c - float2(0, (1.0 - ease) * -size.y * 0.08);
    bool underSheet = all(sc >= -m * 0.35) && all(sc <= size + m * 0.35);
    float3 block = wbBlock(c, w, WB_PASS, u);
    float shadow = 1.0 - 0.35 * ease * smoothstep(m * 0.6, 0.0, max(max(-sc.x - m * 0.35, sc.x - size.x - m * 0.35), max(-sc.y - m * 0.35, sc.y - size.y - m * 0.35)));
    if (view < 1.5) {
        if (!underSheet) return float4(block * shadow, 1);
        float3 back = wbSheetBack(sc, w, WB_PASS);
        return float4(mix(block, back, ease), 1);
    }

    // Peeling from the print's bottom right corner (the block's bottom left): everything past the
    // fold is lifted; the flap, folded back over the sheet, shows the sheet's face.
    // A peel held still (demos) gives its place as a negative duration.
    float prog = w.anim.y < 0.0 ? -w.anim.y : (w.anim.w > 0.5 ? 1.0 : saturate((now - w.anim.x) / max(w.anim.y, 1e-3)));
    prog = prog * prog * (3.0 - 2.0 * prog);
    float2 corner = float2(-m * 0.35, size.y + m * 0.35);
    float2 nrm = normalize(float2(1.0, -1.0));
    float reach = dot(float2(size.x + m * 0.35, -m * 0.35) - corner, nrm);
    float fold = prog * reach * 1.02;
    float along = dot(c - corner, nrm);
    float2 mirrorP = c - 2.0 * (along - fold) * nrm;
    bool sheetHere = all(c >= -m * 0.35) && all(c <= size + m * 0.35);
    bool flapHere = along > fold && all(mirrorP >= -m * 0.35) && all(mirrorP <= size + m * 0.35)
        && dot(mirrorP - corner, nrm) < fold;
    if (flapHere) {
        float3 face = all(mirrorP >= 0.0) && all(mirrorP <= size) ? wbSheetFace(mirrorP, w, WB_PASS) : wbWashi(mirrorP);
        float lift = smoothstep(0.0, m * 2.0, along - fold);
        return float4(face * (0.86 + 0.14 * lift), 1);
    }
    if (along < fold || !sheetHere) {
        // The block, the sheet's shadow falling short of the fold.
        float shade = sheetHere ? 1.0 - 0.3 * smoothstep(m * 1.5, 0.0, fold - along) : 1.0;
        return float4(block * shade, 1);
    }
    return float4(wbSheetBack(c, w, WB_PASS), 1);
}
