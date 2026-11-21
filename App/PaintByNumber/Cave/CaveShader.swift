#if UNRELEASED
import Foundation

/// The cave's Metal source (painting-company row 371), compiled when the cave first opens
/// (`CaveRenderer`), so the release's library carries nothing of it.
///
/// `caveWall` lights the wall: each pixel's wall point found from the camera, the relief's normal
/// with the limestone's grain on it, the rock's color with the pigment soaked into its mottle
/// (the charcoal stays over the paint), soot above, then the torch, the only real light: a warm
/// point light that flickers, its light wrapped a little round the bulges and shut out behind
/// them by a soft shadow marched over the relief toward the flame, so the shadows sway as it
/// moves; the fat lamp's small steady light by the tools; a few calcite crystals glinting as the
/// flame moves; the mouth's cold daylight on the rock near it and, through the opening, only
/// light. Past the cave's end the rock goes on into the dark.
///
/// The fossils (`CaveFossils`): Liquid Glass found in the rock. Each glass shape is a dome over a
/// signed distance; the rock under it is the rock at a point bent by the dome's slope (so the
/// grain and the pigment refract), its albedo crusted with calcite and split by a crack, and the
/// glass itself shows only as light: a highlight where its surface faces the torch or the sky,
/// a bright line along a rim that faces them. Unlit, it is as dark as the rock. The year wheel's
/// rows are cut into the relief itself (the carving texture), so they shade and cast shadows.
///
/// `caveSprite` draws what is in the air over it, in wall points: the torch's sticks, its flame
/// and glow, smoke, sparks, the lamp's flame, pigment dust, the grains round a waited-for hand.
/// Each sprite is a quad with a kind: a glow (light added, bright at its middle), a soft dot or
/// ellipse laid over, or a stick tapering to its foot.
nonisolated enum CaveShader {
    /// Bays held in the textures at once (`CaveRenderer`): each in slot `bay % slots`.
    static let slots = 8

    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct CaveUniforms {
        float4 view;    // drawable width, height (px), px per wall point, camera x (wall points)
        float4 torch;   // x, y, z, flicker
        float4 lamp;    // x, y, z, on (0 or 1)
        float4 mouth;   // x, y, flare (0 to 1), leaving (0 to 1, the daylight taking the screen)
        float4 misc;    // time (s), end of the cave (wall x), relief depth, steady (Reduce Motion)
        int4 slotsA;    // the bay held in slots 0 to 3, -1 for none
        int4 slotsB;    // in slots 4 to 7
    };

    struct Sprite {
        float4 place;   // centre x, y, axis 1 x, y (wall points)
        float4 axis;    // axis 2 x, y, kind, unused
        float4 inner;   // color at the middle (rgb), alpha
        float4 outer;   // color at the rim (rgb), alpha
    };

    constant float BAY = 400.0;
    constant float WALL = 852.0;
    constant int SLOTS = 8;

    // The fossils (CaveFossils).
    constant float2 PILL = float2(\(CaveFossils.pill.x), \(CaveFossils.pill.y));
    constant float2 PILL_AX = float2(0.9135, -0.4067);     // its long axis, rising 24°
    constant float2 CARVE_O = float2(\(CaveFossils.carvingOrigin.x), \(CaveFossils.carvingOrigin.y));
    constant float2 CARVE_S = float2(\(CaveFossils.carvingSize.x), \(CaveFossils.carvingSize.y));
    constant float2 BAND = float2(\(CaveFossils.carvingOrigin.x + CaveFossils.carvingSize.x / 2), \(CaveFossils.selectedRow));
    constant float CARVE_DEPTH = 0.55;

    struct WallOut { float4 position [[position]]; };

    vertex WallOut caveWallVertex(uint vid [[vertex_id]]) {
        float2 p = float2(float((vid << 1) & 2), float(vid & 2));
        WallOut o;
        o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
        return o;
    }

    static float hash21(float2 p) {
        p = fract(p * float2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }

    static float vnoise(float2 p) {
        float2 i = floor(p), f = fract(p);
        f = f * f * (3.0 - 2.0 * f);
        return mix(mix(hash21(i), hash21(i + float2(1, 0)), f.x), mix(hash21(i + float2(0, 1)), hash21(i + float2(1, 1)), f.x), f.y);
    }

    static int slotOf(int bay, constant CaveUniforms& u) {
        if (bay < 0) return -1;
        int s = bay % SLOTS;
        int held = s < 4 ? u.slotsA[s] : u.slotsB[s - 4];
        return held == bay ? s : -1;
    }

    // Where a wall point is in the textures, or a negative x when its bay isn't held.
    static float2 mapUV(float2 w, constant CaveUniforms& u) {
        int bay = int(floor(w.x / BAY));
        int s = slotOf(bay, u);
        if (s < 0) return float2(-1.0);
        float local = clamp(w.x - float(bay) * BAY, 0.25, BAY - 0.25);
        return float2((float(s) * BAY + local) / (float(SLOTS) * BAY), clamp(w.y, 0.25, WALL - 0.25) / WALL);
    }

    // How deep the year wheel's rows are cut at a wall point, 0 to 1.
    static float carved(float2 w, texture2d<float> carving, sampler smp) {
        float2 q = (w - CARVE_O) / CARVE_S;
        if (q.x < 0.0 || q.y < 0.0 || q.x > 1.0 || q.y > 1.0) return 0.0;
        return carving.sample(smp, q).r;
    }

    static float H(float2 w, texture2d<float> relief, texture2d<float> carving, sampler smp, constant CaveUniforms& u) {
        float2 uv = mapUV(w, u);
        return uv.x < 0.0 ? 0.0 : relief.sample(smp, uv).r - carved(w, carving, smp) * CARVE_DEPTH;
    }

    static float sdSegment(float2 p, float2 a, float2 b) {
        float2 pa = p - a, ba = b - a;
        float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
        return length(pa - ba * h);
    }

    // A glass dome over a signed distance (negative inside): a quarter circle `edge` wide at the
    // rim, flat beyond it.
    static float dome(float d, float edge) {
        float t = clamp(-d / edge, 0.0, 1.0);
        return edge * sqrt(max(1.0 - (1.0 - t) * (1.0 - t), 0.0));
    }

    // The "more" pill: a capsule with its three dots domed on it, the far end sunk under flowstone.
    static float pillGlass(float2 p) {
        float along = dot(p - PILL, PILL_AX);
        float d = sdSegment(p, PILL - PILL_AX * 30.0, PILL + PILL_AX * 30.0) - 22.0;
        if (d > 0.0) return 0.0;
        float h = dome(d, 10.0);
        for (int k = -1; k <= 1; k++) h += dome(length(p - PILL - PILL_AX * (float(k) * 18.0)) - 6.0, 4.0);
        float sunk = 24.0 + 22.0 * (vnoise(p * 0.08) - 0.5);
        return h * smoothstep(sunk + 1.5, sunk - 1.5, along);
    }

    // The wheel's selection band, a chip gone from its top right.
    static float bandGlass(float2 p) {
        float d = sdSegment(p, BAND - float2(78.0, 0.0), BAND + float2(78.0, 0.0)) - 16.0;
        d = max(d, 9.0 - length(p - BAND - float2(64.0, -19.0)));
        return d > 0.0 ? 0.0 : dome(d, 7.0);
    }

    static float glassAt(float2 p) {
        if (abs(p.x - PILL.x) < 62.0 && abs(p.y - PILL.y) < 50.0) return pillGlass(p);
        if (abs(p.x - BAND.x) < 100.0 && abs(p.y - BAND.y) < 24.0) return bandGlass(p);
        return 0.0;
    }

    // What the years have laid on the glass: x calcite (0 to 1), y a crack's darkness.
    static float2 fossilMarks(float2 p) {
        float crust = 0.0, crack = 1e3;
        if (abs(p.x - PILL.x) < 66.0 && abs(p.y - PILL.y) < 54.0) {
            float2 a = PILL_AX, c = float2(-PILL_AX.y, PILL_AX.x);
            float along = dot(p - PILL, a);
            float near = smoothstep(3.0, -1.0, sdSegment(p, PILL - a * 30.0, PILL + a * 30.0) - 22.0);
            crust = near * smoothstep(0.42, 0.62, vnoise(p * 0.11) + 0.42 - abs(along + 12.0) / 34.0);
            float2 k0 = PILL + a * -20.0 + c * -21.0, k1 = PILL + a * -11.0 + c * -7.0;
            float2 k2 = PILL + a * -15.0 + c * 5.0, k3 = PILL + a * -3.0 + c * 21.0, k4 = PILL + a * -1.0 + c * -6.0;
            crack = min(min(sdSegment(p, k0, k1), sdSegment(p, k1, k2)), min(sdSegment(p, k2, k3), sdSegment(p, k1, k4)));
        } else if (abs(p.x - BAND.x) < 104.0 && abs(p.y - BAND.y) < 28.0) {
            float near = smoothstep(3.0, -1.0, sdSegment(p, BAND - float2(78.0, 0.0), BAND + float2(78.0, 0.0)) - 16.0);
            crust = near * smoothstep(0.42, 0.62, vnoise(p * 0.13) + 0.45 - abs(p.x - BAND.x + 80.0) / 26.0);
            float2 k0 = BAND + float2(-40.0, -16.0), k1 = BAND + float2(-31.0, -5.0), k2 = BAND + float2(-35.0, 6.0), k3 = BAND + float2(-24.0, 16.0);
            crack = min(min(sdSegment(p, k0, k1), sdSegment(p, k1, k2)), sdSegment(p, k2, k3));
            crack = min(crack, sdSegment(p, k1, BAND + float2(-19.0, -9.0)));
        }
        float grain = 0.6 + 0.8 * vnoise(p * 1.9);
        return float2(clamp(crust * grain, 0.0, 1.0), smoothstep(1.1, 0.3, crack));
    }

    // The mouth's back chevron, on the daylight.
    static float chevronGlass(float2 p, float2 m) {
        float d = min(sdSegment(p, m + float2(18.0, -42.0), m + float2(-21.0, 0.0)), sdSegment(p, m + float2(-21.0, 0.0), m + float2(18.0, 42.0))) - 8.0;
        return d > 0.0 ? 0.0 : dome(d, 6.0);
    }

    fragment float4 caveWall(WallOut in [[stage_in]], constant CaveUniforms& u [[buffer(0)]],
                             texture2d<float> relief [[texture(0)]], texture2d<float> rock [[texture(1)]],
                             texture2d<float> pigment [[texture(2)]], texture2d<float> carving [[texture(3)]]) {
        constexpr sampler smp(filter::linear, address::clamp_to_edge);
        float2 screen = in.position.xy / u.view.xy;
        float2 w0 = in.position.xy / u.view.z + float2(u.view.w, 0.0);
        // Under fossil glass, the rock is seen bent by the dome's slope.
        float gh = glassAt(w0);
        float2 gs = float2(0.0);
        float2 w = w0;
        if (gh > 0.0) {
            gs = float2(glassAt(w0 + float2(0.5, 0)) - glassAt(w0 - float2(0.5, 0)), glassAt(w0 + float2(0, 0.5)) - glassAt(w0 - float2(0, 0.5)));
            float2 bend = gs * 5.0;
            float bl = length(bend);
            w = w0 - (bl > 7.0 ? bend * (7.0 / bl) : bend);
        }
        float2 uv = mapUV(w, u);
        if (uv.x < 0.0) return float4(0.0, 0.0, 0.0, 1.0);
        float HS = u.misc.z;
        float e = 0.5;
        float hx = H(w + float2(e, 0), relief, carving, smp, u) - H(w - float2(e, 0), relief, carving, smp, u);
        float hy = H(w + float2(0, e), relief, carving, smp, u) - H(w - float2(0, e), relief, carving, smp, u);
        // The limestone's grain, finer than the map.
        float g1 = vnoise(w * 1.7), g2 = vnoise(w * 1.7 + float2(0.37, 0)), g3 = vnoise(w * 1.7 + float2(0, 0.37));
        float n1 = vnoise(w * 5.3), n2 = vnoise(w * 5.3 + float2(0.19, 0)), n3 = vnoise(w * 5.3 + float2(0, 0.19));
        float3 N = normalize(float3(-hx * HS - (g2 - g1) * 0.28 - (n2 - n1) * 0.12, -hy * HS - (g3 - g1) * 0.28 - (n3 - n1) * 0.12, 1.0));
        float cut = carved(w, carving, smp);
        float h = relief.sample(smp, uv).r - cut * CARVE_DEPTH;
        float3 P = float3(w, h * HS);
        float4 A = rock.sample(smp, uv);
        float3 base = A.rgb;
        float4 pg = pigment.sample(smp, uv);
        float grain = 0.85 + 0.3 * vnoise(w * 2.3 + 3.1);
        float cov = clamp(pg.a * grain, 0.0, 1.0);
        float3 soaked = pg.rgb * mix(float3(1.0), base / 0.80, 0.55);
        float charcoal = smoothstep(0.30, 0.12, dot(base, float3(0.33)));
        float3 alb = mix(base, soaked, cov * (1.0 - charcoal));
        // The wheel's grooves hold soot; the fossils' calcite and cracks.
        alb *= 1.0 - cut * 0.45;
        float2 marks = fossilMarks(w0);
        alb = mix(alb, float3(0.86, 0.82, 0.74), marks.x);
        alb *= 1.0 - marks.y * 0.85;
        // Soot above, where torches have burned for a thousand years.
        alb *= mix(0.55, 1.0, smoothstep(-40.0, 170.0, w.y + 60.0 * vnoise(w * 0.012)));

        float flick = u.torch.w, flare = u.mouth.z;
        float3 L = u.torch.xyz - P;
        float d = length(L);
        L /= d;
        float att = 1.0 / (1.0 + pow(d / (230.0 + flare * 160.0), 2.0) * 1.6);
        // A soft shadow, marched over the relief toward the flame.
        float shade = 1.0;
        if (att > 0.04) {
            float reach = min(d, 200.0);
            for (int k = 1; k <= 16; k++) {
                float t = reach * float(k) / 16.0;
                float3 q = P + L * t;
                float under = H(q.xy, relief, carving, smp, u) * HS - q.z;
                shade = min(shade, clamp(1.0 - (under + 0.5) / 3.0, 0.0, 1.0));
            }
        }
        float diff = max(dot(N, L), 0.0) * shade;
        float wrap = max(dot(N, L) * 0.5 + 0.5, 0.0);
        float3 flame = float3(1.0, 0.58, 0.26) * flick * (1.0 + flare * 0.8);
        float3 col = alb * flame * att * (diff * 1.6 + wrap * 0.30);
        // The fat lamp on the ledge: a small steady light on the pigments.
        if (u.lamp.w > 0.5) {
            float3 L2 = u.lamp.xyz - P;
            float d2 = length(L2);
            L2 /= d2;
            col += alb * float3(1.0, 0.62, 0.30) * (0.9 + 0.1 * flick) * max(dot(N, L2), 0.0) / (1.0 + pow(d2 / 120.0, 2.0) * 1.6) * 1.1;
        }
        // Calcite: a few crystals glint as the light moves.
        float2 cell = floor(w * 1.1);
        if (hash21(cell) > 0.985) {
            float3 cn = normalize(float3(hash21(cell + 1.0) - 0.5, hash21(cell + 2.0) - 0.5, 0.6));
            float3 Hh = normalize(L + float3(0, 0, 1));
            float s = pow(max(dot(cn, Hh), 0.0), 60.0);
            float r = length(fract(w * 1.1) - 0.5);
            col += float3(1.0, 0.8, 0.55) * s * att * 2.4 * flick * smoothstep(0.5, 0.1, r) * (1.0 - cov) * shade;
        }
        // A damp sheen on the bulges.
        float3 Hv = normalize(L + float3(0, 0, 1));
        col += float3(1.0, 0.7, 0.45) * pow(max(dot(N, Hv), 0.0), 22.0) * att * 0.05 * flick * (1.0 - cov) * shade;
        // Fossil glass shows only as light: where its surface faces the torch or the sky.
        if (gh > 0.0) {
            float3 Ng = normalize(float3(-gs.x, -gs.y, 1.0));
            float3 Pg = float3(w0, h * HS + gh);
            float3 Lt = u.torch.xyz - Pg;
            float dt = length(Lt);
            Lt /= dt;
            float at = flick / (1.0 + pow(dt / (230.0 + flare * 160.0), 2.0) * 1.6);
            float3 Ls = normalize(float3(u.mouth.x - 40.0, u.mouth.y - 260.0, 90.0) - Pg);
            float asky = 1.0 / (1.0 + pow(length(u.mouth.xy - w0) / 260.0, 3.0));
            float rimT = pow(1.0 - Ng.z, 2.0);
            float2 out2 = normalize(-gs + 1e-5);
            float specT = pow(max(dot(Ng, normalize(Lt + float3(0, 0, 1))), 0.0), 90.0) * 2.6 + rimT * pow(max(dot(out2, normalize(Lt.xy + 1e-5)), 0.0), 2.0) * 1.4;
            float specS = pow(max(dot(Ng, normalize(Ls + float3(0, 0, 1))), 0.0), 90.0) * 1.6 + rimT * pow(max(dot(out2, normalize(Ls.xy + 1e-5)), 0.0), 2.0) * 0.9;
            col = col * 0.88 + float3(1.0, 0.86, 0.64) * specT * at * (1.0 - marks.x) + float3(0.78, 0.86, 1.0) * specS * asky * (1.0 - marks.x);
        }
        // The mouth's daylight: cool and steady on the rock near it; through the opening, only light.
        float3 M = float3(u.mouth.xy, 80.0);
        float3 Lm = M - P;
        float dm = length(Lm);
        Lm /= dm;
        col += alb * float3(0.55, 0.68, 0.90) * (max(dot(N, Lm), 0.0) * 0.9 + 0.15) / (1.0 + pow(dm / 240.0, 3.0)) * 1.2;
        // Outside, seen from the dark: a pale sky over the hill's soft green, too bright to hold
        // detail, but never one flat white.
        float sky = smoothstep(u.mouth.y + 120.0, u.mouth.y - 160.0, w.y);
        float3 land = mix(float3(0.62, 0.70, 0.52), float3(0.80, 0.84, 0.70), vnoise(w * 0.02));
        float3 outside = mix(land, mix(float3(0.95, 1.0, 1.08), float3(0.78, 0.88, 1.05), smoothstep(0.0, 1.0, (u.mouth.y - w.y) / 260.0)), sky);
        outside = mix(outside * 0.75, outside, smoothstep(0.3, 0.95, A.a)) * 1.15;
        float open = smoothstep(0.02, 0.5, A.a);
        col = mix(col, outside, open);
        float glare = exp(-pow(length((w - u.mouth.xy) / float2(175.0, 265.0)), 2.0) * 1.3);
        col += float3(0.75, 0.85, 1.0) * glare * 0.55 * (1.0 - open);
        // The mouth, a back button: shards of a glass rim along the opening's edge, lit where
        // they face the torch or the sky, and its chevron on the daylight.
        float2 dmouth = (w0 - u.mouth.xy) / float2(210.0, 300.0);
        if (dot(dmouth, dmouth) < 1.0) {
            float ring = exp(-pow((A.a - 0.14) / 0.07, 2.0)) * smoothstep(0.50, 0.58, vnoise(w0 * 0.045));
            if (ring > 0.01) {
                float ax = rock.sample(smp, mapUV(w0 + float2(1.0, 0.0), u)).a - rock.sample(smp, mapUV(w0 - float2(1.0, 0.0), u)).a;
                float ay = rock.sample(smp, mapUV(w0 + float2(0.0, 1.0), u)).a - rock.sample(smp, mapUV(w0 - float2(0.0, 1.0), u)).a;
                float2 n = -normalize(float2(ax, ay) + 1e-5);   // toward the rock
                float2 toT = normalize(u.torch.xy - w0), toS = normalize(float2(u.mouth.x - 40.0, u.mouth.y - 260.0) - w0);
                float tl = 1.0 / (1.0 + pow(length(u.torch.xy - w0) / (230.0 + flare * 160.0), 2.0) * 1.6);
                float lit = pow(max(dot(-n, toT), 0.0), 3.0) * tl * flick * 1.8 + pow(max(dot(-n, toS), 0.0), 6.0) * 0.9;
                col = col * (1.0 - 0.35 * ring * (1.0 - open)) + float3(1.0, 0.93, 0.82) * ring * lit;
            }
            float ch = chevronGlass(w0, u.mouth.xy);
            float chShadow = smoothstep(14.0, 0.0, -1.0 + min(sdSegment(w0, u.mouth.xy + float2(18.0, -38.0), u.mouth.xy + float2(-21.0, 4.0)),
                                                              sdSegment(w0, u.mouth.xy + float2(-21.0, 4.0), u.mouth.xy + float2(18.0, 46.0))) - 8.0);
            col *= 1.0 - 0.10 * chShadow * open;
            if (ch > 0.0) {
                float2 cg = float2(chevronGlass(w0 + float2(0.5, 0), u.mouth.xy) - chevronGlass(w0 - float2(0.5, 0), u.mouth.xy),
                                   chevronGlass(w0 + float2(0, 0.5), u.mouth.xy) - chevronGlass(w0 - float2(0, 0.5), u.mouth.xy));
                float3 Nc = normalize(float3(-cg, 1.0));
                float3 Lsky = normalize(float3(-0.3, -1.0, 0.9));
                col = col * (0.93 - 0.30 * (1.0 - Nc.z)) + float3(1.0) * pow(max(dot(Nc, normalize(Lsky + float3(0, 0, 1))), 0.0), 40.0) * 0.5;
            }
        }
        col += float3(0.006, 0.007, 0.010);
        // Past the cave's end, the dark.
        col *= 1.0 - smoothstep(u.misc.y - 260.0, u.misc.y, w.x);
        col *= 1.35;
        col = col / (1.0 + col * 0.5);
        col = pow(max(col, 0.0), float3(1.0 / 1.08));
        float vig = smoothstep(1.25, 0.35, length((screen - 0.5) * float2(1.0, 1.25)));
        col *= vig;
        // Walking out: the daylight takes the screen.
        col = mix(col, float3(1.0, 1.0, 0.99), u.mouth.w);
        return float4(col, 1.0);
    }

    struct SpriteOut {
        float4 position [[position]];
        float2 local;
        float kind;
        float4 inner;
        float4 outer;
    };

    vertex SpriteOut caveSpriteVertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                                      constant Sprite* sprites [[buffer(0)]], constant CaveUniforms& u [[buffer(1)]]) {
        float2 c = float2(float(vid & 1) * 2.0 - 1.0, float((vid >> 1) & 1) * 2.0 - 1.0);
        Sprite s = sprites[iid];
        float2 w = s.place.xy + s.place.zw * c.x + s.axis.xy * c.y;
        float2 px = (w - float2(u.view.w, 0.0)) * u.view.z;
        SpriteOut o;
        o.position = float4(px.x / u.view.x * 2.0 - 1.0, 1.0 - px.y / u.view.y * 2.0, 0.0, 1.0);
        o.local = c;
        o.kind = s.axis.z;
        o.inner = s.inner;
        o.outer = s.outer;
        return o;
    }

    // Premultiplied: a glow adds its light (alpha 0), the rest lie over what is under them.
    fragment float4 caveSprite(SpriteOut in [[stage_in]], constant CaveUniforms& u [[buffer(0)]]) {
        float t = length(in.local);
        float4 c;
        if (in.kind < 0.5) {
            // A glow.
            if (t > 1.0) discard_fragment();
            float4 k = mix(in.inner, in.outer, smoothstep(0.0, 1.0, t));
            float a = k.a * (1.0 - smoothstep(0.55, 1.0, t));
            c = float4(k.rgb * a, 0.0);
        } else if (in.kind < 1.5) {
            // A soft dot or ellipse, laid over.
            if (t > 1.0) discard_fragment();
            float a = in.inner.a * (1.0 - smoothstep(0.6, 1.0, t));
            c = float4(in.inner.rgb * a, a);
        } else {
            // A stick, tapering from its head (y -1) to its foot (y 1).
            float halfWidth = mix(1.0, 0.45, in.local.y * 0.5 + 0.5);
            if (abs(in.local.x) > halfWidth) discard_fragment();
            float a = in.inner.a * (1.0 - smoothstep(0.75, 1.0, abs(in.local.x) / halfWidth));
            float3 rgb = in.inner.rgb * (0.85 + 0.15 * (1.0 - abs(in.local.x) / halfWidth));
            c = float4(rgb * a, a);
        }
        // The daylight takes the air too, as the screen goes white.
        return c * (1.0 - u.mouth.w);
    }
    """
}
#endif
