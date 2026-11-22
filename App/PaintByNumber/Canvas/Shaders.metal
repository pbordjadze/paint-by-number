#include <metal_stdlib>
using namespace metal;

// Canvas renderer shaders. Positions arrive in canvas units and are mapped to target pixels
// with `pixel = canvas * transform.z + transform.xy` (origin top-left, +y down). All colors
// are linear Display P3; the render targets are *_srgb so blending happens in linear light.

// Must match `CanvasUniforms` (CanvasTypes.swift).
struct FrameUniforms {
    float4 transform;   // xy: translation (px), z: px per canvas unit, w: px per point
    float4 viewport;    // xy: target size (px), zw: canvas size (units)
    float4 background;  // rgb: backdrop around the paper; no shader reads it (the time-lapse clears to it)
    float4 paper;       // rgb: unpainted paper, a: drop shadow opacity
    float4 ink;         // rgb: outline and number ink, a: outline opacity
    float4 selected;    // rgb: selected paint, a: 1 when a color is selected
    float4 accent;      // rgb: selected paint lifted to read on this paper, a: brightest hatch ink luminance
    float4 rim;         // rgb: rim just outside the sheet, a: its opacity (0 = none)
    float4 outline;     // x: width (px), y: selected width (px), z: hatch strength, w: numbers visibility
    float4 labels;      // x…y: legibility fade (font px), z: max font px, w: min font px of a bumped number
    float4 numbers;     // x: number opacity, y: selected-color number opacity, z: selected boldness, w: reduce motion
    float4 time;        // x: now, y: selection change, z: pulse start, w: bump start
    float4 brush;       // xy: position (px), z: radius (px), w: opacity
    float4 shine;       // x: start of a light sweep over finished paint, y: its color (-1 = all)
    int4   ids;         // x: selected color, y: hovered region, z: pulsing region, w: bumped region
    float4 photo;       // x: source photo opacity, y: the lantern's spread (0…1; < 0: none)
    float4 lineAlpha;   // ink opacity per line layer (x outline, y detail, z texture, w color)
    float4 lineWidth;   // line width (px) per layer
    float4 lineMode;    // x: 1 for a coloring book, y: how far its drawing's ink has gone (0 shown, 1 gone; writing stays)
    float4 lightInk;    // rgb: the tone writing over a dark paint draws in once its region is painted
};

// Must match `RegionState` (CanvasTypes.swift).
struct RegionState {
    float2 origin;      // where the paint starts spreading (canvas units)
    float start;        // seconds (renderer clock)
    float duration;     // seconds
    float radius;       // distance from origin to the farthest point of the region
    float painted;      // 1 painted, 0 not (fading out while `now < start + duration`)
    float seed;         // per-region variation of the paint front
    float mode;         // a mode's own value (CanvasMode; Stained Glass: its glass + 1), else 0
};

// Must match `GlyphInstance` (CanvasTypes.swift).
struct GlyphInstance {
    float2 center;      // label centre (canvas units)
    float size;         // font size that fits the label (canvas units)
    float offset;       // pen position of this glyph relative to the run centre (em)
    uint digit;
    uint region;
};

constant float kWetSettle = 0.7;
constant float kLightWriting = 4.0;      // OutlineGeometry.lightWritingMark (CanvasScene's line layers)
constant float kWriting = 8.0;           // OutlineGeometry.writingMark: any other writing
constant uint kOutside = 0xFFFFFFFFu;    // BoundaryEdge.outside (PaintCore): no region on that side

static float4 toClip(float2 px, constant FrameUniforms &u) {
    return float4(px.x / u.viewport.x * 2.0 - 1.0, 1.0 - px.y / u.viewport.y * 2.0, 0.0, 1.0);
}

static float2 toPixels(float2 canvas, constant FrameUniforms &u) {
    return canvas * u.transform.z + u.transform.xy;
}

// MARK: - Paint

struct PaintSample {
    float coverage;     // 0 paper … 1 paint
    float wet;          // 1 while spreading, eases to 0 as the paint settles
    float rim;          // bright meniscus riding the leading edge
};

