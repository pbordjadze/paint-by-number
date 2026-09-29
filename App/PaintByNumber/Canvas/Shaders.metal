#include <metal_stdlib>
using namespace metal;

// Placeholder kernel so the Metal toolchain is exercised from the first CI build.
kernel void clearTexture(texture2d<float, access::write> target [[texture(0)]],
                         uint2 gid [[thread_position_in_grid]]) {
    if (gid.x < target.get_width() && gid.y < target.get_height()) {
        target.write(float4(1.0), gid);
    }
}
