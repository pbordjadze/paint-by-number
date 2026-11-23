#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// The short Making-of's graphite at `progress`, over its map (`GraphiteSketch.Drawing.map`: red
// the pixel's arrival, green its stroke, blue how close a stroke is). The arithmetic is
// `GraphiteSketch.shade`'s, whose constants come in as arguments: change the two together.
[[ stitchable ]] half4 formingGraphite(
    float2 position, half4 color, float progress, half4 ink, half4 point, half4 paper,
    float pencil, float edge, float fresh, float wash, float inkFrom, float inkTo, float pointFrom, float pointTo
) {
    float arrival = color.r, stroke = color.g, halo = color.b;
    float reached = saturate((progress - arrival) / edge);
    float behind = progress - arrival;
    float tip = (behind >= 0.0 && behind < fresh) ? 1.0 - behind / fresh : 0.0;
    // The map is smaller than the screen: its strokes come in soft, so the ink takes only their
    // ridge, crisp, and the point a little more, so it shows as a warm dot at the front.
    float pointShare = smoothstep(pointFrom, pointTo, stroke) * reached * tip;
    float inkShare = max(smoothstep(inkFrom, inkTo, stroke) * reached * (pencil + (1.0 - pencil) * tip), pointShare);
    float washShare = wash * halo * reached;
    half3 lead = mix(ink.rgb, point.rgb, half(inkShare > 0.0 ? pointShare / inkShare : 0.0));
    half a = half(inkShare), w = half(washShare) * (1.0h - a);
    // Premultiplied: the stroke over the paper the color drained to.
    return half4(lead * a + paper.rgb * w, a + w);
}