static PaintSample samplePaint(RegionState s, float2 p, float now, float unitsPerPixel) {
    PaintSample o;
    o.coverage = 0.0; o.wet = 0.0; o.rim = 0.0;
    float t = (now - s.start) / max(s.duration, 1e-4);
    if (s.painted < 0.5) {
        o.coverage = 1.0 - smoothstep(0.0, 1.0, t);
        return o;
    }
    if (t >= 1.0) {
        float settle = saturate((now - s.start - s.duration) / kWetSettle);
        o.coverage = 1.0;
        o.wet = (1.0 - settle) * (1.0 - settle);
        return o;
    }
    float e = 1.0 - pow(1.0 - saturate(t), 3.0);
    float2 d = p - s.origin;
    float dist = length(d);
    float angle = atan2(d.y, d.x);
    // An organic, slightly lobed front that rounds out as it spreads.
    float wobble = 1.0 + (0.05 * sin(5.0 * angle + s.seed) + 0.035 * sin(9.0 * angle - 1.7 * s.seed)) * (1.0 - e);
    float soft = max(s.radius * 0.1, 2.0 * unitsPerPixel);
    float front = e * (s.radius + soft) * 1.12 * wobble;
    o.coverage = 1.0 - smoothstep(front - soft, front, dist);
    float x = (dist - (front - soft * 0.7)) / (soft * 0.5);
    o.rim = exp(-x * x) * o.coverage;
    o.wet = 1.0;
    return o;
}

/// 0 → 1 as a region becomes painted (1 → 0 while it is being un-painted).
static float paintedAmount(RegionState s, float now) {
    float t = saturate((now - s.start) / max(s.duration, 1e-4));
    return s.painted > 0.5 ? smoothstep(0.3, 1.0, t) : 1.0 - smoothstep(0.0, 1.0, t);
}

static float3 wetPaint(float3 paint, PaintSample ps) {
    float3 c = paint * (1.0 - 0.12 * ps.wet);   // wet paint reads a little deeper
    float3 sheen = min(paint * 1.3 + 0.07, float3(1.0));
    return mix(c, sheen, ps.rim * 0.4);
}

/// Unpainted regions of the selected color: a light tint of the paint plus fine diagonal
/// hatching in screen space that glides in when the color is picked, then rests. Both scale with
/// the hatch strength (`outline.z`), which eases in on a painting just handed over to.
static float3 highlightPaper(float3 paper, float2 pt, constant FrameUniforms &u) {
    float3 sel = u.accent.rgb;
    float since = max(u.time.x - u.time.y, 0.0);
    float intro = exp(-since * 2.5);
    float phase = 6.0 * (1.0 - exp(-since * 1.8));
    float lum = dot(sel, float3(0.2126, 0.7152, 0.0722));
    float3 ink = lum > u.accent.a ? sel * (u.accent.a / lum) : sel;
    float3 tint = mix(paper, sel, (0.14 + 0.12 * intro) * u.outline.z);
    const float period = 6.0;                       // points
    float w = (pt.x + pt.y) * 0.70710678 + phase;
    float d = abs(fract(w / period) - 0.5) * period;
    float aa = 0.5 / u.transform.w;                 // half a pixel, in points
    float line = 1.0 - smoothstep(0.6 - aa, 0.6 + aa, d);
    return mix(tint, mix(paper, ink, 0.55 + 0.25 * intro), line * u.outline.z);
}

// Under Reduce Motion (`still`) the highlight shows at once and fades instead of throbbing.
static float pulse(float t, bool still) {
    if (t < 0.0 || t > 2.0) return 0.0;
    float wave = still ? 1.0 : 0.5 - 0.5 * cos(t * 6.2831853 / 0.66);
    return wave * (1.0 - t / 2.0);
}

// MARK: - Paper and shadow

struct RectOut {
    float4 position [[position]];
};

vertex RectOut canvasRectVertex(uint vid [[vertex_id]],
                                constant FrameUniforms &u [[buffer(0)]],
                                constant float &margin [[buffer(1)]]) {
    float2 lo = u.transform.xy - margin;
    float2 hi = u.transform.xy + u.viewport.zw * u.transform.z + margin;
    float2 p = float2((vid & 1u) != 0u ? hi.x : lo.x, (vid & 2u) != 0u ? hi.y : lo.y);
    RectOut o;
    o.position = toClip(p, u);
    return o;
}

