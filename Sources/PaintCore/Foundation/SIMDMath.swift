/// The 2D vector helpers PaintCore needs: the `simd` module's dot and length do not exist on Linux.
@inline(__always) func simdDot(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { a.x * b.x + a.y * b.y }
@inline(__always) func simdLengthSquared(_ a: SIMD2<Float>) -> Float { a.x * a.x + a.y * a.y }
@inline(__always) func simdLength(_ a: SIMD2<Float>) -> Float { simdLengthSquared(a).squareRoot() }