static float boxDistance(float2 p, float2 center, float2 halfSize) {
    float2 q = abs(p - center) - halfSize;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

fragment float4 paperFragment(RectOut in [[stage_in]], constant FrameUniforms &u [[buffer(0)]]) {
    float pt = u.transform.w;
    float2 lo = u.transform.xy;
    float2 hi = lo + u.viewport.zw * u.transform.z;
    float2 center = 0.5 * (lo + hi);
    float2 halfSize = 0.5 * (hi - lo);
    float2 p = in.position.xy;
    float sd = boxDistance(p, center, halfSize);
    float paper = saturate(0.5 - sd);
    // A soft ambient shadow (offset down) plus a tight contact shadow.
    float ambient = boxDistance(p, center + float2(0.0, 4.0 * pt), halfSize);
    float blur = 22.0 * pt;
    float a = 1.0 - smoothstep(-0.3 * blur, blur, ambient);
    float contact = 1.0 - smoothstep(-0.5 * pt, 2.5 * pt, boxDistance(p, center + float2(0.0, 0.75 * pt), halfSize));
    float shadow = u.paper.a * (0.6 * a * a + 0.4 * contact);
    float alpha = paper + (1.0 - paper) * shadow;
    // Dark paper has no visible shadow: a one-pixel light rim outside the edge outlines it.
    float rim = u.rim.a * saturate(1.0 - abs(sd - 1.0)) * (1.0 - paper);
    // Premultiplied; the shadow is black.
    return float4(u.paper.rgb * paper + u.rim.rgb * rim, alpha + (1.0 - alpha) * rim);
}

// MARK: - Fills

struct FillOut {
    float4 position [[position]];
    float2 canvas;
    uint region [[flat]];
};

vertex FillOut fillVertex(uint vid [[vertex_id]],
                          const device float2 *positions [[buffer(0)]],
                          const device uint *vertexRegion [[buffer(1)]],
                          constant FrameUniforms &u [[buffer(2)]]) {
    float2 p = positions[vid];
    FillOut o;
    o.position = toClip(toPixels(p, u), u);
    o.canvas = p;
    o.region = vertexRegion[vid];
    return o;
}

fragment float4 fillFragment(FillOut in [[stage_in]],
                             const device float4 *regionColors [[buffer(0)]],
                             const device RegionState *states [[buffer(1)]],
                             constant FrameUniforms &u [[buffer(2)]]) {
    uint r = in.region;
    float4 info = regionColors[r];
    RegionState s = states[r];
    float now = u.time.x;
    PaintSample ps = samplePaint(s, in.canvas, now, 1.0 / u.transform.z);

    float3 base = u.paper.rgb;
    int colorIndex = int(info.w + 0.5);
    if (u.selected.a > 0.5 && colorIndex == u.ids.x && ps.coverage < 1.0) {
        base = highlightPaper(base, in.position.xy / u.transform.w, u);
    }
    if (int(r) == u.ids.y) {
        base = mix(base, u.accent.rgb, 0.3);
    }
    if (int(r) == u.ids.z) {
        base = mix(base, u.accent.rgb, 0.6 * pulse(now - u.time.z, u.numbers.w > 0.5));
    }
    float3 paint = wetPaint(info.rgb, ps);
    // A color (or the whole painting) was just finished: a glossy band sweeps across it.
    float since = now - u.shine.x;
    if (since >= 0.0 && since < 1.1 && (u.shine.y < 0.0 || int(u.shine.y + 0.5) == colorIndex)) {
        float2 pt = in.position.xy / u.transform.w;
        float span = (u.viewport.x + u.viewport.y) / u.transform.w * 0.70710678;
        float head = mix(-160.0, span + 160.0, smoothstep(0.0, 1.1, since));
        float x = ((pt.x + pt.y) * 0.70710678 - head) / 70.0;
        paint = mix(paint, min(paint * 1.3 + 0.1, float3(1.0)), 0.55 * exp(-x * x));
    }
    float3 c = mix(base, paint, ps.coverage);
    return float4(c, 1.0);
}

// MARK: - Stained Glass's mode

// Must match `GlassMode.Parameters` (GlassMode.swift).
struct GlassParameters {
    float4 lead;        // rgb: the lead (sRGB-curved), w: its width on average (canvas units)
    float4 lens;        // x: the lens's rim (canvas units), y: how many glasses there are, z: how far past white lit glass may go (0: not at all), w: 1 when real Liquid Glass lies over the glazed pieces (`GlassMode.lensesCovered`)
};

// Must match `GlassMode.Light` (GlassMode.swift).
struct GlassLight {
    float4 sun;         // x: start (renderer clock), y: duration, z: where a demo holds it (0…1; < 0: none), w: 1 while it may pass
    float4 day;         // rgb: the hour's light, added; w: how much it dims the window (night)
    float4 dayFrom;     // x: when the hour's light starts to come (renderer clock), y: 1 while it shows
    float4 glow;        // x: when the glow past white starts to come, over the sun's pass (renderer clock), y: 1 while the window is whole
};

// Smooth value noise, 0…1, on the integer lattice.
static float latticeHash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static float valueNoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 w = f * f * (3.0 - 2.0 * f);
    return mix(mix(latticeHash(i), latticeHash(i + float2(1, 0)), w.x),
               mix(latticeHash(i + float2(0, 1)), latticeHash(i + float2(1, 1)), w.x), w.y);
}

static float3 curveEncode(float3 c) {
    c = max(c, 0.0);
    return select(1.055 * pow(c, 1.0 / 2.4) - 0.055, c * 12.92, c <= 0.0031308);
}

static float3 curveDecode(float3 c) {
    c = max(c, 0.0);
    return select(pow((c + 0.055) / 1.055, 2.4), c / 12.92, c <= 0.04045);
}

/// Light through poured glass: its glass tinting the photo seen through the lens, never covering
/// it (its light and its detail come through), brighter deep in the piece and streaked.
static float3 pouredGlass(float3 glass, float3 seen, float3 detail, float glow) {
    float luma = (seen.r + seen.g + seen.b) / 3.0;
    return (glass * (0.45 + 0.85 * luma) + detail * 1.4 + seen * 0.12) * glow;
}

/// A piece of a Stained Glass window (painting-company row 366) as Liquid Glass misused: every
/// piece a clear lens over the photo, flat inside and rounded at its rim, where it bends the photo
/// in from the lead and catches light from the top left, a thin bright line all round; a glass
/// poured into it tints the lens, from the touch over the glass before it. The lead stays heavy
/// medieval came. A piece not yet framed (led in by the painter, `GlassFraming`) is the photo
/// dimmed behind plain glass, a thin line round it where its lead will go. `states[r].mode` is the
/// glass + 1, plus 1024 × (the glass it replaces + 1), plus 2^20 once framed. The
/// fields texture is `GlassTexture.fields()` (lead distance, shade, depth, grain), the photo
/// texture the window's photo at the template's size, mipmapped. On a canvas drawing past white
/// (`ExtendedRange`) a whole window's poured glass glows brighter than white as the sun passes
/// (`lens.z`, `GlassLight.glow`), deepest inside each piece; everything else stays within white.
fragment float4 glassFillFragment(FillOut in [[stage_in]],
                                  const device RegionState *states [[buffer(1)]],
                                  constant FrameUniforms &u [[buffer(2)]],
                                  const device float4 *glasses [[buffer(3)]],
                                  constant GlassParameters &g [[buffer(4)]],
                                  constant GlassLight &l [[buffer(5)]],
                                  texture2d<float> fields [[texture(0)]],
                                  texture2d<float> photo [[texture(1)]]) {
    constexpr sampler linear(filter::linear, mip_filter::linear, address::clamp_to_edge);
    uint r = in.region;
    RegionState s = states[r];
    float2 size = u.viewport.zw;
    float2 uv = in.canvas / size;
    float4 f = fields.sample(linear, uv);
    // The lead: half on each side of the edge (a piece's edge pixels are 1 away), uneven as cast
    // by hand.
    float d = f.x - 0.5;
    uint code = uint(max(s.mode, 0.0) + 0.5);
    bool framed = code >= 1048576u;
    code %= 1048576u;
    float halfWidth = framed ? 0.5 * g.lead.w * (0.8 + 0.4 * valueNoise(in.canvas / (2.5 * g.lead.w)))
                             : max(0.7, 0.06 * g.lead.w);
    // The lens: 0 at the lead, 1 past its rim; the way into the piece from the lead's distance.
    float rim = max(g.lens.x, 1.0);
    float inner = saturate((d - halfWidth) / rim), t = 1.0 - inner;
    // Measured a quarter of the rim apart: the chamfer's distance turns in steps, and nearer
    // its normals streaked the rim.
    float2 e = float2(0.25 * rim, 0.0) / size;
    float2 n = float2(fields.sample(linear, uv + e.xy).x - fields.sample(linear, uv - e.xy).x,
                      fields.sample(linear, uv + e.yx).x - fields.sample(linear, uv - e.yx).x);
    float slope = length(n);
    n = slope > 1e-4 ? n / slope : float2(0.0);
    // A glass past the last offered (never written so) reads as the last.
    uint count = uint(max(g.lens.y, 1.0));
    uint now = min(code % 1024u, count), before = min(code / 1024u, count);
    // The rim pulls the photo in from deeper in the piece; under real glass (a glazed piece's), the
    // glass does. A piece just poured keeps its own lens until its pane has materialized over it
    // (`GlassPanes.arrivalDuration`), or the photo showed flat and dark under no glass at all.
    float covered = g.lens.w > 0.5 && now > 0u ? smoothstep(0.3, 0.8, u.time.x - s.start) : 0.0;
    float2 seenAt = (in.canvas + n * pow(t, 2.2) * rim * 1.1 * (1.0 - covered)) / size;
    float3 seen = curveEncode(photo.sample(linear, seenAt, bias(0.5)).rgb) * 0.94 + 0.05;
    float3 soft = curveEncode(photo.sample(linear, seenAt, level(3.0)).rgb) * 0.94 + 0.05;
    float3 detail = seen - soft;
    // Darker toward the rim, as light through a thick edge; real glass shades its own, so under
    // it the color stays even out to the lead.
    float glow = mix(0.55 + 0.6 * pow(inner, 1.5), 1.15, covered) * (0.9 + 0.1 * f.y);
    float3 lit = now > 0u ? pouredGlass(curveEncode(glasses[now - 1u].rgb), seen, detail, glow) : seen;
    float3 under = before > 0u ? pouredGlass(curveEncode(glasses[before - 1u].rgb), seen, detail, glow) : seen;
    PaintSample ps = samplePaint(s, in.canvas, u.time.x, 1.0 / u.transform.z);
    float3 c = mix(under, lit, ps.coverage);
    if (!framed) {
        // Waiting for its lead: the photo flat and dim, a thin line round it.
        float3 flat = curveEncode(photo.sample(linear, uv, bias(0.5)).rgb);
        float grey = dot(flat, float3(0.3, 0.59, 0.11));
        c = mix(float3(grey), flat, 0.55) * 0.5 + 0.03;
        float aa = max(fwidth(d), 1e-3);
        c = mix(c, float3(0.62, 0.58, 0.52), 1.0 - smoothstep(halfWidth - aa, halfWidth + aa, d));
        return float4(curveDecode(c), 1.0);
    }
    // Light on the rim from the top left, a thin bright line all round, its shade at the bottom right.
    // Real glass lights its own rim.
    if (covered < 1.0) {
        float facing = saturate(-(n.x + n.y) * 0.70710678);
        float t3 = t * t * t;
        float sigma = rim / 26.0, off = inner * rim - 2.5 * sigma;
        c += (1.0 - covered) * (t3 * facing * facing * 0.9 + 0.35 * exp(-off * off / (2.0 * sigma * sigma))
                                - t3 * saturate((n.x + n.y) * 0.70710678) * 0.12);
    }
    // The came, its rounded face catching a soft sheen.
    float aa = max(fwidth(d), 1e-3);
    float across = saturate(d / halfWidth);
    float crown = (across - 0.38) / 0.22;
    float3 came = g.lead.rgb * (1.0 + 2.2 * exp(-crown * crown) - 0.35 * smoothstep(0.75, 1.0, across));
    float leaded = 1.0 - smoothstep(halfWidth - aa, halfWidth + aa, d);
    c = mix(c, came, leaded);
    // White at most, as an 8-bit target holds it, so only the glow below goes past it.
    float3 lin = curveDecode(saturate(c));
    if (g.lens.z > 0.0 && l.glow.y > 0.5 && now > 0u) {
        float k = smoothstep(l.glow.x, l.glow.x + max(l.sun.y, 1e-3), u.time.x);
        lin *= 1.0 + g.lens.z * k * ps.coverage * (1.0 - leaded) * (0.4 + 0.6 * inner);
    }
    return float4(lin, 1.0);
}


/// Light over a Stained Glass window, drawn on the sheet (canvasRectVertex, margin 0): light from
/// behind, brightest a little above the middle; once the window is whole the sun passing behind
/// it, a band crossing it corner to corner (the line x + 0.6 y), and then the hour's light,
/// coming over it in `GlassMode.dayFade` seconds (premultiplied: rgb added, alpha dims).
fragment float4 glassLightFragment(RectOut in [[stage_in]],
                                   constant FrameUniforms &u [[buffer(0)]],
                                   constant GlassLight &l [[buffer(1)]]) {
    float2 size = u.viewport.zw;
    float2 p = (in.position.xy - u.transform.xy) / u.transform.z;
    float reach = 0.7 * max(size.x, size.y);
    float glow = 0.14 * saturate(1.0 - length(p - float2(0.5 * size.x, 0.4 * size.y)) / reach);
    float3 light = float3(glow * 0.3);
    float4 sun = l.sun;
    float t = sun.z >= 0.0 ? sun.z : (u.time.x - sun.x) / max(sun.y, 1e-3);
    if (sun.w > 0.5 && t > 0.0 && t < 1.0) {
        float band = 0.6 * size.x, depth = band * 1.36;
        float front = -depth + (size.x + 0.6 * size.y + depth) * t;
        float s = (p.x + 0.6 * p.y - front) / depth;
        float a = 0.42 * sin(3.14159265 * t) * saturate(1.0 - abs(2.0 * s - 1.0));
        light += float3(1.0, 0.95, 0.8) * a * 0.45;
    }
    float dim = 0.0;
    if (l.dayFrom.y > 0.5) {
        float k = smoothstep(0.0, 1.5, u.time.x - l.dayFrom.x);
        light += l.day.rgb * k * (0.6 + 0.4 * glow / 0.14);
        dim = l.day.w * k;
    }
    return float4(light, dim);
}

// MARK: - Outlines

// Pass 1: capsule segments expanded in screen space write ink opacity (r) into an RG16F target
// with MAX blending, so overlapping caps and joints never double-darken, and in g the share of
// it that is in the light tone.
//
// A segment belongs to a line: a boundary edge, or a stroke drawn inside a cell (line art, after
// the edges, with its region on both sides). Each line draws with its layer's opacity and width;
// classic templates put every line in layer 0, which is the classic line. A coloring book
// (lineMode.x) is a drawing over the paint: its lines never dissolve, and the selected color's
// cells are not outlined (the fill's highlight shows them); its color edges have no ink
// (lineAlpha.w = 0). Writing over a dark paint (a stroke whose layer carries `kLightWriting`,
// `OutlineGeometry.lightWritingMark`) is drawn in the light tone `lightInk` as its region is
// painted, so it reads on the paint instead of vanishing into it. A finished book shown without
// its ink (lineMode.y) keeps only its writing (either mark), which no paint draws.

struct OutlineOut {
    float4 position [[position]];
    float4 ends [[flat]];       // segment endpoints (px)
    float halfWidth [[flat]];
    float alpha [[flat]];
    float light [[flat]];       // 0…1: how far the ink has turned to the light tone
};

vertex OutlineOut outlineVertex(uint vid [[vertex_id]],
                                uint iid [[instance_id]],
                                const device float2 *points [[buffer(0)]],
                                const device uint2 *segments [[buffer(1)]],
                                const device uint2 *lineRegions [[buffer(2)]],
                                const device RegionState *states [[buffer(3)]],
                                const device float4 *regionColors [[buffer(4)]],
                                constant FrameUniforms &u [[buffer(5)]],
                                const device float *lineLayers [[buffer(6)]]) {
    OutlineOut o;
    uint2 seg = segments[iid];
    uint2 nb = lineRegions[seg.y];
    float rawLayer = lineLayers[seg.y];
    bool writing = rawLayer > kLightWriting - 0.5;
    bool lightWriting = writing && rawLayer < kWriting - 0.5;
    uint layer = min(uint(rawLayer - (lightWriting ? kLightWriting : writing ? kWriting : 0.0) + 0.5), 3u);
    float now = u.time.x;
    bool book = u.lineMode.x > 0.5;
    float left = paintedAmount(states[nb.x], now);
    float right = nb.y == kOutside ? 1.0 : paintedAmount(states[nb.y], now);
    // Classic edges between two painted regions dissolve, so finished areas read as a painting;
    // a coloring book's drawing stays over the paint whole.
    float visible = book ? 1.0 : 1.0 - min(left, right);
    // A classic template outlines the selected color's unpainted cells boldly, so every cell to
    // paint stands out. In a coloring book nothing is outlined for being selected: the drawing is
    // the drawing (strokes inside cells only come with one).
    bool hasSelection = u.selected.a > 0.5 && !book;
    bool selLeft = hasSelection && int(regionColors[nb.x].w + 0.5) == u.ids.x && left < 1.0;
    bool selRight = hasSelection && nb.y != kOutside && int(regionColors[nb.y].w + 0.5) == u.ids.x && right < 1.0;
    bool selected = selLeft || selRight;
    float lineWidth = u.lineWidth[layer];
    float lineAlpha = u.lineAlpha[layer];
    float width = selected ? max(u.outline.y, lineWidth) : lineWidth;
    // Thinner than a pixel: keep one pixel and fade instead, so lines never shimmer.
    float drawn = max(width, 1.0);
    // As strong as the selection shows (the hatch strength, which eases in on a painting just
    // handed over to; the selected width eases with it, `CanvasLook`).
    float strong = selected ? u.outline.z : 0.0;
    float alpha = mix(lineAlpha, max(lineAlpha, u.ink.a) * 1.3, strong) * visible * (width / drawn);
    // The finished picture without its ink: every line but the writing fades with `lineMode.y`.
    if (book && !writing) alpha *= 1.0 - saturate(u.lineMode.y);
    float hw = 0.5 * drawn;

    float2 a = toPixels(points[seg.x], u);
    float2 b = toPixels(points[seg.x + 1], u);
    float2 ab = b - a;
    float len = length(ab);
    float2 dir = len > 1e-5 ? ab / len : float2(1.0, 0.0);
    float2 nrm = float2(-dir.y, dir.x);
    float ext = hw + 1.0;
    float2 corner = ((vid & 1u) != 0u ? b + dir * ext : a - dir * ext) + nrm * ((vid & 2u) != 0u ? ext : -ext);
    o.position = alpha < 0.002 ? float4(-2.0, -2.0, 0.0, 1.0) : toClip(corner, u);
    o.ends = float4(a, b);
    o.halfWidth = hw;
    o.alpha = min(alpha, 1.0);
    // A stroke lies in one region (both sides), so `left` is how far the paint has covered it.
    o.light = lightWriting ? left : 0.0;
    return o;
}

fragment float4 outlineFragment(OutlineOut in [[stage_in]]) {
    float2 p = in.position.xy;
    float2 a = in.ends.xy;
    float2 ba = in.ends.zw - a;
    float2 pa = p - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    float d = length(pa - ba * h);
    float coverage = saturate(in.halfWidth + 0.5 - d) * in.alpha;
    return float4(coverage, coverage * in.light, 0.0, 0.0);
}

// Pass 2: composite the ink opacity over the fills, in the ink or, where writing over a dark paint
// is, the light tone it has turned to.
fragment float4 outlineCompositeFragment(RectOut in [[stage_in]],
                                         texture2d<half, access::read> coverage [[texture(0)]],
                                         constant FrameUniforms &u [[buffer(0)]]) {
    float2 c = float2(coverage.read(uint2(in.position.xy)).rg);
    float a = c.x;
    float light = a > 0.0 ? saturate(c.y / a) : 0.0;
    return float4(mix(u.ink.rgb, u.lightInk.rgb, light) * a, a);
}

// MARK: - Numbers

struct GlyphOut {
    float4 position [[position]];
    float2 uv;
    float alpha [[flat]];
    float weight [[flat]];
};

vertex GlyphOut glyphVertex(uint vid [[vertex_id]],
                            uint iid [[instance_id]],
                            const device GlyphInstance *glyphs [[buffer(0)]],
                            constant float4 *digitRects [[buffer(1)]],
                            constant float4 *digitUVs [[buffer(2)]],
                            const device RegionState *states [[buffer(3)]],
                            const device float4 *regionColors [[buffer(4)]],
                            constant FrameUniforms &u [[buffer(5)]]) {
    GlyphInstance g = glyphs[iid];
    float now = u.time.x;
    float fontPx = g.size * u.transform.z;
    float legible = smoothstep(u.labels.x, u.labels.y, fontPx);
    fontPx = min(fontPx, u.labels.z);
    // A number tapped with the wrong paint pops up so it can be read at any zoom. Under
    // Reduce Motion it shows at the larger size at once and fades out instead of scaling.
    float bump = 0.0;
    if (int(g.region) == u.ids.w) {
        float t = now - u.time.w;
        if (t >= 0.0 && t < 1.4) {
            bool still = u.numbers.w > 0.5;
            float fade = 1.0 - smoothstep(0.8, 1.4, t);
            bump = (still ? 1.0 : sin(min(t / 0.16, 1.0) * 1.5707963)) * fade;
            fontPx = mix(fontPx, max(fontPx * 1.3, u.labels.w), still ? 1.0 : bump);
        }
    }
    PaintSample ps = samplePaint(states[g.region], g.center, now, 1.0 / u.transform.z);
    bool selected = u.selected.a > 0.5 && int(regionColors[g.region].w + 0.5) == u.ids.x;
    // The selected color's numbers stand out as much as its hatch shows.
    float emphasis = selected ? u.outline.z : 0.0;
    float visibility = max(legible * u.outline.w, bump);
    float alpha = visibility * (1.0 - ps.coverage) * (bump > 0.0 ? u.numbers.y : mix(u.numbers.x, u.numbers.y, emphasis));

    float4 rect = digitRects[g.digit];
    float4 uvRect = digitUVs[g.digit];
    float2 corner = float2((vid & 1u) != 0u ? 1.0 : 0.0, (vid & 2u) != 0u ? 1.0 : 0.0);
    float2 em = float2(g.offset, 0.0) + mix(rect.xy, rect.zw, corner);
    float2 p = toPixels(g.center, u) + em * fontPx;
    GlyphOut o;
    o.position = alpha < 0.004 ? float4(-2.0, -2.0, 0.0, 1.0) : toClip(p, u);
    o.uv = mix(uvRect.xy, uvRect.zw, corner);
    o.alpha = alpha;
    o.weight = u.numbers.z * emphasis;
    return o;
}

fragment float4 glyphFragment(GlyphOut in [[stage_in]],
                              texture2d<float> atlas [[texture(0)]],
                              constant FrameUniforms &u [[buffer(0)]]) {
    constexpr sampler bilinear(filter::linear, address::clamp_to_edge);
    float d = atlas.sample(bilinear, in.uv).r;
    float w = max(fwidth(d), 1e-3) * 0.7;
    float edge = 0.5 - in.weight;
    float a = smoothstep(edge - w, edge + w, d) * in.alpha;
    return float4(u.ink.rgb * a, a);
}

// MARK: - Source photo

// The photo the painting was made from, over the canvas rect (drawn with canvasRectVertex,
// margin 0). UVs come from the same transform as the fills, so it lines up exactly at any
// zoom and pan; mipmaps keep zoomed-out views free of aliasing.
fragment float4 photoFragment(RectOut in [[stage_in]],
                              texture2d<float> photo [[texture(0)]],
                              constant FrameUniforms &u [[buffer(0)]]) {
    constexpr sampler trilinear(filter::linear, mip_filter::linear, address::clamp_to_edge);
    float2 uv = (in.position.xy - u.transform.xy) / (u.viewport.zw * u.transform.z);
    float a = u.photo.x;
    // The lantern (painting-company row 351): the photo inside a soft circle that grows from the
    // middle of the page's top edge until it covers the page.
    if (u.photo.y >= 0) {
        float2 size = u.viewport.zw * u.transform.z;
        float2 centre = u.transform.xy + float2(size.x * 0.5, 0);
        float feather = 0.18 * min(size.x, size.y) + 1;
        float r = u.photo.y * (length(float2(size.x * 0.5, size.y)) + feather);
        a *= 1 - smoothstep(r - feather, r, distance(in.position.xy, centre));
    }
    return float4(photo.sample(trilinear, uv).rgb * a, a);     // premultiplied
}

// MARK: - Brush (drag painting)

vertex RectOut brushVertex(uint vid [[vertex_id]], constant FrameUniforms &u [[buffer(0)]]) {
    float r = u.brush.z + 3.0 * u.transform.w;
    float2 p = u.brush.xy + float2((vid & 1u) != 0u ? r : -r, (vid & 2u) != 0u ? r : -r);
    RectOut o;
    o.position = toClip(p, u);
    return o;
}

fragment float4 brushFragment(RectOut in [[stage_in]], constant FrameUniforms &u [[buffer(0)]]) {
    float pt = u.transform.w;
    float d = distance(in.position.xy, u.brush.xy);
    float r = u.brush.z;
    float inside = 1.0 - smoothstep(r - 0.5, r + 0.5, d);
    float ring = saturate(1.0 - abs(d - r) / (0.9 * pt));
    float halo = saturate(1.0 - abs(d - r - 1.4 * pt) / (0.8 * pt));
    // Premultiplied: a tinted disc, a white rim and a faint dark halo for contrast on light paint.
    float fill = 0.28 * inside * (1.0 - ring);
    float3 rgb = u.selected.rgb * fill + float3(0.95 * ring);
    float a = fill + 0.95 * ring + 0.25 * halo * (1.0 - ring);
    return float4(rgb, a) * u.brush.w;
}
